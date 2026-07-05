import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_document_scanner/flutter_document_scanner.dart';
import 'package:provider/provider.dart';
import '../main.dart' show MyAppState;
import '../database/database_helper.dart';
import '../models/models.dart';
import '../services/omr_engine.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _db = DatabaseHelper();
  List<Map<String, dynamic>> _templates = [];
  List<Map<String, dynamic>> _recentRecords = [];
  Map<String, dynamic>? _selectedTemplate;
  bool _isScanning = false;
  String? _lastStudentId;
  String? _lastScore;
  bool _showScanner = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final templates = await _db.getTemplates();
    final records = await _db.getScanRecords(limit: 20);
    if (!mounted) return;
    setState(() {
      _templates = templates;
      _recentRecords = records;
      if (templates.isNotEmpty && _selectedTemplate == null) {
        _selectedTemplate = templates.first;
      }
    });
  }

  void _startScan() {
    if (_selectedTemplate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先在模板管理中创建答题卡模板')),
      );
      return;
    }
    setState(() => _showScanner = true);
  }

  Future<void> _onImageCaptured(Uint8List imageBytes) async {
    setState(() {
      _showScanner = false;
      _isScanning = true;
    });

    try {
      // Run OMR recognition in background isolate
      final layoutConfig = jsonDecode(
          _selectedTemplate!['layout_config_json'] as String);
      final resultMap = await OmrEngine.scanIsolate({
        'image_bytes': imageBytes,
        'layout_config': layoutConfig,
      });
      final result = OmrScanResult.fromMap(resultMap);

      if (!result.success) {
        _showError(result.error ?? '识别失败');
        setState(() => _isScanning = false);
        return;
      }

      // Handle master sheet
      if (result.isMasterSheet) {
        final standardJson = jsonEncode(result.answers);
        await _db.updateTemplateStandardAnswer(
          _selectedTemplate!['id'] as int,
          standardJson,
        );
        _showSuccess('标准答案已录入！共 ${result.answers.length} 题');
        setState(() => _isScanning = false);
        return;
      }

      // Compare with standard answer
      final standardJson =
          _selectedTemplate!['standard_answer_json'] as String?;
      Map<String, dynamic> comparison;
      if (standardJson != null && standardJson.isNotEmpty) {
        final standardAnswers =
            (jsonDecode(standardJson) as List<dynamic>)
                .cast<Map<String, dynamic>>();
        comparison = OmrEngine.compareWithStandard(
          answers: result.answers,
          standardAnswers: standardAnswers,
          layoutConfig: layoutConfig,
        );
      } else {
        comparison = {
          'results': result.answers,
          'total_score': 0,
          'max_score': result.answers.length.toDouble(),
          'correct_count': 0,
          'total_count': result.answers.length,
        };
      }

      // Look up student name
      String? studentName;
      String? className;
      final classes = await _db.getClasses();
      for (final c in classes) {
        final student = await _db.getStudentByStudentId(
            result.studentId, c['id'] as int);
        if (student != null) {
          studentName = student['name'] as String;
          className = c['name'] as String;
          break;
        }
      }

      // Save record
      final record = ScanRecord(
        studentId: result.studentId,
        studentName: studentName,
        templateId: _selectedTemplate!['id'] as int,
        className: className,
        scanTime: DateTime.now().toIso8601String(),
        totalScore: (comparison['total_score'] as num).toDouble(),
        maxScore: (comparison['max_score'] as num).toDouble(),
        answerJson: jsonEncode(comparison['results']),
        standardAnswerJson: standardJson ?? '[]',
        imagePath: null,
      );
      await _db.insertScanRecord(record.toMap());

      if (!mounted) return;
      setState(() {
        _lastStudentId = result.studentId;
        _lastScore =
            '${comparison['total_score']} / ${comparison['max_score']}';
        _isScanning = false;
      });

      _showResultDialog(
        studentId: result.studentId,
        studentName: studentName,
        score: '${comparison['total_score']}',
        maxScore: '${comparison['max_score']}',
        correctCount: '${comparison['correct_count']}',
        totalCount: '${comparison['total_count']}',
        results: (comparison['results'] as List<dynamic>)
            .cast<Map<String, dynamic>>(),
      );

      _loadData();
    } catch (e) {
      _showError('扫描失败: $e');
      setState(() => _isScanning = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green));
  }

  void _showResultDialog({
    required String studentId,
    String? studentName,
    required String score,
    required String maxScore,
    required String correctCount,
    required String totalCount,
    required List<Map<String, dynamic>> results,
  }) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('识别结果'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _resultRow('学号', studentId),
              if (studentName != null) _resultRow('姓名', studentName),
              _resultRow('成绩', '$score / $maxScore'),
              _resultRow('正确率',
                  '${((int.tryParse(correctCount) ?? 0) / (int.tryParse(totalCount) ?? 1) * 100).toStringAsFixed(1)}%'),
              const Divider(),
              ...results.take(10).map((r) => Text(
                    '第${r['q']}题: ${r['ans'] ?? '?'} ${r['correct'] == true ? '✓' : '✗'}',
                    style: TextStyle(
                      fontSize: 12,
                      color: r['correct'] == true ? Colors.green : Colors.red,
                    ),
                  )),
              if (results.length > 10)
                const Text('... 更多结果', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _startScan();
            },
            child: const Text('继续扫描'),
          ),
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text('$label:', style: const TextStyle(color: Colors.grey))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // If scanner is active, show it fullscreen
    if (_showScanner) {
      return Scaffold(
        body: DocumentScanner(
          onSave: _onImageCaptured,
          generalStyles: const GeneralStyles(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('OMR 答题卡阅卷'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.pushNamed(context, '/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Template selector
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Text('答题卡: ', style: TextStyle(fontSize: 14)),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _selectedTemplate?['id'] as int?,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _templates.map((t) {
                      final hasAnswer = t['standard_answer_json'] != null &&
                          (t['standard_answer_json'] as String).isNotEmpty;
                      return DropdownMenuItem<int>(
                        value: t['id'] as int,
                        child: Text(
                          '${t['name']}${hasAnswer ? ' ✓' : ''}',
                          style: const TextStyle(fontSize: 13),
                        ),
                      );
                    }).toList(),
                    onChanged: (id) {
                      setState(() {
                        _selectedTemplate = _templates.firstWhere((t) => t['id'] == id);
                      });
                    },
                  ),
                ),
              ],
            ),
          ),

          // Last scan result
          if (_lastStudentId != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('上次扫描: 学号 $_lastStudentId',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (_lastScore != null)
                        Text('成绩: $_lastScore',
                            style: TextStyle(color: Colors.green.shade700)),
                    ],
                  ),
                  const Icon(Icons.check_circle, color: Colors.green),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // Recent records
          Expanded(
            child: _recentRecords.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.document_scanner, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text('暂无扫描记录', style: TextStyle(color: Colors.grey.shade600)),
                        const SizedBox(height: 4),
                        Text('点击下方按钮开始扫描',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _recentRecords.length,
                    itemBuilder: (ctx, i) {
                      final r = _recentRecords[i];
                      return Card(
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.blue.shade100,
                            child: Text(
                              '${r['student_id']}'.substring(0, 3),
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                          title: Text(
                            '学号: ${r['student_id']} ${r['student_name'] ?? ''}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            '${r['scan_time']} · ${r['total_score']}/${r['max_score']}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isScanning ? null : _startScan,
        icon: _isScanning
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.camera_alt),
        label: Text(_isScanning ? '识别中...' : '扫描答题卡'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: context.watch<MyAppState>().currentTabIndex,
        onTap: (i) {
          context.read<MyAppState>().setTab(i);
          switch (i) {
            case 0:
              break;
            case 1:
              Navigator.pushNamed(context, '/class-management');
              break;
            case 2:
              Navigator.pushNamed(context, '/template-management');
              break;
            case 3:
              Navigator.pushNamed(context, '/statistics');
              break;
          }
        },
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 11,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: '扫描'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: '班级'),
          BottomNavigationBarItem(icon: Icon(Icons.description), label: '模板'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: '统计'),
        ],
      ),
    );
  }
}
