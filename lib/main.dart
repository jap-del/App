import 'package:material_ui/material_ui.dart';

import 'screens/home_screen.dart';
import 'services/location_service.dart';
import 'services/notification_service.dart';
import 'services/settings_store.dart';
import 'services/transit_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notifications = NotificationService();
  await notifications.init();
  runApp(
    LastTrainApp(
      home: HomeScreen(
        transit: createTransitService(),
        settings: SettingsStore(),
        locate: deviceLocation,
        notifications: notifications,
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
