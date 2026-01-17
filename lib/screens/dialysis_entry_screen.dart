import 'package:flutter/material.dart';

import 'machine_dialysis_screen.dart';
import 'manual_dialysis_screen.dart';

class DialysisEntryScreen extends StatelessWidget {
  const DialysisEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('투석결과 입력')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const MachineDialysisScreen()),
                );
              },
              child: const Text('기계투석 입력'),
            ),
            const SizedBox(height: 12),
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
