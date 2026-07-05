import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';

/// Generates printable answer sheet PDFs.
class PdfGenerator {
  // A5 landscape layout for compact answer sheets (half A4).
  static const double pageWidth = 210 * PdfPageFormat.mm;
  static const double pageHeight = 148 * PdfPageFormat.mm;

  /// Generate answer sheet PDF for a given layout config.
  static Future<String> generate({
    required Map<String, dynamic> layoutConfig,
    required String templateName,
    String? className,
    bool showAnswerField = false, // for master sheets
  }) async {
    final pdf = pw.Document();
    final questions = layoutConfig['questions'] as List<dynamic>? ?? [];
    final studentIdDigits =
        layoutConfig['student_id_digits'] as List<dynamic>? ?? [];

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(pageWidth, pageHeight),
        margin: pw.EdgeInsets.all(10),
        build: (context) {
          return pw.Stack(
            children: [
              // Corner markers
              _cornerMarker(-5, -5),
              _cornerMarker(pageWidth - 15, -5),
              _cornerMarker(-5, pageHeight - 15),
              _cornerMarker(pageWidth - 15, pageHeight - 15),

              // Main content
              pw.Positioned(
                left: 15,
                top: 5,
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // Title
                    if (showAnswerField)
                      pw.Text('【标准答案母版】 $templateName',
                          style: pw.TextStyle(
                              fontSize: 12, fontWeight: pw.FontWeight.bold))
                    else
                      pw.Text(templateName,
                          style: pw.TextStyle(
                              fontSize: 12, fontWeight: pw.FontWeight.bold)),

                    pw.SizedBox(height: 8),

                    // Student ID grid
                    _buildStudentIdGrid(studentIdDigits),
                    pw.SizedBox(height: 5),

                    // Name / Class fields
                    pw.Row(
                      children: [
                        pw.Text('姓名: ____________',
                            style: const pw.TextStyle(fontSize: 8)),
                        pw.SizedBox(width: 10),
                        pw.Text('班级: ____________',
                            style: const pw.TextStyle(fontSize: 8)),
                      ],
                    ),

                    pw.SizedBox(height: 5),

                    // Answer grid
                    _buildAnswerGrid(questions),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    final dir = await getApplicationDocumentsDirectory();
    final filePath =
        '${dir.path}/answer_sheet_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File(filePath);
    await file.writeAsBytes(await pdf.save());
    return filePath;
  }

  static pw.Widget _cornerMarker(double left, double top) {
    return pw.Positioned(
      left: left,
      top: top,
      child: pw.Container(
        width: 15,
        height: 15,
        color: PdfColors.black,
      ),
    );
  }

  static pw.Widget _buildStudentIdGrid(List<dynamic> digitCols) {
    const double cellSize = 12;
    const double fontSize = 7;

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('学号:  ',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        ...digitCols.map((col) {
          final colMap = col as Map<String, dynamic>;
          final digits = colMap['digits'] as List<dynamic>? ?? [];
          return pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 2),
            child: pw.Column(
              children: digits.map((d) {
                final dm = d as Map<String, dynamic>;
                final digit = dm['digit'] as int;
                return pw.Container(
                  width: cellSize,
                  height: cellSize * 0.75,
                  margin: const pw.EdgeInsets.all(0.5),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey, width: 0.5),
                  ),
                  child: pw.Center(
                    child: pw.Text('$digit', style: pw.TextStyle(fontSize: fontSize)),
                  ),
                );
              }).toList(),
            ),
          );
        }),
      ],
    );
  }

  static pw.Widget _buildAnswerGrid(List<dynamic> questions) {
    // Group questions by row
    final rows = <int, List<dynamic>>{};
    for (final q in questions) {
      final qm = q as Map<String, dynamic>;
      final row = qm['row'] as int;
      rows.putIfAbsent(row, () => []);
      rows[row]!.add(qm);
    }

    final sortedRows = rows.keys.toList()..sort();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: sortedRows.map((rowIdx) {
        final rowQuestions = rows[rowIdx]!;
        return pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: rowQuestions.map((q) {
            final qi = q['qi'] as int;
            final bubbles = q['bubbles'] as List<dynamic>? ?? [];

            return pw.Container(
              width: (pageWidth - 40) / 5,
              padding: const pw.EdgeInsets.symmetric(vertical: 1, horizontal: 1),
              child: pw.Row(
                children: [
                  pw.SizedBox(
                    width: 16,
                    child: pw.Text('${qi + 1}',
                        style: pw.TextStyle(fontSize: 6)),
                  ),
                  pw.SizedBox(width: 1),
                  ...bubbles.map((b) {
                    final bm = b as Map<String, dynamic>;
                    final label = bm['label'] as String;
                    return pw.Container(
                      width: 11,
                      height: 9,
                      margin: const pw.EdgeInsets.all(0.5),
                      decoration: pw.BoxDecoration(
                        border:
                            pw.Border.all(color: PdfColors.grey, width: 0.5),
                        borderRadius: pw.BorderRadius.circular(1),
                      ),
                      child: pw.Center(
                        child: pw.Text(label,
                            style: pw.TextStyle(fontSize: 5)),
                      ),
                    );
                  }),
                ],
              ),
            );
          }).toList(),
        );
      }).toList(),
    );
  }
}
