import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/home_place.dart';
import '../models/last_route.dart';

/// 집 위치와 알림 설정을 기기에 저장한다.
class SettingsStore {
  static const _homeKey = 'home_place';
  static const _leadKey = 'lead_minutes';
  static const _preferenceKey = 'route_preference';
  static const defaultLeadMinutes = 10;

  Future<HomePlace?> loadHome() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_homeKey);
    if (raw == null) return null;
    return HomePlace.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> saveHome(HomePlace home) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_homeKey, jsonEncode(home.toJson()));
  }

  Future<int> loadLeadMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_leadKey) ?? defaultLeadMinutes;
  }

  Future<void> saveLeadMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_leadKey, minutes);
  }

  /// 어떤 막차를 기준으로 알릴지 (가장 늦은 막차, 지하철만, 버스만, 지하철+버스).
  Future<RoutePreference> loadRoutePreference() async {
    final prefs = await SharedPreferences.getInstance();
    return RoutePreference.parse(prefs.getString(_preferenceKey));
  }

  Future<void> saveRoutePreference(RoutePreference preference) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_preferenceKey, preference.name);
  }
}
