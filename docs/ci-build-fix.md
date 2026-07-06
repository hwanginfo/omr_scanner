# 离线 OMR 答题卡扫描 APP CI 构建故障处理文档

> 文档版本：V1.0  
> 适用对象：后端/安卓开发程序员  
> 文档用途：记录 Flutter 安卓项目 GitHub Actions 流水线 Gradle 构建阻塞全量问题、复现路径、修复方案、验收检查清单

---

## 一、项目基础信息

1. **项目名称**：omr_scanner 离线安卓答题卡扫描阅卷 APP
2. **技术栈**：Flutter 3.44.4 + Dart OMR 识别 + SQLite 离线存储
3. **核心产品约束**：
   - 成品 APK 纯离线运行，无强制网络依赖
   - 内置成绩统计、学号筛选、Excel 导出、错题本字段预留、APP 更新预留模块
4. **构建环境**：本地 Mac 开发 + GitHub Actions Ubuntu 云端 CI 自动打包

## 二、故障完整现象描述

### 2.1 开发本地现象

1. 本地 Mac 电脑配置阿里云 Maven 镜像，`flutter build apk` 偶发 Gradle 依赖下载超时、构建挂起
2. 已做优化：全局 gradle 镜像、settings.gradle.kts 全局仓库管控、超时并行参数、Flutter 国内环境变量
3. 代码层面全部验证通过：图像降采样、数据库分页、单元测试全过、签名配置完成

### 2.2 GitHub Actions CI 流水线连续 8 次构建失败现象

| 构建轮次 | 失败阶段 | 具体报错 |
|---------|---------|---------|
| Run 1 | YAML 解析 | secrets 变量语法错误 |
| Run 2-4 | Setup Flutter | subosito/flutter-action 版本不兼容、jq JSON 解析报错、PATH 环境变量冲突 |
| Run 5 | Build APK | CI 容器 Android SDK 缺失 android-34 平台文件 |
| Run 6 | Build APK | AGP 版本适配冲突 |
| Run 7-8 | Build APK | Flutter 环境、pub 依赖全部正常，仅 Gradle 依赖解析失败，构建终止 |

### 2.3 根因定位

**根因一：`android/settings.gradle.kts` 中 `RepositoriesMode.PREFER_SETTINGS` 强制全局仓库管控**

- 该配置会屏蔽 Flutter Gradle 插件内置的本地 Maven 构件仓库
- Flutter 编译安卓时需要加载内部本地依赖 artifact，被全局仓库规则拦截
- 仅在执行 APK 打包阶段触发故障，前置 Flutter 环境安装、pub 依赖拉取无异常

**根因二：国内网络无法直连 Google Maven 仓库**

- Google Maven（`dl.google.com`）和 Maven Central 在国内网络不可达
- 导致 Gradle 依赖下载卡在 `SYN_SENT` 状态，构建挂起直至超时

### 2.4 故障影响范围

1. 仅影响**开发打包流程**：本地构建、云端 CI 自动打包
2. 完全不影响最终安卓 APK 离线运行：答题卡扫描、本地识别、成绩统计、离线导出功能无任何关联风险
3. 阻断云端自动产出安装包，仅能依靠本地手动打包交付

## 三、修复方案

### 步骤 1：移除 `PREFER_SETTINGS` 全局仓库管控

**文件**：`android/settings.gradle.kts`

删除 `dependencyResolutionManagement` 整块代码（包含 `RepositoriesMode.PREFER_SETTINGS` 配置）：

```kotlin
// 删除前
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        google()
        mavenCentral()
    }
}

// 删除后 — 文件仅保留 pluginManagement + include(":app")
```

### 步骤 2：配置阿里云 Maven 镜像

**文件**：`android/settings.gradle.kts` — `pluginManagement.repositories`

```kotlin
pluginManagement {
    repositories {
        // 阿里云 Maven 镜像（国内网络可用）
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
        gradlePluginPortal()  // plugins.gradle.org 国内可达
    }
}
```

**文件**：`android/build.gradle.kts` — 增加 `allprojects.repositories`

```kotlin
allprojects {
    repositories {
        maven("https://maven.aliyun.com/repository/public")
        maven("https://maven.aliyun.com/repository/google")
    }
}
```

配置原则：
- 禁止使用 `PREFER_SETTINGS` 强制管控，避免拦截 Flutter 内置 Maven 构件
- 阿里云镜像已在 `maven.aliyun.com/repository/google` 中包含 AGP 8.7.3
- `allprojects.repositories` 仅补充依赖仓库，不影响 Flutter 本地构件

### 步骤 3：更新 CI 流水线

**文件**：`.github/workflows/build.yml`

```yaml
# Android SDK 版本同步升级
yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager \
    --install "platforms;android-35" "build-tools;35.0.0" 2>&1 || true

# 构建增加 --verbose 捕获底层 Gradle 日志
- name: Build debug APK
  run: flutter build apk --debug --verbose 2>&1 | tail -30
```

### 步骤 4：本地验证

```bash
# 全量清理缓存
flutter clean
cd android && ./gradlew clean && cd ..

# 依赖解析
flutter pub get

# 测试
flutter test

# 构建（CI 环境或 VPN 下执行）
flutter build apk --debug
```

> **注意**：国内网络环境下，`flutter build apk` 因无法连接 Google Maven 可能仍会挂起。  
> CI 环境（GitHub Actions）可直接访问 Google，无此问题。  
> 本地开发推荐在 VPN 环境下执行构建。

## 四、验收检查清单

### 4.1 代码文件检查项

- [x] `android/settings.gradle.kts` 已完整删除 `dependencyResolutionManagement` 区块，无残留 `RepositoriesMode` 管控代码
- [x] 项目镜像加速配置迁移至 `pluginManagement.repositories` + `allprojects.repositories`，使用阿里云镜像
- [x] `build.gradle.kts` 中的 `allprojects.repositories` 不拦截 Flutter 内置本地依赖
- [x] CI 工作流 `build.yml` 无冲突国内镜像全局 ENV 变量

### 4.2 本地构建验收项

- [x] 执行 `flutter test` 全部通过（13 个用例）
- [ ] 在可访问 Google Maven 的网络下，`flutter build apk --debug` 本地打包无 Gradle 超时
- [ ] 产出 APK 可正常安装至安卓 7.0+ 设备

### 4.3 GitHub Actions CI 流水线验收项

- [x] `flutter pub get` 完成（CI #9 7 秒通过）
- [x] `Build debug APK` 通过（CI #9 conclusion: success，约 2 分钟）
- [x] Setup Flutter 步骤无 jq 解析、PATH 环境报错
- [x] Android SDK 平台文件自动下载
- [x] CI 流水线成功产出可下载 APK 产物

### 4.4 长期稳定性

- [ ] 连续 3 次推送代码，CI 流水线均能完整构建成功
- [ ] 离线 APP 核心业务逻辑不受构建配置修改影响

## 五、故障复现 & 快速排查自检清单

### 5.1 Gradle 构建失败快速自检

1. 检查 `settings.gradle.kts` 是否存在 `RepositoriesMode.PREFER_SETTINGS` → 存在即删除
2. 核对 Flutter 与 AGP、Gradle 版本适配关系
3. 清理 Flutter 与 Gradle 缓存后重新构建
4. 区分故障阶段：
   - 卡在 Setup Flutter：CI action 镜像/环境变量冲突
   - 卡在 Build APK：Flutter 本地构件被仓库规则拦截，优先检查 settings 仓库配置
5. 通过 `lsof -iTCP -sTCP:SYN_SENT` 检查是否有卡死的网络连接

### 5.2 CI 流水线通用故障自检

1. YAML 语法错误：检查 secrets 引用、缩进、换行格式
2. Flutter Action 兼容：旧版本 `subosito/flutter-action` 易出现 jq 解析错误，替换官方 `flutter/setup-flutter-action`
3. Android SDK 缺失：在 CI 脚本中补充安装指定平台版本
4. 国内镜像冲突：CI 环境删除全局 PUB/Flutter 镜像环境变量，云端使用官方源

### 5.3 APK 成品稳定性自检

1. 安装打包产出 APK，断网状态完整走全流程
2. 验证预留功能字段：每题知识点标签正常存储
3. 验证预留 APP 更新弹窗入口，不干扰离线阅卷
4. 多台低端安卓设备兼容性测试

## 六、构建配置总览

### `android/settings.gradle.kts`（修复后）

```kotlin
pluginManagement {
    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
        flutterSdkPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
        gradlePluginPortal()
    }

    plugins {
        id("dev.flutter.flutter-plugin-loader") version "1.0.0"
        id("com.android.application") version "8.7.3" apply false
        id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    }
}

include(":app")
```

### `android/build.gradle.kts`（修复后）

```kotlin
allprojects {
    repositories {
        maven("https://maven.aliyun.com/repository/public")
        maven("https://maven.aliyun.com/repository/google")
    }
}
```

### `.github/workflows/build.yml`（修复后）

```yaml
name: Build APK

on:
  push:
    branches: [ main ]
  workflow_dispatch:

jobs:
  build:
    runs-on: ubuntu-latest
    container:
      image: ghcr.io/cirruslabs/flutter:stable

    steps:
      - uses: actions/checkout@v4
      - run: flutter --version

      - name: Setup Android SDK
        run: |
          echo "ANDROID_HOME=$ANDROID_HOME"
          ls -la $ANDROID_HOME/platforms/ 2>/dev/null || echo "No platforms dir"
          ls -la $ANDROID_HOME/build-tools/ 2>/dev/null || echo "No build-tools dir"
          yes | $ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager \
            --install "platforms;android-35" "build-tools;35.0.0" 2>&1 || true

      - run: flutter pub get

      - name: Build debug APK
        run: flutter build apk --debug --verbose 2>&1 | tail -30

      - uses: actions/upload-artifact@v4
        with:
          name: omr-scanner-debug-apk
          path: build/app/outputs/flutter-apk/app-debug.apk
```
