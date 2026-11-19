import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_ui/material_ui.dart';

import '../models/last_route.dart';

/// 지도 이미지 주소. 출시 전에는 앱 배포를 허용하는 지도 제공자로 바꿔야 한다.
/// `--dart-define=MAP_TILE_URL=https://.../{z}/{x}/{y}.png` 로 바꿀 수 있다.
const mapTileUrl = String.fromEnvironment(
  'MAP_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

/// 지도 아래에 표시할 지도 출처.
const mapAttribution = String.fromEnvironment(
  'MAP_ATTRIBUTION',
  defaultValue: '© OpenStreetMap contributors',
);

/// 지도에 그릴 선 하나 (걷기, 버스, 지하철).
typedef RouteSegment = ({String mode, List<MapPoint> points});

/// 경로를 지도에 그릴 선으로 바꾼다.
///
/// 서버는 버스·지하철 구간의 역과 정류장 좌표만 주므로, 걷는 구간은
/// 현재 위치, 앞뒤 구간의 끝, 집을 이어서 만든다.
List<RouteSegment> routeSegments(
  LastRoute route, {
  required MapPoint? from,
  required MapPoint home,
}) {
  final segments = <RouteSegment>[];
  var cursor = from;
  for (final leg in route.legs) {
    if (leg.mode == 'walk' || leg.path.isEmpty) continue;
    final start = leg.path.first;
    if (cursor != null && cursor != start) {
      segments.add((mode: 'walk', points: [cursor, start]));
    }
    segments.add((mode: leg.mode, points: leg.path));
    cursor = leg.path.last;
  }
  if (cursor != null && cursor != home) {
    segments.add((mode: 'walk', points: [cursor, home]));
  }
  return segments;
}

/// 막차 경로를 지도로 보여주는 화면.
class RouteMapScreen extends StatelessWidget {
  const RouteMapScreen({
    super.key,
    required this.route,
    required this.from,
    required this.home,
    this.title = '이동 경로',
    this.tileUrl = mapTileUrl,
  });

  final LastRoute route;

  /// 경로를 계산할 때의 현재 위치. 모르면 null.
  final MapPoint? from;
  final MapPoint home;
  final String title;

  /// 지도 이미지 주소. 테스트에서는 null로 두어 네트워크를 쓰지 않는다.
  final String? tileUrl;

  static LatLng _latLng(MapPoint p) => LatLng(p.lat, p.lng);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = {
      'subway': scheme.primary,
      'bus': scheme.tertiary,
      'walk': scheme.outline,
    };
    final segments = routeSegments(route, from: from, home: home);
    final points = [
      ?from,
      for (final s in segments) ...s.points,
      home,
    ].map(_latLng).toList();
    final stops = [
      for (final leg in route.legs)
        if (leg.mode != 'walk' && leg.path.isNotEmpty)
          (mode: leg.mode, point: leg.path.first),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCameraFit: points.length >= 2
                    ? CameraFit.coordinates(
                        coordinates: points,
                        padding: const EdgeInsets.all(48),
                        maxZoom: 17,
                      )
                    : null,
                initialCenter: points.first,
                initialZoom: 15,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
              ),
              children: [
                if (tileUrl case final url?)
                  TileLayer(
                    urlTemplate: url,
                    userAgentPackageName: 'com.japdel.last_train',
                  ),
                PolylineLayer(
                  polylines: [
                    for (final s in segments)
                      Polyline(
                        points: s.points.map(_latLng).toList(),
                        color: colors[s.mode] ?? scheme.outline,
                        strokeWidth: s.mode == 'walk' ? 4 : 6,
                        pattern: s.mode == 'walk'
                            ? const StrokePattern.dotted()
                            : const StrokePattern.solid(),
                      ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    for (final stop in stops)
                      Marker(
                        point: _latLng(stop.point),
                        width: 28,
                        height: 28,
                        child: _MapPin(
                          icon: stop.mode == 'bus'
                              ? Icons.directions_bus
                              : Icons.subway,
                          color: colors[stop.mode] ?? scheme.primary,
                          size: 16,
                        ),
                      ),
                    if (from case final start?)
                      Marker(
                        point: _latLng(start),
                        width: 36,
                        height: 36,
                        child: _MapPin(
                          icon: Icons.my_location,
                          color: scheme.secondary,
                          semanticLabel: '현재 위치',
                        ),
                      ),
                    Marker(
                      point: _latLng(home),
                      width: 36,
                      height: 36,
                      child: _MapPin(
                        icon: Icons.home,
                        color: scheme.error,
                        semanticLabel: '집',
                      ),
                    ),
                  ],
                ),
                if (tileUrl != null)
                  const SimpleAttributionWidget(source: Text(mapAttribution)),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _Legend(color: colors['subway']!, label: '지하철'),
                  _Legend(color: colors['bus']!, label: '버스'),
                  _Legend(color: colors['walk']!, label: '걷기'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({
    required this.icon,
    required this.color,
    this.size = 20,
    this.semanticLabel,
  });

  final IconData icon;
  final Color color;
  final double size;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(
        child: Icon(
          icon,
          size: size,
          color: Colors.white,
          semanticLabel: semanticLabel,
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 20, height: 4, color: color),
        const SizedBox(width: 6),
        Text(label),
      ],
    );
  }
}
