import 'package:flutter/material.dart';

/// 앱 전역 컬러 팔레트 (의료 앱 추천 컬러)
abstract final class AppColors {
  AppColors._();

  /// 메인 컬러 (딥 틸) - 로고, 메인 버튼
  static const Color primary = Color(0xFF007B8F);

  /// 보조 컬러 (웜 오렌지) - 기록 추가 등 행동 유도
  static const Color secondary = Color(0xFFFF8C00);

  /// 강조 컬러 (소프트 그린) - 정상 수치, 기록 완료
  static const Color accent = Color(0xFF4DB872);

  /// 배경색 (라이트 그레이)
  static const Color background = Color(0xFFF5F7FA);

  /// 기본 텍스트 (다크 그레이)
  static const Color textPrimary = Color(0xFF333333);

  /// 보조 텍스트 (미디엄 그레이)
  static const Color textSecondary = Color(0xFF777777);

  /// 성공/완료 (석세스 그린)
  static const Color success = Color(0xFF28A745);

  /// 경고/주의 (워닝 옐로우)
  static const Color warning = Color(0xFFFFC107);

  /// 오류/위험 (데인저 레드)
  static const Color error = Color(0xFFDC3545);

  /// 비활성화 요소
  static const Color disabled = Color(0xFFCCCCCC);

  /// 카드/화면 배경 (흰색)
  static const Color surface = Color(0xFFFFFFFF);
}
