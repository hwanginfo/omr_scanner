import 'dart:convert';
import 'dart:math';

/// Generates layout coordinates for all built-in answer sheet templates.
/// Coordinates are relative to a normalized canvas (0..1, 0..1).
class TemplateEngine {
  // Fixed template sizes
  static const List<Map<String, dynamic>> builtInTemplates = [
    {'name': '20题 (单选)', 'count': 20, 'options': 4, 'type': 'single'},
    {'name': '30题 (单选)', 'count': 30, 'options': 4, 'type': 'single'},
    {'name': '50题 (单选)', 'count': 50, 'options': 4, 'type': 'single'},
    {'name': '100题 (单选)', 'count': 100, 'options': 4, 'type': 'single'},
    {'name': '20题 (判断)', 'count': 20, 'options': 2, 'type': 'judge'},
    {'name': '50题 (判断)', 'count': 50, 'options': 2, 'type': 'judge'},
  ];

  /// Layout constants (normalized to 0..1)
  static const double cornerSize = 0.04; // Corner marker size
  static const double cornerMargin = 0.02; // Margin from edge to corner
  static const double studentIdTop = 0.05; // Student ID section top
  static const double studentIdHeight = 0.17; // Student ID section height
  static const double studentIdLeft = 0.08; // Student ID section left
  static const double answerStartTop = 0.25; // Answer section start
  static const double answerBottomMargin = 0.07; // Answer section bottom margin
  static const int columnsPerRow = 5; // Questions per row
  static const int bubblesPerColumn = 4;

  /// Generate layout config for a template.
  static Map<String, dynamic> generateLayoutConfig({
    required int questionCount,
    required int optionCount,
    String questionType = 'single',
  }) {
    final rows = (questionCount / columnsPerRow).ceil();
    final questions = <Map<String, dynamic>>[];

    const double answerAreaHeight = 1.0 - answerStartTop - answerBottomMargin;
    final rowHeight = answerAreaHeight / rows;
    const double colWidth = (1.0 - 0.06) / columnsPerRow;
    const double leftMargin = 0.03;
    final effectiveOptionCount = max(optionCount, 4);

    for (int i = 0; i < questionCount; i++) {
      final row = i ~/ columnsPerRow;
      final col = i % columnsPerRow;

      final cellLeft = leftMargin + col * colWidth;
      final cellTop = answerStartTop + row * rowHeight;

      final bubbles = <Map<String, dynamic>>[];
      for (int b = 0; b < optionCount; b++) {
        final bubbleCenterX = cellLeft +
            (b + 0.5) * (colWidth - 0.01) / effectiveOptionCount;
        final bubbleCenterY = cellTop + rowHeight * 0.45;
        bubbles.add({
          'cx': bubbleCenterX,
          'cy': bubbleCenterY,
          'radius': colWidth / (effectiveOptionCount * 2) * 0.6,
          'label': optionCount == 2
              ? (b == 0 ? 'T' : 'F')
              : String.fromCharCode(65 + b),
        });
      }

      questions.add({
        'qi': i, // 0-based index
        'row': row,
        'col': col,
        'bubbles': bubbles,
        'qid': '', // reserved for question ID
        'ktag': '', // reserved for knowledge tag
        'qtype': optionCount == 2 ? 'judge' : 'single',
        'score': 1.0,
      });
    }

    // Student ID digit positions: 4 columns, 10 rows (0-9)
    final studentIdDigits = <Map<String, dynamic>>[];
    const int numDigitCols = 4;
    const int numDigitRows = 10;
    const double digitColWidth = (1.0 - studentIdLeft * 2) / numDigitCols;
    const double digitRowHeight = studentIdHeight / numDigitRows;
    const double digitTop = studentIdTop;

    for (int col = 0; col < numDigitCols; col++) {
      final digitList = <Map<String, dynamic>>[];
      for (int row = 0; row < numDigitRows; row++) {
        final cx = studentIdLeft + (col + 0.5) * digitColWidth;
        final cy = digitTop + (row + 0.5) * digitRowHeight;
        digitList.add({
          'digit': row,
          'cx': cx,
          'cy': cy,
          'radius': digitColWidth * 0.35,
        });
      }
      studentIdDigits.add({'col': col, 'digits': digitList});
    }

    return {
      'question_count': questionCount,
      'option_count': optionCount,
      'columns_per_row': columnsPerRow,
      'rows': rows,
      'questions': questions,
      'student_id_digits': studentIdDigits,
      'corner_size': cornerSize,
      'corner_margin': cornerMargin,
    };
  }

  /// Get all built-in template definitions.
  static List<Map<String, dynamic>> getBuiltInTemplateDefs() {
    return builtInTemplates.map((t) {
      final config = generateLayoutConfig(
        questionCount: t['count'] as int,
        optionCount: t['options'] as int,
        questionType: t['type'] as String,
      );
      return {
        'name': t['name'] as String,
        'question_count': t['count'] as int,
        'option_count': t['options'] as int,
        'layout_config_json': jsonEncode(config),
      };
    }).toList();
  }
}
