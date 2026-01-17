import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/google_sheets_service.dart';
import '../state/app_state.dart';
import 'manual_dialysis_screen.dart';

class MachineDialysisScreen extends StatefulWidget {
  const MachineDialysisScreen({super.key});

  @override
  State<MachineDialysisScreen> createState() => _MachineDialysisScreenState();
}

class _MachineDialysisScreenState extends State<MachineDialysisScreen> {
  DateTime _dateTime = DateTime.now();
  final List<_DialysisInputRow> _rows = [_DialysisInputRow()];
  bool _saving = false;

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateTime,
      firstDate: DateTime(_dateTime.year - 1),
      lastDate: DateTime(_dateTime.year + 1),
    );
    if (picked != null) {
      setState(() {
        _dateTime = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _dateTime.hour,
          _dateTime.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_dateTime),
    );
    if (picked != null) {
      setState(() {
        _dateTime = DateTime(
          _dateTime.year,
          _dateTime.month,
          _dateTime.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  void _addRow() {
    setState(() {
      _rows.add(_DialysisInputRow());
    });
  }

  void _removeRow() {
    if (_rows.length <= 1) return;
    setState(() {
      _rows.removeLast().dispose();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final dateText = DateFormat('yyyy-MM-dd').format(_dateTime);
    final timeText = DateFormat('HH:mm').format(_dateTime);
    final rows = <DialysisRow>[];
    for (var i = 0; i < _rows.length; i++) {
      final inflow = double.tryParse(_rows[i].inflowController.text) ?? 0;
      final outflow = double.tryParse(_rows[i].outflowController.text) ?? 0;
      rows.add(
        DialysisRow(
          date: dateText,
          time: timeText,
          session: i + 1,
          inflow: inflow,
          outflow: outflow,
        ),
      );
    }

    try {
      await context.read<AppState>().sheetsService.appendMachineDialysis(rows);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장되었습니다.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = DateFormat('yyyy-MM-dd').format(_dateTime);
    final timeLabel = DateFormat('HH:mm').format(_dateTime);
    return Scaffold(
      appBar: AppBar(title: const Text('기계투석 입력')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('날짜와 시간'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(dateLabel)),
                TextButton(onPressed: _pickDate, child: const Text('날짜 수정')),
              ],
            ),
            Row(
              children: [
                Expanded(child: Text(timeLabel)),
                TextButton(onPressed: _pickTime, child: const Text('시간 수정')),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: _addRow,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text('+ 추가'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _removeRow,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  child: const Text('- 삭제'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _rows.length; i++)
              _DialysisRowCard(
                index: i + 1,
                row: _rows[i],
              ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('저장'),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ManualDialysisScreen()),
                );
              },
              child: const Text('손투석 입력'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialysisInputRow {
  final TextEditingController inflowController = TextEditingController();
  final TextEditingController outflowController = TextEditingController();

  void dispose() {
    inflowController.dispose();
    outflowController.dispose();
  }
}

class _DialysisRowCard extends StatelessWidget {
  const _DialysisRowCard({required this.index, required this.row});

  final int index;
  final _DialysisInputRow row;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            SizedBox(
              width: 60,
              child: Text('회차 $index'),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: row.inflowController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '주입량',
                  suffixText: 'L',
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: row.outflowController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '배액량',
                  suffixText: 'L',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
