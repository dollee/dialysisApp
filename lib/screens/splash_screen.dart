import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import '../theme/app_colors.dart';

/// 전체화면 스플래시 (Android 12+ 원형 마스크 대신 Flutter에서 전체 이미지 표시)
class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.onFinish,
    this.minDuration = const Duration(milliseconds: 600),
  });

  final VoidCallback onFinish;
  final Duration minDuration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _timerStarted = false;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
  }

  void _startMinDurationTimer() {
    if (_timerStarted) return;
    _timerStarted = true;
    Future.delayed(widget.minDuration, () {
      if (mounted) widget.onFinish();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/splash.png'), context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: AppColors.primary,
        child: Image.asset(
          'assets/splash.png',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            // 이미지가 실제로 그려진 뒤부터 minDuration(3초) 재기 → 녹색만 보이다 스플래시가 잠깐만 나오는 문제 방지
            if (frame != null) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _startMinDurationTimer();
              });
            }
            return child;
          },
          errorBuilder: (_, __, ___) {
            _startMinDurationTimer();
            return const Center(
              child: Icon(Icons.medical_services, color: Colors.white, size: 80),
            );
          },
        ),
      ),
    );
  }
}
