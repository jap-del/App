import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/home_place.dart';
import '../models/last_route.dart';

/// 현재 위치에서 집까지 가는 마지막 경로를 알려주는 서비스.
abstract class TransitService {
  /// 오늘 남은 경로가 없으면 null.
  Future<LastRoute?> lastRouteHome({
    required double fromLat,
    required double fromLng,
    required HomePlace home,
  });
}

/// 우리 서버를 거쳐 실제 교통 데이터를 가져온다.
///
/// 교통 API 키는 앱에 넣지 않고 서버에만 둔다. 서버 주소는 빌드할 때
/// `--dart-define=API_BASE_URL=https://...` 로 넘긴다.
class BackendTransitService implements TransitService {
  BackendTransitService(
    this.baseUrl, {
    http.Client? client,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now;

  final String baseUrl;
  final http.Client _client;
  final DateTime Function() _now;

  /// 길찾기 API는 호출 수가 제한돼 있어서, 거의 같은 자리에서 다시 물으면
  /// 잠시 전 결과를 다시 쓴다.
  static const cacheFor = Duration(minutes: 10);
  String? _cacheKey;
  DateTime? _cachedAt;
  LastRoute? _cached;

  @override
  Future<LastRoute?> lastRouteHome({
    required double fromLat,
    required double fromLng,
    required HomePlace home,
  }) async {
    // 소수 셋째 자리(약 100m)까지만 같으면 같은 자리로 본다.
    final key = [
      fromLat,
      fromLng,
      home.lat,
      home.lng,
    ].map((v) => v.toStringAsFixed(3)).join(',');
    final now = _now();
    final cachedAt = _cachedAt;
    if (key == _cacheKey &&
        cachedAt != null &&
        now.difference(cachedAt) < cacheFor &&
        (_cached == null || _cached!.departBy.isAfter(now))) {
      return _cached;
    }

    final uri = Uri.parse('$baseUrl/last-route').replace(
      queryParameters: {
        'fromLat': '$fromLat',
        'fromLng': '$fromLng',
        'toLat': '${home.lat}',
        'toLng': '${home.lng}',
      },
    );
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 25));
    final body = _decode(response);
    LastRoute? route;
    if (response.statusCode == 200 && body != null) {
      route = LastRoute.fromJson(body);
    } else if (response.statusCode == 404 &&
        (body?['reason'] == 'missed' || body?['reason'] == 'no-route')) {
      route = null;
    } else {
      throw Exception(
        body?['error'] as String? ??
            '막차 정보를 가져오지 못했어요 (${response.statusCode})',
      );
    }
    _cacheKey = key;
    _cachedAt = now;
    _cached = route;
    return route;
  }

  static Map<String, dynamic>? _decode(http.Response response) {
    try {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      return data is Map<String, dynamic> ? data : null;
    } on FormatException {
      return null;
    }
  }
}

/// 서버가 준비되기 전까지 화면과 알림을 확인하기 위한 예시 데이터.
/// 실제 막차 시간이 아니다.
class SampleTransitService implements TransitService {
  SampleTransitService({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  @override
  Future<LastRoute?> lastRouteHome({
    required double fromLat,
    required double fromLng,
    required HomePlace home,
  }) async {
    final now = _now();
    var departBy = DateTime(now.year, now.month, now.day, 23, 40);
    if (!departBy.isAfter(now)) {
      departBy = departBy.add(const Duration(days: 1));
    }
    return LastRoute(
      departBy: departBy,
      arriveAt: departBy.add(const Duration(minutes: 48)),
      isSample: true,
      legs: const [
        RouteLeg(mode: 'walk', description: '가까운 역까지 도보 6분'),
        RouteLeg(mode: 'subway', description: '지하철 막차 탑승'),
        RouteLeg(mode: 'bus', description: '버스 막차로 환승'),
        RouteLeg(mode: 'walk', description: '집까지 도보 4분'),
      ],
    );
  }
}

/// 막차 계산 서버 (Cloudflare Workers).
const defaultApiBaseUrl = 'https://last-train-api.lasttrain-japdel.workers.dev';

/// 기본은 실제 서버를 쓴다. `--dart-define=API_BASE_URL=sample` 로 실행하면
/// 서버 없이 예시 데이터를 보여준다.
TransitService createTransitService() {
  const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: defaultApiBaseUrl,
  );
  return baseUrl == 'sample'
      ? SampleTransitService()
      : BackendTransitService(baseUrl);
}
