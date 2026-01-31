import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/google_sheets_service.dart';
import 'preprocess_image.dart';
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
    try {
      final input = InputImage.fromFilePath(picked.path);
      // ignore: avoid_print
      print('[OCR] 텍스트 인식 시작 (한국어)...');
      final recognizerKo = TextRecognizer(script: TextRecognitionScript.korean);
      final textKo = await recognizerKo.processImage(input);
      await recognizerKo.close();
      // ignore: avoid_print
      print('[OCR] 한국어 인식 완료. blocks=${textKo.blocks.length}');
      for (var bi = 0; bi < textKo.blocks.length; bi++) {
        final b = textKo.blocks[bi];
        for (var li = 0; li < b.lines.length; li++) {
          // ignore: avoid_print
          print('[OCR]   ko line "${b.lines[li].text.trim()}"');
        }
      }
      // ignore: avoid_print
      print('[OCR] 라틴(숫자) 인식 실행...');
      final recognizerLa = TextRecognizer(script: TextRecognitionScript.latin);
      final textLa = await recognizerLa.processImage(input);
      await recognizerLa.close();
      // ignore: avoid_print
      print('[OCR] 라틴 인식 완료. blocks=${textLa.blocks.length}');
      for (var bi = 0; bi < textLa.blocks.length; bi++) {
        final b = textLa.blocks[bi];
        for (var li = 0; li < b.lines.length; li++) {
          // ignore: avoid_print
          print('[OCR]   la line "${b.lines[li].text.trim()}"');
        }
      }

      // 치료량 통계 화면 등: 원본에서 숫자를 거의 못 찾으면 전처리(그레이+대비) 이미지로 추가 OCR
      List<_DialysisPair> pairs = _parseDialysisPairs(textKo, textLa);
      final prePath = await preprocessImageForOcr(picked.path);
      if (prePath != null) {
        try {
          final inputPre = InputImage.fromFilePath(prePath);
          final recKoPre = TextRecognizer(script: TextRecognitionScript.korean);
          final textPreKo = await recKoPre.processImage(inputPre);
          await recKoPre.close();
          final recLaPre = TextRecognizer(script: TextRecognitionScript.latin);
          final textPreLa = await recLaPre.processImage(inputPre);
          await recLaPre.close();
          // ignore: avoid_print
          print('[OCR] 전처리 이미지 원문(한글):');
          for (final b in textPreKo.blocks) {
            for (final line in b.lines) {
              // ignore: avoid_print
              print('[OCR]   ko(pre) "${line.text.trim()}"');
            }
          }
          // ignore: avoid_print
          print('[OCR] 전처리 이미지 원문(라틴):');
          for (final b in textPreLa.blocks) {
            for (final line in b.lines) {
              // ignore: avoid_print
              print('[OCR]   la(pre) "${line.text.trim()}"');
            }
          }
          // 전처리 이미지는 1.5배 확대됨 → 좌표를 원본 비율(1/1.5)로 맞춰야 행 그룹이 맞음
          const preScale = 1.0 / 1.5;
          final merged = <_SpatialNum>[];
          for (final text in [textKo, textLa]) {
            for (final n in _collectSpatialNumbers(text)) {
              if (_isDuplicateSpatial(merged, n.value, n.left, n.top)) continue;
              merged.add(n);
            }
          }
          for (final text in [textPreKo, textPreLa]) {
            for (final n in _collectSpatialNumbers(text)) {
              final left = n.left * preScale;
              final top = n.top * preScale;
              if (_isDuplicateSpatial(merged, n.value, left, top)) continue;
              merged.add(_SpatialNum(value: n.value, left: left, top: top));
            }
          }
          // iOS는 행 기준만 사용. Android는 열 기준(세로 인식) 우선.
          final rowPairs = _parseTableByPosition(merged);
          final columnPairs = !Platform.isIOS ? _parseTableByColumnMajor(merged) : <_DialysisPair>[];
          if (!Platform.isIOS && columnPairs.length >= 4 && columnPairs.length >= rowPairs.length) {
            pairs = columnPairs;
            // ignore: avoid_print
            print('[OCR] 전처리 이미지 병합 후 열 기준(세로 인식) ${pairs.length}개 쌍 사용');
          } else if (rowPairs.length > pairs.length && rowPairs.length >= 2) {
            pairs = rowPairs;
            // ignore: avoid_print
            print('[OCR] 전처리 이미지 병합 후 ${pairs.length}개 쌍 사용');
          }
        } catch (e) {
          // ignore: avoid_print
          print('[OCR] 전처리 OCR 실패: $e');
        }
        await deletePreprocessedFile(prePath);
      }
      // ignore: avoid_print
      print('[OCR] 최종 파싱 결과: ${pairs.length}개 쌍');
      for (var i = 0; i < pairs.length; i++) {
        final p = pairs[i];
        // ignore: avoid_print
        print(
          '[OCR]   쌍[$i] 회차=${p.sessionIndex >= 0 ? p.sessionIndex + 1 : "?"} 주입=${p.inflow} 배액=${p.outflow}',
        );
      }
      if (pairs.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('이미지에서 값을 찾지 못했습니다.')));
        }
        return;
      }
      final pairsToApply = pairs;
      final usedSingleValueFallback =
          pairs.length == 1 && pairs[0].inflow == 0 && pairs[0].outflow >= 100;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _applyDialysisPairs(pairsToApply);
        if (mounted) {
          context.read<AppState>().addLog('기계투석 자동입력: ${pairsToApply.length}건');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                usedSingleValueFallback
                    ? '숫자 1개만 인식됨. 배액만 입력했고 주입은 0으로 채웠습니다. 필요하면 수동 수정해 주세요.'
                    : '${pairsToApply.length}건을 자동입력했습니다.',
              ),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      });
    } finally {
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

  static const _spatialDedupePx = 25.0;
  /// 같은 행으로 묶을 top 차이(px). 첫/끝 행이 잘려서 [0]만 또는 회차만 나오지 않도록 충분히 크게.
  static const _topTolerance = 48.0;
  /// 같은 열로 묶을 left 차이(px). OCR이 세로(왼쪽→오른쪽, 위→아래)로 인식할 때 열 그룹화용.
  static const _leftTolerance = 50.0;

  bool _isDuplicateSpatial(
    List<_SpatialNum> list,
    double value,
    double left,
    double top,
  ) {
    return list.any(
      (e) =>
          (e.left - left).abs() < _spatialDedupePx &&
          (e.top - top).abs() < _spatialDedupePx &&
          e.value == value,
    );
  }

  /// 대시/하이픈류 문자열이면 true (OCR에서 미측정 등으로 "-" 표시된 경우 0으로 처리).
  static bool _isDashLike(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return false;
    if (s == '-' || s == '--') return true;
    if (s == '－' || s == '—' || s == '–') return true; // 전각/em/en dash
    if (s.length == 1 && RegExp(r'[\-\－\—\–]').hasMatch(s)) return true;
    return false;
  }

  /// 요소 텍스트에서 "-"를 0으로 치환한 뒤 숫자만 추출 (한 요소에 "00 - 1909"처럼 들어온 경우 대비).
  static List<double> _numbersFromElementText(String elementText) {
    final normalized = elementText
        .replaceAll('－', '-')
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll(RegExp(r'\s-\s'), ' 0 ')
        .replaceAll(RegExp(r'^\s*-\s*'), '0 ')
        .replaceAll(RegExp(r'\s*-\s*$'), ' 0')
        .replaceAll(RegExp(r'(?<=\d)-(?=\d)'), ' 0 ');
    final numberRegex = RegExp(r'([0-9]+(?:[\\.,][0-9]+)?)');
    final out = <double>[];
    for (final m in numberRegex.allMatches(normalized)) {
      final s = m.group(1)?.replaceAll(',', '.');
      final v = s == null ? null : double.tryParse(s);
      if (v != null) out.add(v);
    }
    return out;
  }

  /// OCR 결과에서 숫자/대시 요소만 추출해 (left, top)과 함께 수집. 대시는 0으로.
  List<_SpatialNum> _collectSpatialNumbers(RecognizedText text) {
    final numberRegex = RegExp(r'([0-9]+(?:[\\.,][0-9]+)?)');
    final list = <_SpatialNum>[];
    for (final block in text.blocks) {
      for (final line in block.lines) {
        for (final element in line.elements) {
          final raw = element.text.trim();
          final left = element.boundingBox.left;
          final top = element.boundingBox.top;
          final width = element.boundingBox.right - element.boundingBox.left;

          // 요소 전체에 "-"가 섞여 있으면 정규화 후 숫자 추출 (한 요소에 "00 - 1909" 등). 행당 3열만 쓰므로 최대 3개만 추가.
          final fromLine = _numbersFromElementText(element.text);
          if (fromLine.isNotEmpty) {
            final take = fromLine.length > 3 ? 3 : fromLine.length;
            // ignore: avoid_print
            print('[OCR:수집] 원문="${element.text}" → 숫자들=$fromLine (사용 $take개)');
            for (var idx = 0; idx < take; idx++) {
              final value = fromLine[idx];
              final leftI = width > 0
                  ? left + width * (idx + 0.5) / take
                  : left + (idx * 50.0);
              if (_isDuplicateSpatial(list, value, leftI, top)) continue;
              list.add(_SpatialNum(value: value, left: leftI, top: top));
            }
            continue;
          }

          double? value;
          if (_isDashLike(raw)) {
            value = 0.0;
            // ignore: avoid_print
            print('[OCR:수집] 원문="$raw" → 값=$value (대시)');
          } else {
            final match = numberRegex.firstMatch(element.text);
            final s = match?.group(1)?.replaceAll(',', '.');
            value = s == null ? null : double.tryParse(s);
          }
          if (value == null) continue;
          if (_isDuplicateSpatial(list, value, left, top)) continue;
          if (!_isDashLike(raw)) {
            // ignore: avoid_print
            print('[OCR:수집] 원문="${element.text}" → 값=$value');
          }
          list.add(_SpatialNum(value: value, left: left, top: top));
        }
      }
    }
    return list;
  }

  /// 치료량 통계: OCR이 세로(왼쪽 열→오른쪽 열, 위→아래)로 인식할 때. 열로 그룹 후 행으로 맞추고, '-' 누락은 0으로 패딩.
  List<_DialysisPair> _parseTableByColumnMajor(List<_SpatialNum> spatialNumbers) {
    if (spatialNumbers.isEmpty) return [];
    final sorted = List<_SpatialNum>.from(spatialNumbers)
      ..sort((a, b) {
        final c = a.left.compareTo(b.left);
        return c != 0 ? c : a.top.compareTo(b.top);
      });
    var i = 0;
    final columns = <List<double>>[];
    while (i < sorted.length) {
      final colLeft = sorted[i].left;
      final col = <_SpatialNum>[];
      while (i < sorted.length &&
          (sorted[i].left - colLeft).abs() <= _leftTolerance) {
        col.add(sorted[i]);
        i++;
      }
      col.sort((a, b) => a.top.compareTo(b.top));
      columns.add(col.map((e) => e.value).toList());
    }
    if (columns.isEmpty || columns.length > 4) return [];
    final sessionColIdx = columns.indexWhere(
      (col) => col.every((v) => v >= 0 && v <= 99) && col.length >= 2,
    );
    if (sessionColIdx < 0) return [];
    final col0 = columns[sessionColIdx];
    final dataCols = columns
        .asMap()
        .entries
        .where((e) => e.key != sessionColIdx)
        .map((e) => e.value)
        .toList();
    final col1 = dataCols.isNotEmpty ? dataCols[0] : <double>[];
    final col2 = dataCols.length > 1 ? dataCols[1] : <double>[];
    final nRows = col0.length;
    final pairs = <_DialysisPair>[];
    void addPair(double col2Val, double col3Val, int session) {
      pairs.add(_DialysisPair(col3Val, col2Val, session));
    }
    for (var r = 0; r < nRows; r++) {
      final session = col0[r].toInt();
      if (session < 0 || session > 99) continue;
      double v1 = 0;
      double v2 = 0;
      if (col1.length == nRows) {
        v1 = col1[r];
      } else if (col1.length == nRows - 1) {
        v1 = r == 0 ? 0.0 : col1[r - 1];
      } else if (r < col1.length) {
        v1 = col1[r];
      }
      if (col2.length == nRows) {
        v2 = col2[r];
      } else if (col2.length == nRows - 1) {
        v2 = r == nRows - 1 ? 0.0 : col2[r];
      } else if (r < col2.length) {
        v2 = col2[r];
      }
      if (v1 > 0 || v2 > 0) addPair(v2, v1, session);
    }
    if (pairs.length < 2) return [];
    pairs.sort((a, b) => a.sessionIndex.compareTo(b.sessionIndex));
    // ignore: avoid_print
    print('[OCR:parse] 열 기준(세로 인식) ${pairs.length}개 쌍');
    return pairs;
  }

  /// 치료량 통계 테이블: (top, left)로 행 묶은 뒤 행당 2~3값을 (회차, 주입, 배액)으로 파싱.
  List<_DialysisPair> _parseTableByPosition(List<_SpatialNum> spatialNumbers) {
    if (spatialNumbers.isEmpty) return [];
    final sorted = List<_SpatialNum>.from(spatialNumbers)
      ..sort((a, b) {
        final c = a.top.compareTo(b.top);
        return c != 0 ? c : a.left.compareTo(b.left);
      });
    final pairs = <_DialysisPair>[];
    int? pendingSession; // 이전 행이 [회차]만 있었을 때 보관
    var i = 0;
    while (i < sorted.length) {
      final rowTop = sorted[i].top;
      final row = <_SpatialNum>[];
      while (i < sorted.length &&
          (sorted[i].top - rowTop).abs() <= _topTolerance) {
        row.add(sorted[i]);
        i++;
      }
      final values = row.map((e) => e.value).toList();

      // 기기 화면 열 순서: (회차, 배액, 주입) → 쌍은 (주입, 배액)으로 저장
      void addPair(double col2, double col3, int session) {
        pairs.add(_DialysisPair(col3, col2, session));
      }

      // 이전 행이 [회차]만 있었을 때: 이번 행이 2값이면 합쳐 한 쌍, 1값(작은 수)이면 배액만으로 한 쌍
      if (pendingSession != null) {
        if (values.length == 2) {
          final a = values[0];
          final b = values[1];
          if ((a >= 100 || b >= 100) && a >= 0 && b >= 0) {
            addPair(a, b, pendingSession);
            pendingSession = null;
            continue;
          }
        } else if (values.length == 1 && values[0] > 0 && values[0] < 100) {
          addPair(values[0], 0, pendingSession);
          pendingSession = null;
          continue;
        }
        pairs.add(_DialysisPair(0, 0, pendingSession));
        pendingSession = null;
      }

      // 인접 행이 한 그룹으로 묶였을 때: 4~6개 값이면 여러 행으로 나눔 (치료량 통계 00~05)
      if (values.length == 6) {
        final v0 = values[0], v1 = values[1], v2 = values[2];
        final v3 = values[3], v4 = values[4], v5 = values[5];
        if (v0 <= 99 && (v1 > 0 || v2 > 0) && v1 != v2) {
          addPair(v1, v2, v0.toInt());
        }
        if (v3 <= 99 && (v4 > 0 || v5 > 0) && v4 != v5) {
          addPair(v4, v5, v3.toInt());
        }
      } else if (values.length == 5) {
        final v0 = values[0], v1 = values[1], v2 = values[2];
        final v3 = values[3], v4 = values[4];
        if (v0 <= 99 && (v1 > 0 || v2 > 0) && v1 != v2) {
          addPair(v1, v2, v0.toInt());
        }
        // 두 번째 행: (v3=05, v4=1475) → 회차5, 주입1475, 배액0
        if (v3 <= 99 && v3 >= 0 && v4 >= 0 && (v3 > 0 || v4 > 0)) {
          final col2 = v4 >= 100 ? v4 : 0.0;
          final col3 = v4 >= 100 ? 0.0 : v4;
          addPair(col2, col3, v3.toInt());
        } else if (v3 >= 100 && v4 >= 100 && v3 != v4) {
          addPair(v3, v4, -1);
        }
      } else if (values.length == 4) {
        final v0 = values[0], v1 = values[1], v2 = values[2];
        final v3 = values[3];
        if (v0 <= 99 && (v1 > 0 || v2 > 0) && v1 != v2) {
          addPair(v1, v2, v0.toInt());
        }
        if (v3 >= 100) {
          // 4값 = 두 행이 묶인 경우: 두 번째 행은 회차 v0+1 (예: [4,1999,2391,1499] → 회차5 주입1499 배액0)
          addPair(v3, 0, v0 <= 99 ? v0.toInt() + 1 : pairs.length);
        }
      } else if (values.length >= 3) {
        final v0 = values[0];
        final v1 = values[1];
        final v2 = values[2];
        if (v0 <= 99 && (v1 > 0 || v2 > 0) && v1 != v2) {
          addPair(v1, v2, v0.toInt());
        } else if (v0 >= 100 && v1 != v2) {
          addPair(v0, v1, -1);
        }
      } else if (values.length == 2) {
        final a = values[0];
        final b = values[1];
        if (a <= 99 && a >= 0 && b >= 0 && (a > 0 || b > 0)) {
          // 회차 + 값 1개: 100 이상이면 주입만, 미만이면 배액만 (예: [0,26]→주입0 배액26, [0,2001]→주입2001 배액0)
          final col2 = b >= 100 ? 0.0 : b;
          final col3 = b >= 100 ? b : 0.0;
          addPair(col2, col3, a.toInt());
        } else if ((a > 0 && b == 0) || (a == 0 && b > 0)) {
          addPair(a, b, -1);
        } else if (a >= 100 && b >= 100 && a != b) {
          addPair(a, b, -1);
        }
      } else if (values.length == 1) {
        if (values[0] >= 100) {
          addPair(values[0], 0, pairs.length);
        } else if (values[0] > 0 && values[0] < 100 && pairs.isEmpty) {
          // 첫 행이 작은 숫자 하나만 있을 때(예: 배액 26만 인식) → 회차 0 주입 0 배액 value
          addPair(values[0], 0, 0);
        } else if (values[0] <= 99 && values[0] >= 0) {
          // 회차만 있는 행: 다음 행이 2값이면 합쳐서 한 쌍으로, 아니면 마지막에 (0,0) 추가
          pendingSession = values[0].toInt();
        }
      }
    }
    if (pendingSession != null) {
      pairs.add(_DialysisPair(0, 0, pendingSession));
    }
    if (pairs.isEmpty) return [];
    pairs.sort((a, b) {
      final ai = a.sessionIndex < 0 ? 999 : a.sessionIndex;
      final bi = b.sessionIndex < 0 ? 999 : b.sessionIndex;
      return ai.compareTo(bi);
    });
    // 치료량 통계: OCR이 00을 27로 읽는 등 회차가 틀리면, 4~7개일 때 행 순서대로 0..n-1 재할당
    if (pairs.length >= 4 && pairs.length <= 7) {
      final anyBadSession = pairs.any(
        (p) => p.sessionIndex < 0 || p.sessionIndex > 15,
      );
      if (anyBadSession) {
        for (var j = 0; j < pairs.length; j++) {
          final p = pairs[j];
          pairs[j] = _DialysisPair(p.inflow, p.outflow, j);
        }
      }
    }
    return pairs;
  }

  List<_DialysisPair> _parseDialysisPairs(
    RecognizedText text1, [
    RecognizedText? text2,
  ]) {
    // 치료량 통계 화면: 한/라틴 둘 다 있으면 공간(행) 기반 테이블 파싱을 먼저 시도
    if (text2 != null) {
      final merged = <_SpatialNum>[];
      for (final text in [text1, text2]) {
        for (final n in _collectSpatialNumbers(text)) {
          if (_isDuplicateSpatial(merged, n.value, n.left, n.top)) continue;
          merged.add(n);
        }
      }
      // iOS는 OCR 순서가 다르므로 행 기준만 사용. Android는 열 기준(세로 인식) 우선.
      if (!Platform.isIOS) {
        final columnPairs = _parseTableByColumnMajor(merged);
        if (columnPairs.length >= 4) {
          // ignore: avoid_print
          print('[OCR:parse] 치료량 통계 테이블(열 기준/세로 인식) ${columnPairs.length}개 쌍 사용');
          return columnPairs;
        }
      }
      final rowPairs = _parseTableByPosition(merged);
      if (rowPairs.length >= 4) {
        // ignore: avoid_print
        print('[OCR:parse] 치료량 통계 테이블(행 기준) ${rowPairs.length}개 쌍 사용');
        return rowPairs;
      }
    }

    final pairs = <_DialysisPair>[];
    final allNumbers = <double>[];
    final spatialNumbers = <_SpatialNum>[];
    final numberRegex = RegExp(r'([0-9]+(?:[\\.,][0-9]+)?)');
    var lineIndex = 0;

    for (final text in [text1, if (text2 != null) text2]) {
      for (final block in text.blocks) {
        for (final line in block.lines) {
          final lineText = line.text.trim();
          if (lineText.isEmpty) continue;

          // ignore: avoid_print
          print(
            '[OCR:parse] 줄[$lineIndex] 원문="$lineText" elements=${line.elements.length}',
          );

          final numericElements = <_NumericElement>[];
          for (final element in line.elements) {
            final raw = element.text.trim();
            double? parsed;
            if (_isDashLike(raw)) {
              parsed = 0.0;
              // ignore: avoid_print
              print('[OCR:parse]   요소 raw="$raw" → 0 (대시)');
            } else {
              final match = numberRegex.firstMatch(element.text);
              final value = match?.group(1)?.replaceAll(',', '.');
              parsed = value == null ? null : double.tryParse(value);
              // ignore: avoid_print
              print(
                '[OCR:parse]   요소 raw="$raw" left=${element.boundingBox.left} top=${element.boundingBox.top} → parsed=$parsed',
              );
            }
            if (parsed != null) {
              final left = element.boundingBox.left;
              final top = element.boundingBox.top;
              if (_isDuplicateSpatial(spatialNumbers, parsed, left, top)) {
                // ignore: avoid_print
                print('[OCR:parse]   → 중복 위치 스킵 (한/라틴 병합)');
                continue;
              }
              numericElements.add(_NumericElement(value: parsed, left: left));
              allNumbers.add(parsed);
              spatialNumbers.add(
                _SpatialNum(value: parsed, left: left, top: top),
              );
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
          print(
            '[OCR:parse]   정렬 후 values=$values lefts=${numericElements.map((e) => e.left.toStringAsFixed(0)).toList()}',
          );
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
            print(
              '[OCR:parse]   분기: 3요소(위치기반) session=$session inflow=$inflow outflow=$outflow',
            );
            if (session <= 99 &&
                inflow >= 0 &&
                outflow >= 0 &&
                (inflow > 0 || outflow > 0) &&
                inflow != outflow) {
              pairs.add(_DialysisPair(outflow, inflow, session.toInt()));
              // ignore: avoid_print
              print(
                '[OCR:parse]   → 추가 (위치기반) 회차${session.toInt() + 1} ($inflow, $outflow)',
              );
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
              pairs.add(_DialysisPair(v2, v1, v0.toInt()));
              // ignore: avoid_print
              print('[OCR:parse]   → 추가 (3값) 회차${v0.toInt() + 1} ($v1, $v2)');
              lineIndex++;
              continue;
            }
            if (v0 >= 100 && v1 == v2 && v0 >= 0 && v1 >= 0) {
              pairs.add(_DialysisPair(v1, v0));
              // ignore: avoid_print
              print('[OCR:parse]   → 추가 (중복열 보정) ($v0, $v1)');
              lineIndex++;
              continue;
            }
          }

          // 행번호 + 값 하나: 100 이상이면 주입만, 미만이면 배액만 (치료량 통계 00: -, 8 / 05: 1475, -)
          if (values.length == 2 &&
              values[0] <= 99 &&
              values[1] > 0 &&
              values[0] >= 0) {
            final inflow = values[1] >= 100 ? values[1] : 0.0;
            final outflow = values[1] >= 100 ? 0.0 : values[1];
            pairs.add(_DialysisPair(outflow, inflow, values[0].toInt()));
            // ignore: avoid_print
            print(
              '[OCR:parse]   → 추가 (행번호+값1) 회차${values[0].toInt() + 1} ($inflow, $outflow)',
            );
            lineIndex++;
            continue;
          }

          // 한 줄에 숫자 2개만 있을 때 (쌍 또는 한쪽만: 주입/배액 중 하나 0)
          if (values.length >= 2) {
            final inflow = values[values.length - 2];
            final outflow = values.last;
            final bothLarge =
                inflow >= 100 && outflow >= 100 && inflow != outflow;
            final oneZero =
                (inflow == 0 && outflow > 0) || (inflow > 0 && outflow == 0);
            // ignore: avoid_print
            print(
              '[OCR:parse]   분기: 2값 inflow=$inflow outflow=$outflow bothLarge=$bothLarge oneZero=$oneZero',
            );
            if (bothLarge || oneZero) {
              pairs.add(_DialysisPair(outflow, inflow));
              // ignore: avoid_print
              print('[OCR:parse]   → 추가 (2값) ($inflow, $outflow)');
              lineIndex++;
              continue;
            }
          }

          // "-", "--", 전각/em/en dash를 0으로 인식 (치료량 통계 화면 등)
          final normalizedLine = lineText
              .replaceAll('－', '-')
              .replaceAll('—', '-')
              .replaceAll('–', '-')
              .replaceAll('--', ' 0 ')
              .replaceAll(RegExp(r'\s-\s'), ' 0 ')
              .replaceAll(RegExp(r'^\s*-\s*'), '0 ')
              .replaceAll(RegExp(r'\s*-\s*$'), ' 0')
              .replaceAll(RegExp(r'(?<=\d)-(?=\d)'), ' 0 ');
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
          print(
            '[OCR:parse]   inline(정규식) normalized="$normalizedLine" numbers=$inlineNumbers',
          );
          if (inlineNumbers.length >= 3) {
            final first = inlineNumbers[0];
            final second = inlineNumbers[1];
            final third = inlineNumbers[2];
            if (first <= 99 &&
                second >= 0 &&
                third >= 0 &&
                (second > 0 || third > 0) &&
                second != third) {
              pairs.add(_DialysisPair(third, second, first.toInt()));
              // ignore: avoid_print
              print(
                '[OCR:parse]   → 추가 (inline 3값) 회차${first.toInt() + 1} ($second, $third)',
              );
            } else if (first >= 100 && second == third && second >= 0) {
              pairs.add(_DialysisPair(second, first));
              // ignore: avoid_print
              print('[OCR:parse]   → 추가 (inline 중복열) ($first, $second)');
            } else {
              // ignore: avoid_print
              print('[OCR:parse]   → inline 3값 조건 불충족 스킵');
            }
          } else if (inlineNumbers.length == 2 &&
              inlineNumbers[0] <= 99 &&
              inlineNumbers[1] > 0) {
            final inflow = inlineNumbers[1] >= 100 ? inlineNumbers[1] : 0.0;
            final outflow = inlineNumbers[1] >= 100 ? 0.0 : inlineNumbers[1];
            pairs.add(_DialysisPair(outflow, inflow, inlineNumbers[0].toInt()));
            // ignore: avoid_print
            print(
              '[OCR:parse]   → 추가 (inline 행번호+값1) 회차${inlineNumbers[0].toInt() + 1} ($inflow, $outflow)',
            );
          } else if (inlineNumbers.length >= 2) {
            final a = inlineNumbers[inlineNumbers.length - 2];
            final b = inlineNumbers.last;
            final bothLarge = a >= 100 && b >= 100 && a != b;
            final oneZero = (a == 0 && b > 0) || (a > 0 && b == 0);
            if (bothLarge || oneZero) {
              pairs.add(_DialysisPair(b, a));
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
    print(
      '[OCR:parse] fallback: 100 이상 숫자 ${filteredNumbers.length}개 = $filteredNumbers',
    );
    if (filteredNumbers.length >= 2 &&
        filteredNumbers.length <= 20 &&
        filteredNumbers.length.isEven) {
      final fallbackPairs = <_DialysisPair>[];
      for (var i = 0; i + 1 < filteredNumbers.length; i += 2) {
        final a = filteredNumbers[i];
        final b = filteredNumbers[i + 1];
        if (a != b) {
          fallbackPairs.add(_DialysisPair(b, a));
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
    } else if (filteredNumbers.length == 1 && filteredNumbers[0] >= 100) {
      // 숫자 1개만 인식된 경우(예: 치료량 통계 화면에서 배액만): 1회차 (주입 0, 배액 value)
      pairs.add(_DialysisPair(0, filteredNumbers[0]));
      // ignore: avoid_print
      print('[OCR:parse] fallback 단일값 → 1회차 (0, ${filteredNumbers[0]})');
      return pairs;
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
      // 치료량 통계 테이블: 같은 행의 숫자들이 세로로 약간 어긋날 수 있음
      var i = 0;
      while (i < spatialNumbers.length) {
        final rowStart = i;
        final rowTop = spatialNumbers[i].top;
        while (i < spatialNumbers.length &&
            (spatialNumbers[i].top - rowTop).abs() <= _topTolerance) {
          i++;
        }
        final row = spatialNumbers.sublist(rowStart, i);
        final values = row.map((e) => e.value).toList();
        if (values.length >= 3) {
          final v0 = values[0];
          final v1 = values[1];
          final v2 = values[2];
          if (v0 <= 99 && (v1 > 0 || v2 > 0) && v1 != v2) {
            pairs.add(_DialysisPair(v2, v1, v0.toInt()));
            // ignore: avoid_print
            print('[OCR:parse] 위치 fallback 행 회차${v0.toInt() + 1} ($v1, $v2)');
          } else if (v0 >= 100 && v1 != v2) {
            pairs.add(_DialysisPair(v1, v0));
            // ignore: avoid_print
            print('[OCR:parse] 위치 fallback 행 ($v0, $v1)');
          }
        } else if (values.length == 2) {
          final a = values[0];
          final b = values[1];
          if (a <= 99 && a >= 0 && b >= 0 && (a > 0 || b > 0)) {
            // 행번호 + 값 하나: 100 이상이면 주입만, 미만이면 배액만 (치료량 통계 00: -, 8 / 05: 1475, -)
            final inflow = b >= 100 ? b : 0.0;
            final outflow = b >= 100 ? 0.0 : b;
            pairs.add(_DialysisPair(outflow, inflow, a.toInt()));
            // ignore: avoid_print
            print(
              '[OCR:parse] 위치 fallback 행 회차${a.toInt() + 1} ($inflow, $outflow)',
            );
          } else if ((a > 0 && b == 0) || (a == 0 && b > 0)) {
            pairs.add(_DialysisPair(b, a));
            // ignore: avoid_print
            print('[OCR:parse] 위치 fallback 행 2값 ($a, $b)');
          } else if (a >= 100 && b >= 100 && a != b) {
            pairs.add(_DialysisPair(b, a));
            // ignore: avoid_print
            print('[OCR:parse] 위치 fallback 행 2값(주입/배액) ($a, $b)');
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
      if (byPosition.length == 1 && byPosition[0] >= 100) {
        pairs.add(_DialysisPair(0, byPosition[0]));
        // ignore: avoid_print
        print('[OCR:parse] 위치 fallback 단일값 → (0, ${byPosition[0]})');
      } else {
        for (var j = 0; j + 1 < byPosition.length; j += 2) {
          final a = byPosition[j];
          final b = byPosition[j + 1];
          if (a != b) {
            pairs.add(_DialysisPair(b, a));
            // ignore: avoid_print
            print('[OCR:parse] 위치 fallback 쌍 ($a, $b)');
          }
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
        context.read<AppState>().addLog('기계투석 입력 저장: ${rows.length}건');
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('저장되었습니다.')));
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
              _DialysisRowCard(index: i + 1, row: _rows[i]),
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
                  MaterialPageRoute(
                    builder: (_) => const ManualDialysisScreen(),
                  ),
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
            SizedBox(width: 60, child: Text('회차 $index')),
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
