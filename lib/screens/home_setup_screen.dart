import 'package:material_ui/material_ui.dart';

import '../models/home_place.dart';
import '../services/location_service.dart';

/// 집 위치를 설정하는 화면.
///
/// 지금은 현재 위치를 집으로 저장한다. 주소 검색은 서버가 준비되면 추가한다.
class HomeSetupScreen extends StatefulWidget {
  const HomeSetupScreen({super.key, required this.locate, this.current});

  final LocationProvider locate;
  final HomePlace? current;

  @override
  State<HomeSetupScreen> createState() => _HomeSetupScreenState();
}

class _HomeSetupScreenState extends State<HomeSetupScreen> {
  late final _nameController = TextEditingController(
    text: widget.current?.name ?? '우리 집',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final here = await widget.locate();
      if (!mounted) return;
      final name = _nameController.text.trim();
      Navigator.of(context).pop(
        HomePlace(
          name: name.isEmpty ? '우리 집' : name,
          lat: here.lat,
          lng: here.lng,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('집 설정')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '이름',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text('집에 있을 때 아래 버튼을 누르면 지금 위치가 집으로 저장돼요.'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _useCurrentLocation,
              icon: const Icon(Icons.my_location),
              label: Text(_busy ? '위치 확인 중' : '현재 위치를 집으로 설정'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
