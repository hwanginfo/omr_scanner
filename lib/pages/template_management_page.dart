import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../database/database_helper.dart';
import '../services/template_engine.dart';
import '../services/pdf_generator.dart';

class TemplateManagementPage extends StatefulWidget {
  const TemplateManagementPage({super.key});

  @override
  State<TemplateManagementPage> createState() => _TemplateManagementPageState();
}

class _TemplateManagementPageState extends State<TemplateManagementPage> {
  final _db = DatabaseHelper();
  List<Map<String, dynamic>> _templates = [];

  @override
  void initState() {
    super.initState();
    _loadTemplates();
  }

  Future<void> _loadTemplates() async {
    final templates = await _db.getTemplates();
    setState(() => _templates = templates);
  }

  Future<void> _createFromBuiltIn(Map<String, dynamic> def) async {
    await _db.insertTemplate({
      'name': def['name'],
      'question_count': def['question_count'],
      'option_count': def['option_count'],
      'layout_config_json': def['layout_config_json'],
      'created_at': DateTime.now().toIso8601String(),
    });
    _loadTemplates();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('已创建模板: ${def['name']}'),
            backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _generatePdf(int templateId) async {
    final template = await _db.getTemplate(templateId);
    if (template == null) return;

    final layoutConfig =
        jsonDecode(template['layout_config_json'] as String);
    final path = await PdfGenerator.generate(
      layoutConfig: layoutConfig,
      templateName: template['name'] as String,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF已生成: $path'),
          backgroundColor: Colors.green,
          action: SnackBarAction(
            label: '打开',
            onPressed: () => OpenFilex.open(path),
          ),
        ),
      );
    }
  }

  Future<void> _importStandardAnswer(int templateId) async {
    final template = await _db.getTemplate(templateId);
    if (template == null) return;

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('录入标准答案'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'scan'),
            child: const ListTile(
              leading: Icon(Icons.camera_alt),
              title: Text('扫描母版答题卡'),
              subtitle: Text('学号区填 0000 即为母版', style: TextStyle(fontSize: 12)),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'excel'),
            child: const ListTile(
              leading: Icon(Icons.table_chart),
              title: Text('导入 Excel / CSV'),
              subtitle: Text('题号,题型,知识点,标准答案', style: TextStyle(fontSize: 12)),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'manual'),
            child: const ListTile(
              leading: Icon(Icons.edit),
              title: Text('手动逐题录入'),
            ),
          ),
        ],
      ),
    );

    if (action == 'scan') {
      // Navigate to scan page in master mode
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '请前往首页扫描母版答题卡（学号 0000），当前模板: ${template['name']}'),
          ),
        );
      }
    } else if (action == 'excel') {
      _importStandardFromExcel(templateId, template);
    } else if (action == 'manual') {
      _manualEntry(templateId, template);
    }
  }

  Future<void> _importStandardFromExcel(
      int templateId, Map<String, dynamic> template) async {
    final result = await showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('导入标准答案'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('请粘贴 CSV/TSV 内容：\n格式: 题号,题型,知识点,标准答案',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 8,
                decoration: const InputDecoration(
                  hintText:
                      '1,single,一次函数,A\n2,single,几何,B\n3,judge,判断,T',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
            TextButton(
              onPressed: () {
                final lines = controller.text.trim().split('\n');
                final answers = <Map<String, dynamic>>[];
                for (final line in lines) {
                  final parts = line.split(',').map((s) => s.trim()).toList();
                  if (parts.length >= 2) {
                    final qi = int.tryParse(parts[0]);
                    if (qi != null && qi > 0) {
                      answers.add({
                        'qi': qi - 1,
                        'ans': parts.length >= 4 ? parts[3] : parts[1],
                        'qtype': parts.length >= 2 ? parts[1] : 'single',
                        'ktag': parts.length >= 3 ? parts[2] : '',
                      });
                    }
                  }
                }
                Navigator.pop(ctx, answers);
              },
              child: const Text('导入'),
            ),
          ],
        );
      },
    );

    if (result != null && result.isNotEmpty) {
      final standardJson = jsonEncode(result);
      await _db.updateTemplateStandardAnswer(templateId, standardJson);
      _loadTemplates();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('已导入 ${result.length} 题标准答案'),
              backgroundColor: Colors.green),
        );
      }
    }
  }

  Future<void> _manualEntry(
      int templateId, Map<String, dynamic> template) async {
    final count = template['question_count'] as int;
    final optionCount = template['option_count'] as int;
    final options =
        optionCount == 2 ? ['T', 'F'] : ['A', 'B', 'C', 'D'];

    final answers = <Map<String, dynamic>>[];
    for (int i = 0; i < count; i++) {
      final ans = await showDialog<String>(
        context: context,
        builder: (ctx) {
          String? selected;
          return StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
              title: Text('第 ${i + 1} 题 / 共 $count 题'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RadioGroup<String>(
                    groupValue: selected,
                    onChanged: (v) =>
                        setDialogState(() => selected = v),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: options.map((o) {
                        return RadioListTile<String>(
                          title: Text(o),
                          value: o,
                          dense: true,
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('取消全部'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, selected),
                  child: const Text('确定'),
                ),
              ],
            ),
          );
        },
      );
      if (ans == null) break;
      answers.add({
        'qi': i,
        'ans': ans,
        'qtype': optionCount == 2 ? 'judge' : 'single',
        'ktag': '',
      });
    }

    if (answers.isNotEmpty) {
      final standardJson = jsonEncode(answers);
      await _db.updateTemplateStandardAnswer(templateId, standardJson);
      _loadTemplates();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('答题卡模板'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Built-in templates section
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('内置模板',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
          ),
          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: TemplateEngine.builtInTemplates.length,
              itemBuilder: (ctx, i) {
                final t = TemplateEngine.builtInTemplates[i];
                final alreadyExists = _templates.any((tm) =>
                    tm['name'] == t['name']);
                return Card(
                  child: Container(
                    width: 140,
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t['name'] as String,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                            '${t['count']} 题 · ${t['options'] == 4 ? 'ABCD' : 'T/F'}',
                            style: const TextStyle(fontSize: 10)),
                        const Spacer(),
                        ElevatedButton(
                          onPressed: alreadyExists
                              ? null
                              : () => _createFromBuiltIn(
                                  TemplateEngine.getBuiltInTemplateDefs()[i]),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 28),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            textStyle: const TextStyle(fontSize: 10),
                          ),
                          child: Text(alreadyExists ? '已添加' : '添加'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('我的模板',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey)),
          ),

          // User templates
          Expanded(
            child: _templates.isEmpty
                ? const Center(
                    child: Text('请从上方内置模板中添加',
                        style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: _templates.length,
                    itemBuilder: (ctx, i) {
                      final t = _templates[i];
                      final hasAnswer =
                          t['standard_answer_json'] != null &&
                          (t['standard_answer_json'] as String).isNotEmpty;
                      return Card(
                        child: ListTile(
                          leading: Icon(
                            hasAnswer ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: hasAnswer ? Colors.green : Colors.orange,
                          ),
                          title: Text(t['name'] as String),
                          subtitle: Text(
                            '${t['question_count']} 题 · ${t['option_count'] == 4 ? 'ABCD' : 'T/F'}'
                            '${hasAnswer ? ' · 已有标准答案' : ' · 待录入答案'}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (action) {
                              final id = t['id'] as int;
                              switch (action) {
                                case 'pdf':
                                  _generatePdf(id);
                                  break;
                                case 'answer':
                                  _importStandardAnswer(id);
                                  break;
                              }
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'pdf',
                                child: ListTile(
                                  leading: Icon(Icons.print),
                                  title: Text('导出PDF打印'),
                                  dense: true,
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'answer',
                                child: ListTile(
                                  leading: Icon(Icons.edit_note),
                                  title: Text('录入标准答案'),
                                  dense: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
