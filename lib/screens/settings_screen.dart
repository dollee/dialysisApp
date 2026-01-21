import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/contact_picker.dart';
import 'debug_log_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.requireProfile = false,
    this.onCompleted,
  });

  final bool requireProfile;
  final VoidCallback? onCompleted;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _patientController = TextEditingController();
  final _hospitalController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _autoRequest = false;
  bool _showRequiredError = false;
  bool _deliveryGate = true;

  final _machineKeys = [
    'machine_1_5_3l',
    'machine_2_3_3l',
    'machine_4_3_3l',
    'machine_set',
  ];
  final _manualKeys = [
    'manual_1_5_2l',
    'manual_2_3_2l',
    'manual_4_3_2l',
  ];

  late final Map<String, int> _values = {
    for (final key in [..._machineKeys, ..._manualKeys]) key: 0,
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _patientController.text = prefs.getString('patientName') ?? '';
    _hospitalController.text = prefs.getString('hospitalName') ?? '';
    _phoneController.text = prefs.getString('deliveryPhone') ?? '';
    _autoRequest = prefs.getBool('autoDeliveryRequest') ?? false;
    _deliveryGate = prefs.getBool('deliveryRequestGate') ?? true;
    await prefs.setBool('deliveryRequestGate', _deliveryGate);
    for (final key in _values.keys) {
      _values[key] = prefs.getInt(key) ?? 0;
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveTextValues() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('patientName', _patientController.text.trim());
    await prefs.setString('hospitalName', _hospitalController.text.trim());
    await prefs.setString('deliveryPhone', _phoneController.text.trim());
    if (widget.requireProfile) {
      _validateRequired();
    }
  }

  Future<void> _saveAutoRequest(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoDeliveryRequest', value);
    setState(() {
      _autoRequest = value;
    });
    final message = value
        ? '투석액이 10일분 이하가 남았을때 배송 안내 창을 보여주겠습니다.'
        : '환자분이 직접 남은 분량을 계산하여 따로 요청 하셔야 합니다.';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _pickContact() async {
    final phone = await pickContactPhone(context);
    if (phone == null || phone.trim().isEmpty) return;
    _phoneController.text = phone;
    await _saveTextValues();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _setValue(String key, int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, value);
    setState(() {
      _values[key] = value;
    });
  }

  @override
  void dispose() {
    _patientController.dispose();
    _hospitalController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  bool _validateRequired() {
    final valid = _patientController.text.trim().isNotEmpty &&
        _hospitalController.text.trim().isNotEmpty;
    if (!valid && widget.requireProfile) {
      setState(() {
        _showRequiredError = true;
      });
    }
    return valid;
  }

  @override
  Widget build(BuildContext context) {
    final requireProfile = widget.requireProfile;
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: WillPopScope(
        onWillPop: () async {
          if (!requireProfile) {
            return true;
          }
          final ok = _validateRequired();
          if (!ok) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('환자 성명과 병원명을 입력해주세요.')),
            );
          }
          return ok;
        },
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _Section(
              title: '기본정보',
              child: Column(
                children: [
                  TextField(
                    controller: _patientController,
                    decoration: InputDecoration(
                      labelText: '환자 성명',
                      errorText: _showRequiredError &&
                              _patientController.text.trim().isEmpty
                          ? '필수 입력'
                          : null,
                    ),
                    onChanged: (_) => _saveTextValues(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _hospitalController,
                    decoration: InputDecoration(
                      labelText: '다니는 병원명',
                      errorText: _showRequiredError &&
                              _hospitalController.text.trim().isEmpty
                          ? '필수 입력'
                          : null,
                    ),
                    onChanged: (_) => _saveTextValues(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _Section(
              title: '기계투석소모량',
              child: Column(
                children: [
                  _CounterRow(
                    label: '1.5 3리터',
                    value: _values['machine_1_5_3l'] ?? 0,
                    onChanged: (v) => _setValue('machine_1_5_3l', v),
                  ),
                  _CounterRow(
                    label: '2.3 3리터',
                    value: _values['machine_2_3_3l'] ?? 0,
                    onChanged: (v) => _setValue('machine_2_3_3l', v),
                  ),
                  _CounterRow(
                    label: '4.3 3리터',
                    value: _values['machine_4_3_3l'] ?? 0,
                    onChanged: (v) => _setValue('machine_4_3_3l', v),
                  ),
                  _CounterRow(
                    label: '세트',
                    value: _values['machine_set'] ?? 0,
                    onChanged: (v) => _setValue('machine_set', v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _Section(
              title: '손투석 하루 소모량',
              child: Column(
                children: [
                  _CounterRow(
                    label: '1.5 2리터',
                    value: _values['manual_1_5_2l'] ?? 0,
                    onChanged: (v) => _setValue('manual_1_5_2l', v),
                  ),
                  _CounterRow(
                    label: '2.3 2리터',
                    value: _values['manual_2_3_2l'] ?? 0,
                    onChanged: (v) => _setValue('manual_2_3_2l', v),
                  ),
                  _CounterRow(
                    label: '4.3 2리터',
                    value: _values['manual_4_3_2l'] ?? 0,
                    onChanged: (v) => _setValue('manual_4_3_2l', v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _Section(
              title: '미배송 관리',
              child: Column(
                children: [
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: '배송 요청 전화번호',
                    ),
                    onChanged: (_) => _saveTextValues(),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _pickContact,
                      icon: const Icon(Icons.contacts),
                      label: const Text('주소록에서 불러오기'),
                    ),
                  ),
                  SwitchListTile(
                    value: _autoRequest,
                    onChanged: _saveAutoRequest,
                    title: const Text('미배송분 자동요청'),
                  ),
                if (kDebugMode) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '배송요청 게이트: ${_deliveryGate ? 'ON' : 'OFF'}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const DebugLogScreen(),
                        ),
                      ),
                      child: const Text('디버그 로그 보기'),
                    ),
                  ),
                ],
                ],
              ),
            ),
            if (requireProfile) ...[
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: _validateRequired()
                    ? () {
                        widget.onCompleted?.call();
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      }
                    : () => _validateRequired(),
                child: const Text('완료'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class _CounterRow extends StatelessWidget {
  const _CounterRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
            onPressed: () => onChanged(value > 0 ? value - 1 : 0),
            icon: const Icon(Icons.remove_circle_outline),
          ),
          SizedBox(
            width: 36,
            child: Text(
              value.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            onPressed: () => onChanged(value + 1),
            icon: const Icon(Icons.add_circle_outline),
          ),
        ],
      ),
    );
  }
}
