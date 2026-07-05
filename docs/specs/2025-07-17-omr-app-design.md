# Flutter 离线 OMR 答题卡 APP — 设计规格说明

> 日期: 2025-07-17 | 状态: 已批准 | 版本: v1.0

## 一、项目总定位

基于 Flutter + 本地图像处理的纯安卓离线答题卡扫描阅卷 APP。
- 输出: Release APK（Android 7.0+）
- 核心约束: 100% 离线阅卷，网络权限默认关闭，仅版本更新页可用
- 目标用户: 教师单人单设备阅卷

## 二、技术选型

| 层级 | 选型 | 理由 |
|---|---|---|
| 前端框架 | Flutter 3.x Stable + Dart | 单套代码 → Android APK |
| 文档扫描 | `flutter_document_scanner` | 原生相机 + 四点透视矫正 |
| 图像处理 | Dart `image` 包 | 灰度 + 网格采样，固定模板不依赖 OpenCV |
| 本地数据库 | `sqflite` | SQLite |
| Excel 导出 | `excel` Dart 包 | 纯 Dart 生成 xlsx |
| PDF 生成 | `pdf` + `printing` 包 | 答题卡打印输出 |
| 图表 | `fl_chart` | 柱状图 + 正确率饼图 |
| 状态管理 | `provider` | 轻量够用 |
| 文件操作 | `path_provider` + `open_filex` | 本地路径 + 打开文件 |

## 三、分层架构

```
UI 层 (pages/)
  扫描首页 · 模板管理 · 成绩统计 · 班级管理 · 
  数据导出 · 设置(版本更新) · [错题本入口·置灰预留]

业务逻辑层 (services/)
  OMR识别引擎 · 成绩计算 · 统计图表 · 模板引擎 · 
  PDF答题卡生成 · Excel导出 · 版本检测 · 标签关联预留

数据持久层 (models/ + database/)
  classes · students · paper_templates · scan_records ·
  knowledge_tags(预留) · wrong_questions(预留) · app_version

能力层 (utils/)
  文档扫描 · 图像灰度+采样 · 文件IO · PDF渲染 · 分享
```

## 四、核心数据流

```
1. 模板配置 → 生成答题卡PDF → 打印
2. 教师录入标准答案 (扫描母版 / Excel导入)
3. 学生填涂答题卡 → APP拍照/选图 → 文档扫描矫正 → 灰度化
4. 定位四角标记 → 计算坐标网格 → 学号区4列识别(0-9) → 答题区逐题采样
5. 灰度阈值判定填涂 → 与标准答案比对 → 计分 → 存入 scan_records
6. 查看：成绩统计图表 / 学号筛选 / 导出Excel
```

## 五、答题卡模板布局（半张 A4 = 148mm × 210mm）

```
┌──────────────────────────────────────┐
│  ■定位点   学号：[0][1][2][3]    ■定位点│
│               [4][5][6][7]            │
│               [8][9] (4列×10行数字)    │
│  姓名：______________  班级：________  │
│  1 [A][B][C][D]   11 [A][B][C][D]    │
│  2 [A][B][C][D]   12 [A][B][C][D]    │
│  ... (5列排列，20题=4行，50题=10行)    │
│  ■定位点                         ■定位点│
└──────────────────────────────────────┘
```

- 四角定位标记: 12×12mm 黑色方块，用于透视矫正 + 坐标原点
- 学号区: 4 列 × 10 行（数字 0-9），独立于答题区
- 答题区: 每题一行，选项水平排列，5列/行紧凑布局
- 内置模板: 20题 / 30题 / 50题 / 100题
- 判断题: 选项简化为 [✓] [✗] 两个气泡，题型在模板配置中标记

## 六、OMR 识别算法

1. 文档扫描: flutter_document_scanner 自动检测边缘 → 四点透视矫正 → 输出正视图
2. 定位标记检测: 在四角区域搜索最大黑色连通域 → 确定坐标原点与缩放比例
3. 学号识别: 4列×10行网格 → 每格采样中心区域灰度均值 → 最暗格=填涂数字
4. 答题识别: 每题按模板配置的网格坐标 → 每选项采样 5×5 像素均值 → 阈值判定
5. 阈值: 自适应（整张卡灰度分布取 40% 分位作为填涂阈值）

## 七、数据库设计

```sql
-- 班级表
CREATE TABLE classes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL UNIQUE,
  created_at TEXT NOT NULL
);

-- 学生表
CREATE TABLE students (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  student_id TEXT NOT NULL,  -- 4位学号
  name TEXT NOT NULL,
  class_id INTEGER NOT NULL REFERENCES classes(id),
  UNIQUE(student_id, class_id)
);

-- 答题卡模板表
CREATE TABLE paper_templates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  question_count INTEGER NOT NULL,
  option_count INTEGER NOT NULL,  -- 4=ABCD, 2=判断
  layout_config_json TEXT NOT NULL,  -- 网格坐标、每题题型、知识点预留
  created_at TEXT NOT NULL
);

-- 扫描记录表
CREATE TABLE scan_records (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  student_id TEXT NOT NULL,
  student_name TEXT,
  template_id INTEGER NOT NULL,
  class_name TEXT,
  scan_time TEXT NOT NULL,
  total_score REAL NOT NULL,
  max_score REAL NOT NULL,
  answer_json TEXT NOT NULL,        -- [{q:1, ans:"A", correct:true}, ...]
  standard_answer_json TEXT NOT NULL,
  image_path TEXT,
  FOREIGN KEY (template_id) REFERENCES paper_templates(id)
);

-- 知识点标签表（二期使用）
CREATE TABLE knowledge_tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tag_name TEXT NOT NULL UNIQUE
);

-- 错题记录表（二期使用）
CREATE TABLE wrong_questions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  student_id TEXT NOT NULL,
  record_id INTEGER NOT NULL,
  template_id INTEGER NOT NULL,
  question_index INTEGER NOT NULL,
  tag_ids TEXT,
  wrong_answer TEXT,
  correct_answer TEXT,
  wrong_count INTEGER DEFAULT 1,
  last_wrong_time TEXT
);

-- 版本缓存表
CREATE TABLE app_version (
  id INTEGER PRIMARY KEY,
  current_version TEXT NOT NULL,
  latest_version TEXT,
  apk_url TEXT,
  update_info TEXT,
  last_check_time TEXT
);
```

## 八、标准答案录入（两条路径）

1. **扫描母版**: 教师填涂一份答题卡（学号区 0000 为母版标识），APP 识别提取 standard_json
2. **Excel 导入**: 列格式 `题号 | 题型 | 知识点(可选) | 标准答案`，支持 .xlsx/.csv

## 九、一期交付范围

| 模块 | 状态 |
|---|---|
| 班级管理（CRUD + 学生花名册） | ✅ 完整 |
| 答题卡模板（4种内置 + PDF生成打印） | ✅ 完整 |
| 拍照扫描 + OMR识别（单选+判断） | ✅ 完整 |
| 学号 4位气泡识别 | ✅ 完整 |
| 标准答案（扫描母版 + Excel导入） | ✅ 完整 |
| 成绩统计图表 + 学号筛选 | ✅ 完整 |
| Excel 成绩导出 | ✅ 完整 |
| 每题知识点/题型标签（DB字段预埋） | ✅ 字段预留 |
| 错题本 UI 入口（置灰） | ✅ 入口预留 |
| 版本更新检测 + APK下载 | ✅ 基础逻辑 |
| 网络权限默认关闭 | ✅ |

## 十、二期迭代（不纳入当前开发）

- 完整错题本页面：按学号/知识点汇总，重复做错统计
- 知识点薄弱项分析 + 专项错题导出
- 可选配套更新后台
- 自定义模板编辑器

## 十一、稳定性约束

- 单张识别 ≤ 1.5s（中端机型）
- 连续扫描无内存泄漏
- APK ≤ 30MB
- Android 7.0+ 兼容
- 数据库自动备份（导出时附带 .db 备份）
- 更新模块与阅卷逻辑完全解耦
