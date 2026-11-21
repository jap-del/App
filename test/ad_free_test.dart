import 'package:flutter_test/flutter_test.dart';
import 'package:last_train/services/ad_free.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AdFreeState', () {
    test('처음에는 광고를 보여준다', () async {
      final state = AdFreeState();
      await state.load();
      expect(state.adsHidden, isFalse);
    });

    test('광고 제거를 사면 계속 숨기고, 다시 불러와도 유지된다', () async {
      await AdFreeState().markPurchased();
      final reloaded = AdFreeState();
      await reloaded.load();
      expect(reloaded.purchased, isTrue);
      expect(reloaded.adsHidden, isTrue);
    });

    test('보상형 광고는 24시간 숨기고, 남은 시간 뒤로 이어 붙인다', () async {
      var now = DateTime(2026, 11, 20, 22);
      final state = AdFreeState(now: () => now);
      await state.grantReward();
      expect(state.adsHidden, isTrue);
      now = now.add(const Duration(hours: 10));
      await state.grantReward();
      expect(state.rewardUntil, DateTime(2026, 11, 22, 22));
      now = DateTime(2026, 11, 22, 22, 1);
      expect(state.adsHidden, isFalse);
    });
  });

  group('shouldShowInterstitial', () {
    final now = DateTime(2026, 11, 20, 21);

    test('출발까지 여유가 있고 처음이면 띄운다', () {
      expect(
        shouldShowInterstitial(
          now: now,
          lastShown: null,
          departBy: now.add(const Duration(hours: 2)),
        ),
        isTrue,
      );
    });

    test('출발 30분 전부터는 띄우지 않는다', () {
      expect(
        shouldShowInterstitial(
          now: now,
          lastShown: null,
          departBy: now.add(const Duration(minutes: 29)),
        ),
        isFalse,
      );
    });

    test('30분 안에 다시 띄우지 않는다', () {
      expect(
        shouldShowInterstitial(
          now: now,
          lastShown: now.subtract(const Duration(minutes: 10)),
          departBy: null,
        ),
        isFalse,
      );
    });

    test('광고 제거 중이면 띄우지 않는다', () {
      expect(
        shouldShowInterstitial(
          now: now,
          lastShown: null,
          departBy: null,
          adsHidden: true,
        ),
        isFalse,
      );
    });
  });
}
