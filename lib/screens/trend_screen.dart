import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/google_sheets_service.dart';
import '../state/app_state.dart';

class TrendScreen extends StatelessWidget {
  const TrendScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('추이보기')),
      body: FutureBuilder<MonthlyData>(
        future: state.sheetsService.fetchMonthlyData(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _SectionTitle(title: '투석결과 (배액량 기준)'),
              _DialysisChart(
                machine: data.machineDialysis,
                manual: data.manualDialysis,
              ),
              const SizedBox(height: 24),
              _SectionTitle(title: '체중'),
              _WeightChart(entries: data.weight),
              const SizedBox(height: 24),
              _SectionTitle(title: '혈압'),
              _BloodPressureChart(entries: data.bloodPressure),
            ],
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
    );
  }
}

class _WeightChart extends StatelessWidget {
  const _WeightChart({required this.entries});

  final List<WeightEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Text('데이터가 없습니다.');
    }
    final points = _dateToSpot(entries.map((e) {
      final date = _parseDate(e.date);
      return _ChartPoint(date: date, value: e.weight);
    }).toList());
    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: _simpleTitles(),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              color: Colors.blue,
              spots: points,
              isCurved: true,
              barWidth: 3,
              dotData: const FlDotData(show: true),
            ),
          ],
        ),
      ),
    );
  }
}

class _BloodPressureChart extends StatelessWidget {
  const _BloodPressureChart({required this.entries});

  final List<BloodPressureEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Text('데이터가 없습니다.');
    }
    final systolic = _dateToSpot(entries.map((e) {
      final date = _parseDate(e.date);
      return _ChartPoint(date: date, value: e.systolic.toDouble());
    }).toList());
    final diastolic = _dateToSpot(entries.map((e) {
      final date = _parseDate(e.date);
      return _ChartPoint(date: date, value: e.diastolic.toDouble());
    }).toList());
    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: _simpleTitles(),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              color: Colors.red,
              spots: systolic,
              isCurved: true,
              barWidth: 3,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              color: Colors.blueGrey,
              spots: diastolic,
              isCurved: true,
              barWidth: 3,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialysisChart extends StatelessWidget {
  const _DialysisChart({required this.machine, required this.manual});

  final List<DialysisRow> machine;
  final List<DialysisRow> manual;

  @override
  Widget build(BuildContext context) {
    if (machine.isEmpty && manual.isEmpty) {
      return const Text('데이터가 없습니다.');
    }
    final map = <int, _DialysisBars>{};
    for (final row in machine) {
      final date = _parseDate(row.date);
      final day = date.day;
      map.putIfAbsent(day, () => _DialysisBars(day: day));
      map[day]!.machine += row.outflow;
    }
    for (final row in manual) {
      final date = _parseDate(row.date);
      final day = date.day;
      map.putIfAbsent(day, () => _DialysisBars(day: day));
      map[day]!.manual += row.outflow;
    }
    final sorted = map.values.toList()..sort((a, b) => a.day.compareTo(b.day));
    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          gridData: const FlGridData(show: false),
          titlesData: _simpleTitles(),
          borderData: FlBorderData(show: false),
          barGroups: sorted
              .map(
                (entry) => BarChartGroupData(
                  x: entry.day,
                  barRods: [
                    BarChartRodData(
                      toY: entry.machine,
                      color: Colors.blue,
                      width: 6,
                    ),
                    BarChartRodData(
                      toY: entry.manual,
                      color: Colors.lightBlueAccent,
                      width: 6,
                    ),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

FlTitlesData _simpleTitles() {
  return FlTitlesData(
    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true)),
    bottomTitles: const AxisTitles(
      sideTitles: SideTitles(showTitles: true, interval: 5),
    ),
    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
  );
}

List<FlSpot> _dateToSpot(List<_ChartPoint> points) {
  points.sort((a, b) => a.date.compareTo(b.date));
  return points
      .map(
        (point) => FlSpot(point.date.day.toDouble(), point.value),
      )
      .toList();
}

DateTime _parseDate(String raw) {
  try {
    return DateFormat('yyyy-MM-dd').parse(raw);
  } catch (_) {
    return DateTime.now();
  }
}

class _ChartPoint {
  _ChartPoint({required this.date, required this.value});

  final DateTime date;
  final double value;
}

class _DialysisBars {
  _DialysisBars({required this.day});

  final int day;
  double machine = 0;
  double manual = 0;
}
