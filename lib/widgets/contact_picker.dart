import 'package:contacts_service/contacts_service.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

Future<String?> pickContactPhone(BuildContext context) async {
  final status = await Permission.contacts.status;
  if (status.isDenied || status.isPermanentlyDenied) {
    final result = await Permission.contacts.request();
    if (result.isPermanentlyDenied) {
      if (context.mounted) _showSettingsDialog(context);
      return null;
    }
    if (!result.isGranted && !result.isLimited) return null;
  }

  try {
    // 1. 네이티브 피커 시도
    final contact = await ContactsService.openDeviceContactPicker();
    if (contact != null && contact.phones != null && contact.phones!.isNotEmpty) {
      return _selectPhoneFromContact(context, contact);
    }
    
    // 2. 네이티브 피커에서 취소했거나 결과가 없으면 커스텀 리스트 시도
    if (context.mounted) {
      return await _pickFromLocalContacts(context);
    }
  } catch (e) {
    // 에러 발생 시 커스텀 리스트로 폴백
    if (context.mounted) {
      return await _pickFromLocalContacts(context);
    }
  }
  return null;
}

Future<String?> _pickFromLocalContacts(BuildContext context) async {
  final contacts = await ContactsService.getContacts(withThumbnails: false);
  if (contacts.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('연락처가 비어있거나 접근 권한이 제한되어 있습니다.')),
      );
    }
    return null;
  }

  if (context.mounted) {
    return showModalBottomSheet<String>(
      context: context,
      builder: (context) => _ContactPickerSheet(contacts: contacts.toList()),
    );
  }
  return null;
}

String? _selectPhoneFromContact(BuildContext context, Contact contact) {
  if (contact.phones == null || contact.phones!.isEmpty) return null;
  if (contact.phones!.length == 1) return contact.phones!.first.value;

  // 번호가 여러 개인 경우 선택 팝업 (필요 시 구현)
  return contact.phones!.first.value;
}

class _ContactPickerSheet extends StatelessWidget {
  const _ContactPickerSheet({required this.contacts});
  final List<Contact> contacts;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('연락처 선택', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final contact = contacts[index];
              final phone = (contact.phones != null && contact.phones!.isNotEmpty)
                  ? contact.phones!.first.value
                  : '번호 없음';
              return ListTile(
                title: Text(contact.displayName ?? '이름 없음'),
                subtitle: Text(phone ?? ''),
                onTap: () => Navigator.pop(context, phone),
              );
            },
          ),
        ),
      ],
    );
  }
}

void _showSettingsDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('연락처 권한 필요'),
      content: const Text(
          '주소록을 불러오려면 연락처 접근 권한이 필요합니다. 설정에서 "전체 접근"으로 변경해 주세요.\n\n(설정 > 개인정보 보호 및 보안 > 연락처 > 투석앱)'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: () {
            openAppSettings();
            Navigator.pop(context);
          },
          child: const Text('설정 열기'),
        ),
      ],
    ),
  );
}
