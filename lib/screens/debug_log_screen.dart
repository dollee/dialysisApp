import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class DebugLogScreen extends StatelessWidget {
  const DebugLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final logs = state.debugLogs;
    return Scaffold(
      appBar: AppBar(
        title: const Text('디버그 로그'),
        actions: [
          TextButton(
            onPressed: () => state.clearLogs(),
            child: const Text('지우기'),
          ),
        ],
      ),
      body: logs.isEmpty
          ? const Center(child: Text('로그가 없습니다.'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: logs.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = logs[index];
                final time =
                    DateFormat('yyyy-MM-dd HH:mm:ss').format(entry.timestamp);
                return ListTile(
                  dense: true,
                  title: Text(entry.message),
                  subtitle: Text(time),
                );
              },
            ),
    );
  }
}
