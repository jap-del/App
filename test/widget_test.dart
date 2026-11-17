import 'package:flutter_test/flutter_test.dart';
import 'package:last_train/legal/consent_store.dart';
import 'package:last_train/main.dart';
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
}
