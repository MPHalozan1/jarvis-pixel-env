import 'package:flutter/material.dart';
import 'backend/ultron_brain_router.dart';
import 'frontend/ultron_dashboard_ui.dart';
import 'frontend/ultron_hud_theme.dart';

//**********************************************************************
// ULTRON // NEURAL CONSCIOUSNESS ENTRY POINT                          *
// Boots the local Qwen2.5-Coder-14B engine, project code learner,     *
// Git automation bridge, and interactive 3D HUD workspace.            *
//**********************************************************************

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
  // True = Deep Void Dark Mode, False = Technical Daylight Mode
  bool _isDarkMode = true;
  late final UltronBrainRouter _brain;

  @override
  void initState() {
    super.initState();
    _brain = UltronBrainRouter();
  }

  @override
  void dispose() {
    _brain.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ULTRON // LOCAL QWEN 14B & GIT STUDIO',
      debugShowCheckedModeBanner: false,
      theme: UltronHudTheme.buildThemeData(_isDarkMode),
      home: UltronDashboardScreen(
        brain: _brain,
        isDarkMode: _isDarkMode,
        onToggleTheme: () => setState(() => _isDarkMode = !_isDarkMode),
      ),
    );
  }
}