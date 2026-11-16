import 'package:flutter_test/flutter_test.dart';
import 'package:last_train/logic/alert_planner.dart';

void main() {
  final now = DateTime(2026, 11, 16, 22, 0);

  group('planAlertTime', () {
    test('출발 시각보다 설정한 분만큼 먼저 알린다', () {
      final alertAt = planAlertTime(
        departBy: DateTime(2026, 11, 16, 23, 40),
        leadMinutes: 10,
        now: now,
      );
      expect(alertAt, DateTime(2026, 11, 16, 23, 30));
    });

    test('알림 시각은 지났지만 출발이 가능하면 바로 알린다', () {
      final alertAt = planAlertTime(
        departBy: DateTime(2026, 11, 16, 22, 5),
        leadMinutes: 10,
        now: now,
      );
      expect(alertAt, now);
    });

    test('막차가 이미 떠났으면 알리지 않는다', () {
      final alertAt = planAlertTime(
        departBy: DateTime(2026, 11, 16, 21, 59),
        leadMinutes: 10,
        now: now,
      );
      expect(alertAt, isNull);
    });
  });

  group('formatRemaining', () {
    test('시간과 분을 함께 보여준다', () {
      expect(formatRemaining(const Duration(minutes: 65)), '1시간 5분');
      expect(formatRemaining(const Duration(minutes: 120)), '2시간');
      expect(formatRemaining(const Duration(minutes: 7)), '7분');
    });

    test('시간이 다 됐으면 지금 출발하라고 한다', () {
      expect(formatRemaining(Duration.zero), '지금 출발');
      expect(formatRemaining(const Duration(minutes: -3)), '지금 출발');
    });
  });
}
