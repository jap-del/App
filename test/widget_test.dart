import 'package:flutter_test/flutter_test.dart';
import 'package:last_train/legal/consent_store.dart';
import 'package:last_train/main.dart';
import 'package:last_train/models/home_place.dart';
import 'package:last_train/models/last_route.dart';
import 'package:last_train/screens/home_screen.dart';
import 'package:last_train/services/settings_store.dart';
import 'package:last_train/services/transit_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

LastTrainApp buildApp() => LastTrainApp(
  home: HomeScreen(
    transit: SampleTransitService(now: () => DateTime(2026, 11, 16, 22, 0)),
    settings: SettingsStore(),
    locate: () async => (lat: 37.5665, lng: 126.9780),
    consent: ConsentStore(),
    onWithdrawn: () {},
  ),
);

class _NightBusTransit implements TransitService {
  @override
  Future<LastRoute?> lastRouteHome({
    required double fromLat,
    required double fromLng,
    required HomePlace home,
  }) async {
    final departBy = DateTime.now().add(const Duration(hours: 2));
    return LastRoute(
      departBy: departBy,
      arriveAt: departBy.add(const Duration(minutes: 30)),
      legs: const [RouteLeg(mode: 'bus', description: '402번 버스 01:33 막차')],
      nightBus: NightBusOption(
        departBy: DateTime(2026, 11, 20, 4, 7),
        buses: const ['N75'],
      ),
    );
  }
}

void main() {
  testWidgets('집이 없으면 집 설정을 안내한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('집 설정하기'), findsOneWidget);
  });

  testWidgets('집을 설정하면 막차 시간이 보인다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('집 설정하기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('현재 위치를 집으로 설정'));
    await tester.pumpAndSettle();

    expect(find.text('우리 집'), findsOneWidget);
    expect(find.text('23:40'), findsOneWidget);
    expect(find.text('예시 데이터예요. 실제 막차 시간이 아닙니다.'), findsOneWidget);
  });

  testWidgets('저장된 집과 알림 시간을 다시 불러온다', (tester) async {
    SharedPreferences.setMockInitialValues({
      'home_place': '{"name":"본가","lat":35.1796,"lng":129.0756}',
      'lead_minutes': 20,
    });
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('본가'), findsOneWidget);
    expect(find.text('20분 전'), findsOneWidget);
  });

  testWidgets('일반 막차 뒤 심야버스가 있으면 한 줄 더 보여준다', (tester) async {
    SharedPreferences.setMockInitialValues({
      'home_place': '{"name":"우리 집","lat":37.4979,"lng":127.0276}',
    });
    await tester.pumpWidget(
      LastTrainApp(
        home: HomeScreen(
          transit: _NightBusTransit(),
          settings: SettingsStore(),
          locate: () async => (lat: 37.5547, lng: 126.9707),
          consent: ConsentStore(),
          onWithdrawn: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('놓쳐도 심야버스 N75번으로 04:07까지 출발할 수 있어요'), findsOneWidget);
  });
}
