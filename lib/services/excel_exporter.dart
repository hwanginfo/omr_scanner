import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import '../models/models.dart';

class ExcelExporter {
  static Future<String> exportSingleRecord({
    required ScanRecord record,
    required String templateName,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['阅卷结果'];
    _buildHeaderRow(sheet);
    _buildRecordRow(sheet, record, templateName);
    return await _saveExcel(excel, 'scan_${record.studentId}_${record.id}.xlsx');
  }

  static Future<String> exportBatch({
    required List<ScanRecord> records,
    required Map<int, String> templateNames,
    String? fileName,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel['阅卷结果'];
    _buildHeaderRow(sheet);
    for (final record in records) {
      _buildRecordRow(sheet, record, templateNames[record.templateId] ?? '');
    }
    final name = fileName ?? 'batch_export_${DateTime.now().millisecondsSinceEpoch}.xlsx';
    return await _saveExcel(excel, name);
  }

  static void _buildHeaderRow(Sheet sheet) {
    sheet.appendRow([
      '学号', '姓名', '班级', '答题卡模板', '扫描时间',
      '总分', '满分', '正确数', '总题数', '每题作答详情',
    ]);
  }

  static void _buildRecordRow(Sheet sheet, ScanRecord record, String templateName) {
    final decoded = jsonDecode(record.answerJson) as List<dynamic>;
    final answerList = decoded.cast<Map<String, dynamic>>();
    final answers = answerList
        .map((m) {
          return 'Q${m['q']}=${m['ans']}(${m['correct'] == true ? '✓' : '✗'})';
        })
        .join('; ');
    final totalCount = answerList.length;
    final correctCount = answerList
        .where((m) => m['correct'] == true)
        .length;

    sheet.appendRow([
      record.studentId,
      record.studentName ?? '',
      record.className ?? '',
      templateName,
      record.scanTime,
      record.totalScore.toStringAsFixed(1),
      record.maxScore.toStringAsFixed(0),
      '$correctCount',
      '$totalCount',
      answers.length > 500 ? '${answers.substring(0, 500)}...' : answers,
    ]);
  }

  static Future<String> _saveExcel(Excel excel, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final filePath = '${dir.path}/$fileName';
    final file = File(filePath);
    await file.writeAsBytes(excel.encode()!);
    return filePath;
  }

  static Future<String> getExportPath(String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/$fileName';
  }
}
