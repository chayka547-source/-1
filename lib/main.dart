import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'ui/home_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Фоновое воспроизведение и управление из шторки уведомлений.
  try {
    await JustAudioBackground.init(
      androidNotificationChannelId: 'com.volna.volna.audio',
      androidNotificationChannelName: 'Воспроизведение',
      androidNotificationOngoing: true,
    );
  } catch (e) {
    debugPrint('JustAudioBackground.init: $e');
  }

  final state = AppState();
  await state.init();

  // Android 13+: без этого разрешения не будет плеера в шторке уведомлений.
  try {
    await Permission.notification.request();
  } catch (_) {}

  runApp(ChangeNotifierProvider<AppState>.value(
    value: state,
    child: const VolnaApp(),
  ));
}

class VolnaApp extends StatelessWidget {
  const VolnaApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Тёмный фон задаём через colorScheme.surface: AppBar и фон экрана совпадают,
    // и не нужны AppBarTheme/CardTheme, которые Flutter меняет от версии к версии.
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF3D6E),
      brightness: Brightness.dark,
    ).copyWith(surface: const Color(0xFF0B0B0B));
    return MaterialApp(
      title: 'Волна',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: messengerKey,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: const Color(0xFF0B0B0B),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF121212),
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: const HomeShell(),
    );
  }
}
