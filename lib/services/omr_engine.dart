import 'dart:isolate';
import 'dart:typed_data';
import 'package:meta/meta.dart';
import 'package:image/image.dart' as img;

/// OMR (Optical Mark Recognition) engine.
/// Works on pre-corrected (perspective-corrected) images.
class OmrEngine {
  /// Run OMR scan in a background isolate.
  /// [params] must contain: 'image_bytes' (Uint8List), 'layout_config' (Map).
  /// Returns a serializable Map (same shape as OmrScanResult.toMap()).
  static Future<Map<String, dynamic>> scanIsolate(
      Map<String, dynamic> params) async {
    return Isolate.run(() => _omrScanIsolateSync(params));
  }

  /// Synchronous isolate entry — decodes image, downsamples, runs recognition.
  static Map<String, dynamic> _omrScanIsolateSync(
      Map<String, dynamic> params) {
    final imageBytes = params['image_bytes'] as Uint8List;
    final layoutConfig = params['layout_config'] as Map<String, dynamic>;

    // 1. Decode image (inside isolate, does not block UI)
    final image = img.decodeImage(imageBytes);
    if (image == null) {
      return OmrScanResult(success: false, error: '无法加载图片').toMap();
    }

    // 2. Downsample for performance: target ~1600px on the longest side
    final downsampled = _downsampleImage(image, 1600);

    // 3. Run OMR recognition
    final result = scan(correctedImage: downsampled, layoutConfig: layoutConfig);
    return result.toMap();
  }

  /// Downsample image so the longest side does not exceed [maxPixels].
  static img.Image _downsampleImage(img.Image src, int maxPixels) {
    final w = src.width;
    final h = src.height;
    final longest = w > h ? w : h;
    if (longest <= maxPixels) return src;

    final scale = maxPixels / longest;
    final newW = (w * scale).round();
    final newH = (h * scale).round();
    return img.copyResize(src, width: newW, height: newH);
  }

  /// Test-only: expose _downsampleImage for unit testing.
  /// Visible via package-level access in test/ directory.
  @visibleForTesting
  static img.Image downsampleForTest(img.Image src, int maxPixels) =>
      _downsampleImage(src, maxPixels);

  /// Result of a full OMR scan.
  static OmrScanResult scan({
    required img.Image correctedImage,
    required Map<String, dynamic> layoutConfig,
  }) {
    // 1. Convert to grayscale
    final grayImg = img.grayscale(correctedImage);

    // 2. Detect corner markers → establish coordinate transform
    final corners = _detectCorners(grayImg);
    if (corners == null) {
      return OmrScanResult(
        success: false,
        error: '无法检测到四角定位标记，请确保答题卡完整清晰',
      );
    }

    // 3. Identify student ID (4-digit)
    final studentIdDigits =
        layoutConfig['student_id_digits'] as List<dynamic>?;
    String studentId = '0000';
    if (studentIdDigits != null) {
      studentId = _recognizeStudentId(grayImg, studentIdDigits, corners);
    }

    // 4. Recognize answers
    final questions = layoutConfig['questions'] as List<dynamic>? ?? [];
    final answers = <Map<String, dynamic>>[];
    double totalScore = 0;
    double maxScore = 0;

    for (final q in questions) {
      final qi = q['qi'] as int;
      final bubbles = q['bubbles'] as List<dynamic>? ?? [];
      final score = (q['score'] as num?)?.toDouble() ?? 1.0;
      maxScore += score;

      // Sample each bubble
      final bubbleGrays = <int, double>{};
      for (int b = 0; b < bubbles.length; b++) {
        final bubble = bubbles[b] as Map<String, dynamic>;
        final cx = (bubble['cx'] as num).toDouble();
        final cy = (bubble['cy'] as num).toDouble();
        final radius = (bubble['radius'] as num).toDouble();

        final avgGray = _sampleBubble(grayImg, cx, cy, radius, corners);
        bubbleGrays[b] = avgGray;
      }

      // Find the darkest bubble (lowest gray value = most filled)
      int darkestIdx = 0;
      double darkestGray = 255;
      for (final entry in bubbleGrays.entries) {
        if (entry.value < darkestGray) {
          darkestGray = entry.value;
          darkestIdx = entry.key;
        }
      }

      // Threshold: must be significantly darker than unfilled bubbles
      final sortedGrays = bubbleGrays.values.toList()..sort();
      final medianUnfilled =
          sortedGrays.length > 1 ? sortedGrays[sortedGrays.length ~/ 2] : 200.0;
      final isFilled = darkestGray < medianUnfilled * 0.65 && darkestGray < 150;

      final answer = isFilled
          ? (bubbles[darkestIdx] as Map<String, dynamic>)['label'] as String
          : '?';

      answers.add({
        'qi': qi,
        'ans': answer,
        'score': isFilled ? score : 0,
      });
    }

    // Count answers
    for (final a in answers) {
      if (a['ans'] != '?') {
        totalScore += (a['score'] as num).toDouble();
      }
    }

    return OmrScanResult(
      success: true,
      studentId: studentId,
      answers: answers,
      totalScore: totalScore,
      maxScore: maxScore,
    );
  }

  /// Detect four corner markers. Returns their pixel coordinates
  /// in order: topLeft, topRight, bottomLeft, bottomRight.
  static _Corners? _detectCorners(img.Image grayImg) {
    final w = grayImg.width;
    final h = grayImg.height;
    const int searchMargin = 50;
    const int markerMinSize = 15;

    // Search corners: look for dark regions
    final tl = _findDarkBlob(grayImg, searchMargin, searchMargin,
        searchMargin * 2, searchMargin * 2, markerMinSize);
    final tr = _findDarkBlob(grayImg, w - searchMargin * 2, searchMargin,
        searchMargin * 2, searchMargin * 2, markerMinSize);
    final bl = _findDarkBlob(grayImg, searchMargin, h - searchMargin * 2,
        searchMargin * 2, searchMargin * 2, markerMinSize);
    final br = _findDarkBlob(grayImg, w - searchMargin * 2, h - searchMargin * 2,
        searchMargin * 2, searchMargin * 2, markerMinSize);

    if (tl == null || tr == null || bl == null || br == null) return null;

    return _Corners(
      topLeft: tl,
      topRight: tr,
      bottomLeft: bl,
      bottomRight: br,
      imageWidth: w,
      imageHeight: h,
    );
  }

  static (int, int)? _findDarkBlob(
      img.Image gray, int x, int y, int w, int h, int minSize) {
    double sum = 0;
    int count = 0;
    for (int dy = y; dy < y + h && dy < gray.height; dy++) {
      for (int dx = x; dx < x + w && dx < gray.width; dx++) {
        final pixel = gray.getPixel(dx, dy);
        final luminance = img.getLuminance(pixel);
        sum += luminance;
        count++;
      }
    }
    if (count == 0) return null;
    final avg = sum / count;
    // If the region is dark enough (avg < 80), consider it a marker
    if (avg < 80) {
      return (x + w ~/ 2, y + h ~/ 2);
    }
    return null;
  }

  /// Recognize 4-digit student ID from digit grid.
  static String _recognizeStudentId(
      img.Image grayImg, List<dynamic> digitCols, _Corners corners) {
    final digits = <int>[];
    for (final colData in digitCols) {
      final col = colData as Map<String, dynamic>;
      final digitCells = col['digits'] as List<dynamic>? ?? [];
      int bestDigit = 0;
      double bestGray = 255;

      for (final cell in digitCells) {
        final cellMap = cell as Map<String, dynamic>;
        final cx = (cellMap['cx'] as num).toDouble();
        final cy = (cellMap['cy'] as num).toDouble();
        final radius = (cellMap['radius'] as num).toDouble();

        final avgGray = _sampleBubble(grayImg, cx, cy, radius, corners);
        if (avgGray < bestGray) {
          bestGray = avgGray;
          bestDigit = cellMap['digit'] as int;
        }
      }

      // Only accept if clearly filled
      if (bestGray < 140) {
        digits.add(bestDigit);
      } else {
        digits.add(0);
      }
    }

    return digits.map((d) => d.toString()).join();
  }

  /// Sample average grayscale within a bubble's center region.
  static double _sampleBubble(
    img.Image grayImg,
    double normX,
    double normY,
    double normRadius,
    _Corners corners,
  ) {
    // Map normalized coordinates to pixel coordinates
    final px = (normX * grayImg.width).round().clamp(0, grayImg.width - 1);
    final py = (normY * grayImg.height).round().clamp(0, grayImg.height - 1);
    final r = (normRadius * grayImg.width * 0.7)
        .round()
        .clamp(3, grayImg.width ~/ 20);

    double sum = 0;
    int count = 0;

    for (int dy = -r; dy <= r; dy++) {
      for (int dx = -r; dx <= r; dx++) {
        if (dx * dx + dy * dy <= r * r) {
          final sx = (px + dx).clamp(0, grayImg.width - 1);
          final sy = (py + dy).clamp(0, grayImg.height - 1);
          final pixel = grayImg.getPixel(sx, sy);
          sum += img.getLuminance(pixel);
          count++;
        }
      }
    }

    return count > 0 ? sum / count : 255;
  }

  /// Compare recognized answers against standard answers.
  /// [answers] is a list of maps with keys: 'qi', 'ans', 'score'.
  static Map<String, dynamic> compareWithStandard({
    required List<Map<String, dynamic>> answers,
    required List<Map<String, dynamic>> standardAnswers,
    required Map<String, dynamic> layoutConfig,
  }) {
    final questions = layoutConfig['questions'] as List<dynamic>? ?? [];
    final results = <Map<String, dynamic>>[];
    int correctCount = 0;
    double score = 0;

    for (final q in questions) {
      final qi = q['qi'] as int;
      final qScore = (q['score'] as num?)?.toDouble() ?? 1.0;
      final stdAns = standardAnswers.firstWhere(
        (s) => s['qi'] == qi,
        orElse: () => <String, dynamic>{'ans': '?'},
      );
      final recognized = answers.firstWhere(
        (a) => a['qi'] == qi,
        orElse: () => <String, dynamic>{'qi': qi, 'ans': '?', 'score': 0},
      );

      final correct = recognized['ans'] == stdAns['ans'];
      if (correct) {
        correctCount++;
        score += qScore;
      }

      results.add({
        'q': qi + 1,
        'ans': recognized['ans'],
        'correct': correct,
        'std': stdAns['ans'],
        'qid': q['qid'] as String? ?? '',
        'ktag': q['ktag'] as String? ?? '',
        'qtype': q['qtype'] as String? ?? 'single',
        'score': correct ? qScore : 0,
      });
    }

    return {
      'results': results,
      'total_score': score,
      'max_score': questions.fold<double>(
          0, (sum, q) => sum + ((q['score'] as num?)?.toDouble() ?? 1.0)),
      'correct_count': correctCount,
      'total_count': questions.length,
    };
  }
}

class _Corners {
  final (int, int) topLeft;
  final (int, int) topRight;
  final (int, int) bottomLeft;
  final (int, int) bottomRight;
  final int imageWidth;
  final int imageHeight;

  _Corners({
    required this.topLeft,
    required this.topRight,
    required this.bottomLeft,
    required this.bottomRight,
    required this.imageWidth,
    required this.imageHeight,
  });
}

class OmrScanResult {
  final bool success;
  final String? error;
  final String studentId;
  final List<Map<String, dynamic>> answers;
  final double totalScore;
  final double maxScore;

  OmrScanResult({
    required this.success,
    this.error,
    this.studentId = '0000',
    this.answers = const [],
    this.totalScore = 0,
    this.maxScore = 0,
  });

  /// Serialize to a cross-isolate-safe Map.
  Map<String, dynamic> toMap() => {
        'success': success,
        'error': error,
        'studentId': studentId,
        'answers': answers,
        'totalScore': totalScore,
        'maxScore': maxScore,
      };

  /// Deserialize from a Map produced by [toMap].
  factory OmrScanResult.fromMap(Map<String, dynamic> map) => OmrScanResult(
        success: map['success'] as bool,
        error: map['error'] as String?,
        studentId: (map['studentId'] as String?) ?? '0000',
        answers: (map['answers'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [],
        totalScore: (map['totalScore'] as num?)?.toDouble() ?? 0,
        maxScore: (map['maxScore'] as num?)?.toDouble() ?? 0,
      );

  bool get isMasterSheet => studentId == '0000';
}
