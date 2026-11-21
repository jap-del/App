import 'dart:convert';
import 'dart:math' as math;

import 'package:shared_preferences/shared_preferences.dart';

import '../models/home_place.dart';

/// 서버가 찾아 준 길찾기 경로를 기기에 저장해 둔다.
///
/// 같은 곳(약 300m 안)에서 같은 집으로 다시 물으면 저장한 경로를 서버에 보내
/// 길찾기(ODsay, 유료 호출)를 건너뛰고 시간표로만 막차를 계산한다.
/// 출발 위치는 약 100m 단위로 줄여서 이 기기에만 저장하고, 서버에는 보내지 않는다.
class SavedRouteStore {
  SavedRouteStore({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const _key = 'saved_routes';

  /// 노선이 바뀌었을 수 있으니 이보다 오래된 경로는 다시 찾는다.
  static const keepFor = Duration(days: 7);

  /// 이 거리 안이면 같은 곳으로 본다.
  static const sameSpotMeters = 300.0;

  /// 저장해 두는 출발지 수 (오래 안 쓴 것부터 지운다).
  static const maxEntries = 5;

  final DateTime Function() _now;

  /// 저장된 경로(서버의 savedPaths 그대로)를 찾는다. 없으면 null.
  Future<List<dynamic>?> find({
    required double fromLat,
    required double fromLng,
    required HomePlace home,
  }) async {
    final entries = await _load();
    for (final e in entries) {
      if (_sameHome(e, home) &&
          distanceMeters(fromLat, fromLng, e.lat, e.lng) <= sameSpotMeters) {
        return e.paths;
      }
    }
    return null;
  }

  Future<void> save({
    required double fromLat,
    required double fromLng,
    required HomePlace home,
    required List<dynamic> paths,
  }) async {
    final entries = await _load();
    entries.removeWhere(
      (e) =>
          _sameHome(e, home) &&
          distanceMeters(fromLat, fromLng, e.lat, e.lng) <= sameSpotMeters,
    );
    entries.insert(
      0,
      _Entry(
        lat: _round(fromLat),
        lng: _round(fromLng),
        homeLat: home.lat,
        homeLng: home.lng,
        savedAt: _now(),
        paths: paths,
      ),
    );
    await _store(entries.take(maxEntries).toList());
  }

  /// 저장한 경로로 계산이 안 되면 지워서 다음에는 새로 찾게 한다.
  Future<void> remove({
    required double fromLat,
    required double fromLng,
    required HomePlace home,
  }) async {
    final entries = await _load();
    entries.removeWhere(
      (e) =>
          _sameHome(e, home) &&
          distanceMeters(fromLat, fromLng, e.lat, e.lng) <= sameSpotMeters,
    );
    await _store(entries);
  }

  Future<List<_Entry>> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final now = _now();
      return (jsonDecode(raw) as List)
          .map((j) => _Entry.fromJson(j as Map<String, dynamic>))
          .where((e) => now.difference(e.savedAt) < keepFor)
          .toList();
    } on Object {
      return [];
    }
  }

  Future<void> _store(List<_Entry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  static bool _sameHome(_Entry e, HomePlace home) =>
      (e.homeLat - home.lat).abs() < 1e-6 &&
      (e.homeLng - home.lng).abs() < 1e-6;

  /// 소수 셋째 자리(약 100m)까지만 남긴다.
  static double _round(double v) => (v * 1000).round() / 1000;
}

/// 두 좌표 사이 거리(m).
double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a =
      math.pow(math.sin(dLat / 2), 2) +
      math.cos(rad(lat1)) *
          math.cos(rad(lat2)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(a));
}

class _Entry {
  _Entry({
    required this.lat,
    required this.lng,
    required this.homeLat,
    required this.homeLng,
    required this.savedAt,
    required this.paths,
  });

  factory _Entry.fromJson(Map<String, dynamic> j) => _Entry(
    lat: (j['lat'] as num).toDouble(),
    lng: (j['lng'] as num).toDouble(),
    homeLat: (j['homeLat'] as num).toDouble(),
    homeLng: (j['homeLng'] as num).toDouble(),
    savedAt: DateTime.parse(j['savedAt'] as String),
    paths: j['paths'] as List<dynamic>,
  );

  final double lat;
  final double lng;
  final double homeLat;
  final double homeLng;
  final DateTime savedAt;
  final List<dynamic> paths;

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lng': lng,
    'homeLat': homeLat,
    'homeLng': homeLng,
    'savedAt': savedAt.toIso8601String(),
    'paths': paths,
  };
}
