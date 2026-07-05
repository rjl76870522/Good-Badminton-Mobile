import 'package:flutter/material.dart';

import 'pages/main_shell_page.dart';

void main() {
  runApp(const GoodBadmintonApp());
}

class GoodBadmintonApp extends StatelessWidget {
  const GoodBadmintonApp({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF2E7D32),
    );
    return MaterialApp(
      title: 'Good-Badminton',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: const Color(0xFFF7F9F4),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Color(0xFFF7F9F4),
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shadowColor: const Color(0x182E7D32),
          color: Colors.white,
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
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
      home: const MainShellPage(),
    );
  }
}
