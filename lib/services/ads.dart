import 'dart:io' show Platform;

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';

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

Future<void> initAds() => MobileAds.instance.initialize();

/// 화면 아래에 붙는 배너 광고.
///
/// 광고를 불러오지 못하면 자리를 차지하지 않는다. 막차 시간을 가리지
/// 않도록 전면 광고는 쓰지 않는다.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ad = BannerAd(
      size: AdSize.banner,
      adUnitId: Platform.isIOS ? _bannerIos : _bannerAndroid,
      // 맞춤형 광고는 별도 동의(iOS는 추적 허용)가 필요해서 일반 광고만 요청한다.
      request: const AdRequest(nonPersonalizedAds: true),
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
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
