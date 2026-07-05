# OMR 答题卡扫描阅卷系统

**100% 离线 Android 应用** — 教师创建答题卡模板（20/30/50/100 题，单选/判断），
打印为 PDF，手机拍照扫描，自动识别批改，生成成绩统计和 Excel 导出。

## 功能

| 功能 | 说明 |
|---|---|
| 📝 **答题卡模板** | 内置 6 种模板（20/30/50/100 题单选 + 20/50 题判断），一键创建 |
| 🖨️ **打印输出** | 生成 A5 横向 PDF 答题卡，含四角定位标记 + 学号区域 |
| 📸 **拍照扫描** | 调用手机相机，自动边缘检测 + 透视校正 |
| 🧠 **OMR 识别** | 纯 Dart 光学标记识别，后台 Isolate 运行不卡 UI |
| ✅ **自动批改** | 与标准答案对比，逐题判定正误 |
| 📊 **成绩统计** | 分数分布图 + 单题正确率 + 学生答卷明细 |
| 📗 **Excel 导出** | 单条或批量导出阅卷结果 |
| 👥 **班级管理** | 创建班级、导入学生名单（CSV） |
| 🔄 **母版扫描** | 学号填 0000 即为母版，一次扫描完成标准答案录入 |
| 📦 **完全离线** | 无需网络连接，所有数据存储在本地 SQLite |

## 技术栈

| 层 | 技术 | 用途 |
|---|---|---|
| UI 框架 | **Flutter 3.x** (Dart) + Material 3 | 跨平台 UI，只部署 Android |
| 状态管理 | **provider** ^6.1.1 | 底部导航栏索引 |
| 拍照 / 扫描 | **flutter_document_scanner** ^1.1.2 | 原生相机 + 边缘检测 |
| 图像处理 | **Dart image** ^4.1.3 | 灰度转换 + 像素采样 |
| OMR 引擎 | **纯 Dart + Isolate** | 后台隔离区执行，主线程不阻塞 |
| 本地数据库 | **sqflite** ^2.3.0 | SQLite（7 张表） |
| PDF 生成 | **pdf** ^3.10.7 + **printing** ^5.11.1 | A5 答题卡 PDF |
| 图表 | **fl_chart** ^0.66.2 | 分数分布 + 单题正确率 |
| Excel 导出 | **excel** ^2.1.0 | xlsx 格式 |

## 性能优化

- **后台 Isolate 执行 OMR** — `Isolate.run()` 将图像解码/降采样/识别移到独立隔离区，UI 零阻塞
- **图像自动降采样** — 相机 12MP 原始帧自动缩放到最长边 ≤1600px，像素量减少约 85%
- **数据库 LIMIT** — 首页只查询最近 20 条记录，不加载全表
- **JSON 解析缓存** — Excel 导出时每条记录只解析一次 answerJson

## 构建

```bash
# 安装依赖
flutter pub get

# 静态分析
flutter analyze

# 运行测试
flutter test

# 构建 debug APK
flutter build apk --debug

# 构建 release APK
flutter build apk --release
```

**release 签名**：已配置 `android/key.properties` + `upload-keystore.jks`，
如需要更换签名文件，编辑 `android/key.properties` 中的 `storeFile` 路径。

## 运行环境

| 要求 | 说明 |
|---|---|
| Android | 7.0+ (API 24+)，需相机硬件 |
| 存储 | 约 50MB（不含数据库增长） |
| 网络 | 不需要（完全离线） |
| 权限 | CAMERA（扫描用），WRITE_EXTERNAL_STORAGE（≤API 28） |

## 项目结构

```
lib/
├── main.dart                          — 应用入口
├── database/database_helper.dart      — SQLite 单例（7 表）
├── models/models.dart                 — 数据模型
├── services/
│   ├── omr_engine.dart                — OMR 引擎（Isolate + 降采样）
│   ├── template_engine.dart           — 模板坐标生成
│   ├── pdf_generator.dart             — 答题卡 PDF 生成
│   ├── excel_exporter.dart            — Excel 导出
│   └── version_checker.dart           — 版本检查（预留）
├── pages/
│   ├── home_page.dart                 — 扫描首页
│   ├── class_management_page.dart     — 班级管理
│   ├── template_management_page.dart  — 模板管理
│   ├── statistics_page.dart           — 成绩统计
│   └── settings_page.dart             — 设置
└── utils/                             — 工具类（预留）
test/
└── services/
    └── omr_engine_test.dart           — OMR 引擎单元测试（13 个用例）
```

## 许可

仅供教育用途。
