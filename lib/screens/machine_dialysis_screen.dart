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

    // ignore: avoid_print
    print('[OCR] 이미지 선택: path=${picked.path} source=${source.name}');

    setState(() => _autoFilling = true);
    final recognizer = TextRecognizer(script: TextRecognitionScript.korean);
    try {
      final input = InputImage.fromFilePath(picked.path);
      // ignore: avoid_print
      print('[OCR] 텍스트 인식 시작...');
      final text = await recognizer.processImage(input);
      // ignore: avoid_print
      print('[OCR] 인식 완료. blocks=${text.blocks.length}');
      for (var bi = 0; bi < text.blocks.length; bi++) {
        final b = text.blocks[bi];
        // ignore: avoid_print
        print('[OCR]   block[$bi] lines=${b.lines.length}');
        for (var li = 0; li < b.lines.length; li++) {
          // ignore: avoid_print
          print('[OCR]     line[$li] text="${b.lines[li].text.trim()}"');
        }
      }
      final pairs = _parseDialysisPairs(text);
      // ignore: avoid_print
      print('[OCR] 파싱 결과: ${pairs.length}개 쌍');
      for (var i = 0; i < pairs.length; i++) {
        final p = pairs[i];
        // ignore: avoid_print
        print('[OCR]   쌍[$i] 회차=${p.sessionIndex >= 0 ? p.sessionIndex + 1 : "?"} 주입=${p.inflow} 배액=${p.outflow}');
      }
      if (pairs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이미지에서 값을 찾지 못했습니다.')),
          );
        }
        return;
      }
      final pairsToApply = pairs;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyDialysisPairs(pairsToApply);
        if (mounted) {
          context.read<AppState>().addLog('기계투석 자동입력: ${pairsToApply.length}건');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${pairsToApply.length}건을 자동입력했습니다.')),
          );
        }
      });
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
    final spatialNumbers = <_SpatialNum>[];
    final numberRegex = RegExp(r'([0-9]+(?:[\\.,][0-9]+)?)');
    var lineIndex = 0;

    for (final block in text.blocks) {
      for (final line in block.lines) {
        final lineText = line.text.trim();
        if (lineText.isEmpty) continue;

        // ignore: avoid_print
        print('[OCR:parse] 줄[$lineIndex] 원문="$lineText" elements=${line.elements.length}');

        final numericElements = <_NumericElement>[];
        for (final element in line.elements) {
          final raw = element.text.trim();
          double? parsed;
          if (raw == '-' || raw == '--') {
            parsed = 0.0;
            // ignore: avoid_print
            print('[OCR:parse]   요소 raw="$raw" → 0 (대시)');
          } else {
            final match = numberRegex.firstMatch(element.text);
            final value = match?.group(1)?.replaceAll(',', '.');
            parsed = value == null ? null : double.tryParse(value);
            // ignore: avoid_print
            print('[OCR:parse]   요소 raw="$raw" left=${element.boundingBox.left} top=${element.boundingBox.top} → parsed=$parsed');
          }
          if (parsed != null) {
            final left = element.boundingBox.left;
            final top = element.boundingBox.top;
            numericElements.add(_NumericElement(value: parsed, left: left));
            allNumbers.add(parsed);
            spatialNumbers.add(_SpatialNum(value: parsed, left: left, top: top));
          }
        }

        numericElements.sort((a, b) => a.left.compareTo(b.left));
        if (numericElements.isEmpty) {
          // ignore: avoid_print
          print('[OCR:parse]   → 숫자 없음, 스킵');
          lineIndex++;
          continue;
        }

        final values = numericElements.map((e) => e.value).toList();
        // ignore: avoid_print
        print('[OCR:parse]   정렬 후 values=$values lefts=${numericElements.map((e) => e.left.toStringAsFixed(0)).toList()}');
        final lefts = numericElements.map((e) => e.left).toList()..sort();
        final minLeft = lefts.first;
        final maxLeft = lefts.last;
        final span = (maxLeft - minLeft).abs();
        final boundary1 = minLeft + span * 0.33;
        final boundary2 = minLeft + span * 0.66;
        // ignore: avoid_print
        print('[OCR:parse]   구간 boundary1=$boundary1 boundary2=$boundary2');

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
          // ignore: avoid_print
          print('[OCR:parse]   분기: 3요소(위치기반) session=$session inflow=$inflow outflow=$outflow');
          if (session <= 99 &&
              inflow >= 0 &&
              outflow >= 0 &&
              (inflow > 0 || outflow > 0) &&
              inflow != outflow) {
            pairs.add(_DialysisPair(inflow, outflow, session.toInt()));
            // ignore: avoid_print
            print('[OCR:parse]   → 추가 (위치기반) 회차${session.toInt() + 1} ($inflow, $outflow)');
            lineIndex++;
            continue;
          }
          // ignore: avoid_print
          print('[OCR:parse]   → 조건 불충족(주입==배액 등) 스킵');
        }
        if (values.length >= 3) {
          final v0 = values[0];
          final v1 = values[1];
          final v2 = values[2];
          // ignore: avoid_print
          print('[OCR:parse]   분기: values.length>=3 v0=$v0 v1=$v1 v2=$v2');
          if (v0 <= 99 &&
              v1 >= 0 &&
              v2 >= 0 &&
              (v1 > 0 || v2 > 0) &&
              v1 != v2) {
            pairs.add(_DialysisPair(v1, v2, v0.toInt()));
            // ignore: avoid_print
            print('[OCR:parse]   → 추가 (3값) 회차${v0.toInt() + 1} ($v1, $v2)');
            lineIndex++;
            continue;
          }
          if (v0 >= 100 && v1 == v2 && v0 >= 0 && v1 >= 0) {
            pairs.add(_DialysisPair(v0, v1));
            // ignore: avoid_print
            print('[OCR:parse]   → 추가 (중복열 보정) ($v0, $v1)');
            lineIndex++;
            continue;
          }
        }

        // 행번호 + 값 하나: 주입 0, 배액 값 (예: 00행에 배액만 15)
        if (values.length == 2 &&
            values[0] <= 99 &&
            values[1] > 0 &&
            values[0] >= 0) {
          pairs.add(_DialysisPair(0, values[1], values[0].toInt()));
          // ignore: avoid_print
          print('[OCR:parse]   → 추가 (행번호+값1) 회차${values[0].toInt() + 1} (0, ${values[1]})');
          lineIndex++;
          continue;
        }

        // 한 줄에 숫자 2개만 있을 때 (쌍 또는 한쪽만: 주입/배액 중 하나 0)
        if (values.length >= 2) {
          final inflow = values[values.length - 2];
          final outflow = values.last;
          final bothLarge = inflow >= 100 && outflow >= 100 && inflow != outflow;
          final oneZero =
              (inflow == 0 && outflow > 0) || (inflow > 0 && outflow == 0);
          // ignore: avoid_print
          print('[OCR:parse]   분기: 2값 inflow=$inflow outflow=$outflow bothLarge=$bothLarge oneZero=$oneZero');
          if (bothLarge || oneZero) {
            pairs.add(_DialysisPair(inflow, outflow));
            // ignore: avoid_print
            print('[OCR:parse]   → 추가 (2값) ($inflow, $outflow)');
            lineIndex++;
            continue;
          }
        }

        // "-", "--"를 0으로 인식 (치료량 통계 화면 등)
        final normalizedLine = lineText
            .replaceAll('--', ' 0 ')
            .replaceAll(RegExp(r'\s-\s'), ' 0 ')
            .replaceAll(RegExp(r'^\s*-\s*'), '0 ')
            .replaceAll(RegExp(r'\s*-\s*$'), ' 0');
        final matches = numberRegex.allMatches(normalizedLine);
        final inlineNumbers = <double>[];
        for (final match in matches) {
          final value = match.group(1)?.replaceAll(',', '.');
          final parsed = value == null ? null : double.tryParse(value);
          if (parsed != null) {
            inlineNumbers.add(parsed);
          }
        }
        // ignore: avoid_print
        print('[OCR:parse]   inline(정규식) normalized="$normalizedLine" numbers=$inlineNumbers');
        if (inlineNumbers.length >= 3) {
          final first = inlineNumbers[0];
          final second = inlineNumbers[1];
          final third = inlineNumbers[2];
          if (first <= 99 &&
              second >= 0 &&
              third >= 0 &&
              (second > 0 || third > 0) &&
              second != third) {
            pairs.add(_DialysisPair(second, third, first.toInt()));
            // ignore: avoid_print
            print('[OCR:parse]   → 추가 (inline 3값) 회차${first.toInt() + 1} ($second, $third)');
          } else if (first >= 100 && second == third && second >= 0) {
            pairs.add(_DialysisPair(first, second));
            // ignore: avoid_print
            print('[OCR:parse]   → 추가 (inline 중복열) ($first, $second)');
          } else {
            // ignore: avoid_print
            print('[OCR:parse]   → inline 3값 조건 불충족 스킵');
          }
        } else if (inlineNumbers.length == 2 &&
            inlineNumbers[0] <= 99 &&
            inlineNumbers[1] > 0) {
          pairs.add(_DialysisPair(0, inlineNumbers[1], inlineNumbers[0].toInt()));
          // ignore: avoid_print
          print('[OCR:parse]   → 추가 (inline 행번호+값1) 회차${inlineNumbers[0].toInt() + 1} (0, ${inlineNumbers[1]})');
        } else if (inlineNumbers.length >= 2) {
          final a = inlineNumbers[inlineNumbers.length - 2];
          final b = inlineNumbers.last;
          final bothLarge = a >= 100 && b >= 100 && a != b;
          final oneZero = (a == 0 && b > 0) || (a > 0 && b == 0);
          if (bothLarge || oneZero) {
            pairs.add(_DialysisPair(a, b));
            // ignore: avoid_print
            print('[OCR:parse]   → 추가 (inline 2값) ($a, $b)');
          } else {
            // ignore: avoid_print
            print('[OCR:parse]   → inline 2값 조건 불충족 스킵');
          }
        } else {
          // ignore: avoid_print
          print('[OCR:parse]   → 이 줄에서 쌍 미추가');
        }
        lineIndex++;
      }
    }

    if (pairs.isNotEmpty) {
      // 기기 행 번호(00→0, 01→1, …) 순으로 정렬. 00=회차1, 01=회차2, …
      // ignore: avoid_print
      print('[OCR:parse] 줄 단위 쌍 ${pairs.length}개 → 회차 순 정렬');
      pairs.sort((a, b) {
        final ai = a.sessionIndex < 0 ? 999 : a.sessionIndex;
        final bi = b.sessionIndex < 0 ? 999 : b.sessionIndex;
        return ai.compareTo(bi);
      });
      return pairs;
    }

    // 줄 단위로 쌍을 못 찾았을 때만: 100 이상 숫자만 나열해 (0,1),(2,3)... 짝 지음.
    final filteredNumbers = allNumbers.where((value) => value >= 100).toList();
    // ignore: avoid_print
    print('[OCR:parse] fallback: 100 이상 숫자 ${filteredNumbers.length}개 = $filteredNumbers');
    if (filteredNumbers.length >= 2 &&
        filteredNumbers.length <= 20 &&
        filteredNumbers.length.isEven) {
      final fallbackPairs = <_DialysisPair>[];
      for (var i = 0; i + 1 < filteredNumbers.length; i += 2) {
        final a = filteredNumbers[i];
        final b = filteredNumbers[i + 1];
        if (a != b) {
          fallbackPairs.add(_DialysisPair(a, b));
          // ignore: avoid_print
          print('[OCR:parse] fallback 쌍 ($a, $b)');
        } else {
          // ignore: avoid_print
          print('[OCR:parse] fallback 스킵 (동일값 $a)');
        }
      }
      if (fallbackPairs.isNotEmpty) {
        // ignore: avoid_print
        print('[OCR:parse] fallback 결과 ${fallbackPairs.length}개 쌍 반환');
        return fallbackPairs;
      }
    } else {
      // ignore: avoid_print
      print('[OCR:parse] fallback 미사용 (짝수 아님 또는 개수 초과)');
    }

    // 위치 기반 fallback: OCR이 숫자를 한 블록씩만 반환할 때 (top, left) 순 정렬
    // 같은 행(top 비슷)에서 왼쪽→오른쪽 순으로 (행번호, 열1, 열2) 또는 (열1, 열2)로 쌍 구성
    if (pairs.isEmpty && spatialNumbers.isNotEmpty) {
      spatialNumbers.sort((a, b) {
        final c = a.top.compareTo(b.top);
        return c != 0 ? c : a.left.compareTo(b.left);
      });
      const topTolerance = 15.0;
      var i = 0;
      while (i < spatialNumbers.length) {
        final rowStart = i;
        final rowTop = spatialNumbers[i].top;
        while (i < spatialNumbers.length &&
            (spatialNumbers[i].top - rowTop).abs() <= topTolerance) {
          i++;
        }
        final row = spatialNumbers.sublist(rowStart, i);
        final values = row.map((e) => e.value).toList();
        if (values.length >= 3) {
          final v0 = values[0];
          final v1 = values[1];
          final v2 = values[2];
          if (v0 <= 99 && (v1 > 0 || v2 > 0) && v1 != v2) {
            pairs.add(_DialysisPair(v1, v2, v0.toInt()));
            // ignore: avoid_print
            print('[OCR:parse] 위치 fallback 행 회차${v0.toInt() + 1} ($v1, $v2)');
          } else if (v0 >= 100 && v1 != v2) {
            pairs.add(_DialysisPair(v0, v1));
            // ignore: avoid_print
            print('[OCR:parse] 위치 fallback 행 ($v0, $v1)');
          }
        } else if (values.length == 2) {
          final a = values[0];
          final b = values[1];
          if (a <= 99 && a >= 0 && b > 0) {
            pairs.add(_DialysisPair(0, b, a.toInt()));
            // ignore: avoid_print
            print('[OCR:parse] 위치 fallback 행 회차${a.toInt() + 1} (0, $b)');
          } else if ((a > 0 && b == 0) || (a == 0 && b > 0)) {
            pairs.add(_DialysisPair(a, b));
            // ignore: avoid_print
            print('[OCR:parse] 위치 fallback 행 2값 ($a, $b)');
          }
        }
      }
      if (pairs.isNotEmpty) {
        pairs.sort((a, b) {
          final ai = a.sessionIndex < 0 ? 999 : a.sessionIndex;
          final bi = b.sessionIndex < 0 ? 999 : b.sessionIndex;
          return ai.compareTo(bi);
        });
        // ignore: avoid_print
        print('[OCR:parse] 위치 fallback 결과 ${pairs.length}개 쌍 반환');
        return pairs;
      }
      // 행 단위로 못 묶었으면: 100 이상만 추출해 연속 쌍 (기존 방식)
      final byPosition = spatialNumbers
          .where((e) => e.value >= 100 || e.value == 0)
          .map((e) => e.value)
          .toList();
      // ignore: avoid_print
      print('[OCR:parse] 위치 fallback 연속쌍: ${byPosition.length}개 = $byPosition');
      for (var j = 0; j + 1 < byPosition.length; j += 2) {
        final a = byPosition[j];
        final b = byPosition[j + 1];
        if (a != b) {
          pairs.add(_DialysisPair(a, b));
          // ignore: avoid_print
          print('[OCR:parse] 위치 fallback 쌍 ($a, $b)');
        }
      }
      if (pairs.isNotEmpty) {
        // ignore: avoid_print
        print('[OCR:parse] 위치 fallback 연속쌍 결과 ${pairs.length}개 반환');
        return pairs;
      }
    }
    return pairs;
  }

  void _applyDialysisPairs(List<_DialysisPair> pairs) {
    if (!mounted) return;
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
  const _DialysisPair(this.inflow, this.outflow, [this.sessionIndex = -1]);

  final double inflow;
  final double outflow;
  /// 기기 화면 행 번호 (00→0, 01→1, …). -1이면 미확인.
  final int sessionIndex;
}

class _NumericElement {
  const _NumericElement({required this.value, required this.left});

  final double value;
  final double left;
}

class _SpatialNum {
  const _SpatialNum({
    required this.value,
    required this.left,
    required this.top,
  });

  final double value;
  final double left;
  final double top;
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
