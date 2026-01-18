import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'blood_pressure_screen.dart';
import 'dialysis_entry_screen.dart';
import 'inventory_screen.dart';
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
                      title: '투석 결과',
                      value: '입력하기',
                      icon: Icons.monitor_heart,
                      accentColor: Colors.indigo,
                      onTap: () => _go(context, const DialysisEntryScreen()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      title: '체중',
                      value: '입력하기',
                      icon: Icons.scale,
                      accentColor: Colors.teal,
                      onTap: () => _go(context, const WeightScreen()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      title: '혈압',
                      value: '입력하기',
                      icon: Icons.favorite,
                      accentColor: Colors.redAccent,
                      onTap: () => _go(context, const BloodPressureScreen()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      title: '추이 보기',
                      value: '그래프',
                      icon: Icons.show_chart,
                      accentColor: Colors.blueGrey,
                      onTap: () => _go(context, const TrendScreen()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _StatCard(
                title: '투석물품 재고관리',
                value: '관리하기',
                icon: Icons.inventory_2,
                accentColor: Colors.blue,
                onTap: () => _go(context, const InventoryScreen()),
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
                          accentColor: Colors.redAccent,
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
                          accentColor: Colors.green,
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
        backgroundColor: Colors.white,
        foregroundColor: Colors.blue,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
            backgroundColor: Colors.indigo.shade50,
            child: Icon(icon, color: Colors.indigo),
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
            style: const TextStyle(color: Colors.black54),
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
    required this.icon,
    required this.accentColor,
    required this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: accentColor),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(color: Colors.black54),
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
