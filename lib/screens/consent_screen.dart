import 'package:material_ui/material_ui.dart';

import '../legal/consent_store.dart';
import '../legal/legal_documents.dart';
import 'legal_document_screen.dart';

/// 처음 실행할 때 접근권한을 안내하고 필수 동의를 받는다.
class ConsentScreen extends StatefulWidget {
  const ConsentScreen({super.key, required this.store, required this.onAgreed});

  final ConsentStore store;
  final VoidCallback onAgreed;

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _over14 = false;
  bool _locationTerms = false;
  bool _saving = false;

  bool get _canStart => _over14 && _locationTerms && !_saving;

  void _open(LegalDocument document) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalDocumentScreen(document: document),
      ),
    );
  }

  Future<void> _start() async {
    setState(() => _saving = true);
    await widget.store.recordConsent();
    widget.onAgreed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('시작하기 전에')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('앱 접근권한 안내', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            const _PermissionRow(
              icon: Icons.location_on_outlined,
              title: '위치 (선택)',
              reason: '현재 위치에서 집까지 가는 막차를 계산해요.',
            ),
            const _PermissionRow(
              icon: Icons.notifications_outlined,
              title: '알림 (선택)',
              reason: '출발할 때를 알려주고 잠금화면에 막차 시간을 보여줘요.',
            ),
            const Text('선택 권한은 허용하지 않아도 앱을 열 수 있지만, 해당 기능은 쓸 수 없어요.'),
            const Divider(height: 40),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _over14,
              onChanged: (v) => setState(() => _over14 = v ?? false),
              title: const Text('[필수] 만 14세 이상입니다'),
              subtitle: const Text('만 14세 미만은 이용할 수 없어요.'),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _locationTerms,
              onChanged: (v) => setState(() => _locationTerms = v ?? false),
              title: const Text('[필수] 위치기반서비스 이용약관 동의'),
              secondary: TextButton(
                onPressed: () => _open(LegalDocument.locationTerms),
                child: const Text('보기'),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => _open(LegalDocument.privacyPolicy),
                child: const Text('개인정보처리방침 보기'),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _canStart ? _start : null,
              child: const Text('동의하고 시작하기'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.reason,
  });

  final IconData icon;
  final String title;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(reason),
    );
  }
}
