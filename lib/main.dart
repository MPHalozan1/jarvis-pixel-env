import 'package:flutter/material.dart';
import 'backend/connections_manager.dart';
import 'backend/office_orchestrator.dart';
import 'frontend/office_workspace_ui.dart';

//**********************************************************************
// JARVIS PIXEL ENV // APPLICATION ENTRY POINT                         *
// Uses a sleek modern sans-serif UI theme for all surrounding panels  *
// while keeping the 2D Office Canvas strictly pixelated.              *
//**********************************************************************

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const JarvisV2OpenSourceApp());
}

class JarvisV2OpenSourceApp extends StatefulWidget {
  const JarvisV2OpenSourceApp({super.key});

  @override
  State<JarvisV2OpenSourceApp> createState() => _JarvisV2OpenSourceAppState();
}

class _JarvisV2OpenSourceAppState extends State<JarvisV2OpenSourceApp> {
  // True = Sleek Navy Dark Mode, False = Crisp Daylight Mode
  bool _isDarkMode = true;
  late final ConnectionsManager _connections;
  late final OfficeOrchestrator _orchestrator;

  @override
  void initState() {
    super.initState();
    _connections = ConnectionsManager();
    _orchestrator = OfficeOrchestrator(connections: _connections);
  }

  @override
  void dispose() {
    _orchestrator.dispose();
    _connections.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'jarvis-pixel-env // Sleek Control Deck & Pixel Office',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: _isDarkMode ? Brightness.dark : Brightness.light,
        colorSchemeSeed: const Color(0xFF00D2FF),
        scaffoldBackgroundColor:
            _isDarkMode ? const Color(0xFF111524) : const Color(0xFFF1F5F9),
      ),
      home: OfficeWorkspaceScreen(
        connections: _connections,
        orchestrator: _orchestrator,
        isDarkMode: _isDarkMode,
        onToggleTheme: () => setState(() => _isDarkMode = !_isDarkMode),
      ),
    );
  }
}