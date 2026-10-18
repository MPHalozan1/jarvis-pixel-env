import 'package:flutter/material.dart';
import 'backend/connections_manager.dart';
import 'backend/office_orchestrator.dart';
import 'frontend/office_workspace_ui.dart';

//**********************************************************************
// JARVIS_V2 (OPEN SOURCE) // APPLICATION ENTRY POINT                  *
// Initializes the Backend ConnectionsManager and OfficeOrchestrator.  *
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
  // True = Obsidian Dark Mode, False = Studio Daylight Mode
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
      title: 'jarvis_v2 // Open-Source Multi-Agent Pixel Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: _isDarkMode ? Brightness.dark : Brightness.light,
        fontFamily: 'monospace',
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