import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/google_sheets_service.dart';
import '../state/app_state.dart';

class TrendScreen extends StatefulWidget {
  const TrendScreen({super.key});

  static List<DateTime> get last30Days {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    return List.generate(30, (i) => end.subtract(Duration(days: 29 - i)));
  }

  @override
  State<TrendScreen> createState() => _TrendScreenState();
}

class _TrendScreenState extends State<TrendScreen> {
  static const _allId = 'all';
  String _selectedSeriesId = _allId;
  static const _minChartHeight = 200.0;
  static const _maxChartHeight = 600.0;
  static const _minWidthFactor = 1.0;
  static const _maxWidthFactor = 2.5;
  double _chartHeight = 280;
  double _chartWidthFactor = 1.0;

  @override
  Widget build(BuildContext context) {
    final state = context.read<AppState>();
    final orderedDates = TrendScreen.last30Days;
    return Scaffold(
      appBar: AppBar(title: const Text('추이보기')),
      body: FutureBuilder<MonthlyData>(
        future: state.sheetsService.fetchLast30DaysData(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final options = _buildSeriesOptions(data);
          if (!options.any((e) => e.id == _selectedSeriesId)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _selectedSeriesId = _allId);
            });
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _SectionTitle(title: '투석결과 (최근 30일)'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: options.any((e) => e.id == _selectedSeriesId)
                    ? _selectedSeriesId
                    : _allId,
                decoration: const InputDecoration(
                  labelText: '시리즈 선택',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                items: options
                    .map(
                      (e) => DropdownMenuItem<String>(
                        value: e.id,
                        child: Text(e.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _selectedSeriesId = value);
                },
              ),
              const SizedBox(height: 16),
              _buildChartSizeControls(),
              const SizedBox(height: 8),
              _buildChartContent(
                data: data,
                orderedDates: orderedDates,
                selectedId: _selectedSeriesId,
                chartHeight: _chartHeight,
                chartWidthFactor: _chartWidthFactor,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChartSizeControls() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('차트 크기', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('세로:', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  onPressed: _chartHeight <= _minChartHeight
                      ? null
                      : () => setState(
                          () => _chartHeight = (_chartHeight - 40).clamp(
                            _minChartHeight,
                            _maxChartHeight,
                          ),
                        ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                SizedBox(
                  width: 28,
                  child: Text(
                    '${_chartHeight.toInt()}',
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  onPressed: _chartHeight >= _maxChartHeight
                      ? null
                      : () => setState(
                          () => _chartHeight = (_chartHeight + 40).clamp(
                            _minChartHeight,
                            _maxChartHeight,
                          ),
                        ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Text('가로:', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  onPressed: _chartWidthFactor <= _minWidthFactor
                      ? null
                      : () => setState(
                          () => _chartWidthFactor = (_chartWidthFactor - 0.25)
                              .clamp(_minWidthFactor, _maxWidthFactor),
                        ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '${(_chartWidthFactor * 100).toInt()}%',
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline, size: 20),
                  onPressed: _chartWidthFactor >= _maxWidthFactor
                      ? null
                      : () => setState(
                          () => _chartWidthFactor = (_chartWidthFactor + 0.25)
                              .clamp(_minWidthFactor, _maxWidthFactor),
                        ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _chartHeight = 280;
                  _chartWidthFactor = 1.0;
                }),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('원래대로'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_SeriesOption> _buildSeriesOptions(MonthlyData data) {
    final options = <_SeriesOption>[_SeriesOption(_allId, 'All')];
    final machineByDate = <String, List<DialysisRow>>{};
    for (final row in data.machineDialysis) {
      machineByDate.putIfAbsent(row.date, () => []).add(row);
    }
    final manualByDate = <String, List<DialysisRow>>{};
    for (final row in data.manualDialysis) {
      manualByDate.putIfAbsent(row.date, () => []).add(row);
    }
    int maxMachine = 0, maxManual = 0;
    for (final rows in machineByDate.values) {
      for (final r in rows) {
        if (r.session > maxMachine) maxMachine = r.session;
      }
    }
    for (final rows in manualByDate.values) {
      for (final r in rows) {
        if (r.session > maxManual) maxManual = r.session;
      }
    }
    for (var s = 1; s <= maxMachine; s++) {
      options.add(_SeriesOption('machine_$s', '기계투석$s'));
    }
    for (var s = 1; s <= maxManual; s++) {
      options.add(_SeriesOption('manual_$s', '손투석$s'));
    }
    options.add(_SeriesOption('net', '순배액'));
    options.add(_SeriesOption('weight', '체중'));
    options.add(_SeriesOption('blood_pressure', '혈압'));
    return options;
  }

  (double, double, double, double) _dialysisDataExtent(
    MonthlyData data,
    int dateCount,
  ) {
    double maxY = 100;
    for (final r in data.machineDialysis) {
      if (r.inflow > maxY) maxY = r.inflow;
      if (r.outflow > maxY) maxY = r.outflow;
    }
    for (final r in data.manualDialysis) {
      if (r.inflow > maxY) maxY = r.inflow;
      if (r.outflow > maxY) maxY = r.outflow;
    }
    maxY = (maxY * 1.1).clamp(100, double.infinity);
    return (0, (dateCount - 1).toDouble(), 0, maxY);
  }

  (double, double, double, double) _weightDataExtent(
    List<WeightEntry> entries,
    int dateCount,
  ) {
    double maxY = 100;
    for (final e in entries) {
      if (e.weight > maxY) maxY = e.weight;
    }
    maxY = (maxY * 1.1).clamp(50, double.infinity);
    return (0, (dateCount - 1).toDouble(), 0, maxY);
  }

  (double, double, double, double) _bpDataExtent(
    List<BloodPressureEntry> entries,
    int dateCount,
  ) {
    double maxY = 120;
    for (final e in entries) {
      if (e.systolic > maxY) maxY = e.systolic.toDouble();
      if (e.diastolic > maxY) maxY = e.diastolic.toDouble();
    }
    maxY = (maxY * 1.1).clamp(100, double.infinity);
    return (0, (dateCount - 1).toDouble(), 0, maxY);
  }

  Widget _buildChartContent({
    required MonthlyData data,
    required List<DateTime> orderedDates,
    required String selectedId,
    required double chartHeight,
    required double chartWidthFactor,
  }) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final chartWidth = screenWidth * chartWidthFactor;
    final useHorizontalScroll = chartWidthFactor > 1.0;
    final n = orderedDates.length;
    final dateCount = n > 0 ? n : 1;

    Widget wrapWithSize(Widget chart) {
      if (useHorizontalScroll) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: chartWidth, child: chart),
        );
      }
      return chart;
    }

    Widget zoomableDialysis({String? seriesId}) {
      final (dxMin, dxMax, dyMin, dyMax) = _dialysisDataExtent(data, dateCount);
      return _ZoomableChart(
        key: ValueKey('dialysis-$selectedId'),
        dataMinX: dxMin,
        dataMaxX: dxMax,
        dataMinY: dyMin,
        dataMaxY: dyMax,
        childBuilder: (minX, maxX, minY, maxY) => _DialysisChart(
          machine: data.machineDialysis,
          manual: data.manualDialysis,
          orderedDates: orderedDates,
          selectedSeriesId: seriesId,
          chartHeight: chartHeight,
          chartWidth: useHorizontalScroll ? chartWidth : null,
          visibleMinX: minX,
          visibleMaxX: maxX,
          visibleMinY: minY,
          visibleMaxY: maxY,
        ),
      );
    }

    Widget zoomableWeight() {
      final (dxMin, dxMax, dyMin, dyMax) = _weightDataExtent(
        data.weight,
        dateCount,
      );
      return _ZoomableChart(
        key: const ValueKey('weight'),
        dataMinX: dxMin,
        dataMaxX: dxMax,
        dataMinY: dyMin,
        dataMaxY: dyMax,
        childBuilder: (minX, maxX, minY, maxY) => _WeightChart(
          entries: data.weight,
          orderedDates: orderedDates,
          chartHeight: chartHeight,
          chartWidth: useHorizontalScroll ? chartWidth : null,
          visibleMinX: minX,
          visibleMaxX: maxX,
          visibleMinY: minY,
          visibleMaxY: maxY,
        ),
      );
    }

    Widget zoomableBp() {
      final (dxMin, dxMax, dyMin, dyMax) = _bpDataExtent(
        data.bloodPressure,
        dateCount,
      );
      return _ZoomableChart(
        key: const ValueKey('bp'),
        dataMinX: dxMin,
        dataMaxX: dxMax,
        dataMinY: dyMin,
        dataMaxY: dyMax,
        childBuilder: (minX, maxX, minY, maxY) => _BloodPressureChart(
          entries: data.bloodPressure,
          orderedDates: orderedDates,
          chartHeight: chartHeight,
          chartWidth: useHorizontalScroll ? chartWidth : null,
          visibleMinX: minX,
          visibleMaxX: maxX,
          visibleMinY: minY,
          visibleMaxY: maxY,
        ),
      );
    }

    if (selectedId == _allId) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          wrapWithSize(zoomableDialysis(seriesId: null)),
          const SizedBox(height: 24),
          _SectionTitle(title: '체중'),
          wrapWithSize(zoomableWeight()),
          const SizedBox(height: 24),
          _SectionTitle(title: '혈압'),
          wrapWithSize(zoomableBp()),
        ],
      );
    }
    if (selectedId == 'weight') {
      return wrapWithSize(zoomableWeight());
    }
    if (selectedId == 'blood_pressure') {
      return wrapWithSize(zoomableBp());
    }
    return wrapWithSize(zoomableDialysis(seriesId: selectedId));
  }
}

class _SeriesOption {
  const _SeriesOption(this.id, this.label);
  final String id;
  final String label;
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

/// 핀치 줌·팬으로 차트 보기 영역을 조절하는 래퍼
class _ZoomableChart extends StatefulWidget {
  const _ZoomableChart({
    required this.dataMinX,
    required this.dataMaxX,
    required this.dataMinY,
    required this.dataMaxY,
    required this.childBuilder,
    super.key,
  });

  final double dataMinX;
  final double dataMaxX;
  final double dataMinY;
  final double dataMaxY;
  final Widget Function(double minX, double maxX, double minY, double maxY)
  childBuilder;

  @override
  State<_ZoomableChart> createState() => _ZoomableChartState();
}

class _ZoomableChartState extends State<_ZoomableChart> {
  double _scaleX = 1.0;
  double _scaleY = 1.0;
  double _centerX = 0;
  double _centerY = 0;
  bool _initialized = false;

  void _ensureCenter() {
    if (_initialized) return;
    _centerX = (widget.dataMinX + widget.dataMaxX) / 2;
    _centerY = (widget.dataMinY + widget.dataMaxY) / 2;
    _initialized = true;
  }

  @override
  void didUpdateWidget(covariant _ZoomableChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dataMaxX != widget.dataMaxX ||
        oldWidget.dataMaxY != widget.dataMaxY) {
      _initialized = false;
    }
  }

  (double, double, double, double) _visibleRange(double width, double height) {
    _ensureCenter();
    final rangeX = widget.dataMaxX - widget.dataMinX;
    final rangeY = widget.dataMaxY - widget.dataMinY;
    final halfW = (rangeX / _scaleX) / 2;
    final halfH = (rangeY / _scaleY) / 2;
    var minX = _centerX - halfW;
    var maxX = _centerX + halfW;
    var minY = _centerY - halfH;
    var maxY = _centerY + halfH;
    if (minX < widget.dataMinX) {
      minX = widget.dataMinX;
      maxX = minX + rangeX / _scaleX;
      _centerX = (minX + maxX) / 2;
    }
    if (maxX > widget.dataMaxX) {
      maxX = widget.dataMaxX;
      minX = maxX - rangeX / _scaleX;
      _centerX = (minX + maxX) / 2;
    }
    if (minY < widget.dataMinY) {
      minY = widget.dataMinY;
      maxY = minY + rangeY / _scaleY;
      _centerY = (minY + maxY) / 2;
    }
    if (maxY > widget.dataMaxY) {
      maxY = widget.dataMaxY;
      minY = maxY - rangeY / _scaleY;
      _centerY = (minY + maxY) / 2;
    }
    return (minX, maxX, minY, maxY);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        if (w <= 0 || h <= 0)
          return widget.childBuilder(
            widget.dataMinX,
            widget.dataMaxX,
            widget.dataMinY,
            widget.dataMaxY,
          );
        final (minX, maxX, minY, maxY) = _visibleRange(w, h);

        return GestureDetector(
          onScaleStart: (_) {},
          onScaleUpdate: (details) {
            setState(() {
              final rangeX = widget.dataMaxX - widget.dataMinX;
              final rangeY = widget.dataMaxY - widget.dataMinY;
              final visibleW = maxX - minX;
              final visibleH = maxY - minY;
              final focalX = minX + (details.focalPoint.dx / w) * visibleW;
              final focalY = maxY - (details.focalPoint.dy / h) * visibleH;

              final newScaleX = _scaleX * details.scale;
              final newScaleY = _scaleY * details.scale;
              // 원래 크기(scale 1.0) 이하로 줌아웃되지 않도록
              if (newScaleX >= 1.0 && newScaleY >= 1.0) {
                _scaleX = newScaleX.clamp(1.0, 15.0);
                _scaleY = newScaleY.clamp(1.0, 15.0);
                _centerX = focalX;
                _centerY = focalY;
              }

              final panDataX = visibleW * (-details.focalPointDelta.dx / w);
              final panDataY = visibleH * (details.focalPointDelta.dy / h);
              _centerX += panDataX;
              _centerY += panDataY;
              _centerX = _centerX.clamp(
                widget.dataMinX + rangeX / (_scaleX * 2),
                widget.dataMaxX - rangeX / (_scaleX * 2),
              );
              _centerY = _centerY.clamp(
                widget.dataMinY + rangeY / (_scaleY * 2),
                widget.dataMaxY - rangeY / (_scaleY * 2),
              );
            });
          },
          child: widget.childBuilder(minX, maxX, minY, maxY),
        );
      },
    );
  }
}

class _WeightChart extends StatelessWidget {
  const _WeightChart({
    required this.entries,
    required this.orderedDates,
    this.chartHeight = 220,
    this.chartWidth,
    this.visibleMinX,
    this.visibleMaxX,
    this.visibleMinY,
    this.visibleMaxY,
  });

  final List<WeightEntry> entries;
  final List<DateTime> orderedDates;
  final double chartHeight;
  final double? chartWidth;
  final double? visibleMinX;
  final double? visibleMaxX;
  final double? visibleMinY;
  final double? visibleMaxY;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Text('데이터가 없습니다.');
    }
    final dateStrToIndex = <String, int>{};
    for (var i = 0; i < orderedDates.length; i++) {
      dateStrToIndex[DateFormat('yyyy-MM-dd').format(orderedDates[i])] = i;
    }
    final weightByDate = <String, double>{};
    for (final e in entries) {
      weightByDate[e.date] = e.weight;
    }
    final spots = orderedDates.map((d) {
      final dateStr = DateFormat('yyyy-MM-dd').format(d);
      final idx = dateStrToIndex[dateStr] ?? 0;
      final y = weightByDate[dateStr] ?? 0.0;
      return FlSpot(idx.toDouble(), y);
    }).toList();
    final chartChild = SizedBox(
      height: chartHeight,
      width: chartWidth,
      child: LineChart(
        LineChartData(
          minX: visibleMinX,
          maxX: visibleMaxX,
          minY: visibleMinY ?? 0,
          maxY: visibleMaxY,
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 5,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i >= 0 && i < orderedDates.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        DateFormat('M/d').format(orderedDates[i]),
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              color: Colors.blue,
              spots: spots,
              isCurved: true,
              barWidth: 3,
              dotData: const FlDotData(show: true),
            ),
          ],
        ),
      ),
    );
    return chartChild;
  }
}

class _BloodPressureChart extends StatelessWidget {
  const _BloodPressureChart({
    required this.entries,
    required this.orderedDates,
    this.chartHeight = 220,
    this.chartWidth,
    this.visibleMinX,
    this.visibleMaxX,
    this.visibleMinY,
    this.visibleMaxY,
  });

  final List<BloodPressureEntry> entries;
  final List<DateTime> orderedDates;
  final double chartHeight;
  final double? chartWidth;
  final double? visibleMinX;
  final double? visibleMaxX;
  final double? visibleMinY;
  final double? visibleMaxY;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Text('데이터가 없습니다.');
    }
    final dateStrToIndex = <String, int>{};
    for (var i = 0; i < orderedDates.length; i++) {
      dateStrToIndex[DateFormat('yyyy-MM-dd').format(orderedDates[i])] = i;
    }
    final bpByDate = <String, (int, int)>{};
    for (final e in entries) {
      bpByDate[e.date] = (e.systolic, e.diastolic);
    }
    final systolicSpots = orderedDates.map((d) {
      final dateStr = DateFormat('yyyy-MM-dd').format(d);
      final idx = dateStrToIndex[dateStr] ?? 0;
      final bp = bpByDate[dateStr];
      final y = bp != null ? bp.$1.toDouble() : 0.0;
      return FlSpot(idx.toDouble(), y);
    }).toList();
    final diastolicSpots = orderedDates.map((d) {
      final dateStr = DateFormat('yyyy-MM-dd').format(d);
      final idx = dateStrToIndex[dateStr] ?? 0;
      final bp = bpByDate[dateStr];
      final y = bp != null ? bp.$2.toDouble() : 0.0;
      return FlSpot(idx.toDouble(), y);
    }).toList();
    return SizedBox(
      height: chartHeight,
      width: chartWidth,
      child: LineChart(
        LineChartData(
          minX: visibleMinX,
          maxX: visibleMaxX,
          minY: visibleMinY ?? 0,
          maxY: visibleMaxY,
          gridData: const FlGridData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: true),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 5,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i >= 0 && i < orderedDates.length) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        DateFormat('M/d').format(orderedDates[i]),
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
          ),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              color: Colors.red,
              spots: systolicSpots,
              isCurved: true,
              barWidth: 3,
              dotData: const FlDotData(show: false),
            ),
            LineChartBarData(
              color: Colors.blueGrey,
              spots: diastolicSpots,
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
  const _DialysisChart({
    required this.machine,
    required this.manual,
    required this.orderedDates,
    this.selectedSeriesId,
    this.chartHeight = 280,
    this.chartWidth,
    this.visibleMinX,
    this.visibleMaxX,
    this.visibleMinY,
    this.visibleMaxY,
  });

  final List<DialysisRow> machine;
  final List<DialysisRow> manual;
  final List<DateTime> orderedDates;
  final String? selectedSeriesId;
  final double chartHeight;
  final double? chartWidth;
  final double? visibleMinX;
  final double? visibleMaxX;
  final double? visibleMinY;
  final double? visibleMaxY;

  @override
  Widget build(BuildContext context) {
    if (machine.isEmpty && manual.isEmpty) {
      return const Text('데이터가 없습니다.');
    }
    final dateStrToIndex = <String, int>{};
    for (var i = 0; i < orderedDates.length; i++) {
      dateStrToIndex[DateFormat('yyyy-MM-dd').format(orderedDates[i])] = i;
    }

    // 날짜별 기계/손투석 행 그룹
    final machineByDate = <String, List<DialysisRow>>{};
    for (final row in machine) {
      machineByDate.putIfAbsent(row.date, () => []).add(row);
    }
    final manualByDate = <String, List<DialysisRow>>{};
    for (final row in manual) {
      manualByDate.putIfAbsent(row.date, () => []).add(row);
    }

    int maxMachineSession = 0;
    int maxManualSession = 0;
    for (final rows in machineByDate.values) {
      for (final r in rows) {
        if (r.session > maxMachineSession) maxMachineSession = r.session;
      }
    }
    for (final rows in manualByDate.values) {
      for (final r in rows) {
        if (r.session > maxManualSession) maxManualSession = r.session;
      }
    }

    final lineBars = <LineChartBarData>[];
    // 투입량: 파랑 계열, 배약량: 주황 계열로 구분
    const colorInflow = Colors.blue;
    const colorOutflow = Colors.deepOrange;

    for (var s = 1; s <= maxMachineSession; s++) {
      final session = s;
      final inflowSpots = orderedDates.map((d) {
        final dateStr = DateFormat('yyyy-MM-dd').format(d);
        final idx = dateStrToIndex[dateStr] ?? -1;
        if (idx < 0) return FlSpot(d.day.toDouble(), 0);
        final rows = machineByDate[dateStr] ?? [];
        double y = 0.0;
        for (final r in rows) {
          if (r.session == session) {
            y = r.inflow;
            break;
          }
        }
        return FlSpot(idx.toDouble(), y);
      }).toList();
      final outflowSpots = orderedDates.map((d) {
        final dateStr = DateFormat('yyyy-MM-dd').format(d);
        final idx = dateStrToIndex[dateStr] ?? -1;
        if (idx < 0) return FlSpot(d.day.toDouble(), 0);
        final rows = machineByDate[dateStr] ?? [];
        double y = 0.0;
        for (final r in rows) {
          if (r.session == session) {
            y = r.outflow;
            break;
          }
        }
        return FlSpot(idx.toDouble(), y);
      }).toList();
      lineBars.add(
        LineChartBarData(
          color: colorInflow,
          spots: inflowSpots,
          isCurved: true,
          barWidth: 2,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: false),
        ),
      );
      lineBars.add(
        LineChartBarData(
          color: colorOutflow,
          spots: outflowSpots,
          isCurved: true,
          barWidth: 2,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: false),
        ),
      );
    }

    for (var s = 1; s <= maxManualSession; s++) {
      final session = s;
      final inflowSpots = orderedDates.map((d) {
        final dateStr = DateFormat('yyyy-MM-dd').format(d);
        final idx = dateStrToIndex[dateStr] ?? -1;
        if (idx < 0) return FlSpot(d.day.toDouble(), 0);
        final rows = manualByDate[dateStr] ?? [];
        double y = 0.0;
        for (final r in rows) {
          if (r.session == session) {
            y = r.inflow;
            break;
          }
        }
        return FlSpot(idx.toDouble(), y);
      }).toList();
      final outflowSpots = orderedDates.map((d) {
        final dateStr = DateFormat('yyyy-MM-dd').format(d);
        final idx = dateStrToIndex[dateStr] ?? -1;
        if (idx < 0) return FlSpot(d.day.toDouble(), 0);
        final rows = manualByDate[dateStr] ?? [];
        double y = 0.0;
        for (final r in rows) {
          if (r.session == session) {
            y = r.outflow;
            break;
          }
        }
        return FlSpot(idx.toDouble(), y);
      }).toList();
      lineBars.add(
        LineChartBarData(
          color: colorInflow,
          spots: inflowSpots,
          isCurved: true,
          barWidth: 2,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: false),
        ),
      );
      lineBars.add(
        LineChartBarData(
          color: colorOutflow,
          spots: outflowSpots,
          isCurved: true,
          barWidth: 2,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: false),
        ),
      );
    }

    final netSpots = orderedDates.map((d) {
      final dateStr = DateFormat('yyyy-MM-dd').format(d);
      final idx = dateStrToIndex[dateStr] ?? 0;
      double out = 0, inp = 0;
      for (final r in machineByDate[dateStr] ?? []) {
        out += r.outflow;
        inp += r.inflow;
      }
      for (final r in manualByDate[dateStr] ?? []) {
        out += r.outflow;
        inp += r.inflow;
      }
      final net = out - inp;
      return FlSpot(idx.toDouble(), net);
    }).toList();
    lineBars.add(
      LineChartBarData(
        color: Colors.green,
        spots: netSpots,
        isCurved: true,
        barWidth: 3,
        dotData: const FlDotData(show: true),
        belowBarData: BarAreaData(
          show: true,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.green.withValues(alpha: 0.4),
              Colors.green.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );

    // 세션별로 투입량·배약량 2개 라인씩: [m1_in, m1_out, m2_in, m2_out, ...], [손투석...], [net]
    List<LineChartBarData> displayBars = lineBars;
    if (selectedSeriesId != null) {
      if (selectedSeriesId!.startsWith('machine_')) {
        final s = int.tryParse(selectedSeriesId!.split('_').last) ?? 1;
        if (s >= 1 && s <= maxMachineSession) {
          final base = (s - 1) * 2;
          displayBars = [lineBars[base], lineBars[base + 1]];
        }
      } else if (selectedSeriesId!.startsWith('manual_')) {
        final s = int.tryParse(selectedSeriesId!.split('_').last) ?? 1;
        if (s >= 1 && s <= maxManualSession) {
          final base = maxMachineSession * 2 + (s - 1) * 2;
          displayBars = [lineBars[base], lineBars[base + 1]];
        }
      } else if (selectedSeriesId == 'net') {
        displayBars = [lineBars.last];
      }
    }

    final showLegend =
        selectedSeriesId != 'net' &&
        (selectedSeriesId == null ||
            selectedSeriesId!.startsWith('machine_') ||
            selectedSeriesId!.startsWith('manual_'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showLegend)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 14,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorInflow,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                const Text('투입량', style: TextStyle(fontSize: 12)),
                const SizedBox(width: 16),
                Container(
                  width: 14,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorOutflow,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 6),
                const Text('배약량', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        SizedBox(
          height: chartHeight,
          width: chartWidth,
          child: LineChart(
            LineChartData(
              minX: visibleMinX,
              maxX: visibleMaxX,
              minY: visibleMinY ?? 0,
              maxY: visibleMaxY,
              gridData: const FlGridData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: true),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    interval: 5,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i >= 0 && i < orderedDates.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            DateFormat('M/d').format(orderedDates[i]),
                            style: const TextStyle(fontSize: 10),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: displayBars,
            ),
          ),
        ),
      ],
    );
  }
}
