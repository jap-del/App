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
  BackendTransitService(this.baseUrl, {http.Client? client})
    : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  @override
  Future<LastRoute?> lastRouteHome({
    required double fromLat,
    required double fromLng,
    required HomePlace home,
  }) async {
    final uri = Uri.parse('$baseUrl/last-route').replace(
      queryParameters: {
        'fromLat': '$fromLat',
        'fromLng': '$fromLng',
        'toLat': '${home.lat}',
        'toLng': '${home.lng}',
      },
    );
    final response = await _client.get(uri);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw Exception('막차 정보를 가져오지 못했습니다 (${response.statusCode})');
    }
    return LastRoute.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );
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

/// 서버 주소가 설정돼 있으면 실제 서비스, 아니면 예시 서비스를 쓴다.
TransitService createTransitService() {
  const baseUrl = String.fromEnvironment('API_BASE_URL');
  return baseUrl.isEmpty
      ? SampleTransitService()
      : BackendTransitService(baseUrl);
}
