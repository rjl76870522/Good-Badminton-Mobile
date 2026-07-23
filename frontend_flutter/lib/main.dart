import 'package:flutter/material.dart';

import 'pages/main_shell_page.dart';
import 'services/app_preferences.dart';
import 'services/notification_service.dart';
import 'services/task_notification_monitor.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppPreferences.instance.load();
  await NotificationService.instance.initialize();
  TaskNotificationMonitor.instance.start();
  runApp(const GoodBadmintonApp());
}

class GoodBadmintonApp extends StatelessWidget {
  const GoodBadmintonApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppPreferences.instance.eyeCareEnabled,
      builder: (context, eyeCareEnabled, _) {
        final colorScheme = ColorScheme.fromSeed(
          seedColor: eyeCareEnabled
              ? const Color(0xFF54705A)
              : const Color(0xFF2E7D32),
          surface: eyeCareEnabled
              ? const Color(0xFFF1F0E4)
              : const Color(0xFFF7F9F4),
        );
        final background =
            eyeCareEnabled ? const Color(0xFFF1F0E4) : const Color(0xFFF7F9F4);
        final cardColor =
            eyeCareEnabled ? const Color(0xFFF8F6E9) : Colors.white;
        return MaterialApp(
          title: 'Good-Badminton',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: colorScheme,
            scaffoldBackgroundColor: background,
            useMaterial3: true,
            appBarTheme: AppBarTheme(
              centerTitle: false,
              backgroundColor: background,
              surfaceTintColor: Colors.transparent,
            ),
            cardTheme: CardThemeData(
              elevation: 2,
              shadowColor: const Color(0x182E7D32),
              color: cardColor,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: cardColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          home: const MainShellPage(),
        );
      },
    );
  }
}
