import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/google_sheets_service.dart';
import '../state/app_state.dart';

class BloodPressureScreen extends StatefulWidget {
  const BloodPressureScreen({super.key});

  @override
  State<BloodPressureScreen> createState() => _BloodPressureScreenState();
}

class _BloodPressureScreenState extends State<BloodPressureScreen> {
  final TextEditingController _systolicController = TextEditingController();
  final TextEditingController _diastolicController = TextEditingController();
  DateTime _dateTime = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _systolicController.dispose();
    _diastolicController.dispose();
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
    final ok =
        await state.healthService.requestBloodPressureAuthorization(write: false);
    if (!ok) return;
    final result = await state.healthService.fetchLatestBloodPressure(_dateTime);
    if (result != null && mounted) {
      setState(() {
        _systolicController.text = result.systolic.toString();
        _diastolicController.text = result.diastolic.toString();
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final state = context.read<AppState>();
    final systolic = int.tryParse(_systolicController.text) ?? 0;
    final diastolic = int.tryParse(_diastolicController.text) ?? 0;
    final dateText = DateFormat('yyyy-MM-dd').format(_dateTime);
    final timeText = DateFormat('HH:mm').format(_dateTime);
    final entry = BloodPressureEntry(
      date: dateText,
      time: timeText,
      systolic: systolic,
      diastolic: diastolic,
    );
    try {
      await state.sheetsService.appendBloodPressure(entry);
      if (state.writeBloodPressureToHealth) {
        final ok = await state.healthService
            .requestBloodPressureAuthorization(write: true);
        if (ok) {
          await state.healthService.writeBloodPressure(
            systolic: systolic,
            diastolic: diastolic,
            date: _dateTime,
          );
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장되었습니다.')),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
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
      appBar: AppBar(title: const Text('혈압입력')),
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
              controller: _systolicController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '수축기',
                suffixText: 'mmHg',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _diastolicController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '이완기',
                suffixText: 'mmHg',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadFromHealth,
              child: const Text('건강데이터 불러오기'),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: state.writeBloodPressureToHealth,
              onChanged: (value) => state.setWriteBloodPressureToHealth(value),
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
