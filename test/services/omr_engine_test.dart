import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

// Import the OMR engine
// Note: omr_engine.dart uses dart:isolate which is not available in test runner
// We test the synchronous parts directly
import 'package:omr_scanner/services/omr_engine.dart';

void main() {
  group('OmrScanResult serialization', () {
    test('toMap / fromMap round-trip with success', () {
      final result = OmrScanResult(
        success: true,
        studentId: '1234',
        answers: [
          {'qi': 0, 'ans': 'A', 'score': 1.0},
          {'qi': 1, 'ans': 'B', 'score': 1.0},
        ],
        totalScore: 2.0,
        maxScore: 2.0,
      );

      final map = result.toMap();
      final restored = OmrScanResult.fromMap(map);

      expect(restored.success, true);
      expect(restored.studentId, '1234');
      expect(restored.answers.length, 2);
      expect(restored.answers[0]['ans'], 'A');
      expect(restored.answers[1]['ans'], 'B');
      expect(restored.totalScore, 2.0);
      expect(restored.maxScore, 2.0);
      expect(restored.isMasterSheet, false);
    });

    test('toMap / fromMap round-trip with error', () {
      final result = OmrScanResult(
        success: false,
        error: '无法检测到四角定位标记',
      );

      final map = result.toMap();
      final restored = OmrScanResult.fromMap(map);

      expect(restored.success, false);
      expect(restored.error, '无法检测到四角定位标记');
      expect(restored.isMasterSheet, true); // default studentId '0000'
    });

    test('isMasterSheet with studentId 0000', () {
      final result = OmrScanResult(
        success: true,
        studentId: '0000',
        answers: [],
        totalScore: 0,
        maxScore: 10,
      );
      expect(result.isMasterSheet, true);
    });

    test('isMasterSheet with non-zero studentId', () {
      final result = OmrScanResult(
        success: true,
        studentId: '0105',
      );
      expect(result.isMasterSheet, false);
    });
  });

  group('OmrEngine.compareWithStandard', () {
    test('all answers correct', () {
      final List<Map<String, dynamic>> answers = [
        <String, dynamic>{'qi': 0, 'ans': 'A', 'score': 1.0},
        <String, dynamic>{'qi': 1, 'ans': 'B', 'score': 1.0},
        <String, dynamic>{'qi': 2, 'ans': 'C', 'score': 1.0},
      ];
      final List<Map<String, dynamic>> standardAnswers = [
        <String, dynamic>{'qi': 0, 'ans': 'A'},
        <String, dynamic>{'qi': 1, 'ans': 'B'},
        <String, dynamic>{'qi': 2, 'ans': 'C'},
      ];
      final Map<String, dynamic> layoutConfig = <String, dynamic>{
        'questions': [
          <String, dynamic>{'qi': 0, 'score': 1.0, 'qid': '', 'ktag': '', 'qtype': 'single'},
          <String, dynamic>{'qi': 1, 'score': 1.0, 'qid': '', 'ktag': '', 'qtype': 'single'},
          <String, dynamic>{'qi': 2, 'score': 1.0, 'qid': '', 'ktag': '', 'qtype': 'single'},
        ],
      };

      final comparison = OmrEngine.compareWithStandard(
        answers: answers,
        standardAnswers: standardAnswers,
        layoutConfig: layoutConfig,
      );

      expect(comparison['correct_count'], 3);
      expect(comparison['total_count'], 3);
      expect(comparison['total_score'], 3.0);
      expect(comparison['max_score'], 3.0);
      final results = comparison['results'] as List;
      expect(results.every((r) => r['correct'] == true), true);
    });

    test('mixed correct and incorrect answers', () {
      final List<Map<String, dynamic>> answers = [
        <String, dynamic>{'qi': 0, 'ans': 'A', 'score': 1.0},
        <String, dynamic>{'qi': 1, 'ans': 'B', 'score': 1.0},
        <String, dynamic>{'qi': 2, 'ans': 'C', 'score': 1.0},
      ];
      final List<Map<String, dynamic>> standardAnswers = [
        <String, dynamic>{'qi': 0, 'ans': 'A'},
        <String, dynamic>{'qi': 1, 'ans': 'X'},
        <String, dynamic>{'qi': 2, 'ans': 'Z'},
      ];
      final layoutConfig = {
        'questions': [
          {'qi': 0, 'score': 1.5, 'qid': '', 'ktag': '', 'qtype': 'single'},
          {'qi': 1, 'score': 1.5, 'qid': '', 'ktag': '', 'qtype': 'single'},
          {'qi': 2, 'score': 2.0, 'qid': '', 'ktag': '', 'qtype': 'single'},
        ],
      };

      final comparison = OmrEngine.compareWithStandard(
        answers: answers,
        standardAnswers: standardAnswers,
        layoutConfig: layoutConfig,
      );

      expect(comparison['correct_count'], 1);
      expect(comparison['total_count'], 3);
      expect((comparison['total_score'] as num).toDouble(), 1.5);
      expect((comparison['max_score'] as num).toDouble(), 5.0);
    });

    test('all answers wrong', () {
      final List<Map<String, dynamic>> answers = [
        <String, dynamic>{'qi': 0, 'ans': 'A', 'score': 1.0},
        <String, dynamic>{'qi': 1, 'ans': 'B', 'score': 1.0},
      ];
      final List<Map<String, dynamic>> standardAnswers = [
        <String, dynamic>{'qi': 0, 'ans': 'C'},
        <String, dynamic>{'qi': 1, 'ans': 'D'},
      ];
      final layoutConfig = {
        'questions': [
          {'qi': 0, 'score': 1.0, 'qid': '', 'ktag': '', 'qtype': 'single'},
          {'qi': 1, 'score': 1.0, 'qid': '', 'ktag': '', 'qtype': 'single'},
        ],
      };

      final comparison = OmrEngine.compareWithStandard(
        answers: answers,
        standardAnswers: standardAnswers,
        layoutConfig: layoutConfig,
      );

      expect(comparison['correct_count'], 0);
      expect(comparison['total_score'], 0.0);
      expect(comparison['total_count'], 2);
    });

    test('unanswered questions (marked as ?)', () {
      final List<Map<String, dynamic>> answers = [
        <String, dynamic>{'qi': 0, 'ans': '?', 'score': 0.0},
        <String, dynamic>{'qi': 1, 'ans': 'B', 'score': 1.0},
      ];
      final List<Map<String, dynamic>> standardAnswers = [
        <String, dynamic>{'qi': 0, 'ans': 'A'},
        <String, dynamic>{'qi': 1, 'ans': 'B'},
      ];
      final layoutConfig = {
        'questions': [
          {'qi': 0, 'score': 1.0, 'qid': '', 'ktag': '', 'qtype': 'single'},
          {'qi': 1, 'score': 1.0, 'qid': '', 'ktag': '', 'qtype': 'single'},
        ],
      };

      final comparison = OmrEngine.compareWithStandard(
        answers: answers,
        standardAnswers: standardAnswers,
        layoutConfig: layoutConfig,
      );

      expect(comparison['correct_count'], 1);
      expect(comparison['total_count'], 2);
      expect(comparison['total_score'], 1.0);
    });

    test('with knowledge tags and question types', () {
      final List<Map<String, dynamic>> answers = [
        <String, dynamic>{'qi': 0, 'ans': 'T', 'score': 1.0},
        <String, dynamic>{'qi': 1, 'ans': 'F', 'score': 1.0},
      ];
      final List<Map<String, dynamic>> standardAnswers = [
        <String, dynamic>{'qi': 0, 'ans': 'T'},
        <String, dynamic>{'qi': 1, 'ans': 'T'},
      ];
      final layoutConfig = {
        'questions': [
          {'qi': 0, 'score': 1.0, 'qid': 'Q001', 'ktag': '一次函数', 'qtype': 'judge'},
          {'qi': 1, 'score': 1.0, 'qid': 'Q002', 'ktag': '几何', 'qtype': 'judge'},
        ],
      };

      final comparison = OmrEngine.compareWithStandard(
        answers: answers,
        standardAnswers: standardAnswers,
        layoutConfig: layoutConfig,
      );

      final results = comparison['results'] as List;
      expect(results[0]['correct'], true);
      expect(results[0]['ktag'], '一次函数');
      expect(results[0]['qtype'], 'judge');
      expect(results[1]['correct'], false);
      expect(results[1]['ktag'], '几何');
    });
  });

  group('OmrEngine.downsampleForTest', () {
    test('downsamples large image to max 1600px longest side', () {
      // _downsampleForTest only reads width/height, not pixel data
      final src = img.Image(width: 4000, height: 3000);
      final resized = OmrEngine.downsampleForTest(src, 1600);
      expect(resized.width, 1600);
      expect(resized.height, 1200);
    });

    test('no downsampling when image is smaller than max', () {
      final src = img.Image(width: 800, height: 600);
      final resized = OmrEngine.downsampleForTest(src, 1600);
      expect(resized.width, 800);
      expect(resized.height, 600);
    });

    test('downsamples portrait image correctly', () {
      final src = img.Image(width: 2000, height: 4000);
      final resized = OmrEngine.downsampleForTest(src, 1600);
      expect(resized.width, 800);
      expect(resized.height, 1600);
    });
  });
}
