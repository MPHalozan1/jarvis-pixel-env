import 'package:flutter/material.dart';
import 'backend/ultron_brain_router.dart';
import 'frontend/ultron_dashboard_ui.dart';
import 'frontend/ultron_hud_theme.dart';

//**************
// Vstopna točka aplikacije ULTRON *
// Skrbi za inicializacijo jedra in dinamično prilagajanje temnega/svetlega videza *
//**************
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const UltronApp());
}

// Ohranimo vzdevek za popolno združljivost z obstoječimi testi
class UltronNeuralApp extends UltronApp {
  const UltronNeuralApp({super.key});
}

class UltronApp extends StatefulWidget {
  const UltronApp({super.key});

  @override
  State<UltronApp> createState() => _UltronAppState();
}

class _UltronAppState extends State<UltronApp> {
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

  // Preklopi med temno in svetlo ULTRON temo z gladko animacijo
  void _toggleTheme() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _brain,
      builder: (context, _) {
        final themeData = UltronHudTheme.buildThemeData(
          isDark: _isDarkMode,
          accentIndex: _brain.accentPresetIndex,
          cutRadius: _brain.customCutRadius,
          orbGlowMultiplier: _brain.orbGlowMultiplier,
        );

        return MaterialApp(
          title: 'ULTRON',
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
      },
    );
  }
}