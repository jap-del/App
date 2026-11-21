import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import 'ad_free.dart';

/// 광고 제거 상품 ID. Google Play Console과 App Store Connect에
/// 같은 ID로 "비소모성"(한 번 사면 계속 유지) 상품을 만든다.
const removeAdsProductId = 'remove_ads';

/// 스토어 인앱 결제로 광고 제거를 판다.
class PurchaseService {
  PurchaseService(this.adFree, {InAppPurchase? store})
    : _store = store ?? InAppPurchase.instance;

  final AdFreeState adFree;
  final InAppPurchase _store;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  ProductDetails? _product;

  /// 스토어에 연결해 상품 정보를 받아 둔다. 스토어를 쓸 수 없으면 조용히 넘어간다.
  Future<void> init() async {
    _sub = _store.purchaseStream.listen(_onPurchases, onError: (_) {});
    if (!await _store.isAvailable()) return;
    final response = await _store.queryProductDetails({removeAdsProductId});
    if (response.productDetails.isNotEmpty) {
      _product = response.productDetails.first;
    }
  }

  /// 스토어에 표시된 가격 (예: ₩3,300). 상품을 못 받았으면 null.
  String? get price => _product?.price;

  /// 결제 창을 연다. 상품 정보가 없으면 false.
  Future<bool> buyRemoveAds() async {
    final product = _product;
    if (product == null) return false;
    return _store.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product),
    );
  }

  /// 다른 기기나 재설치 뒤에 산 기록을 다시 불러온다.
  Future<void> restore() => _store.restorePurchases();

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      if (p.productID == removeAdsProductId &&
          (p.status == PurchaseStatus.purchased ||
              p.status == PurchaseStatus.restored)) {
        await adFree.markPurchased();
      }
      if (p.pendingCompletePurchase) await _store.completePurchase(p);
    }
  }

  void dispose() => _sub?.cancel();
}
