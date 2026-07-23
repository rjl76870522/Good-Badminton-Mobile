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
        final outlineColor =
            eyeCareEnabled ? const Color(0xFFD8D9CB) : const Color(0xFFDDE6DA);
        return MaterialApp(
          title: 'Good-Badminton',
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            colorScheme: colorScheme,
            scaffoldBackgroundColor: background,
            useMaterial3: true,
            appBarTheme: AppBarTheme(
              centerTitle: false,
              elevation: 1,
              backgroundColor: background,
              surfaceTintColor: Colors.transparent,
              titleTextStyle: TextStyle(
                color: colorScheme.onSurface,
                fontSize: 25,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
            cardTheme: CardThemeData(
              elevation: 0,
              shadowColor: const Color(0x122E7D32),
              color: cardColor,
              margin: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: outlineColor),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                side: BorderSide(color: outlineColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            inputDecorationTheme: InputDecorationTheme(
              filled: true,
              fillColor: cardColor,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: outlineColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: outlineColor),
              ),
            ),
            dividerTheme: DividerThemeData(color: outlineColor, thickness: 1),
            progressIndicatorTheme: ProgressIndicatorThemeData(
              color: colorScheme.primary,
              linearTrackColor: colorScheme.primary.withValues(alpha: 0.12),
            ),
          ),
          home: const MainShellPage(),
        );
      },
    );
  }
}
