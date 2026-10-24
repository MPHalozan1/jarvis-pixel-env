import 'package:flutter/material.dart';
import 'backend/ultron_brain_router.dart';
import 'frontend/ultron_dashboard_ui.dart';
import 'frontend/ultron_hud_theme.dart';

//**************
// Vstopna točka aplikacije Ultron Neural Core *
// Skrbi za inicializacijo jedra in preklop temnega ter svetlega načina *
//**************
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UltronNeuralApp());
}

class UltronNeuralApp extends StatefulWidget {
  const UltronNeuralApp({super.key});

  @override
  State<UltronNeuralApp> createState() => _UltronNeuralAppState();
}

class _UltronNeuralAppState extends State<UltronNeuralApp> {
  late final UltronBrainRouter _brain;
  bool _isDarkMode = true;

  @override
  void initState() {
    super.initState();
    _brain = UltronBrainRouter();
    _brain.initialize();
  }

  @override
  void dispose() {
    _brain.dispose();
    super.dispose();
  }

  // Preklopi med temno in svetlo HUD temo z gladko animacijo
  void _toggleTheme() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeData = UltronHudTheme.buildThemeData(isDark: _isDarkMode);

    return MaterialApp(
      title: 'Ultron Neural Core',
      debugShowCheckedModeBanner: false,
      theme: themeData,
      themeAnimationDuration: const Duration(milliseconds: 280),
      themeAnimationCurve: Curves.easeOutCubic,
      home: UltronDashboardScreen(
        brain: _brain,
        isDarkMode: _isDarkMode,
        onToggleTheme: _toggleTheme,
      ),
    );
  }
}