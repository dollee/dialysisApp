import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/settings_screen.dart';
import 'state/app_state.dart';

void main() {
  runApp(const DialysisApp());
}

class DialysisApp extends StatelessWidget {
  const DialysisApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState()..initialize(),
      child: MaterialApp(
        title: 'Dialysis',
        theme: ThemeData(
          scaffoldBackgroundColor: Colors.white,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.blue,
            primary: Colors.blue,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white,
            foregroundColor: Colors.black,
            elevation: 0,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.blue, width: 2),
            ),
          ),
        ),
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
