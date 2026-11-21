import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../services/ad_free.dart';

/// 설정 화면의 광고 제거 메뉴: 결제로 영구 제거, 영상 광고 보고 하루 제거, 구매 복원.
class AdFreeSection extends StatelessWidget {
  const AdFreeSection({
    super.key,
    required this.adFree,
    required this.price,
    required this.onBuy,
    required this.onRestore,
    required this.onWatchReward,
  });

  final AdFreeState adFree;

  /// 스토어 가격. 상품을 못 받았으면 null.
  final String? Function() price;
  final Future<bool> Function() onBuy;
  final Future<void> Function() onRestore;
  final Future<bool> Function() onWatchReward;

  void _toast(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: adFree,
      builder: (context, _) {
        if (adFree.purchased) {
          return const ListTile(
            leading: Icon(Icons.check_circle_outline),
            title: Text('광고 제거됨'),
            subtitle: Text('구매해 주셔서 감사해요.'),
          );
        }
        final until = adFree.rewardUntil;
        final rewardActive = until != null && until.isAfter(DateTime.now());
        final p = price();
        return Column(
          children: [
            ListTile(
              leading: const Icon(Icons.block),
              title: const Text('광고 제거'),
              subtitle: Text(
                p == null ? '한 번 구매로 계속 광고 없이' : '$p · 한 번 구매로 계속',
              ),
              onTap: () async {
                final ok = await onBuy();
                if (!ok && context.mounted) {
                  _toast(context, '지금은 스토어에 연결할 수 없어요.');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.ondemand_video),
              title: const Text('영상 보고 하루 동안 광고 없이'),
              subtitle: rewardActive
                  ? Text('${DateFormat('M월 d일 HH:mm').format(until)}까지 광고 없음')
                  : null,
              onTap: () async {
                final shown = await onWatchReward();
                if (!shown && context.mounted) {
                  _toast(context, '영상을 불러오는 중이에요. 잠시 뒤 다시 눌러 주세요.');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('구매 복원'),
              onTap: onRestore,
            ),
          ],
        );
      },
    );
  }
}
