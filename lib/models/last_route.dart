/// 지도 위의 한 점 (위도, 경도).
typedef MapPoint = ({double lat, double lng});

/// 집까지 가는 마지막 경로의 한 구간 (도보, 버스, 지하철).
class RouteLeg {
  const RouteLeg({
    required this.mode,
    required this.description,
    this.path = const [],
  });

  /// 'walk', 'bus', 'subway' 중 하나.
  final String mode;
  final String description;

  /// 버스·지하철이 지나는 역과 정류장 좌표. 걷는 구간은 비어 있다.
  final List<MapPoint> path;

  factory RouteLeg.fromJson(Map<String, dynamic> json) => RouteLeg(
    mode: json['mode'] as String,
    description: json['description'] as String,
    path: [
      for (final p in (json['path'] as List? ?? const []))
        if (p is List && p.length >= 2 && p[0] is num && p[1] is num)
          (lat: (p[0] as num).toDouble(), lng: (p[1] as num).toDouble()),
    ],
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

/// 막차 종류.
enum RouteKind {
  subway('지하철만'),
  bus('버스만'),
  mixed('지하철+버스');

  const RouteKind(this.label);

  final String label;

  static RouteKind? parse(Object? value) {
    for (final kind in values) {
      if (kind.name == value) return kind;
    }
    return null;
  }
}

/// 어떤 막차를 크게 보여주고 알림 기준으로 쓸지.
enum RoutePreference {
  latest('가장 늦은 막차', null),
  subway('지하철만', RouteKind.subway),
  bus('버스만', RouteKind.bus),
  mixed('지하철+버스', RouteKind.mixed);

  const RoutePreference(this.label, this.kind);

  final String label;

  /// latest면 null (종류와 상관없이 가장 늦은 막차).
  final RouteKind? kind;

  static RoutePreference parse(Object? value) {
    for (final pref in values) {
      if (pref.name == value) return pref;
    }
    return latest;
  }
}

/// 종류별 막차를 계산한 결과.
enum RouteStatus {
  /// 막차가 있다.
  ok,

  /// 오늘 막차가 이미 끊겼다.
  missed,

  /// 시간표가 없어 계산하지 못했다.
  unknown,

  /// 이 종류로 가는 경로가 없다.
  none;

  static RouteStatus parse(Object? value) {
    for (final status in values) {
      if (status.name == value) return status;
    }
    return unknown;
  }
}

/// 지하철만, 버스만, 지하철+버스 중 한 종류의 막차.
class RouteOption {
  const RouteOption({required this.kind, required this.status, this.route});

  final RouteKind kind;
  final RouteStatus status;

  /// status가 ok일 때만 있다.
  final LastRoute? route;

  static RouteOption? fromJson(Map<String, dynamic> json) {
    final kind = RouteKind.parse(json['kind']);
    if (kind == null) return null;
    final status = RouteStatus.parse(json['status']);
    if (status == RouteStatus.ok && json['departBy'] is String) {
      return RouteOption(
        kind: kind,
        status: status,
        route: LastRoute.fromJson({...json, 'kind': kind.name}),
      );
    }
    return RouteOption(
      kind: kind,
      status: status == RouteStatus.ok ? RouteStatus.unknown : status,
    );
  }
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
    this.kind,
    this.options = const [],
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

  /// 이 경로의 종류. 예전 서버 응답에는 없다.
  final RouteKind? kind;

  /// 종류별 막차 (지하철만, 버스만, 지하철+버스). 예전 서버 응답에는 없다.
  final List<RouteOption> options;

  /// 이 종류의 막차 결과. 서버가 종류별로 주지 않았으면 null.
  RouteOption? option(RouteKind kind) {
    for (final o in options) {
      if (o.kind == kind) return o;
    }
    return null;
  }

  /// 고른 기준에 맞는 막차. 그 종류의 막차가 없으면 null.
  /// 서버가 종류별로 주지 않았으면 가장 늦은 막차(자기 자신)를 쓴다.
  LastRoute? pick(RoutePreference preference) {
    final kind = preference.kind;
    if (kind == null || options.isEmpty) return this;
    return option(kind)?.route;
  }

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
    kind: RouteKind.parse(json['kind']),
    options: [
      for (final o in (json['options'] as List? ?? const []))
        if (o is Map<String, dynamic>) ?RouteOption.fromJson(o),
    ],
  );
}
