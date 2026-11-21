import 'dart:io' show Platform;

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';

import 'ad_free.dart';

/// Google이 공개한 테스트용 배너 광고 ID. 실제 수익이 나지 않는다.
const _testBannerAndroid = 'ca-app-pub-3940256099942544/6300978111';
const _testBannerIos = 'ca-app-pub-3940256099942544/2934735716';

/// 실제 광고 ID는 빌드할 때 넘긴다.
/// `--dart-define=AD_BANNER_ANDROID=ca-app-pub-...` 와
/// `--dart-define=AD_BANNER_IOS=ca-app-pub-...`
const _bannerAndroid = String.fromEnvironment(
  'AD_BANNER_ANDROID',
  defaultValue: _testBannerAndroid,
);
const _bannerIos = String.fromEnvironment(
  'AD_BANNER_IOS',
  defaultValue: _testBannerIos,
);

/// Google이 공개한 테스트용 전면 영상 광고, 보상형 광고 ID.
const _testInterstitialAndroid = 'ca-app-pub-3940256099942544/8691691433';
const _testInterstitialIos = 'ca-app-pub-3940256099942544/5135589807';
const _testRewardedAndroid = 'ca-app-pub-3940256099942544/5224354917';
const _testRewardedIos = 'ca-app-pub-3940256099942544/1712485313';

/// `--dart-define=AD_INTERSTITIAL_ANDROID=...`, `AD_INTERSTITIAL_IOS`,
/// `AD_REWARDED_ANDROID`, `AD_REWARDED_IOS` 로 실제 ID를 넘긴다.
const _interstitialAndroid = String.fromEnvironment(
  'AD_INTERSTITIAL_ANDROID',
  defaultValue: _testInterstitialAndroid,
);
const _interstitialIos = String.fromEnvironment(
  'AD_INTERSTITIAL_IOS',
  defaultValue: _testInterstitialIos,
);
const _rewardedAndroid = String.fromEnvironment(
  'AD_REWARDED_ANDROID',
  defaultValue: _testRewardedAndroid,
);
const _rewardedIos = String.fromEnvironment(
  'AD_REWARDED_IOS',
  defaultValue: _testRewardedIos,
);

// 맞춤형 광고는 별도 동의(iOS는 추적 허용)가 필요해서 일반 광고만 요청한다.
const _request = AdRequest(nonPersonalizedAds: true);

Future<void> initAds() => MobileAds.instance.initialize();

/// 전면 영상 광고와 보상형 영상 광고를 미리 불러 두고 띄운다.
class VideoAds {
  VideoAds(this.adFree);

  final AdFreeState adFree;
  InterstitialAd? _interstitial;
  RewardedAd? _rewarded;
  DateTime? _lastInterstitial;

  void preload() {
    _loadInterstitial();
    _loadRewarded();
  }

  void _loadInterstitial() {
    if (adFree.adsHidden || _interstitial != null) return;
    InterstitialAd.load(
      adUnitId: Platform.isIOS ? _interstitialIos : _interstitialAndroid,
      request: _request,
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => _interstitial = ad,
        onAdFailedToLoad: (_) => _interstitial = null,
      ),
    );
  }

  void _loadRewarded() {
    if (adFree.purchased || _rewarded != null) return;
    RewardedAd.load(
      adUnitId: Platform.isIOS ? _rewardedIos : _rewardedAndroid,
      request: _request,
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => _rewarded = ad,
        onAdFailedToLoad: (_) => _rewarded = null,
      ),
    );
  }

  /// 지도 화면을 닫을 때처럼 흐름이 끊기는 자리에서 부른다.
  /// 조건([shouldShowInterstitial])이 맞고 광고가 준비됐을 때만 띄운다.
  Future<void> maybeShowInterstitial({DateTime? departBy}) async {
    final now = DateTime.now();
    final ad = _interstitial;
    if (ad == null) {
      _loadInterstitial();
      return;
    }
    if (!shouldShowInterstitial(
      now: now,
      lastShown: _lastInterstitial,
      departBy: departBy,
      adsHidden: adFree.adsHidden,
    )) {
      return;
    }
    _interstitial = null;
    _lastInterstitial = now;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _loadInterstitial();
      },
    );
    await ad.show();
  }

  bool get rewardedReady => _rewarded != null;

  /// 보상형 광고를 띄운다. 끝까지 보면 광고 없는 시간을 준다.
  /// 광고가 아직 준비되지 않았으면 false.
  Future<bool> showRewarded() async {
    final ad = _rewarded;
    if (ad == null) {
      _loadRewarded();
      return false;
    }
    _rewarded = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _loadRewarded();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _loadRewarded();
      },
    );
    await ad.show(onUserEarnedReward: (_, _) => adFree.grantReward());
    return true;
  }
}

/// 화면 아래에 붙는 배너 광고.
///
/// 광고를 불러오지 못하거나 광고 제거 중이면 자리를 차지하지 않는다.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key, required this.adFree});

  final AdFreeState adFree;

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.adFree.addListener(_onAdFreeChanged);
    if (!widget.adFree.adsHidden) _load();
  }

  void _onAdFreeChanged() {
    if (!mounted) return;
    if (widget.adFree.adsHidden) {
      _ad?.dispose();
      setState(() {
        _ad = null;
        _loaded = false;
      });
    } else if (_ad == null) {
      _load();
    }
  }

  void _load() {
    _ad = BannerAd(
      size: AdSize.banner,
      adUnitId: Platform.isIOS ? _bannerIos : _bannerAndroid,
      request: _request,
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    widget.adFree.removeListener(_onAdFreeChanged);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded || widget.adFree.adsHidden) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
