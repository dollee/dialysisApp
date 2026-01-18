import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
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
  bool _autoFilling = false;

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

  Future<void> _autoFillFromImage() async {
    final source = await _pickImageSource();
    if (source == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;

    setState(() => _autoFilling = true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.korean);
    try {
      final input = InputImage.fromFilePath(picked.path);
      final text = await recognizer.processImage(input);
      final pairs = _parseDialysisPairs(text);
      if (pairs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이미지에서 값을 찾지 못했습니다.')),
          );
        }
        return;
      }
      _applyDialysisPairs(pairs);
      if (mounted) {
        context.read<AppState>().addLog('기계투석 자동입력: ${pairs.length}건');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${pairs.length}건을 자동입력했습니다.')),
        );
      }
    } finally {
      await recognizer.close();
      if (mounted) {
        setState(() => _autoFilling = false);
      }
    }
  }

  Future<ImageSource?> _pickImageSource() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('카메라로 촬영'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('앨범에서 선택'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
  }

  List<_DialysisPair> _parseDialysisPairs(RecognizedText text) {
    final pairs = <_DialysisPair>[];
    final allNumbers = <double>[];
    final numberRegex = RegExp(r'([0-9]+(?:[\\.,][0-9]+)?)');

    for (final block in text.blocks) {
      for (final line in block.lines) {
        final lineText = line.text.trim();
        if (lineText.isEmpty) continue;

        final numericElements = <_NumericElement>[];
        for (final element in line.elements) {
          final match = numberRegex.firstMatch(element.text);
          final value = match?.group(1)?.replaceAll(',', '.');
          final parsed = value == null ? null : double.tryParse(value);
          if (parsed != null) {
            numericElements.add(
              _NumericElement(
                value: parsed,
                left: element.boundingBox.left,
              ),
            );
            allNumbers.add(parsed);
          }
        }

        numericElements.sort((a, b) => a.left.compareTo(b.left));
        if (numericElements.isEmpty) {
          continue;
        }

        final values = numericElements.map((e) => e.value).toList();
        final lefts = numericElements.map((e) => e.left).toList()..sort();
        final minLeft = lefts.first;
        final maxLeft = lefts.last;
        final span = (maxLeft - minLeft).abs();
        final boundary1 = minLeft + span * 0.33;
        final boundary2 = minLeft + span * 0.66;

        _NumericElement? sessionElement;
        _NumericElement? inflowElement;
        _NumericElement? outflowElement;
        for (final element in numericElements) {
          if (element.left < boundary1) {
            sessionElement ??= element;
          } else if (element.left < boundary2) {
            inflowElement ??= element;
          } else {
            outflowElement ??= element;
          }
        }

        if (sessionElement != null &&
            inflowElement != null &&
            outflowElement != null) {
          final session = sessionElement.value;
          final inflow = inflowElement.value;
          final outflow = outflowElement.value;
          if (session <= 99 && inflow >= 100 && outflow >= 100) {
            pairs.add(_DialysisPair(inflow, outflow));
            continue;
          }
        }
        if (values.length >= 3) {
          final session = values[0];
          final inflow = values[1];
          final outflow = values[2];
          if (session <= 99 && inflow >= 100 && outflow >= 100) {
            pairs.add(_DialysisPair(inflow, outflow));
            continue;
          }
        }

        if (values.length >= 2) {
          final inflow = values[values.length - 2];
          final outflow = values.last;
          if (inflow >= 100 || outflow >= 100) {
            pairs.add(_DialysisPair(inflow, outflow));
            continue;
          }
        }

        final matches = numberRegex.allMatches(lineText);
        final inlineNumbers = <double>[];
        for (final match in matches) {
          final value = match.group(1)?.replaceAll(',', '.');
          final parsed = value == null ? null : double.tryParse(value);
          if (parsed != null) {
            inlineNumbers.add(parsed);
            allNumbers.add(parsed);
          }
        }
        if (inlineNumbers.length >= 3 && inlineNumbers.first <= 99) {
          pairs.add(
            _DialysisPair(inlineNumbers[1], inlineNumbers[2]),
          );
        } else if (inlineNumbers.length >= 2) {
          pairs.add(
            _DialysisPair(
              inlineNumbers[inlineNumbers.length - 2],
              inlineNumbers.last,
            ),
          );
        }
      }
    }

    if (pairs.isNotEmpty) {
      return pairs;
    }

    final filteredNumbers = allNumbers.where((value) => value >= 100).toList();
    final fallbackPairs = <_DialysisPair>[];
    for (var i = 0; i + 1 < filteredNumbers.length; i += 2) {
      fallbackPairs.add(
        _DialysisPair(filteredNumbers[i], filteredNumbers[i + 1]),
      );
    }
    return fallbackPairs;
  }

  void _applyDialysisPairs(List<_DialysisPair> pairs) {
    setState(() {
      while (_rows.length < pairs.length) {
        _rows.add(_DialysisInputRow());
      }
      for (var i = 0; i < pairs.length; i++) {
        _rows[i].inflowController.text = _formatVolume(pairs[i].inflow);
        _rows[i].outflowController.text = _formatVolume(pairs[i].outflow);
      }
    });
  }

  String _formatVolume(double value) {
    if (value % 1 == 0) {
      return value.toStringAsFixed(0);
    }
    return value.toString();
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
        context
            .read<AppState>()
            .addLog('기계투석 입력 저장: ${rows.length}건');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('저장되었습니다.')),
        );
        await context.read<AppState>().applyMachineConsumption();
        await context.read<AppState>().maybeRequestDelivery(context);
        Navigator.of(context).popUntil((route) => route.isFirst);
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
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _autoFilling ? null : _autoFillFromImage,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                  ),
                  child: _autoFilling
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('자동입력'),
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

class _DialysisPair {
  const _DialysisPair(this.inflow, this.outflow);

  final double inflow;
  final double outflow;
}

class _NumericElement {
  const _NumericElement({required this.value, required this.left});

  final double value;
  final double left;
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
