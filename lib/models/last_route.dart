/// 집까지 가는 마지막 경로의 한 구간 (도보, 버스, 지하철).
class RouteLeg {
  const RouteLeg({required this.mode, required this.description});

  /// 'walk', 'bus', 'subway' 중 하나.
  final String mode;
  final String description;

  factory RouteLeg.fromJson(Map<String, dynamic> json) => RouteLeg(
    mode: json['mode'] as String,
    description: json['description'] as String,
  );
}

/// 일반 막차 뒤에도 탈 수 있는 심야버스.
class NightBusOption {
  const NightBusOption({required this.departBy, required this.buses});

  /// 이 시각까지 출발하면 심야버스로 집에 갈 수 있다.
  final DateTime departBy;

  /// 탈 심야버스 번호 (예: N75).
  final List<String> buses;

  factory NightBusOption.fromJson(Map<String, dynamic> json) => NightBusOption(
    departBy: DateTime.parse(json['departBy'] as String).toLocal(),
    buses: [for (final b in (json['buses'] as List? ?? const [])) '$b'],
  );
}

/// 오늘 집에 갈 수 있는 마지막 경로.
class LastRoute {
  const LastRoute({
    required this.departBy,
    required this.arriveAt,
    required this.legs,
    this.isSample = false,
    this.estimated = false,
    this.nightBus,
  });

  /// 이 시각까지 출발해야 막차를 탈 수 있다.
  final DateTime departBy;
  final DateTime arriveAt;
  final List<RouteLeg> legs;

  /// 실제 교통 데이터가 아닌 예시 데이터인지 여부.
  final bool isSample;

  /// 버스처럼 정류장 시간표가 없어 막차 시각을 추정한 구간이 있는지 여부.
  final bool estimated;

  /// 일반 막차 뒤에도 탈 수 있는 심야버스. 없으면 null.
  final NightBusOption? nightBus;

  factory LastRoute.fromJson(Map<String, dynamic> json) => LastRoute(
    departBy: DateTime.parse(json['departBy'] as String).toLocal(),
    arriveAt: DateTime.parse(json['arriveAt'] as String).toLocal(),
    legs: (json['legs'] as List)
        .map((e) => RouteLeg.fromJson(e as Map<String, dynamic>))
        .toList(),
    estimated: json['estimated'] == true,
    nightBus: json['nightBus'] is Map<String, dynamic>
        ? NightBusOption.fromJson(json['nightBus'] as Map<String, dynamic>)
        : null,
  );
}
