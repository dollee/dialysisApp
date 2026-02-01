import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:provider/provider.dart';

import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'state/app_state.dart';

void main() {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  runApp(const RootApp());
}

/// 네이티브 스플래시(SplashActivity 2.8초)만 사용. Flutter 쪽에서 스플래시를 다시 보이지 않음.
class RootApp extends StatefulWidget {
  const RootApp({super.key});

  @override
  State<RootApp> createState() => _RootAppState();
}

class _RootAppState extends State<RootApp> {
  @override
  void initState() {
    super.initState();
    // 첫 프레임 그린 뒤 네이티브 스플래시 오버레이 제거 → 스플래시가 두 번 나오는 느낌 방지
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
  }

  @override
  Widget build(BuildContext context) {
    return const DialysisApp();
  }
}

class DialysisApp extends StatelessWidget {
  const DialysisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..initialize(),
      child: MaterialApp(
        title: 'Dialysis',
        theme: AppTheme.light,
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? _hasProfile;
  bool _didRecheckAfterInit = false;
  bool _didRecheckAfterSignIn = false;

  @override
  void initState() {
    super.initState();
    _checkProfile();
  }

  Future<void> _checkProfile() async {
    final hasProfile = await context.read<AppState>().hasRequiredProfile();
    if (mounted) {
      setState(() {
        _hasProfile = hasProfile;
      });
    }
  }

  void _handleProfileCompleted() {
    context.read<AppState>().clearShouldShowSettingsAfterInit();
    setState(() {
      _hasProfile = true;
    });
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AppState>(
      builder: (context, state, _) {
        // 초기화가 끝나면 프로필을 한 번 더 확인 (설정 화면에서 완료 후 홈으로 갈 때 등)
        if (!state.isInitializing && !_didRecheckAfterInit) {
          _didRecheckAfterInit = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _checkProfile();
          });
        }
        // 구글 로그인 직후 프로필 재확인 → 원격 설정에서 프로필 적용 시 홈으로 전환
        if (!state.isSignedIn) {
          _didRecheckAfterSignIn = false;
        } else if (!_didRecheckAfterSignIn) {
          _didRecheckAfterSignIn = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (mounted) await _checkProfile();
          });
        }
        late final Widget screen;
        if (state.isInitializing || _hasProfile == null) {
          screen = const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        } else if (!state.isSignedIn && !state.everSignedIn) {
          screen = const LoginScreen();
        } else if (state.shouldShowSettingsAfterInit || _hasProfile == false) {
          // 원격 설정이 없거나 로컬 프로필이 없으면 설정 화면 먼저
          screen = SettingsScreen(
            requireProfile: true,
            onCompleted: _handleProfileCompleted,
          );
        } else {
          screen = const HomeScreen();
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: KeyedSubtree(key: ValueKey(screen.runtimeType), child: screen),
        );
      },
    );
  }
}
