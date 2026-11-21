import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:last_train/models/home_place.dart';
import 'package:last_train/services/saved_route_store.dart';
import 'package:last_train/services/transit_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const home = HomePlace(name: '우리 집', lat: 37.4979, lng: 127.0276);

http.Response jsonResponse(Object body, int status) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

const savedPaths = [
  {
    'pathType': 1,
    'subPath': [
      {'trafficType': 3, 'sectionTime': 3, 'distance': 200},
      {'trafficType': 1, 'startName': '서울역', 'endName': '강남'},
    ],
  },
];

const okBody = {
  'departBy': '2026-11-19T15:54:00.000Z',
  'arriveAt': '2026-11-19T16:20:00.000Z',
  'legs': [
    {'mode': 'subway', 'description': '4호선 서울역 00:58 출발'},
  ],
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('SavedRouteStore', () {
    test('300m 안에서 같은 집으로 물으면 저장한 경로를 찾는다', () async {
      final store = SavedRouteStore();
      await store.save(
        fromLat: 37.5547,
        fromLng: 126.9707,
        home: home,
        paths: savedPaths,
      );
      // 약 200m 떨어진 곳
      expect(
        await store.find(fromLat: 37.5565, fromLng: 126.9707, home: home),
        isNotNull,
      );
      // 약 1km 떨어진 곳
      expect(
        await store.find(fromLat: 37.5637, fromLng: 126.9707, home: home),
        isNull,
      );
      // 집이 바뀌면 다시 찾는다
      expect(
        await store.find(
          fromLat: 37.5547,
          fromLng: 126.9707,
          home: const HomePlace(name: '새 집', lat: 37.6, lng: 127.1),
        ),
        isNull,
      );
    });

    test('7일이 지나면 다시 찾는다', () async {
      var now = DateTime(2026, 11, 21);
      final store = SavedRouteStore(now: () => now);
      await store.save(
        fromLat: 37.5547,
        fromLng: 126.9707,
        home: home,
        paths: savedPaths,
      );
      now = now.add(const Duration(days: 8));
      expect(
        await store.find(fromLat: 37.5547, fromLng: 126.9707, home: home),
        isNull,
      );
    });

    test('출발지는 5곳까지만 둔다', () async {
      final store = SavedRouteStore();
      for (var i = 0; i < 6; i++) {
        await store.save(
          fromLat: 37.5 + i * 0.05,
          fromLng: 126.97,
          home: home,
          paths: savedPaths,
        );
      }
      expect(
        await store.find(fromLat: 37.5, fromLng: 126.97, home: home),
        isNull,
      );
      expect(
        await store.find(fromLat: 37.75, fromLng: 126.97, home: home),
        isNotNull,
      );
    });
  });

  group('BackendTransitService 저장 경로', () {
    test('처음에는 길찾기를 하고, 다음에는 좌표 없이 저장한 경로만 보낸다', () async {
      final requests = <http.Request>[];
      final service = BackendTransitService(
        'https://api.example.com',
        saved: SavedRouteStore(),
        client: MockClient((request) async {
          requests.add(request);
          return jsonResponse(
            request.method == 'GET'
                ? {...okBody, 'savedPaths': savedPaths}
                : okBody,
            200,
          );
        }),
        now: () => DateTime.utc(2026, 11, 19, 9),
      );
      await service.lastRouteHome(
        fromLat: 37.5547,
        fromLng: 126.9707,
        home: home,
      );
      // 10분 캐시를 피하려고 조금 떨어진 곳에서 다시 묻는다.
      final route = await service.lastRouteHome(
        fromLat: 37.5560,
        fromLng: 126.9707,
        home: home,
      );

      expect(requests.map((r) => r.method), ['GET', 'POST']);
      final post = requests[1];
      expect(post.url.query, isEmpty, reason: '좌표를 보내지 않는다');
      expect(jsonDecode(post.body), {'paths': savedPaths});
      expect(post.body.contains('37.55'), isFalse);
      expect(route!.departBy, DateTime.utc(2026, 11, 19, 15, 54).toLocal());
    });

    test('저장한 경로로 계산하지 못하면 지우고 길찾기를 다시 한다', () async {
      final store = SavedRouteStore();
      await store.save(
        fromLat: 37.5547,
        fromLng: 126.9707,
        home: home,
        paths: savedPaths,
      );
      final methods = <String>[];
      final service = BackendTransitService(
        'https://api.example.com',
        saved: store,
        client: MockClient((request) async {
          methods.add(request.method);
          if (request.method == 'POST') {
            return jsonResponse({'reason': 'unknown'}, 503);
          }
          return jsonResponse(okBody, 200);
        }),
        now: () => DateTime.utc(2026, 11, 19, 9),
      );
      final route = await service.lastRouteHome(
        fromLat: 37.5547,
        fromLng: 126.9707,
        home: home,
      );
      expect(methods, ['POST', 'GET']);
      expect(route, isNotNull);
      expect(
        await store.find(fromLat: 37.5547, fromLng: 126.9707, home: home),
        isNull,
      );
    });

    test('저장한 경로로 막차가 끊겼다고 나오면 길찾기를 하지 않는다', () async {
      final store = SavedRouteStore();
      await store.save(
        fromLat: 37.5547,
        fromLng: 126.9707,
        home: home,
        paths: savedPaths,
      );
      final methods = <String>[];
      final service = BackendTransitService(
        'https://api.example.com',
        saved: store,
        client: MockClient((request) async {
          methods.add(request.method);
          return jsonResponse({'reason': 'missed'}, 404);
        }),
      );
      final route = await service.lastRouteHome(
        fromLat: 37.5547,
        fromLng: 126.9707,
        home: home,
      );
      expect(methods, ['POST']);
      expect(route, isNull);
    });
  });
}
