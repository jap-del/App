import 'package:material_ui/material_ui.dart';

import '../legal/consent_store.dart';
import '../legal/legal_documents.dart';
import 'legal_document_screen.dart';

/// 약관, 데이터 출처, 라이선스, 위치정보 권리 행사를 모아둔 화면.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.consent,
    required this.onWithdrawn,
    this.adFreeSection,
  });

  final ConsentStore consent;

  /// 광고 제거 메뉴. 테스트에서는 null.
  final Widget? adFreeSection;

  /// 동의를 철회한 뒤 호출된다. 알림 정리와 첫 화면 이동을 맡는다.
  final Future<void> Function() onWithdrawn;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _paused;

  @override
  void initState() {
    super.initState();
    widget.consent.isLocationPaused().then((v) {
      if (mounted) setState(() => _paused = v);
    });
  }

  void _open(LegalDocument document) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalDocumentScreen(document: document),
      ),
    );
  }

  Future<void> _setPaused(bool paused) async {
    setState(() => _paused = paused);
    await widget.consent.setLocationPaused(paused);
  }

  void _showDataSources() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('데이터 출처'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final source in dataSources)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('${source.name}\n${source.via}'),
              ),
            const Text('시간표와 실시간 정보는 실제 운행과 다를 수 있어요.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmWithdraw() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('위치정보 동의를 철회할까요?'),
        content: const Text('저장된 집 위치와 설정, 예약된 알림이 모두 삭제돼요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('철회'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await widget.consent.withdraw();
    await widget.onWithdrawn();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('설정')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('위치 사용 일시 중지'),
            subtitle: const Text('켜두면 현재 위치를 쓰지 않아요.'),
            value: _paused ?? false,
            onChanged: _paused == null ? null : _setPaused,
          ),
          const Divider(),
          if (widget.adFreeSection case final section?) ...[
            section,
            const Divider(),
          ],
          ListTile(
            title: const Text('개인정보처리방침'),
            onTap: () => _open(LegalDocument.privacyPolicy),
          ),
          ListTile(
            title: const Text('위치기반서비스 이용약관'),
            onTap: () => _open(LegalDocument.locationTerms),
          ),
          ListTile(title: const Text('데이터 출처'), onTap: _showDataSources),
          ListTile(
            title: const Text('오픈소스 라이선스'),
            onTap: () =>
                showLicensePage(context: context, applicationName: '막차 알림'),
          ),
          const Divider(),
          ListTile(
            title: Text(
              '위치정보 동의 철회',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: _confirmWithdraw,
          ),
        ],
      ),
    );
  }
}
