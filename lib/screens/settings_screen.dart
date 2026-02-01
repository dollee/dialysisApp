import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import '../state/app_state.dart';
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
  final FocusNode _deliveryPhoneFocusNode = FocusNode();
  bool _autoRequest = false;
  bool _showRequiredError = false;
  bool _deliveryGate = true;

  final _machineKeys = [
    'machine_1_5_3l',
    'machine_2_3_3l',
    'machine_4_3_3l',
    'machine_set',
  ];
  final _manualKeys = ['manual_1_5_2l', 'manual_2_3_2l', 'manual_4_3_2l'];

  late final Map<String, int> _values = {
    for (final key in [..._machineKeys, ..._manualKeys]) key: 0,
  };

  @override
  void initState() {
    super.initState();
    // 로컬 값으로 먼저 그려서 화면이 바로 보이게 한 뒤, 원격에서 읽어와 덮어씀
    _loadFromLocal();
    _loadSettings();
  }

  /// SharedPreferences에서만 읽어 UI를 바로 채움 (설정 화면이 즉시 표시되도록)
  Future<void> _loadFromLocal() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _patientController.text = prefs.getString('patientName') ?? '';
      _hospitalController.text = prefs.getString('hospitalName') ?? '';
      _phoneController.text = prefs.getString('deliveryPhone') ?? '';
      _autoRequest = prefs.getBool('autoDeliveryRequest') ?? false;
      _deliveryGate = prefs.getBool('deliveryRequestGate') ?? true;
      for (final key in _values.keys) {
        _values[key] = prefs.getInt(key) ?? 0;
      }
    });
  }

  Future<void> _loadSettings() async {
    // ignore: avoid_print
    print('[Settings] _loadSettings 시작');
    final prefs = await SharedPreferences.getInstance();
    Map<String, String> remote = {};

    // 1) 서버 쪽 설정 파일(재고 시트)을 보정하고, 원격 설정을 시도해서 읽어온다.
    try {
      final appState = context.read<AppState>();
      // ignore: avoid_print
      print('[Settings] ensureSettingsSheet(설정 파일) 호출');
      await appState.sheetsService.ensureSettingsSheet();
      // ignore: avoid_print
      print('[Settings] loadSettingsFromSheet 호출');
      remote = await appState.sheetsService.loadSettingsFromSheet();
      // ignore: avoid_print
      print('[Settings] 원격 설정: ${remote.isEmpty ? "없음" : "${remote.length}개"}');
    } catch (e) {
      // ignore: avoid_print
      print('[Settings] _loadSettings 예외: $e → remote 비움');
      remote = {};
    }

    if (remote.isNotEmpty) {
      // 2-A) 원격 설정이 존재하면, 이를 진실(source of truth)로 사용하고
      //      로컬 SharedPreferences도 동일 값으로 덮어쓴다.
      _patientController.text = remote['patientName'] ?? '';
      _hospitalController.text = remote['hospitalName'] ?? '';
      _phoneController.text = remote['deliveryPhone'] ?? '';
      _autoRequest = remote['autoDeliveryRequest'] == 'true';
      _deliveryGate = remote['deliveryRequestGate'] == 'true';

      await prefs.setString('patientName', _patientController.text);
      await prefs.setString('hospitalName', _hospitalController.text);
      await prefs.setString('deliveryPhone', _phoneController.text);
      await prefs.setBool('autoDeliveryRequest', _autoRequest);
      await prefs.setBool('deliveryRequestGate', _deliveryGate);

      for (final key in _values.keys) {
        final v = remote[key];
        final parsed = int.tryParse(v ?? '');
        final value = parsed ?? 0;
        _values[key] = value;
        await prefs.setInt(key, value);
      }
      // ignore: avoid_print
      print('[Settings] 원격 값으로 UI/로컬 동기화 완료');
    } else {
      // 2-B) 원격 설정이 전혀 없다면(= 새 시트이거나 서버에 데이터가 없는 상태),
      //      로컬에 남아 있는 이전 설정을 모두 무시하고 초기 상태로 시작한다.
      // ignore: avoid_print
      print('[Settings] 원격 없음 → 로컬 초기화');
      await prefs.remove('patientName');
      await prefs.remove('hospitalName');
      await prefs.remove('deliveryPhone');
      await prefs.remove('autoDeliveryRequest');
      await prefs.remove('deliveryRequestGate');
      for (final key in _values.keys) {
        await prefs.remove(key);
        _values[key] = 0;
      }
      _patientController.text = '';
      _hospitalController.text = '';
      _phoneController.text = '';
      _autoRequest = false;
      _deliveryGate = true;
    }

    // ignore: avoid_print
    print('[Settings] _loadSettings 완료');
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveTextValues({bool syncRemote = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('patientName', _patientController.text.trim());
    await prefs.setString('hospitalName', _hospitalController.text.trim());
    await prefs.setString('deliveryPhone', _phoneController.text.trim());
    if (widget.requireProfile) {
      _validateRequired();
    }

    if (syncRemote) {
      try {
        // ignore: avoid_print
        print('[Settings] saveSettingsToSheet(원격 동기화) 시작');
        final appState = context.read<AppState>();
        final Map<String, String> settings = {
          'patientName': _patientController.text.trim(),
          'hospitalName': _hospitalController.text.trim(),
          'deliveryPhone': _phoneController.text.trim(),
          'autoDeliveryRequest': _autoRequest.toString(),
          'deliveryRequestGate': _deliveryGate.toString(),
          for (final entry in _values.entries)
            entry.key: entry.value.toString(),
        };
        await appState.sheetsService.saveSettingsToSheet(settings);
        // ignore: avoid_print
        print('[Settings] saveSettingsToSheet 완료');
      } catch (e) {
        // ignore: avoid_print
        print('[Settings] saveSettingsToSheet 예외: $e');
      }
    }
  }

  Future<void> _saveAutoRequest(bool value) async {
    if (value) {
      if (_phoneController.text.trim().isEmpty) {
        setState(() {
          _autoRequest = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('미배송분 자동요청을 사용하려면 배송 요청 전화번호를 먼저 입력해주세요.'),
            duration: Duration(seconds: 2),
          ),
        );
        _deliveryPhoneFocusNode.requestFocus();
        return;
      }
    }
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
    _deliveryPhoneFocusNode.dispose();
    super.dispose();
  }

  bool _validateRequired() {
    final valid =
        _patientController.text.trim().isNotEmpty &&
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
                      errorText:
                          _showRequiredError &&
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
                      errorText:
                          _showRequiredError &&
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
                    focusNode: _deliveryPhoneFocusNode,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(labelText: '배송 요청 전화번호'),
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
                        style: const TextStyle(color: AppColors.textSecondary),
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
            const SizedBox(height: 12),
            // 항상 저장/완료 버튼을 보여준다.
            // requireProfile 이 true 인 경우에는 필수 항목을 모두 채워야만 화면을 닫을 수 있다.
            ElevatedButton(
              onPressed: () async {
                if (requireProfile) {
                  final ok = _validateRequired();
                  if (!ok) return;
                }
                // 로컬 + Google Sheets(settings 시트)에 모두 저장
                await _saveTextValues(syncRemote: true);
                widget.onCompleted?.call();
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop();
                }
              },
              child: Text(requireProfile ? '완료' : '저장'),
            ),
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
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
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
