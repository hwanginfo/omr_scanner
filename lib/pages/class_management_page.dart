import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../database/database_helper.dart';

class ClassManagementPage extends StatefulWidget {
  const ClassManagementPage({super.key});

  @override
  State<ClassManagementPage> createState() => _ClassManagementPageState();
}

class _ClassManagementPageState extends State<ClassManagementPage> {
  final _db = DatabaseHelper();
  List<Map<String, dynamic>> _classes = [];
  Map<int, List<Map<String, dynamic>>> _studentsByClass = {};
  int? _selectedClassId;
  final _classNameController = TextEditingController();
  final _studentIdController = TextEditingController();
  final _studentNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    final classes = await _db.getClasses();
    final studentsByClass = <int, List<Map<String, dynamic>>>{};
    for (final c in classes) {
      final id = c['id'] as int;
      studentsByClass[id] = await _db.getStudentsByClass(id);
    }
    setState(() {
      _classes = classes;
      _studentsByClass = studentsByClass;
    });
  }

  Future<void> _addClass() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加班级'),
        content: TextField(
          controller: _classNameController,
          decoration: const InputDecoration(hintText: '班级名称，如: 高三(1)班'),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _classNameController.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await _db.insertClass({
        'name': name,
        'created_at': DateTime.now().toIso8601String(),
      });
      _classNameController.clear();
      _loadClasses();
    }
  }

  Future<void> _deleteClass(int id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('删除班级将同时删除该班级下所有学生，确定继续？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _db.deleteStudentsByClass(id);
      await _db.deleteClass(id);
      _loadClasses();
    }
  }

  Future<void> _addStudent(int classId) async {
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) {
        final idCtrl = TextEditingController();
        final nameCtrl = TextEditingController();
        return AlertDialog(
          title: const Text('添加学生'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idCtrl,
                decoration: const InputDecoration(hintText: '4位学号，如: 0105'),
                keyboardType: TextInputType.number,
                maxLength: 4,
              ),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(hintText: '学生姓名'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () {
                final id = idCtrl.text.padLeft(4, '0');
                final name = nameCtrl.text;
                if (id.length == 4 && name.isNotEmpty) {
                  Navigator.pop(ctx, {'id': id, 'name': name});
                }
              },
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (result != null) {
      try {
        await _db.insertStudent({
          'student_id': result['id']!,
          'name': result['name']!,
          'class_id': classId,
        });
        _loadClasses();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('添加失败: 学号可能已存在'),
                backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _deleteStudent(int id) async {
    await _db.deleteStudent(id);
    _loadClasses();
  }

  Future<void> _importStudents(int classId) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.first.path!);
      final content = await file.readAsString();
      final csvData = const CsvToListConverter().convert(content);

      int added = 0;
      for (final row in csvData.skip(1)) {
        // Skip header
        if (row.length < 2) continue;
        final id = row[0].toString().padLeft(4, '0');
        final name = row[1].toString();
        if (id.length == 4 && name.isNotEmpty) {
          try {
            await _db.insertStudent({
              'student_id': id,
              'name': name,
              'class_id': classId,
            });
            added++;
          } catch (_) {
            // Skip duplicates
          }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('成功导入 $added 名学生'),
              backgroundColor: Colors.green),
        );
      }
      _loadClasses();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('班级管理'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _addClass,
            tooltip: '添加班级',
          ),
        ],
      ),
      body: _classes.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('暂无班级', style: TextStyle(color: Colors.grey)),
                  Text('点击右上角 + 添加班级',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _classes.length,
              itemBuilder: (ctx, i) {
                final c = _classes[i];
                final classId = c['id'] as int;
                final students = _studentsByClass[classId] ?? [];
                final isExpanded = _selectedClassId == classId;

                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ExpansionTile(
                    initiallyExpanded: isExpanded,
                    onExpansionChanged: (expanded) {
                      setState(() {
                        _selectedClassId = expanded ? classId : null;
                      });
                    },
                    leading: const Icon(Icons.school),
                    title: Text(c['name'] as String,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle:
                        Text('${students.length} 名学生', style: const TextStyle(fontSize: 12)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.file_upload, size: 18),
                          onPressed: () => _importStudents(classId),
                          tooltip: '导入CSV',
                        ),
                        IconButton(
                          icon:
                              const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          onPressed: () => _deleteClass(classId),
                        ),
                      ],
                    ),
                    children: [
                      // Add student row
                      ListTile(
                        leading: const Icon(Icons.person_add, size: 18),
                        title: const Text('添加学生', style: TextStyle(fontSize: 13)),
                        onTap: () => _addStudent(classId),
                      ),
                      const Divider(height: 1),
                      // Student list
                      if (students.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('暂无学生，点击上方添加或导入CSV',
                              style: TextStyle(color: Colors.grey, fontSize: 12)),
                        )
                      else
                        ...students.map((s) => ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                radius: 12,
                                backgroundColor: Colors.blue.shade100,
                                child: Text(
                                  (s['student_id'] as String).substring(2, 4),
                                  style: const TextStyle(fontSize: 9),
                                ),
                              ),
                              title: Text(
                                s['name'] as String,
                                style: const TextStyle(fontSize: 13),
                              ),
                              subtitle: Text(
                                '学号: ${s['student_id']}',
                                style: const TextStyle(fontSize: 11),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete, size: 16),
                                onPressed: () => _deleteStudent(s['id'] as int),
                              ),
                            )),
                    ],
                  ),
                );
              },
            ),
    );
  }

  @override
  void dispose() {
    _classNameController.dispose();
    _studentIdController.dispose();
    _studentNameController.dispose();
    super.dispose();
  }
}
