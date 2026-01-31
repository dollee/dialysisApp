import 'dart:io' show File;

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// 치료량 통계 화면 등 LCD 인식률 향상: 1.5배 확대 + 그레이스케일 + 대비 강화 후 임시 파일로 저장.
/// Android ML Kit이 작은 숫자(8, 05, 1475 등)를 더 잘 잡도록 함.
Future<String?> preprocessImageForOcr(String filePath) async {
  try {
    final bytes = await File(filePath).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final w = (decoded.width * 1.5).round();
    final h = (decoded.height * 1.5).round();
    final scaled = img.copyResize(decoded, width: w, height: h);
    img.grayscale(scaled);
    img.contrast(scaled, contrast: 130);
    final outBytes = img.encodeJpg(scaled, quality: 90);
    final dir = await getTemporaryDirectory();
    final outPath =
        '${dir.path}/ocr_pre_${DateTime.now().millisecondsSinceEpoch}.jpg';
    await File(outPath).writeAsBytes(outBytes);
    return outPath;
  } catch (e) {
    return null;
  }
}

Future<void> deletePreprocessedFile(String? path) async {
  if (path == null) return;
  try {
    await File(path).delete();
  } catch (_) {}
}
