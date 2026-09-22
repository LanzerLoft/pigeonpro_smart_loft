import 'package:flutter/material.dart';
import 'screens/main_navigation_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PigeonProApp());
}

class PigeonProApp extends StatelessWidget {
  const PigeonProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PigeonPro Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF1E293B),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF1E293B),
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          actionTextColor: const Color(0xFF38BDF8),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: Color(0xFF334155), width: 1.0),
          ),
        ),
        useMaterial3: true,
        fontFamilyFallback: const ['Roboto', 'sans-serif', 'Segoe UI'],
      ),
      home: const MainNavigationScreen(),
    );
  }
}
