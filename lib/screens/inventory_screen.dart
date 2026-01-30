import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../state/app_state.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _owned = InventorySectionController();
  final _pending = InventorySectionController();
  final _defective = InventorySectionController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadValues();
  }

  Future<void> _loadValues() async {
    final service = context.read<AppState>().sheetsService;
    final owned = await service.fetchLatestInventory('owned');
    final pending = await service.fetchLatestInventory('pending');
    final defective = await service.fetchLatestInventory('defective');
    if (mounted) {
      setState(() {
        _owned.setValues(owned.values);
        _pending.setValues(pending.values);
        _defective.setValues(defective.values);
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _owned.dispose();
    _pending.dispose();
    _defective.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('투석물품 재고관리')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                InventorySection(
                  title: '보유물품관리',
                  controller: _owned,
                  onSave: () =>
                      _saveSection(context, 'owned', _owned.currentValues()),
                ),
                const SizedBox(height: 24),
                InventorySection(
                  title: '미배송분 관리',
                  controller: _pending,
                  onSave: () => _saveSection(
                    context,
                    'pending',
                    _pending.currentValues(),
                  ),
                ),
                const SizedBox(height: 24),
                InventorySection(
                  title: '불량관리',
                  controller: _defective,
                  onSave: () => _saveSection(
                    context,
                    'defective',
                    _defective.currentValues(),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _saveSection(
    BuildContext context,
    String section,
    List<int> values,
  ) async {
    final service = context.read<AppState>().sheetsService;
    final prefs = await SharedPreferences.getInstance();
    final autoRequest = prefs.getBool('autoDeliveryRequest') ?? false;
    await service.appendInventory(section, values, autoRequest: autoRequest);
    if (section == 'pending' && values.any((value) => value > 0)) {
      await prefs.setBool('deliveryRequestGate', false);
    }
    if (mounted) {
      context.read<AppState>().addLog('재고 저장($section): ${values.join(",")}');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('저장되었습니다.')));
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }
}

class InventorySectionController {
  InventorySectionController()
    : controllers = List.generate(8, (_) => TextEditingController());

  final List<TextEditingController> controllers;

  void setValues(List<int> values) {
    for (var i = 0; i < controllers.length; i++) {
      controllers[i].text = values.length > i ? values[i].toString() : '0';
    }
  }

  List<int> currentValues() {
    return controllers
        .map((controller) => int.tryParse(controller.text) ?? 0)
        .toList();
  }

  void increment(int index) {
    final current = int.tryParse(controllers[index].text) ?? 0;
    controllers[index].text = (current + 1).toString();
  }

  void decrement(int index) {
    final current = int.tryParse(controllers[index].text) ?? 0;
    final next = current > 0 ? current - 1 : 0;
    controllers[index].text = next.toString();
  }

  void dispose() {
    for (final controller in controllers) {
      controller.dispose();
    }
  }
}

class InventorySection extends StatelessWidget {
  const InventorySection({
    super.key,
    required this.title,
    required this.controller,
    required this.onSave,
  });

  final String title;
  final InventorySectionController controller;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _InventoryGroup(
          title: '손투석',
          startIndex: 0,
          endIndex: 2,
          controller: controller,
        ),
        const SizedBox(height: 12),
        _InventoryGroup(
          title: '기계투석',
          startIndex: 3,
          endIndex: 7,
          controller: controller,
        ),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: onSave, child: const Text('저장')),
      ],
    );
  }
}

class _InventoryGroup extends StatelessWidget {
  const _InventoryGroup({
    required this.title,
    required this.startIndex,
    required this.endIndex,
    required this.controller,
  });

  final String title;
  final int startIndex;
  final int endIndex;
  final InventorySectionController controller;

  static const _labels = [
    '1.5 2리터',
    '2.3 2리터',
    '4.3 2리터',
    '1.5 3리터',
    '2.3 3리터',
    '4.3 3리터',
    '세트',
    '배액백',
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (var i = startIndex; i <= endIndex; i++)
              _InventoryRow(
                label: _labels[i],
                controller: controller.controllers[i],
                onIncrement: () => controller.increment(i),
                onDecrement: () => controller.decrement(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _InventoryRow extends StatelessWidget {
  const _InventoryRow({
    required this.label,
    required this.controller,
    required this.onIncrement,
    required this.onDecrement,
  });

  final String label;
  final TextEditingController controller;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          SizedBox(
            width: 80,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onDecrement,
            icon: const Icon(Icons.remove_circle_outline),
          ),
          IconButton(
            onPressed: onIncrement,
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}
