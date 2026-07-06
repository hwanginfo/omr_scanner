# OMR 答题卡扫描 APP — CI 构建故障综述与根因分析

> 文档版本：V2.0  
> 日期：2026-07-06  
> 涵盖范围：Commit 96e08b7 → 0500df3（Run #1 → #25）  
> 状态：⚠️ 部分修复，Kotlin 编译问题未彻底解决

---

## 一、项目架构概述

### 1.1 应用架构

```
┌─────────────────────────────────────────────────────────────┐
│  OMR 答题卡扫描阅卷 APP                                      │
│  Flutter 3.44.4 · Dart 3.x · 100% 离线 · Android 7.0+      │
├─────────────────────────────────────────────────────────────┤
│  UI 层 (lib/pages/)                                         │
│  扫描首页 · 模板管理 · 成绩统计 · 班级管理 · 设置             │
├─────────────────────────────────────────────────────────────┤
│  业务逻辑层 (lib/services/)                                  │
│  OMR引擎 · 模板引擎 · PDF生成 · Excel导出 · 版本检查          │
├─────────────────────────────────────────────────────────────┤
│  数据持久层 (lib/database/ + lib/models/)                    │
│  SQLite 7表 · 班级/学生/模板/扫描记录/错题本预留               │
└─────────────────────────────────────────────────────────────┘
```

### 1.2 构建管线架构（GitHub Actions）

```
┌─ Developer Push ────────────────────────────────────────────┐
│  git push → GitHub → 触发 workflow_dispatch                 │
└──────────────────────────────┬──────────────────────────────┘
                               ▼
┌─ CI 容器 (Docker) ─────────────────────────────────────────┐
│  ghcr.io/cirruslabs/flutter:stable                          │
│  - OS: Ubuntu 24.04 LTS                                    │
│  - Flutter 3.44.4 (stable channel)                         │
│  - JDK 21 (容器内置)                                       │
│  - Android SDK 35 (通过 sdkmanager 附加安装)                 │
│  - 资源: 2 vCPU · 7 GB RAM · 14 GB SSD                    │
└──────────────────────────────┬──────────────────────────────┘
                               ▼
┌─ Gradle 构建 (容器内) ──────────────────────────────────────┐
│  1. flutter pub get (pub.dev 解析 Dart 依赖)                │
│  2. settings.gradle.kts: pluginManagement + repos          │
│  3. build.gradle.kts: allprojects.repositories             │
│  4. app/build.gradle.kts: AGP + Kotlin 插件                │
│  5. assembleDebug:                                          │
│     ├─ compileDebugKotlin  ←── ★ 故障频发阶段              │
│     ├─ compileDebugJavaWithJavac                            │
│     ├─ mergeDebugNativeLibs                                │
│     └─ packageDebug                                        │
│  6. 产出 app-debug.apk → upload-artifact                    │
└─────────────────────────────────────────────────────────────┘
```

### 1.3 Gradle 配置体系

项目涉及 4 个关键配置文件，它们之间的协作关系如下：

| 文件 | 职责 | 关键点 |
|------|------|--------|
| `android/settings.gradle.kts` | 插件版本声明 + 仓库地址 | 声明 `kotlin 2.0.21`、`AGP 8.7.3` |
| `android/build.gradle.kts` | 根项目 + 子项目通用仓库 | `allprojects.repositories` |
| `android/app/build.gradle.kts` | 应用模块构建配置 | `plugins` 块、`kotlin` 块、`signingConfigs` |
| `android/gradle.properties` | Gradle 全局属性 | `-Xmx`、`android.builtInKotlin`、并行编译 |

---

## 二、问题时间线（完整故障演进）

### 第一阶段：CI 环境适配（Run #1 — #8）

| 构建 | 失败阶段 | 根因 |
|------|---------|------|
| #1 | YAML 解析 | secrets 变量语法错误 |
| #2-4 | Setup Flutter | `subosito/flutter-action` 版本不兼容，jq JSON 解析报错 |
| #5 | Setup Android SDK | Docker 容器无预装 Android SDK |
| #6-8 | Build APK | AGP 版本不匹配 + Gradle 依赖解析失败 |

**修复**：改用 `ghcr.io/cirruslabs/flutter:stable` 容器镜像，手动安装 SDK，降级 AGP 8.7.3 / Kotlin 2.0.21

### 第二阶段：Gradle 仓库与 Maven 镜像（Run #9 — #13）

| 构建 | 失败阶段 | 根因 |
|------|---------|------|
| **#9** ✅ | **成功** | 使用 `--verbose ... \| tail -30` 掩盖了错误 |
| #13 | Build APK | `signingConfigs` 中 keystore 为 null |

**关键发现**：#9 实际是**假成功**——`| tail -30` 吃掉了 Gradle 的 exit code 1。真正的 Kotlin 编译错误从一开始就存在，但被管道掩盖。

### 第三阶段：Kotlin 编译持续失败（Run #14 — #25）

这是问题最密集的阶段，共 11 次构建全部失败。以下是每次尝试及诊断演进：

```
Run #14 → signingConfigs null → 修复: if (key.properties.exists()) 保护
Run #15 → android.builtInKotlin=false 导致 Flutter 丢失 Kotlin 管理 → 修复: 移除
Run #16 → Aliyun 502 Bad Gateway → 修复: + google() mavenCentral()
Run #17 → 移除 kotlin 块后 JVM 17 vs 21 不匹配 → 修复: + kotlinOptions
Run #18 → kotlinOptions 没用（app 内 kotlin 块被移除）→ 修复: 加回 kotlin 块
Run #19 → kotlin('android') + builtInKotlin=false 仍失败 → 修复: plugins 不对
Run #20 → 完全还原 Flutter 标准（无 kotlin 插件）→ JVM 17 vs 21
Run #21 → kotlin('android') + builtInKotlin=false + kotlin 块 → OOM (8G超限)
Run #22 → -Xmx4G → OOM (daemon 启动终止)
Run #23 → 移除 builtInKotlin + kotlin('android') → JVM 不匹配
Run #24 → org.jetbrains.kotlin.android (无版本) + builtInKotlin=false → 还是失败
Run #25 → -Xmx6G + parallel=false + builtInKotlin=false → 失败（Kotlin 依然找不到 FlutterActivity）
```

---

## 三、根因深入分析

### 3.1 Kotlin 编译失败 — 三类问题的纠缠

```
问题一：插件未应用                   问题二：JVM 目标不匹配
┌─────────────────────────┐         ┌─────────────────────┐
│ app/build.gradle.kts    │         │ JDK 21 (容器)       │
│ plugins {               │         │                     │
│   kotlin("android") ✗   │ ←──→   │ compileDebugJava → 17│
│   dev.flutter...        │         │ compileDebugKotlin→21│
│ }                       │         │ 冲突！              │
└─────────────────────────┘         └─────────────────────┘
         ↕                                   ↕
┌────────────────────────────────────────────────────────────┐
│ 问题三：Flutter Built-in Kotlin 迁移                   │
│                                                          │
│ Flutter 3.44.4 要求使用 built-in Kotlin（移除              │
│ kotlin("android") 插件，由 flutter-gradle-plugin 自动管理）│
│                                                          │
│ 但迁移后 JVM 目标默认 21，与 compileOptions 的 17 冲突      │
│                                                          │
│ 设置 android.builtInKotlin=false 后项目自管 Kotlin，       │
│ 但需要 kotlin("android") 插件，否则 Kotlin 编译器不执行    │
└──────────────────────────────────────────────────────────┘
```

**根本矛盾**：Flutter 3.44.4 + AGP 8.7.3 + Kotlin 2.0.21 的组合中：

| 方案 | `builtInKotlin` | `kotlin("android")` 插件 | JVM 对齐 | 结果 |
|------|-----------------|------------------------|----------|------|
| A（Flutter 默认） | true（不设） | 不声明 | JDK 21 → Kotlin 21 vs Java 17 ❌ | 冲突 |
| B（自管理） | false | 声明 | 需要 kotlin 块设 17 ✅ | 插件未应用 ❌ |
| C（混合） | false | 声明 + kotlin 块设 17 | 理论上 ✅ | 但 OOM ❌ |

方案 C 理论上正确但遇 OOM。

### 3.2 Gradle OOM — Docker 容器的"隐形天花板"

```
GitHub Actions ubuntu-latest Runner 规格:
  CPU: 2 核
  RAM: 7 GB 总物理内存
  Disk: 14 GB SSD

Docker 容器额外开销:
  - 容器运行时: ~300MB
  - Docker 镜像层: ~2GB (cirruslabs/flutter:stable)
  - 可用给 Gradle 的: ~6.5 GB

Gradle 内存配置实验:
  -Xmx8G  → ❌ 超限 (需要 8G, 仅剩 ~6.5G)
  -Xmx4G  → ⚠️ Gradle daemon OOM + Metaspace 1G 不够
  -Xmx6G  → ⚠️ 仍可能 OOM（加上 Metaspace 2G = 8G 总需求）

解决方案: 移除 Docker 容器，直接在 Runner 上构建
```

### 3.3 Maven 仓库镜像冲突

```
国内开发环境 (Mac + 阿里云)          CI 环境 (GitHub + 美国)
┌──────────────────────┐          ┌──────────────────────┐
│ google() ❌ 被墙      │          │ google() ✅ 可达     │
│ mavenCentral() ❌ 被墙│          │ mavenCentral() ✅    │
│ aliyun ✅ 可用        │          │ aliyun  502 错误     │
│ graldePluginPortal ✅ │          │ gradlePluginPortal ✅│
└──────────────────────┘          └──────────────────────┘

当前配置（折中方案）：
  pluginManagement.repositories = google() + mavenCentral() + gradlePluginPortal() + aliyun
  allprojects.repositories = google() + mavenCentral() + aliyun
```

### 3.4 被掩盖的原始错误

#9 是唯一"成功"的 CI 构建，但仔细检查发现：

```yaml
# 旧版 build.yml
- name: Build debug APK
  run: flutter build apk --debug --verbose 2>&1 | tail -30
```

`| tail -30` 的行为：
- `tail` 从管道读取输出，当行数超过 30 时输出最后 30 行
- 如果 Gradle 构建失败，`exit code 1` 被 `tail` 吞掉
- GitHub Actions 只看 `tail` 的 exit code，而不是 `flutter build` 的
- 所以 #9 显示"success"，实际上 `compileDebugKotlin` 从未成功

---

## 四、当前配置快照（Commit 0500df3）

### android/settings.gradle.kts

```kotlin
pluginManagement {
    // Flutter SDK 路径
    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
    }

    plugins {
        id("dev.flutter.flutter-plugin-loader") version "1.0.0"
        id("com.android.application")     version "8.7.3"   apply false
        id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    }
}
```

### android/app/build.gradle.kts

```kotlin
plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
    id("org.jetbrains.kotlin.android")          // 版本由 settings 管理
}

android {
    compileSdk = flutter.compileSdkVersion
    compileOptions { sourceCompatibility = VERSION_17; targetCompatibility = VERSION_17 }
    // release signing: 仅本地存在 key.properties 时配置
    if (keystorePropertiesFile.exists()) { signingConfigs { create("release") {...} } }
    buildTypes {
        release { if (keystorePropertiesFile.exists()) { signingConfig = signingConfigs["release"] } }
    }
}

kotlin {
    compilerOptions { jvmTarget = JvmTarget.JVM_17 }
}
```

### android/gradle.properties

```properties
org.gradle.jvmargs=-Xmx6G -XX:MaxMetaspaceSize=2G -XX:ReservedCodeCacheSize=512m
android.useAndroidX=true
org.gradle.parallel=false
android.builtInKotlin=false
```

### .github/workflows/build.yml

```yaml
name: Build APK
on: [push, workflow_dispatch]
jobs:
  build:
    runs-on: ubuntu-latest
    container: ghcr.io/cirruslabs/flutter:stable
    steps:
      - uses: actions/checkout@v4
      - run: flutter --version
      - name: Setup Android SDK
        run: sdkmanager --install "platforms;android-35" "build-tools;35.0.0"
      - run: flutter pub get
      - name: Build debug APK
        run: flutter build apk --debug --android-skip-build-dependency-validation
      - name: List APK output
        run: find . -name "*.apk" -type f
      - uses: actions/upload-artifact@v4
        with: { name: omr-scanner-debug-apk, path: "**/app-debug.apk" }
```

---

## 五、推荐下一步方案

### 方案 A：放弃 Docker 容器（推荐）

**修改**：移除 `build.yml` 中的 `container:` 配置，改用 `subosito/flutter-action` 或 `flutter/setup-flutter-action` 在 Runner 上直接安装 Flutter。

**优势**：
- 完整 7GB 内存给 Gradle
- 避免容器镜像拉取耗时
- 更直观的调试（日志直接对应 Runner）

### 方案 B：在 app 模块精确配置 Kotlin

**前提**：移除 `android.builtInKotlin=false`，改用 Flutter 内置 Kotlin 管理，但通过 AGP 层面控制 JVM 版本：

```kotlin
// app/build.gradle.kts
android {
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}
```

（无需 plugin 声明、无需 `kotlin {}` 块）

### 方案 C：本地构建 + 手动发布

在本地 Mac 上构建 APK，直接上传 GitHub Release：
```bash
flutter build apk --release
# 产出: build/app/outputs/flutter-apk/app-release.apk
```

---

## 六、附：CI 构建数据总表

| Run | Commit | 状态 | 差异 | 问题 |
|-----|--------|------|------|------|
| #1 | 96e08b7 | ❌ | init | YAML syntax |
| #2 | 632c07d | ❌ | - | flutter-action |
| #3 | 4caf4fa | ❌ | - | flutter-action |
| #4 | b7291fb | ❌ | - | flutter-action |
| #5 | 2b06933 | ❌ | Docker | Android SDK |
| #6 | db708a3 | ❌ | android-34 | SDK 版本 |
| #7 | ba50313 | ❌ | AGP/Kotlin | 版本冲突 |
| #8 | bcb669d | ❌ | sdkmanager | SDK 诊断 |
| **#9** | **8f51749** | **✅** | **(假)** | **tail 掩盖** |
| **#10** | **6d62377** | **✅** | **(假)** | **tail 掩盖** |
| #11 | 65b27db | ❌ | APK 路径 | key.properties null |
| #12 | 75f104c | ❌ | CI 简化 | signingConfigs null |
| #13 | — | ❌ | dispatch | signingConfigs null |
| #14 | 2e7cadc | ❌ | null-safe | Kotlin 编译 |
| #15 | ed51b54 | ❌ | gradle.properties | Kotlin 编译 |
| #16 | 62f272f | ❌ | 镜像配置 | Aliyun 502 |
| #17 | fa31539 | ❌ | kotlin 块 | JVM 冲突 |
| #18 | a13423d | ❌ | jvmTarget=17 | Kotlin 不执行 |
| #19 | 4c6f50c | ❌ | kotlin(android) | 依然失败 |
| #20 | b064dbe | ❌ | 还原标准 | JVM 冲突 |
| #21 | 9f4df37 | ❌ | kotlin + builtIn | OOM |
| #22 | 1c2cd17 | ❌ | -Xmx4G | OOM |
| #23 | 04284c3 | ❌ | Flutter 管理 | JVM 冲突 |
| #24 | 64c3167 | ❌ | kotlin.android | 依然失败 |
| #25 | 0500df3 | ❌ | +6G+parallel=false | 依然失败 |

---

## 七、要点总结

1. **根因链条**：项目初始化时 `app/build.gradle.kts` 缺少 `kotlin("android")` 插件声明，导致 Kotlin 编译器找不到 `FlutterActivity` → 后续所有修复都在这个基础上打补丁 → 多个配置项的叠加导致状态混乱

2. **关键教训**：
   - `flutter build apk` 的输出永远不要 `| tail` 管道，这会掩盖 exit code
   - Docker 容器内的内存管理需要精确计算：Gradle daemon + 容器 = OOM
   - `android.builtInKotlin` 开关涉及 Flutter 内部 Kotlin 管理机制，切换后必须配套修改 plugins 和 kotlin 块
   - CI 和开发环境使用不同 Maven 源时，必须同时保留官方源和镜像源

3. **当前状态**：CI 构建仍未成功产出 APK。推荐采用方案 A（移除 Docker 容器）作为最短修复路径。
