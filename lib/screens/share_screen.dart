import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  final TextEditingController _emailController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final stored = context.read<AppState>().shareEmail;
    if (stored != null) {
      _emailController.text = stored;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    setState(() => _saving = true);
    final state = context.read<AppState>();
    final email = _emailController.text.trim();
    try {
      if (email.isNotEmpty) {
        await state.sheetsService.shareAppFolder(email);
        await state.setShareEmail(email);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('공유가 완료되었습니다.')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('데이터 공유')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Google ID (email)',
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _saving ? null : _share,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('공유'),
            ),
          ],
        ),
      ),
    );
  }
}
