import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../database/database_helper.dart';

/// Version check and update service.
/// Network calls are isolated here — only invoked from Settings page.
class VersionChecker {
  // This URL is a placeholder — replace with actual update server when ready.
  static const String _updateCheckUrl =
      'https://example.com/omr_scanner/version.json';

  /// Check for latest version. Returns (hasUpdate, latestVersion, apkUrl, updateInfo).
  /// Returns null if network is unavailable.
  static Future<Map<String, dynamic>?> checkForUpdate() async {
    try {
      final response = await http
          .get(Uri.parse(_updateCheckUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final latestVersion = data['version'] as String? ?? '0.0.0';
        final apkUrl = data['apk_url'] as String? ?? '';
        final updateInfo = data['update_info'] as String? ?? '';

        // Cache to local DB
        final db = DatabaseHelper();
        await db.updateAppVersion({
          'id': 1,
          'latest_version': latestVersion,
          'apk_url': apkUrl,
          'update_info': updateInfo,
          'last_check_time': DateTime.now().toIso8601String(),
        });

        // Compare versions (simple string compare, assumes semver)
        final current = await db.getAppVersion();
        final currentVersion = current?['current_version'] as String? ?? '1.0.0';

        return {
          'has_update': _compareVersions(latestVersion, currentVersion) > 0,
          'latest_version': latestVersion,
          'apk_url': apkUrl,
          'update_info': updateInfo,
        };
      }
    } catch (e) {
      // Network unavailable or server not reachable — silently ignore
    }
    return null;
  }

  /// Download new APK to downloads directory.
  static Future<String?> downloadApk(String url) async {
    try {
      final response = await http
          .get(Uri.parse(url))
          .timeout(const Duration(minutes: 10));

      if (response.statusCode == 200) {
        final dir = Directory('/storage/emulated/0/Download');
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final filePath = '${dir.path}/omr_scanner_update.apk';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);
        return filePath;
      }
    } catch (e) {
      // Download failed
    }
    return null;
  }

  static int _compareVersions(String a, String b) {
    final aParts = a.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    final bParts = b.split('.').map((s) => int.tryParse(s) ?? 0).toList();
    for (int i = 0; i < 3; i++) {
      final av = i < aParts.length ? aParts[i] : 0;
      final bv = i < bParts.length ? bParts[i] : 0;
      if (av != bv) return av.compareTo(bv);
    }
    return 0;
  }
}

/// Tag/Knowledge-point association service (reserved for Phase 2).
/// Phase 1: only provides data structures and stubs.
class KnowledgeTagService {
  /// Reserved: batch update question tags in a template.
  static Map<String, dynamic> buildQuestionConfig({
    required int questionIndex,
    String questionId = '',
    String knowledgeTag = '',
    String questionType = 'single',
    double scoreValue = 1.0,
  }) {
    return {
      'qi': questionIndex,
      'qid': questionId,
      'ktag': knowledgeTag,
      'qtype': questionType,
      'score': scoreValue,
    };
  }

  /// Reserved: extract wrong questions from scan records for a student.
  static List<Map<String, dynamic>> extractWrongQuestions(
      List<Map<String, dynamic>> scanRecords) {
    final wrong = <Map<String, dynamic>>[];
    for (final record in scanRecords) {
      final answers = jsonDecode(record['answer_json'] as String) as List;
      for (final a in answers) {
        final m = a as Map<String, dynamic>;
        if (m['correct'] != true) {
          wrong.add({
            'student_id': record['student_id'],
            'record_id': record['id'],
            'template_id': record['template_id'],
            'question_index': m['q'] as int,
            'wrong_answer': m['ans'],
            'ktag': m['ktag'] ?? '',
            'qid': m['qid'] ?? '',
          });
        }
      }
    }
    return wrong;
  }
}
