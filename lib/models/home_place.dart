/// 사용자가 설정한 집 위치.
class HomePlace {
  const HomePlace({required this.name, required this.lat, required this.lng});

  final String name;
  final double lat;
  final double lng;

  Map<String, dynamic> toJson() => {'name': name, 'lat': lat, 'lng': lng};

  factory HomePlace.fromJson(Map<String, dynamic> json) => HomePlace(
    name: json['name'] as String,
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
  );
}
