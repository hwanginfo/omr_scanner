import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';
import '../services/version_checker.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _db = DatabaseHelper();
  bool _isChecking = false;
  Map<String, dynamic>? _updateInfo;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final v = await _db.getAppVersion();
    setState(() {
      if (v != null && v['latest_version'] != null) {
        _updateInfo = v;
      }
    });
  }

  Future<void> _checkForUpdate() async {
    setState(() => _isChecking = true);
    final result = await VersionChecker.checkForUpdate();
    setState(() {
      _isChecking = false;
      _updateInfo = result;
    });

    if (mounted) {
      if (result != null && result['has_update'] == true) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('发现新版本'),
            content: Text(
                '最新版本: ${result['latest_version']}\n\n${result['update_info'] ?? ''}'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('稍后更新')),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _downloadUpdate(result['apk_url'] as String);
                },
                child: const Text('下载更新'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('已是最新版本'), backgroundColor: Colors.green),
        );
      }
    }
  }

  Future<void> _downloadUpdate(String url) async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('正在下载...')),
      );
    }
    final path = await VersionChecker.downloadApk(url);
    if (mounted && path != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('下载完成: $path，请手动安装'),
            backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _exportDatabase() async {
    final dbPath = await _db.exportDatabase();
    try {
      await Share.shareXFiles(
        [XFile(dbPath)],
        text: 'OMR 阅卷数据备份',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('备份失败: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: ListView(
        children: [
          // Version section
          const _SectionHeader('版本信息'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('当前版本'),
            subtitle: const Text('v1.0.0'),
          ),
          ListTile(
            leading: const Icon(Icons.system_update),
            title: const Text('检查更新'),
            subtitle: Text(_updateInfo?['latest_version'] != null
                ? '最新版本: ${_updateInfo!['latest_version']}'
                : '点击检查'),
            trailing: _isChecking
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: _isChecking ? null : _checkForUpdate,
          ),
          if (_updateInfo != null && _updateInfo!['latest_version'] != null)
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('下载更新'),
              subtitle: Text('版本 ${_updateInfo!['latest_version']}'),
              onTap: () => _downloadUpdate(
                  _updateInfo!['apk_url'] as String? ?? ''),
            ),

          const Divider(),

          // Data section
          const _SectionHeader('数据管理'),
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('导出数据库备份'),
            subtitle: const Text('备份全部扫描记录和模板数据'),
            onTap: _exportDatabase,
          ),

          const Divider(),

          // Reserved: Wrong question book (Phase 2)
          const _SectionHeader('扩展功能'),
          ListTile(
            leading: const Icon(Icons.book, color: Colors.grey),
            title: const Text('错题本',
                style: TextStyle(color: Colors.grey)),
            subtitle: const Text('按学号/知识点汇总错题（即将上线）',
                style: TextStyle(color: Colors.grey)),
            enabled: false,
            onTap: null,
          ),
          ListTile(
            leading: const Icon(Icons.insights, color: Colors.grey),
            title: const Text('知识点薄弱项分析',
                style: TextStyle(color: Colors.grey)),
            subtitle: const Text('自动分析薄弱知识点（即将上线）',
                style: TextStyle(color: Colors.grey)),
            enabled: false,
            onTap: null,
          ),

          const Divider(),

          // About
          const _SectionHeader('关于'),
          const ListTile(
            leading: Icon(Icons.info),
            title: Text('OMR 答题卡阅卷系统'),
            subtitle: Text('v1.0.0 · 离线版 · Android 7.0+'),
          ),
          const ListTile(
            leading: Icon(Icons.security),
            title: Text('隐私与安全'),
            subtitle: Text('全部数据本地存储，不联网不上传'),
          ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        ),
      ),
    );
  }
}
