import 'package:flutter_test/flutter_test.dart';
import 'package:last_train/legal/consent_store.dart';
import 'package:last_train/main.dart';
import 'package:last_train/screens/home_screen.dart';
import 'package:last_train/services/settings_store.dart';
import 'package:last_train/services/transit_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

LastTrainApp buildGatedApp() => LastTrainApp(
  home: AppGate(
    consent: ConsentStore(),
    homeBuilder: (consent, onWithdrawn) => HomeScreen(
      transit: SampleTransitService(now: () => DateTime(2026, 11, 16, 22, 0)),
      settings: SettingsStore(),
      locate: () async => (lat: 37.5665, lng: 126.9780),
      consent: consent,
      onWithdrawn: onWithdrawn,
    ),
  ),
);

void main() {
  testWidgets('필수 항목에 모두 동의해야 시작할 수 있다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(buildGatedApp());
    await tester.pumpAndSettle();

    final start = find.widgetWithText(FilledButton, '동의하고 시작하기');
    expect(tester.widget<FilledButton>(start).onPressed, isNull);

    await tester.tap(find.text('[필수] 만 14세 이상입니다'));
    await tester.pump();
    expect(tester.widget<FilledButton>(start).onPressed, isNull);

    await tester.tap(find.text('[필수] 위치기반서비스 이용약관 동의'));
    await tester.pump();
    await tester.tap(start);
    await tester.pumpAndSettle();

    expect(find.text('집 설정하기'), findsOneWidget);
    expect(await ConsentStore().hasValidConsent(), isTrue);
  });

  testWidgets('이용약관을 앱 안에서 읽을 수 있다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(buildGatedApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('보기'));
    await tester.pumpAndSettle();

    expect(find.text('위치기반서비스 이용약관'), findsOneWidget);
    expect(find.text('제5조 (이용자의 권리)'), findsOneWidget);
  });

  testWidgets('동의를 철회하면 저장된 정보가 지워지고 동의 화면으로 돌아간다', (tester) async {
    SharedPreferences.setMockInitialValues({
      'consent_version': currentConsentVersion,
      'home_place': '{"name":"본가","lat":35.1796,"lng":129.0756}',
    });
    await tester.pumpWidget(buildGatedApp());
    await tester.pumpAndSettle();
    expect(find.text('본가'), findsOneWidget);

    await tester.tap(find.byTooltip('설정'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('위치정보 동의 철회'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('철회'));
    await tester.pumpAndSettle();

    expect(find.text('동의하고 시작하기'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('home_place'), isNull);
  });

  testWidgets('위치 사용을 일시 중지하면 위치를 쓰지 않는다', (tester) async {
    var located = 0;
    SharedPreferences.setMockInitialValues({
      'consent_version': currentConsentVersion,
      'home_place': '{"name":"본가","lat":35.1796,"lng":129.0756}',
      'location_paused': true,
    });
    await tester.pumpWidget(
      LastTrainApp(
        home: HomeScreen(
          transit: SampleTransitService(),
          settings: SettingsStore(),
          locate: () async {
            located++;
            return (lat: 37.5665, lng: 126.9780);
          },
          consent: ConsentStore(),
          onWithdrawn: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(located, 0);
    expect(find.textContaining('일시 중지'), findsOneWidget);
  });
}
