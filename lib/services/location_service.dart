import 'package:geolocator/geolocator.dart';

/// 위도와 경도.
typedef LatLng = ({double lat, double lng});

/// 현재 위치를 알려주는 함수. 테스트에서는 가짜로 바꿔 끼운다.
typedef LocationProvider = Future<LatLng> Function();

/// 기기의 현재 위치를 가져온다. 권한이 없으면 요청한다.
Future<LatLng> deviceLocation() async {
  if (!await Geolocator.isLocationServiceEnabled()) {
    throw Exception('위치 서비스가 꺼져 있어요. 설정에서 켜주세요.');
  }
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    throw Exception('위치 권한이 필요해요. 설정에서 허용해주세요.');
  }
  final position = await Geolocator.getCurrentPosition();
  return (lat: position.latitude, lng: position.longitude);
}
