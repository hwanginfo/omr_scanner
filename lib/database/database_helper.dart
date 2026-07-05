import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'omr_scanner.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE classes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE students (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id TEXT NOT NULL,
        name TEXT NOT NULL,
        class_id INTEGER NOT NULL,
        FOREIGN KEY (class_id) REFERENCES classes(id),
        UNIQUE(student_id, class_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE paper_templates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        question_count INTEGER NOT NULL,
        option_count INTEGER NOT NULL,
        layout_config_json TEXT NOT NULL,
        standard_answer_json TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE scan_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        student_id TEXT NOT NULL,
        student_name TEXT,
        template_id INTEGER NOT NULL,
        class_name TEXT,
        scan_time TEXT NOT NULL,
        total_score REAL NOT NULL,
        max_score REAL NOT NULL,
        answer_json TEXT NOT NULL,
        standard_answer_json TEXT NOT NULL,
        image_path TEXT,
        FOREIGN KEY (template_id) REFERENCES paper_templates(id)
      )
    ''');

    // 预留：知识点标签表
    await db.execute('''
      CREATE TABLE knowledge_tags (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        tag_name TEXT NOT NULL UNIQUE
      )
    ''');

    // 预留：错题记录表
    await db.execute('''
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
      )
    ''');

    // 版本缓存表
    await db.execute('''
      CREATE TABLE app_version (
        id INTEGER PRIMARY KEY,
        current_version TEXT NOT NULL,
        latest_version TEXT,
        apk_url TEXT,
        update_info TEXT,
        last_check_time TEXT
      )
    ''');

    // 插入默认版本记录
    await db.insert('app_version', {
      'id': 1,
      'current_version': '1.0.0',
    });
  }

  // ---- 便捷查询方法 ----

  // Classes
  Future<List<Map<String, dynamic>>> getClasses() async {
    final db = await database;
    return db.query('classes', orderBy: 'created_at DESC');
  }

  Future<int> insertClass(Map<String, dynamic> row) async {
    final db = await database;
    return db.insert('classes', row);
  }

  Future<int> updateClass(int id, Map<String, dynamic> row) async {
    final db = await database;
    return db.update('classes', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteClass(int id) async {
    final db = await database;
    return db.delete('classes', where: 'id = ?', whereArgs: [id]);
  }

  // Students
  Future<List<Map<String, dynamic>>> getStudentsByClass(int classId) async {
    final db = await database;
    return db.query('students',
        where: 'class_id = ?', whereArgs: [classId], orderBy: 'student_id ASC');
  }

  Future<Map<String, dynamic>?> getStudentByStudentId(
      String studentId, int classId) async {
    final db = await database;
    final results = await db.query('students',
        where: 'student_id = ? AND class_id = ?',
        whereArgs: [studentId, classId],
        limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> insertStudent(Map<String, dynamic> row) async {
    final db = await database;
    return db.insert('students', row);
  }

  Future<int> updateStudent(int id, Map<String, dynamic> row) async {
    final db = await database;
    return db.update('students', row, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteStudent(int id) async {
    final db = await database;
    return db.delete('students', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteStudentsByClass(int classId) async {
    final db = await database;
    return db.delete('students', where: 'class_id = ?', whereArgs: [classId]);
  }

  // Paper Templates
  Future<List<Map<String, dynamic>>> getTemplates() async {
    final db = await database;
    return db.query('paper_templates', orderBy: 'created_at DESC');
  }

  Future<Map<String, dynamic>?> getTemplate(int id) async {
    final db = await database;
    final results =
        await db.query('paper_templates', where: 'id = ?', whereArgs: [id]);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> insertTemplate(Map<String, dynamic> row) async {
    final db = await database;
    return db.insert('paper_templates', row);
  }

  Future<int> updateTemplateStandardAnswer(
      int id, String standardAnswerJson) async {
    final db = await database;
    return db.update('paper_templates',
        {'standard_answer_json': standardAnswerJson},
        where: 'id = ?',
        whereArgs: [id]);
  }

  // Scan Records
  Future<int> insertScanRecord(Map<String, dynamic> row) async {
    final db = await database;
    return db.insert('scan_records', row);
  }

  Future<List<Map<String, dynamic>>> getScanRecords(
      {String? studentId, int? templateId, String? className, int? limit}) async {
    final db = await database;
    String? where;
    List<dynamic>? whereArgs;
    final conditions = <String>[];
    final args = <dynamic>[];

    if (studentId != null) {
      conditions.add('student_id = ?');
      args.add(studentId);
    }
    if (templateId != null) {
      conditions.add('template_id = ?');
      args.add(templateId);
    }
    if (className != null) {
      conditions.add('class_name = ?');
      args.add(className);
    }
    if (conditions.isNotEmpty) {
      where = conditions.join(' AND ');
      whereArgs = args;
    }
    return db.query('scan_records',
        where: where, whereArgs: whereArgs, orderBy: 'scan_time DESC', limit: limit);
  }

  Future<List<Map<String, dynamic>>> getRecordsByStudentId(
      String studentId) async {
    final db = await database;
    return db.query('scan_records',
        where: 'student_id = ?',
        whereArgs: [studentId],
        orderBy: 'scan_time DESC');
  }

  // App Version
  Future<Map<String, dynamic>?> getAppVersion() async {
    final db = await database;
    final results = await db.query('app_version', limit: 1);
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateAppVersion(Map<String, dynamic> row) async {
    final db = await database;
    return db.update('app_version', row, where: 'id = ?', whereArgs: [1]);
  }

  // 数据库备份导出路径
  Future<String> exportDatabase() async {
    final db = await database;
    final dbPath = db.path;
    return dbPath;
  }
}
