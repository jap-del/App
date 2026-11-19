import 'dart:async';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../legal/consent_store.dart';
import '../logic/alert_planner.dart';
import '../models/home_place.dart';
import '../models/last_route.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/settings_store.dart';
import '../services/transit_service.dart';
import 'home_setup_screen.dart';
import 'route_map_screen.dart';
import 'settings_screen.dart';

/// 오늘의 막차 시간을 보여주는 첫 화면.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.transit,
    required this.settings,
    required this.locate,
    required this.consent,
    required this.onWithdrawn,
    this.notifications,
    this.adBanner,
  });

  final TransitService transit;
  final SettingsStore settings;
  final LocationProvider locate;
  final ConsentStore consent;

  /// 위치정보 동의를 철회한 뒤 동의 화면으로 돌아가게 한다.
  final VoidCallback onWithdrawn;

  /// 테스트에서는 null로 두어 알림을 건너뛴다.
  final NotificationService? notifications;

  /// 화면 아래에 붙는 광고. 테스트에서는 null로 두어 광고를 뺀다.
  final Widget? adBanner;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _leadOptions = [5, 10, 15, 20, 30];

  HomePlace? _home;
  LastRoute? _route;
  MapPoint? _here;
  int _leadMinutes = SettingsStore.defaultLeadMinutes;

  /// 알림 기준으로 고른 막차 종류 (저장됨).
  RoutePreference _preference = RoutePreference.latest;

  /// 지금 화면에서 보고 있는 막차 종류.
  RoutePreference _viewing = RoutePreference.latest;
  bool _loading = true;
  bool _noRoute = false;
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
    // 남은 시간 표시를 30초마다 새로 그린다.
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final home = await widget.settings.loadHome();
    final lead = await widget.settings.loadLeadMinutes();
    final preference = await widget.settings.loadRoutePreference();
    if (!mounted) return;
    setState(() {
      _home = home;
      _leadMinutes = lead;
      _preference = preference;
      _viewing = preference;
    });
    await _refresh();
  }

  Future<void> _refresh() async {
    final home = _home;
    if (home == null) {
      setState(() => _loading = false);
      return;
    }
    if (await widget.consent.isLocationPaused()) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _route = null;
        _error = '위치 사용이 일시 중지돼 있어요. 설정에서 다시 켤 수 있어요.';
      });
      await widget.notifications?.clear();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _noRoute = false;
    });
    try {
      final here = await widget.locate();
      final route = await widget.transit.lastRouteHome(
        fromLat: here.lat,
        fromLng: here.lng,
        home: home,
      );
      if (!mounted) return;
      setState(() {
        _here = (lat: here.lat, lng: here.lng);
        _route = route;
        _noRoute = route == null;
        _loading = false;
      });
      await _updateNotifications();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _updateNotifications() async {
    final notifications = widget.notifications;
    if (notifications == null) return;
    await notifications.clear();
    // 고른 종류의 막차가 끊겼거나 계산되지 않았으면 가장 늦은 막차로 알린다.
    final route = _route?.pick(_preference) ?? _route;
    if (route == null) return;
    final alertAt = planAlertTime(
      departBy: route.departBy,
      leadMinutes: _leadMinutes,
      now: DateTime.now(),
    );
    if (alertAt == null) return;
    await notifications.requestPermission();
    await notifications.showLockScreenStatus(route);
    // 예약은 미래 시각이어야 해서 몇 초 여유를 둔다.
    final earliest = DateTime.now().add(const Duration(seconds: 5));
    await notifications.scheduleDepartAlert(
      alertAt: alertAt.isAfter(earliest) ? alertAt : earliest,
      route: route,
    );
  }

  Future<void> _editHome() async {
    final result = await Navigator.of(context).push<HomePlace>(
      MaterialPageRoute(
        builder: (_) => HomeSetupScreen(locate: widget.locate, current: _home),
      ),
    );
    if (result == null) return;
    await widget.settings.saveHome(result);
    if (!mounted) return;
    setState(() => _home = result);
    await _refresh();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          consent: widget.consent,
          onWithdrawn: () async {
            await widget.notifications?.clear();
            widget.onWithdrawn();
          },
        ),
      ),
    );
    // 일시 중지 설정이 바뀌었을 수 있다.
    if (mounted && _home != null) await _refresh();
  }

  Future<void> _changePreference(RoutePreference preference) async {
    setState(() {
      _preference = preference;
      _viewing = preference;
    });
    await widget.settings.saveRoutePreference(preference);
    await _updateNotifications();
  }

  void _showMap(LastRoute route) {
    final home = _home;
    if (home == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RouteMapScreen(
          route: route,
          from: _here,
          home: (lat: home.lat, lng: home.lng),
          title: '${_viewing.label} 이동 경로',
        ),
      ),
    );
  }

  Future<void> _changeLead(int minutes) async {
    setState(() => _leadMinutes = minutes);
    await widget.settings.saveLeadMinutes(minutes);
    await _updateNotifications();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('막차 알림'),
        actions: [
          if (_home != null)
            IconButton(
              onPressed: _loading ? null : _refresh,
              icon: const Icon(Icons.refresh),
              tooltip: '새로고침',
            ),
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
            tooltip: '설정',
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildBody(context)),
            ?widget.adBanner,
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final home = _home;
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (home == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.home_outlined, size: 64),
              const SizedBox(height: 16),
              const Text('집을 설정하면 막차 시간을 알려드려요.'),
              const SizedBox(height: 24),
              FilledButton(onPressed: _editHome, child: const Text('집 설정하기')),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.home),
          title: Text(home.name),
          trailing: TextButton(onPressed: _editHome, child: const Text('변경')),
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          )
        else if (_noRoute)
          const Text('오늘은 집까지 가는 대중교통이 끝났어요.')
        else if (_route case final route?)
          ..._buildRoute(context, route),
        const SizedBox(height: 24),
        Row(
          children: [
            const Expanded(child: Text('어떤 막차로 알릴까요?')),
            DropdownButton<RoutePreference>(
              value: _preference,
              items: [
                for (final p in RoutePreference.values)
                  DropdownMenuItem(value: p, child: Text(p.label)),
              ],
              onChanged: (p) {
                if (p != null) _changePreference(p);
              },
            ),
          ],
        ),
        Row(
          children: [
            const Expanded(child: Text('출발 몇 분 전에 알릴까요?')),
            DropdownButton<int>(
              value: _leadMinutes,
              items: [
                for (final m in _leadOptions)
                  DropdownMenuItem(value: m, child: Text('$m분 전')),
              ],
              onChanged: (m) {
                if (m != null) _changeLead(m);
              },
            ),
          ],
        ),
      ],
    );
  }

  /// 종류 고르기 칩과, 고른 종류의 막차 카드.
  List<Widget> _buildRoute(BuildContext context, LastRoute route) {
    final time = DateFormat('HH:mm');
    final shown = route.pick(_viewing);
    final option = _viewing.kind == null ? null : route.option(_viewing.kind!);
    return [
      if (route.options.isNotEmpty) ...[
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final p in RoutePreference.values)
              if (p.kind == null ||
                  route.option(p.kind!)?.status != RouteStatus.none)
                ChoiceChip(
                  label: Text(_chipLabel(p, route, time)),
                  selected: _viewing == p,
                  onSelected: (_) => setState(() => _viewing = p),
                ),
          ],
        ),
        const SizedBox(height: 12),
      ],
      if (shown != null)
        _RouteCard(
          route: shown,
          onShowMap: shown.legs.any((l) => l.path.isNotEmpty)
              ? () => _showMap(shown)
              : null,
        )
      else
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(switch (option?.status) {
              RouteStatus.missed => '${_viewing.label}로 가는 막차는 끊겼어요.',
              RouteStatus.none => '${_viewing.label}로 가는 경로가 없어요.',
              _ => '${_viewing.label}로 가는 막차 시간을 계산하지 못했어요.',
            }),
          ),
        ),
    ];
  }

  static String _chipLabel(
    RoutePreference preference,
    LastRoute route,
    DateFormat time,
  ) {
    final name = switch (preference) {
      RoutePreference.latest => '가장 늦게',
      RoutePreference.subway => '지하철',
      RoutePreference.bus => '버스',
      RoutePreference.mixed => '지하철+버스',
    };
    final kind = preference.kind;
    if (kind == null) return '$name ${time.format(route.departBy)}';
    final option = route.option(kind);
    return switch (option?.status) {
      RouteStatus.ok => '$name ${time.format(option!.route!.departBy)}',
      RouteStatus.missed => '$name 끊김',
      _ => '$name 모름',
    };
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.route, this.onShowMap});

  final LastRoute route;

  /// 지도로 보기. 좌표가 없으면 null이라 버튼을 숨긴다.
  final VoidCallback? onShowMap;

  static const _icons = {
    'walk': Icons.directions_walk,
    'bus': Icons.directions_bus,
    'subway': Icons.subway,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = DateFormat('HH:mm');
    final remaining = route.departBy.difference(DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (route.isSample)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  '예시 데이터예요. 실제 막차 시간이 아닙니다.',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            Text('이 시간까지 출발하세요', style: theme.textTheme.labelLarge),
            Text(
              time.format(route.departBy),
              style: theme.textTheme.displayMedium,
            ),
            Text('남은 시간 ${formatRemaining(remaining)}'),
            const SizedBox(height: 4),
            Text('도착 예정 ${time.format(route.arriveAt)}'),
            if (route.estimated)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '버스 막차는 추정 시간이에요. 정류장 시간표도 함께 확인해 주세요.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (route.nightBus case final night?)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    const Icon(Icons.nightlight_round, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '놓쳐도 심야버스 ${night.buses.join(', ')}번으로 '
                        '${time.format(night.departBy)}까지 출발할 수 있어요',
                      ),
                    ),
                  ],
                ),
              ),
            const Divider(height: 32),
            for (final leg in route.legs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(_icons[leg.mode] ?? Icons.more_horiz, size: 20),
                    const SizedBox(width: 12),
                    Expanded(child: Text(leg.description)),
                  ],
                ),
              ),
            if (onShowMap != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton.icon(
                  onPressed: onShowMap,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('지도로 보기'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
