import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:last_train/models/home_place.dart';
import 'package:last_train/services/transit_service.dart';

const home = HomePlace(name: '우리 집', lat: 37.4979, lng: 127.0276);

http.Response jsonResponse(Object body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const okBody = {
  'departBy': '2026-11-19T15:54:00.000Z',
  'arriveAt': '2026-11-19T16:20:00.000Z',
  'estimated': true,
  'legs': [
    {'mode': 'walk', 'description': '서울역까지 걸어서 3분', 'minutes': 3},
    {'mode': 'subway', 'description': '4호선 서울역 00:58 출발', 'isLast': true},
  ],
};

void main() {
  test('서버의 막차 경로를 읽는다', () async {
    late Uri called;
    final service = BackendTransitService(
      'https://api.example.com',
      client: MockClient((request) async {
        called = request.url;
        return jsonResponse(okBody, 200);
      }),
      now: () => DateTime.utc(2026, 11, 19, 9),
    );

    final route = await service.lastRouteHome(
      fromLat: 37.5547,
      fromLng: 126.9707,
      home: home,
    );

    expect(called.path, '/last-route');
    expect(called.queryParameters['toLng'], '127.0276');
    expect(route!.departBy, DateTime.utc(2026, 11, 19, 15, 54).toLocal());
    expect(route.estimated, isTrue);
    expect(route.isSample, isFalse);
    expect(route.legs.map((l) => l.mode), ['walk', 'subway']);
    expect(route.nightBus, isNull);
  });

  test('일반 막차 뒤의 심야버스를 읽는다', () async {
    final service = BackendTransitService(
      'https://api.example.com',
      client: MockClient(
        (_) async => jsonResponse({
          ...okBody,
          'nightBus': {
            'departBy': '2026-11-19T19:07:00.000Z',
            'buses': ['N75'],
            'legs': [],
          },
        }, 200),
      ),
    );
    final route = await service.lastRouteHome(
      fromLat: 37.5,
      fromLng: 127,
      home: home,
    );
    expect(route!.nightBus!.buses, ['N75']);
    expect(
      route.nightBus!.departBy,
      DateTime.utc(2026, 11, 19, 19, 7).toLocal(),
    );
  });

  test('막차가 끊겼으면 null', () async {
    final service = BackendTransitService(
      'https://api.example.com',
      client: MockClient(
        (_) async => jsonResponse({'error': '끊겼어요', 'reason': 'missed'}, 404),
      ),
    );
    expect(
      await service.lastRouteHome(fromLat: 37.5, fromLng: 127, home: home),
      isNull,
    );
  });

  test('집이 너무 가까우면 서버가 준 문구로 알려준다', () async {
    final service = BackendTransitService(
      'https://api.example.com',
      client: MockClient(
        (_) async => jsonResponse({
          'error': '집이 아주 가까워요. 걸어서 갈 수 있어요.',
          'reason': 'too-close',
        }, 404),
      ),
    );
    expect(
      () => service.lastRouteHome(fromLat: 37.5, fromLng: 127, home: home),
      throwsA(predicate((e) => e.toString().contains('집이 아주 가까워요'))),
    );
  });

  test('같은 자리에서 10분 안에 다시 물으면 서버를 다시 부르지 않는다', () async {
    var calls = 0;
    var now = DateTime.utc(2026, 11, 19, 9);
    final service = BackendTransitService(
      'https://api.example.com',
      client: MockClient((_) async {
        calls += 1;
        return jsonResponse(okBody, 200);
      }),
      now: () => now,
    );

    await service.lastRouteHome(
      fromLat: 37.55471,
      fromLng: 126.9707,
      home: home,
    );
    now = now.add(const Duration(minutes: 5));
    await service.lastRouteHome(
      fromLat: 37.55474,
      fromLng: 126.97071,
      home: home,
    );
    expect(calls, 1);

    now = now.add(const Duration(minutes: 6));
    await service.lastRouteHome(
      fromLat: 37.55474,
      fromLng: 126.97071,
      home: home,
    );
    expect(calls, 2);

    await service.lastRouteHome(fromLat: 37.60, fromLng: 126.9707, home: home);
    expect(calls, 3);
  });

  test('서버 오류는 서버가 준 문구로 알려준다', () async {
    final service = BackendTransitService(
      'https://api.example.com',
      client: MockClient(
        (_) async => jsonResponse({'error': '이 경로는 막차 시간을 계산하지 못했어요.'}, 503),
      ),
    );
    expect(
      () => service.lastRouteHome(fromLat: 37.5, fromLng: 127, home: home),
      throwsA(predicate((e) => e.toString().contains('계산하지 못했어요'))),
    );
  });
}
