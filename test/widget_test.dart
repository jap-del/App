import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:last_train/legal/consent_store.dart';
import 'package:last_train/main.dart';
import 'package:last_train/models/home_place.dart';
import 'package:last_train/models/last_route.dart';
import 'package:last_train/screens/home_screen.dart';
import 'package:last_train/screens/route_map_screen.dart';
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

LastRoute _route(
  RouteKind kind,
  DateTime departBy,
  String description, {
  List<MapPoint> path = const [],
}) => LastRoute(
  departBy: departBy,
  arriveAt: departBy.add(const Duration(minutes: 40)),
  kind: kind,
  legs: [
    const RouteLeg(mode: 'walk', description: '걸어서 3분'),
    RouteLeg(
      mode: kind == RouteKind.bus ? 'bus' : 'subway',
      description: description,
      path: path,
    ),
  ],
);

class _KindsTransit implements TransitService {
  @override
  Future<LastRoute?> lastRouteHome({
    required double fromLat,
    required double fromLng,
    required HomePlace home,
  }) async {
    final subway = _route(
      RouteKind.subway,
      DateTime(2026, 11, 20, 0, 21),
      '4호선 서울역 00:27 출발',
      path: const [
        (lat: 37.5547, lng: 126.9707),
        (lat: 37.5443, lng: 126.9723),
      ],
    );
    final bus = _route(
      RouteKind.bus,
      DateTime(2026, 11, 20, 1, 29),
      '402번 버스 01:33 막차',
    );
    return LastRoute(
      departBy: bus.departBy,
      arriveAt: bus.arriveAt,
      legs: bus.legs,
      kind: RouteKind.bus,
      options: [
        RouteOption(
          kind: RouteKind.subway,
          status: RouteStatus.ok,
          route: subway,
        ),
        RouteOption(kind: RouteKind.bus, status: RouteStatus.ok, route: bus),
        const RouteOption(kind: RouteKind.mixed, status: RouteStatus.missed),
      ],
    );
  }
}

LastTrainApp _kindsApp() => LastTrainApp(
  home: HomeScreen(
    transit: _KindsTransit(),
    settings: SettingsStore(),
    locate: () async => (lat: 37.5547, lng: 126.9707),
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

  testWidgets('지하철만, 버스만, 지하철+버스 막차를 골라 본다', (tester) async {
    SharedPreferences.setMockInitialValues({
      'home_place': '{"name":"우리 집","lat":37.4979,"lng":127.0276}',
    });
    await tester.pumpWidget(_kindsApp());
    await tester.pumpAndSettle();

    expect(find.text('가장 늦게 01:29'), findsOneWidget);
    expect(find.text('지하철 00:21'), findsOneWidget);
    expect(find.text('버스 01:29'), findsOneWidget);
    expect(find.text('지하철+버스 끊김'), findsOneWidget);
    expect(find.text('01:29'), findsOneWidget);
    expect(find.text('지도로 보기'), findsNothing, reason: '좌표가 없으면 지도 버튼을 숨긴다');

    await tester.tap(find.text('지하철 00:21'));
    await tester.pumpAndSettle();
    expect(find.text('00:21'), findsOneWidget);
    expect(find.text('4호선 서울역 00:27 출발'), findsOneWidget);
    expect(find.text('지도로 보기'), findsOneWidget);

    await tester.tap(find.text('지하철+버스 끊김'));
    await tester.pumpAndSettle();
    expect(find.text('지하철+버스로 가는 막차는 끊겼어요.'), findsOneWidget);
  });

  testWidgets('알림 기준 막차를 고르면 저장하고 그 막차를 보여준다', (tester) async {
    SharedPreferences.setMockInitialValues({
      'home_place': '{"name":"우리 집","lat":37.4979,"lng":127.0276}',
    });
    await tester.pumpWidget(_kindsApp());
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('가장 늦은 막차'), 200);
    await tester.tap(find.text('가장 늦은 막차'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('지하철만').last);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('route_preference'), 'subway');
    await tester.scrollUntilVisible(find.text('00:21'), -200);
    expect(find.text('00:21'), findsOneWidget);
  });

  testWidgets('저장된 알림 기준 막차를 먼저 보여준다', (tester) async {
    SharedPreferences.setMockInitialValues({
      'home_place': '{"name":"우리 집","lat":37.4979,"lng":127.0276}',
      'route_preference': 'subway',
    });
    await tester.pumpWidget(_kindsApp());
    await tester.pumpAndSettle();
    expect(find.text('00:21'), findsOneWidget);
  });

  test('걷는 구간은 현재 위치, 정류장, 집을 이어 그린다', () {
    final route = LastRoute(
      departBy: DateTime(2026, 11, 20),
      arriveAt: DateTime(2026, 11, 20, 1),
      legs: const [
        RouteLeg(mode: 'walk', description: '걷기'),
        RouteLeg(
          mode: 'subway',
          description: '지하철',
          path: [(lat: 1, lng: 1), (lat: 2, lng: 2)],
        ),
        RouteLeg(mode: 'walk', description: '갈아타기'),
        RouteLeg(
          mode: 'bus',
          description: '버스',
          path: [(lat: 2.1, lng: 2.1), (lat: 3, lng: 3)],
        ),
        RouteLeg(mode: 'walk', description: '집까지'),
      ],
    );
    final segments = routeSegments(
      route,
      from: (lat: 0, lng: 0),
      home: (lat: 4, lng: 4),
    );
    expect(segments.map((s) => s.mode), [
      'walk',
      'subway',
      'walk',
      'bus',
      'walk',
    ]);
    expect(segments.first.points, [(lat: 0.0, lng: 0.0), (lat: 1.0, lng: 1.0)]);
    expect(segments[2].points, [(lat: 2.0, lng: 2.0), (lat: 2.1, lng: 2.1)]);
    expect(segments.last.points, [(lat: 3.0, lng: 3.0), (lat: 4.0, lng: 4.0)]);
  });

  testWidgets('지도 화면에 경로와 집, 현재 위치를 그린다', (tester) async {
    final route = _route(
      RouteKind.subway,
      DateTime(2026, 11, 20, 0, 21),
      '4호선',
      path: const [
        (lat: 37.5547, lng: 126.9707),
        (lat: 37.5443, lng: 126.9723),
      ],
    );
    await tester.pumpWidget(
      LastTrainApp(
        home: RouteMapScreen(
          route: route,
          from: (lat: 37.5550, lng: 126.9700),
          home: (lat: 37.4979, lng: 127.0276),
          tileUrl: null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('이동 경로'), findsOneWidget);
    expect(find.byIcon(Icons.home), findsOneWidget);
    expect(find.byIcon(Icons.my_location), findsOneWidget);
    expect(find.byIcon(Icons.subway), findsOneWidget);
    expect(find.text('지하철'), findsOneWidget);
  });
}
