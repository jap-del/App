import 'package:shared_preferences/shared_preferences.dart';

/// 약관이 바뀌어 다시 동의를 받아야 할 때 올린다.
const currentConsentVersion = 2;

/// 이용자의 동의 기록과 위치 사용 일시 중지 상태를 기기에 저장한다.
class ConsentStore {
  static const _versionKey = 'consent_version';
  static const _agreedAtKey = 'consent_agreed_at';
  static const _pausedKey = 'location_paused';

  Future<bool> hasValidConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getInt(_versionKey) ?? 0) >= currentConsentVersion;
  }

  /// 동의한 약관 버전과 시각을 남긴다.
  Future<void> recordConsent({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_versionKey, currentConsentVersion);
    await prefs.setString(
      _agreedAtKey,
      (now ?? DateTime.now()).toUtc().toIso8601String(),
    );
  }

  Future<bool> isLocationPaused() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_pausedKey) ?? false;
  }

  Future<void> setLocationPaused(bool paused) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_pausedKey, paused);
  }

  /// 동의 철회: 동의 기록과 기기에 저장된 위치 관련 정보를 모두 지운다.
  Future<void> withdraw() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
