import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 광고를 숨길지 정한다.
///
/// 광고 제거를 샀거나, 보상형 영상 광고를 보고 받은 광고 없는 시간이
/// 남아 있으면 배너와 전면 광고를 모두 숨긴다.
class AdFreeState extends ChangeNotifier {
  AdFreeState({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const _purchasedKey = 'ads_removed';
  static const _rewardUntilKey = 'ad_free_until';

  /// 보상형 영상 광고 한 번에 받는 광고 없는 시간.
  static const rewardDuration = Duration(hours: 24);

  final DateTime Function() _now;
  bool _purchased = false;
  DateTime? _rewardUntil;

  bool get purchased => _purchased;
  DateTime? get rewardUntil => _rewardUntil;

  bool get adsHidden => _purchased || (_rewardUntil?.isAfter(_now()) ?? false);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _purchased = prefs.getBool(_purchasedKey) ?? false;
    final until = prefs.getInt(_rewardUntilKey);
    _rewardUntil = until == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(until);
    notifyListeners();
  }

  /// 광고 제거를 샀거나 구매를 복원했다.
  Future<void> markPurchased() async {
    if (_purchased) return;
    _purchased = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_purchasedKey, true);
    notifyListeners();
  }

  /// 보상형 영상 광고를 끝까지 봤다. 남은 시간이 있으면 그 뒤로 이어 붙인다.
  Future<void> grantReward() async {
    final now = _now();
    final from = (_rewardUntil != null && _rewardUntil!.isAfter(now))
        ? _rewardUntil!
        : now;
    _rewardUntil = from.add(rewardDuration);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_rewardUntilKey, _rewardUntil!.millisecondsSinceEpoch);
    notifyListeners();
  }
}

/// 전면 영상 광고를 지금 띄워도 되는지.
///
/// 막차를 잡으러 급하게 나가는 사람을 막지 않도록, 출발까지 30분이
/// 안 남았으면 띄우지 않는다. 너무 자주 뜨지 않게 30분에 한 번까지만.
bool shouldShowInterstitial({
  required DateTime now,
  required DateTime? lastShown,
  required DateTime? departBy,
  bool adsHidden = false,
  Duration minGap = const Duration(minutes: 30),
  Duration quietBeforeDeparture = const Duration(minutes: 30),
}) {
  if (adsHidden) return false;
  if (lastShown != null && now.difference(lastShown) < minGap) return false;
  if (departBy != null && departBy.difference(now) < quietBeforeDeparture) {
    return false;
  }
  return true;
}
