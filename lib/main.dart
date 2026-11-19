import 'package:material_ui/material_ui.dart';

import 'legal/consent_store.dart';
import 'screens/consent_screen.dart';
import 'screens/home_screen.dart';
import 'services/ads.dart';
import 'services/location_service.dart';
import 'services/notification_service.dart';
import 'services/settings_store.dart';
import 'services/transit_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notifications = NotificationService();
  await notifications.init();
  await initAds();
  runApp(
    LastTrainApp(
      home: AppGate(
        consent: ConsentStore(),
        homeBuilder: (consent, onWithdrawn) => HomeScreen(
          transit: createTransitService(),
          settings: SettingsStore(),
          locate: deviceLocation,
          consent: consent,
          onWithdrawn: onWithdrawn,
          notifications: notifications,
          adBanner: const AdBanner(),
        ),
      ),
    ),
  );
}

class LastTrainApp extends StatelessWidget {
  const LastTrainApp({super.key, required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '막차 알림',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      home: home,
    );
  }
}

/// 필수 동의가 없으면 동의 화면을, 있으면 첫 화면을 보여준다.
class AppGate extends StatefulWidget {
  const AppGate({super.key, required this.consent, required this.homeBuilder});

  final ConsentStore consent;
  final Widget Function(ConsentStore consent, VoidCallback onWithdrawn)
  homeBuilder;

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  bool? _agreed;

  @override
  void initState() {
    super.initState();
    widget.consent.hasValidConsent().then((v) {
      if (mounted) setState(() => _agreed = v);
    });
  }

  void _onWithdrawn() {
    // 설정 화면 위에 쌓인 화면을 닫고 동의 화면으로 돌아간다.
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() => _agreed = false);
  }

  @override
  Widget build(BuildContext context) {
    final agreed = _agreed;
    if (agreed == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!agreed) {
      return ConsentScreen(
        store: widget.consent,
        onAgreed: () => setState(() => _agreed = true),
      );
    }
    return widget.homeBuilder(widget.consent, _onWithdrawn);
  }
}
