import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/last_route.dart';

/// 막차 알림과 잠금화면 표시를 담당한다.
class NotificationService {
  static const _departAlertId = 1;
  static const _lockScreenId = 2;

  final _plugin = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    tzdata.initializeTimeZones();
    // 전국 서비스라서 한국 시간대로 고정한다.
    tz.setLocalLocation(tz.getLocation('Asia/Seoul'));
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
    );
  }

  Future<void> requestPermission() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
  }

  /// [alertAt]에 "지금 출발하세요" 알림을 예약한다.
  Future<void> scheduleDepartAlert({
    required DateTime alertAt,
    required LastRoute route,
  }) async {
    final time = DateFormat('HH:mm').format(route.departBy);
    await _plugin.zonedSchedule(
      id: _departAlertId,
      title: '막차 시간이 다가와요',
      body: '$time까지 출발해야 집에 갈 수 있어요.',
      scheduledDate: tz.TZDateTime.from(alertAt, tz.local),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'depart_alert',
          '막차 출발 알림',
          channelDescription: '막차를 타려면 출발해야 할 때 알려줍니다.',
          importance: Importance.max,
          priority: Priority.high,
          visibility: NotificationVisibility.public,
        ),
        iOS: DarwinNotificationDetails(
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
    );
  }

  /// 잠금화면에 막차 시간을 계속 보여준다.
  ///
  /// Android에서는 지워지지 않는 고정 알림으로 보인다. iOS의 라이브
  /// 액티비티는 별도의 네이티브 코드가 필요해서 다음 단계에서 추가한다.
  Future<void> showLockScreenStatus(LastRoute route) async {
    final time = DateFormat('HH:mm').format(route.departBy);
    await _plugin.show(
      id: _lockScreenId,
      title: '오늘 막차 $time',
      body: '$time까지 출발하면 집에 갈 수 있어요.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'lock_screen_status',
          '잠금화면 막차 시간',
          channelDescription: '잠금화면에 오늘의 막차 시간을 보여줍니다.',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          onlyAlertOnce: true,
          visibility: NotificationVisibility.public,
        ),
        iOS: DarwinNotificationDetails(presentSound: false),
      ),
    );
  }

  Future<void> clear() async {
    await _plugin.cancel(id: _departAlertId);
    await _plugin.cancel(id: _lockScreenId);
  }
}
