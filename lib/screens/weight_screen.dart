import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/google_sheets_service.dart';
import '../state/app_state.dart';

class WeightScreen extends StatefulWidget {
  const WeightScreen({super.key});

  @override
  State<WeightScreen> createState() => _WeightScreenState();
}

class _WeightScreenState extends State<WeightScreen> {
  final TextEditingController _weightController = TextEditingController();
  DateTime _dateTime = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _weightController.dispose();
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

  Future<void> _loadFromHealth() async {
    final state = context.read<AppState>();
    final ok = await state.healthService.requestWeightAuthorization(write: false);
    if (!ok) return;
    final value = await state.healthService.fetchLatestWeight(_dateTime);
    if (value != null && mounted) {
      setState(() {
        _weightController.text = value.toStringAsFixed(1);
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final state = context.read<AppState>();
    final weight = double.tryParse(_weightController.text) ?? 0;
    final dateText = DateFormat('yyyy-MM-dd').format(_dateTime);
    final timeText = DateFormat('HH:mm').format(_dateTime);
    final entry = WeightEntry(date: dateText, time: timeText, weight: weight);
    try {
      await state.sheetsService.appendWeight(entry);
      if (state.writeWeightToHealth) {
        final ok = await state.healthService.requestWeightAuthorization(write: true);
        if (ok) {
          await state.healthService.writeWeight(weight, _dateTime);
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장되었습니다.')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final dateLabel = DateFormat('yyyy-MM-dd').format(_dateTime);
    return Scaffold(
      appBar: AppBar(title: const Text('체중입력')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('날짜: $dateLabel')),
                TextButton(onPressed: _pickDate, child: const Text('날짜 수정')),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _weightController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '체중',
                suffixText: 'kg',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadFromHealth,
              child: const Text('건강데이터 불러오기'),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: state.writeWeightToHealth,
              onChanged: (value) => state.setWriteWeightToHealth(value),
              title: const Text('건강데이터 추가'),
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
          ],
        ),
      ),
    );
  }
}
