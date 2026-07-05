import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../database/database_helper.dart';
import '../models/models.dart';
import '../services/excel_exporter.dart';

class StatisticsPage extends StatefulWidget {
  const StatisticsPage({super.key});

  @override
  State<StatisticsPage> createState() => _StatisticsPageState();
}

class _StatisticsPageState extends State<StatisticsPage> {
  final _db = DatabaseHelper();
  List<Map<String, dynamic>> _records = [];
  List<Map<String, dynamic>> _templates = [];
  String? _studentIdFilter;
  int? _templateIdFilter;
  String? _classNameFilter;

  // Stats
  Map<String, int> _scoreDistribution = {};
  Map<int, Map<String, int>> _questionCorrectRate = {};
  int _totalRecords = 0;
  double _averageScore = 0;

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  final _searchController = TextEditingController();

  Future<void> _loadFilters() async {
    _templates = await _db.getTemplates();
    setState(() {});
  }

  Future<void> _loadRecords() async {
    final records = await _db.getScanRecords(
      studentId: _studentIdFilter,
      templateId: _templateIdFilter,
      className: _classNameFilter,
    );
    setState(() {
      _records = records;
    });
    _computeStats();
  }

  void _computeStats() {
    if (_records.isEmpty) {
      setState(() {
        _scoreDistribution = {};
        _questionCorrectRate = {};
        _totalRecords = 0;
        _averageScore = 0;
      });
      return;
    }

    // Score distribution
    final dist = <String, int>{
      '0-20': 0,
      '21-40': 0,
      '41-60': 0,
      '61-80': 0,
      '81-100': 0,
    };

    double totalPercent = 0;

    for (final r in _records) {
      final total = (r['total_score'] as num).toDouble();
      final max = (r['max_score'] as num).toDouble();
      final percent = max > 0 ? (total / max * 100) : 0;
      totalPercent += percent;

      if (percent <= 20) {
        dist['0-20'] = (dist['0-20'] ?? 0) + 1;
      } else if (percent <= 40) {
        dist['21-40'] = (dist['21-40'] ?? 0) + 1;
      } else if (percent <= 60) {
        dist['41-60'] = (dist['41-60'] ?? 0) + 1;
      } else if (percent <= 80) {
        dist['61-80'] = (dist['61-80'] ?? 0) + 1;
      } else {
        dist['81-100'] = (dist['81-100'] ?? 0) + 1;
      }
    }

    // Question correct rate
    final questionStats = <int, Map<String, int>>{};
    for (final r in _records) {
      final answers = jsonDecode(r['answer_json'] as String) as List;
      for (final a in answers) {
        final m = a as Map<String, dynamic>;
        final qi = m['q'] as int;
        questionStats.putIfAbsent(qi, () => {'total': 0, 'correct': 0});
        questionStats[qi]!['total'] = (questionStats[qi]!['total'] ?? 0) + 1;
        if (m['correct'] == true) {
          questionStats[qi]!['correct'] =
              (questionStats[qi]!['correct'] ?? 0) + 1;
        }
      }
    }

    setState(() {
      _scoreDistribution = dist;
      _questionCorrectRate = questionStats;
      _totalRecords = _records.length;
      _averageScore = _records.isNotEmpty ? totalPercent / _records.length : 0;
    });
  }

  Future<void> _exportExcel() async {
    if (_records.isEmpty) return;

    final templateNames = <int, String>{};
    for (final t in _templates) {
      templateNames[t['id'] as int] = t['name'] as String;
    }

    final scanRecords = _records
        .map((r) => ScanRecord.fromMap(r))
        .toList();

    final path = await ExcelExporter.exportBatch(
      records: scanRecords,
      templateNames: templateNames,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已导出: $path'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('成绩统计'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: _records.isNotEmpty ? _exportExcel : null,
            tooltip: '导出Excel',
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                // Search by student ID
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          hintText: '输入学号筛选（留空查全部）',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        onSubmitted: (v) {
                          _studentIdFilter =
                              v.isEmpty ? null : v.padLeft(4, '0');
                          _loadRecords();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Template filter
                    DropdownButton<int?>(
                      value: _templateIdFilter,
                      hint: const Text('模板', style: TextStyle(fontSize: 13)),
                      underline: const SizedBox(),
                      items: [
                        const DropdownMenuItem<int?>(
                            value: null, child: Text('全部模板')),
                        ..._templates.map((t) => DropdownMenuItem<int?>(
                            value: t['id'] as int,
                            child: Text(
                                t['name'] as String))),
                      ],
                      onChanged: (v) {
                        _templateIdFilter = v;
                        _loadRecords();
                      },
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _loadRecords,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Stats summary
          if (_records.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statItem('答卷数', '$_totalRecords'),
                  _statItem('平均分', '${_averageScore.toStringAsFixed(1)}%'),
                  _statItem(
                      '最高分',
                      _records.isNotEmpty
                          ? '${_getMaxPercent().toStringAsFixed(0)}%'
                          : '-'),
                ],
              ),
            ),

          const SizedBox(height: 8),

          // Content
          Expanded(
            child: _records.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bar_chart, size: 64, color: Colors.grey),
                        SizedBox(height: 12),
                        Text('点击刷新按钮加载数据',
                            style: TextStyle(color: Colors.grey)),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Score distribution chart
                        const Text('分数区间分布',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 200,
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: (_scoreDistribution.values
                                          .fold<int>(
                                              0, (a, b) => a > b ? a : b) +
                                      1)
                                  .toDouble(),
                              barGroups: _scoreDistribution.entries.map((e) {
                                final idx = [
                                  '0-20',
                                  '21-40',
                                  '41-60',
                                  '61-80',
                                  '81-100'
                                ].indexOf(e.key);
                                return BarChartGroupData(
                                  x: idx,
                                  barRods: [
                                    BarChartRodData(
                                      toY: e.value.toDouble(),
                                      color: _getBarColor(idx),
                                      width: 24,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(4),
                                        topRight: Radius.circular(4),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                              titlesData: FlTitlesData(
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    getTitlesWidget: (v, _) {
                                      const labels = [
                                        '0-20',
                                        '21-40',
                                        '41-60',
                                        '61-80',
                                        '81-100'
                                      ];
                                      return Text(labels[v.toInt()],
                                          style:
                                              const TextStyle(fontSize: 10));
                                    },
                                  ),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 30,
                                    getTitlesWidget: (v, _) =>
                                        Text('${v.toInt()}',
                                            style:
                                                const TextStyle(fontSize: 10)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 20),

                        // Question correct rate
                        const Text('单题正确率统计',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 200,
                          child: _questionCorrectRate.isEmpty
                              ? const Center(child: Text('暂无数据'))
                              : BarChart(
                                  BarChartData(
                                    alignment: BarChartAlignment.center,
                                    maxY: 100,
                                    barGroups: _questionCorrectRate.entries
                                        .take(50) // max 50 questions visible
                                        .map((e) {
                                      final correct =
                                          e.value['correct'] ?? 0;
                                      final total =
                                          e.value['total'] ?? 1;
                                      final rate =
                                          (total > 0 ? correct / total * 100 : 0).toDouble();
                                      return BarChartGroupData(
                                        x: e.key,
                                        barRods: [
                                          BarChartRodData(
                                            toY: rate,
                                            color: rate >= 80
                                                ? Colors.green
                                                : rate >= 60
                                                    ? Colors.orange
                                                    : Colors.red,
                                            width: 6,
                                          ),
                                        ],
                                      );
                                    }).toList(),
                                    titlesData: FlTitlesData(
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          interval: 5,
                                          getTitlesWidget: (v, _) => Text(
                                              'Q${v.toInt() + 1}',
                                              style: const TextStyle(
                                                  fontSize: 7)),
                                        ),
                                      ),
                                      leftTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          reservedSize: 30,
                                          getTitlesWidget: (v, _) => Text(
                                              '${v.toInt()}%',
                                              style: const TextStyle(
                                                  fontSize: 9)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                        ),

                        const SizedBox(height: 20),

                        // Student records list
                        const Text('答卷明细',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        ..._records.take(30).map((r) {
                          final total =
                              (r['total_score'] as num).toDouble();
                          final max =
                              (r['max_score'] as num).toDouble();
                          final percent =
                              max > 0 ? (total / max * 100).toStringAsFixed(0) : '0';
                          return ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              radius: 14,
                              backgroundColor: _getColorForPercent(
                                  int.tryParse(percent) ?? 0),
                              child: Text('$percent%',
                                  style: const TextStyle(
                                      fontSize: 9, color: Colors.white)),
                            ),
                            title: Text(
                              '学号: ${r['student_id']} ${r['student_name'] ?? ''}',
                              style: const TextStyle(fontSize: 13),
                            ),
                            subtitle: Text(
                              '${r['scan_time']} · $total/$max · ${r['class_name'] ?? ''}',
                              style: const TextStyle(fontSize: 10),
                            ),
                          );
                        }),
                        if (_records.length > 30)
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Text(
                              '... 还有 ${_records.length - 30} 条记录，导出Excel查看全部',
                              style: const TextStyle(
                                  color: Colors.grey, fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      children: [
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Text(value,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold)),
      ],
    );
  }

  double _getMaxPercent() {
    double maxP = 0;
    for (final r in _records) {
      final total = (r['total_score'] as num).toDouble();
      final max = (r['max_score'] as num).toDouble();
      final p = (max > 0 ? total / max * 100 : 0).toDouble();
      if (p > maxP) maxP = p;
    }
    return maxP;
  }

  Color _getBarColor(int index) {
    const colors = [
      Colors.red, Colors.orange, Colors.yellow,
      Colors.lightGreen, Colors.green,
    ];
    return colors[index.clamp(0, colors.length - 1)];
  }

  Color _getColorForPercent(int p) {
    if (p >= 80) return Colors.green;
    if (p >= 60) return Colors.orange;
    return Colors.red;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
