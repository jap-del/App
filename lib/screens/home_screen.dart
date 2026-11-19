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
  int _leadMinutes = SettingsStore.defaultLeadMinutes;
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
    if (!mounted) return;
    setState(() {
      _home = home;
      _leadMinutes = lead;
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
    final route = _route;
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
        else if (_route != null)
          _RouteCard(route: _route!),
        const SizedBox(height: 24),
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
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.route});

  final LastRoute route;

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
          ],
        ),
      ),
    );
  }
}
