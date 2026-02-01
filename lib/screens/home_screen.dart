import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/app_colors.dart';
import '../state/app_state.dart';
import 'blood_pressure_screen.dart';
import 'inventory_screen.dart';
import 'machine_dialysis_screen.dart';
import 'manual_dialysis_screen.dart';
import 'share_screen.dart';
import 'settings_screen.dart';
import 'trend_screen.dart';
import 'weight_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<_HealthSummary>? _summaryFuture;
  bool _checkedProfile = false;

  @override
  void initState() {
    super.initState();
    _summaryFuture = _loadSummary();
    _ensureProfile();
  }

  Future<void> _ensureProfile() async {
    if (_checkedProfile) return;
    _checkedProfile = true;
    final hasProfile = await context.read<AppState>().hasRequiredProfile();
    if (!hasProfile && mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const SettingsScreen(requireProfile: true),
        ),
      );
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<_HealthSummary> _loadSummary() async {
    final state = context.read<AppState>();
    final now = DateTime.now();
    final pulseOk = await state.healthService.requestPulseAuthorization();
    final stepsOk = await state.healthService.requestStepsAuthorization();
    final pulse = pulseOk ? await state.healthService.fetchLatestPulse(now) : null;
    final steps = stepsOk ? await state.healthService.fetchTodaySteps(now) : null;
    return _HealthSummary(pulse: pulse, steps: steps);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('투석 결과 관리'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => _go(context, const SettingsScreen()),
          ),
          TextButton(
            onPressed: () async {
              await state.signOut();
            },
            child: const Text('로그아웃'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            children: [
              _InfoCard(
                title: 'Health Data Tracker',
                subtitle: '건강 지표를 기록하고 Google Sheets와 동기화합니다.',
                icon: Icons.health_and_safety,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      title: '기계투석 결과 입력',
                      value: '입력하기',
                      imagePath: 'assets/icons/icon_machine_dialysis.png',
                      accentColor: AppColors.primary,
                      onTap: () => _go(context, const MachineDialysisScreen()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      title: '손투석 결과 입력',
                      value: '입력하기',
                      imagePath: 'assets/icons/icon_manual_dialysis.png',
                      accentColor: AppColors.primary,
                      onTap: () => _go(context, const ManualDialysisScreen()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      title: '혈압데이터 입력',
                      value: '입력하기',
                      imagePath: 'assets/icons/icon_blood_pressure.png',
                      accentColor: AppColors.error,
                      onTap: () => _go(context, const BloodPressureScreen()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      title: '몸무게입력',
                      value: '입력하기',
                      imagePath: 'assets/icons/icon_weight.png',
                      accentColor: AppColors.accent,
                      onTap: () => _go(context, const WeightScreen()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      title: '재고관리',
                      value: '관리하기',
                      imagePath: 'assets/icons/icon_inventory.png',
                      accentColor: AppColors.primary,
                      onTap: () => _go(context, const InventoryScreen()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      title: '추이보기',
                      value: '그래프',
                      imagePath: 'assets/icons/icon_trend.png',
                      accentColor: AppColors.textSecondary,
                      onTap: () => _go(context, const TrendScreen()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FutureBuilder<_HealthSummary>(
                future: _summaryFuture,
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const SizedBox.shrink();
                  }
                  final summary = snapshot.data!;
                  return Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: '맥박',
                          value: summary.pulse != null
                              ? '${summary.pulse} BPM'
                              : '데이터 없음',
                          icon: Icons.favorite,
                          accentColor: AppColors.error,
                          onTap: () {},
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatCard(
                          title: '오늘 걸음',
                          value: summary.steps != null
                              ? '${summary.steps} 걸음'
                              : '데이터 없음',
                          icon: Icons.directions_walk,
                          accentColor: AppColors.accent,
                          onTap: () {},
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _go(context, const ShareScreen()),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.primary,
        elevation: 2,
        mini: true,
        child: const Icon(Icons.share),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  void _go(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.textPrimary.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primary.withOpacity(0.15),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    this.icon,
    this.imagePath,
    required this.accentColor,
    required this.onTap,
  }) : assert(icon != null || imagePath != null);

  final String title;
  final String value;
  final IconData? icon;
  final String? imagePath;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppColors.textPrimary.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imagePath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  imagePath!,
                  height: 56,
                  width: double.infinity,
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                ),
              )
            else if (icon != null)
              Icon(icon, color: accentColor),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthSummary {
  _HealthSummary({required this.pulse, required this.steps});

  final int? pulse;
  final int? steps;
}
