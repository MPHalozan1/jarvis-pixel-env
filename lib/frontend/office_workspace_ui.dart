import 'dart:math';
import 'package:flutter/material.dart';
import '../backend/connections_manager.dart';
import '../backend/office_orchestrator.dart';
import 'connections_window.dart';
import 'pixel_art_engine.dart';

//**********************************************************************
// JARVIS PIXEL ENV FRONT-END // SLEEK CONTROL DECK + PIXEL OFFICE     *
// Surrounding UI styled after the Neon Pink & Cyan Control Deck:      *
// - Sleek Navy Cards (#181C2E), Pill Buttons, Sparkline Telemetry     *
// - Center Canvas remains a crisp 16-bit 2D RPG Pixel Office          *
//**********************************************************************

class OfficeWorkspaceScreen extends StatefulWidget {
  final ConnectionsManager connections;
  final OfficeOrchestrator orchestrator;
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  const OfficeWorkspaceScreen({
    super.key,
    required this.connections,
    required this.orchestrator,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  @override
  State<OfficeWorkspaceScreen> createState() => _OfficeWorkspaceScreenState();
}

class _OfficeWorkspaceScreenState extends State<OfficeWorkspaceScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loopController;
  final TransformationController _cameraController = TransformationController();
  final TextEditingController _taskInputController = TextEditingController();
  final TextEditingController _interceptController = TextEditingController();

  int _selectedAgentId = 1;
  String _activeTopTab = 'CTRL';
  bool _showConnectionsWindow = false;
  int _connectionsInitialTab = 0;
  Size _lastViewportSize = Size.zero;

  static const Color _navyCard = Color(0xFF191E31);
  static const Color _navyBorder = Color(0xFF2E3654);
  static const Color _neonPink = Color(0xFFF43F5E);
  static const Color _neonCyan = Color(0xFF00D2FF);

  @override
  void initState() {
    super.initState();
    _loopController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )
      ..addListener(() {
        widget.orchestrator.tickMovement();
      })
      ..repeat();
  }

  @override
  void dispose() {
    _loopController.dispose();
    _cameraController.dispose();
    _taskInputController.dispose();
    _interceptController.dispose();
    super.dispose();
  }

  void _centerOfficeInViewport(Size viewport) {
    if (viewport.isEmpty) return;
    final scaleX = (viewport.width - 570) / OfficeOrchestrator.mapSize.width;
    final scaleY = (viewport.height - 95) / OfficeOrchestrator.mapSize.height;
    final scale = min(scaleX, scaleY).clamp(0.58, 1.12);

    final dx =
        (viewport.width - OfficeOrchestrator.mapSize.width * scale) / 2 - 42;
    final dy =
        (viewport.height - OfficeOrchestrator.mapSize.height * scale) / 2 - 12;

    _cameraController.value = Matrix4.identity()
      ..translateByDouble(dx, dy, 0.0, 1.0)
      ..scaleByDouble(scale, scale, 1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkMode;
    final bgColor = isDark ? const Color(0xFF101322) : const Color(0xFFE2E8F0);
    final panelColor = isDark
        ? _navyCard.withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: 0.95);
    final borderColor = isDark ? _navyBorder : const Color(0xFFCBD5E1);

    return ListenableBuilder(
      listenable: Listenable.merge([widget.orchestrator, widget.connections]),
      builder: (context, child) {
        final orch = widget.orchestrator;
        final selectedAgent = orch.agents.firstWhere(
          (a) => a.id == _selectedAgentId,
          orElse: () => orch.agents.first,
        );

        return Scaffold(
          backgroundColor: bgColor,
          body: Column(
            children: [
              // 1. SLEEK TOP NAVIGATION & DISPATCH DECK
              _buildSleekTopHeader(orch, isDark, borderColor),

              // 2. MAIN WORKSPACE
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final vpSize = Size(
                      constraints.maxWidth,
                      constraints.maxHeight,
                    );
                    if (_lastViewportSize != vpSize) {
                      _lastViewportSize = vpSize;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _centerOfficeInViewport(vpSize);
                      });
                    }

                    return Stack(
                      children: [
                        // CENTER 16-BIT PIXEL ART OFFICE CANVAS
                        Positioned.fill(
                          child: InteractiveViewer(
                            transformationController: _cameraController,
                            constrained: false,
                            boundaryMargin: const EdgeInsets.all(800),
                            minScale: 0.45,
                            maxScale: 2.5,
                            child: GestureDetector(
                              onTapDown: (d) =>
                                  _onMapClicked(d.localPosition, orch),
                              child: AnimatedBuilder(
                                animation: _loopController,
                                builder: (context, child) {
                                  return CustomPaint(
                                    size: OfficeOrchestrator.mapSize,
                                    painter: UltraDetailedPixelOfficePainter(
                                      agents: orch.agents,
                                      selectedAgentId: _selectedAgentId,
                                      isDarkMode: isDark,
                                      animTick: _loopController.value,
                                      isDirectorAvailable:
                                          orch.isDirectorAvailable,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),

                        // TOP TAB OVERLAY DRAWER
                        if (_activeTopTab != 'CTRL')
                          Positioned(
                            top: 14,
                            left: 275,
                            right: 375,
                            height: 270,
                            child: _buildTopTabDrawer(
                              orch,
                              panelColor,
                              borderColor,
                            ),
                          ),

                        // VIP QUESTION BANNER
                        if (orch.pendingQuestionForDirector != null &&
                            orch.isDirectorAvailable)
                          Positioned(
                            top: 14,
                            left: 275,
                            right: 375,
                            child: _buildDirectorQuestionBanner(orch),
                          ),

                        // LEFT SLEEK SQUAD HIERARCHY & OVERALL PROGRESS CARD
                        Positioned(
                          left: 14,
                          top: 14,
                          bottom: 72,
                          width: 250,
                          child: _buildLeftSleekSidebar(
                            orch,
                            panelColor,
                            borderColor,
                          ),
                        ),

                        // RIGHT SLEEK INSPECTOR + SEGMENTED LED METERS
                        Positioned(
                          right: 14,
                          top: 14,
                          bottom: 72,
                          width: 355,
                          child: _buildRightSleekInspector(
                            orch,
                            selectedAgent,
                            panelColor,
                            borderColor,
                          ),
                        ),

                        // SLEEK CONNECTIONS, MODELS, GITHUB & SLIDERS WINDOW
                        if (_showConnectionsWindow)
                          Center(
                            child: ConnectionsManagementWindow(
                              connections: widget.connections,
                              isDarkMode: isDark,
                              initialTab: _connectionsInitialTab,
                              onClose: () => setState(
                                () => _showConnectionsWindow = false,
                              ),
                            ),
                          ),

                        // BOTTOM NEON ICON DOCK
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildBottomNeonDock(
                              orch,
                              vpSize,
                              panelColor,
                              borderColor,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onMapClicked(Offset pos, OfficeOrchestrator orch) {
    for (final a in orch.agents) {
      if ((a.currentPos - pos).distance <= 32) {
        setState(() => _selectedAgentId = a.id);
        return;
      }
    }
  }

  //********************************************************************
  // SLEEK TOP HEADER BAR                                              *
  //********************************************************************
  Widget _buildSleekTopHeader(
    OfficeOrchestrator orch,
    bool isDark,
    Color borderColor,
  ) {
    final tabs = [
      ('01', 'CTRL'),
      ('02', 'TERMINAL'),
      ('03', 'PROBLEMS'),
      ('04', 'GITLENS'),
      ('05', 'LEARNING'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141828) : Colors.white,
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          ...tabs.map((t) {
            final isSel = _activeTopTab == t.$2;
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: InkWell(
                onTap: () => setState(() => _activeTopTab = t.$2),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSel
                        ? _neonCyan.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSel ? _neonCyan : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: isSel ? _neonPink : const Color(0xFF262D47),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          t.$1,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        t.$2,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight:
                              isSel ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),

          // Sleek "Websites & GitHub Login" Button
          InkWell(
            onTap: () => setState(() {
              _connectionsInitialTab = 0;
              _showConnectionsWindow = !_showConnectionsWindow;
            }),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFEC4899), Color(0xFFE11D48)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                children: [
                  Icon(Icons.person_outline, size: 15, color: Colors.white),
                  SizedBox(width: 6),
                  Text(
                    'Websites & GitHub Login',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const Spacer(),

          // Task Input Field
          SizedBox(
            width: 240,
            height: 34,
            child: TextField(
              controller: _taskInputController,
              onSubmitted: (v) {
                orch.dispatchMission(v);
                _taskInputController.clear();
              },
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Dispatch task to 3.8 Flash...',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF1B2035)
                    : const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(color: borderColor),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),

          // Cyan Pill "Dispatch" Button
          InkWell(
            onTap: () {
              orch.dispatchMission(_taskInputController.text);
              _taskInputController.clear();
            },
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00D2FF), Color(0xFF0284C7)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Dispatch',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  //********************************************************************
  // LEFT SLEEK SIDEBAR: SQUAD MENU + OVERALL PROGRESS SPARKLINE CARD  *
  //********************************************************************
  Widget _buildLeftSleekSidebar(
    OfficeOrchestrator orch,
    Color panelColor,
    Color borderColor,
  ) {
    return Column(
      children: [
        // Top Card: Squad List with Glowing Highlight Bars
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: panelColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI Website Squads',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  orch.sshProjectPath.split('/').last,
                  style: const TextStyle(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: ListView.builder(
                    itemCount: orch.agents.length,
                    itemBuilder: (context, i) {
                      final a = orch.agents[i];
                      final isSel = a.id == _selectedAgentId;
                      final isPink = a.id % 2 == 0;
                      final highlight = isPink ? _neonPink : _neonCyan;

                      return InkWell(
                        onTap: () => setState(() => _selectedAgentId = a.id),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            gradient: isSel
                                ? LinearGradient(
                                    colors: [
                                      highlight.withValues(alpha: 0.25),
                                      Colors.transparent,
                                    ],
                                  )
                                : null,
                            borderRadius: BorderRadius.circular(8),
                            border: Border(
                              left: BorderSide(
                                color: isSel ? highlight : Colors.transparent,
                                width: 3,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                '0${a.id}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w800,
                                  color: highlight,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  a.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSel
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSel
                                        ? highlight
                                        : const Color(0xFFCBD5E1),
                                  ),
                                ),
                              ),
                              Text(
                                a.modelName.split(' ').first,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Bottom Card: "Overall Progress" Sparkline Card
        Container(
          height: 175,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: panelColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Overall Progress',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              const Text(
                'Gemini Web & Jules Telemetry',
                style: TextStyle(
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${widget.connections.totalOperationsCount}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.change_history,
                    size: 12,
                    color: _neonPink,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '+${widget.connections.learnedRules.length}.87',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: CustomPaint(
                    painter: SparklineAreaChartPainter(
                      points: widget.connections.progressHistory,
                      lineColor: _neonCyan,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  //********************************************************************
  // RIGHT SLEEK INSPECTOR + SEGMENTED LED METERS                      *
  //********************************************************************
  Widget _buildRightSleekInspector(
    OfficeOrchestrator orch,
    OfficeAgent selected,
    Color panelColor,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected.name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${selected.role} • ${selected.modelName}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () => setState(() {
                  _connectionsInitialTab = 1;
                  _showConnectionsWindow = true;
                }),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00D2FF), Color(0xFF0284C7)],
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Text(
                    'Choose Model',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Segmented Neon Progress Bars
          Row(
            children: [
              Expanded(
                child: _buildSegmentedNeonBar(
                  label: 'Web Quota',
                  ratio: selected.tokenRatio,
                  color: _neonCyan,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSegmentedNeonBar(
                  label: 'Strictness',
                  ratio: widget.connections.critiqueStrictness,
                  color: _neonPink,
                ),
              ),
            ],
          ),
          const Divider(height: 22),

          const Text(
            'Live Activity Stream',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: _neonCyan,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: selected.logs.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  selected.logs[i],
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: Color(0xFFCBD5E1),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Live Intercept & Teach Input
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 34,
                  child: TextField(
                    controller: _interceptController,
                    style: const TextStyle(fontSize: 11.5),
                    onSubmitted: (v) {
                      orch.injectInstructionAndLearn(selected.id, v);
                      _interceptController.clear();
                    },
                    decoration: InputDecoration(
                      hintText: 'Teach / intercept ${selected.name}...',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      filled: true,
                      fillColor: const Color(0xFF131726),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(color: borderColor),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  orch.injectInstructionAndLearn(
                    selected.id,
                    _interceptController.text,
                  );
                  _interceptController.clear();
                },
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEC4899), Color(0xFFE11D48)],
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text(
                    'Teach',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedNeonBar({
    required String label,
    required double ratio,
    required Color color,
  }) {
    const segments = 10;
    final activeSegs = (ratio * segments).round();

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF131726),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
              ),
              Text(
                '${(ratio * 100).round()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: List.generate(segments, (index) {
              final isLit = index < activeSegs;
              return Expanded(
                child: Container(
                  height: 6,
                  margin: const EdgeInsets.only(right: 2.5),
                  decoration: BoxDecoration(
                    color: isLit ? color : const Color(0xFF252C47),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  //********************************************************************
  // TOP TAB DRAWER, VIP QUESTION CARD & SLEEK BOTTOM NEON DOCK        *
  //********************************************************************
  Widget _buildTopTabDrawer(
    OfficeOrchestrator orch,
    Color panelColor,
    Color borderColor,
  ) {
    final rules = widget.connections.learnedRules;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _neonCyan),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$_activeTopTab // ${orch.sshProjectPath}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: _neonCyan,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _activeTopTab = 'CTRL'),
                child: const Text('Close'),
              ),
            ],
          ),
          const Divider(),
          Expanded(
            child: _activeTopTab == 'TERMINAL'
                ? ListView.builder(
                    itemCount: orch.globalTerminalLogs.length,
                    itemBuilder: (context, i) => Text(
                      orch.globalTerminalLogs[i],
                      style: const TextStyle(fontSize: 11, height: 1.4),
                    ),
                  )
                : _activeTopTab == 'PROBLEMS'
                    ? (orch.problemsList.isEmpty
                        ? const Center(
                            child: Text(
                              '0 Problems detected by 3.8 Flash (High) & Argon (High).',
                              style: TextStyle(color: _neonCyan),
                            ),
                          )
                        : ListView.builder(
                            itemCount: orch.problemsList.length,
                            itemBuilder: (context, i) => Text(
                              orch.problemsList[i],
                              style: const TextStyle(color: _neonPink),
                            ),
                          ))
                    : _activeTopTab == 'GITLENS'
                        ? ListView.builder(
                            itemCount: orch.gitCommitHistory.length,
                            itemBuilder: (context, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text('• ${orch.gitCommitHistory[i]}'),
                            ),
                          )
                        : ListView.builder(
                            itemCount: rules.length,
                            itemBuilder: (context, i) {
                              final r = rules[i];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  '[${r.category}] ${r.ruleText} (${r.learnedFrom})',
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectorQuestionBanner(OfficeOrchestrator orch) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _navyCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _neonPink, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            '3.8 FLASH (MID) IN YOUR VIP OFFICE // DECISION + AUTO-LEARN',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: _neonPink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            orch.pendingQuestionForDirector ?? '',
            style: const TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton(
                onPressed: () =>
                    orch.resolveDirectorQuestion('Atomic Local JSON Cache'),
                child: const Text('1. Local JSON (Learn)'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () =>
                    orch.resolveDirectorQuestion('SQLite WAL Database'),
                child: const Text('2. SQLite DB (Learn)'),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  orch.toggleDirectorAvailability();
                  orch.resolveDirectorQuestion(
                    'Delegated to 3.1 Pro (Mid / Srednja raven)',
                    learnedSource: '3.1 Pro (Mid / Srednja raven)',
                  );
                },
                child: const Text('Go AFK -> Send to 3.1 Pro Mid'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNeonDock(
    OfficeOrchestrator orch,
    Size viewport,
    Color panelColor,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _neonDockButton(
            icon: Icons.public,
            label: 'Web Login',
            filledColor: _neonPink,
            onTap: () => setState(() {
              _connectionsInitialTab = 0;
              _showConnectionsWindow = true;
            }),
          ),
          const SizedBox(width: 8),
          _neonDockButton(
            icon: Icons.tune,
            label: 'Sliders & Learn',
            filledColor: _neonCyan,
            onTap: () => setState(() {
              _connectionsInitialTab = 3;
              _showConnectionsWindow = true;
            }),
          ),
          const SizedBox(width: 8),
          _neonDockButton(
            icon: orch.isDirectorAvailable ? Icons.person : Icons.auto_mode,
            label: orch.isDirectorAvailable ? 'Available' : 'AFK (3.1 Mid)',
            outlineColor: _neonCyan,
            onTap: orch.toggleDirectorAvailability,
          ),
          const SizedBox(width: 8),
          _neonDockButton(
            icon: Icons.bolt,
            label: orch.simulateTokenExhaustion
                ? 'Jules Quota: ON'
                : 'Jules Quota: OFF',
            outlineColor: _neonPink,
            onTap: () => setState(
              () => orch.simulateTokenExhaustion =
                  !orch.simulateTokenExhaustion,
            ),
          ),
          const SizedBox(width: 8),
          _neonDockButton(
            icon: Icons.center_focus_strong,
            label: 'Center Office',
            outlineColor: _neonCyan,
            onTap: () => _centerOfficeInViewport(viewport),
          ),
          const SizedBox(width: 8),
          _neonDockButton(
            icon: Icons.play_arrow,
            label: 'Run Workflow',
            filledColor: _neonCyan,
            onTap: () => orch.dispatchMission(
              'Build feature in ${orch.sshProjectPath}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _neonDockButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? filledColor,
    Color? outlineColor,
  }) {
    final isFilled = filledColor != null;
    final c = filledColor ?? outlineColor ?? _neonCyan;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isFilled ? c : const Color(0xFF141828),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c, width: 1.3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isFilled ? Colors.white : c,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: isFilled ? Colors.white : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

//**********************************************************************
// SPARKLINE AREA CHART PAINTER                                        *
//**********************************************************************
class SparklineAreaChartPainter extends CustomPainter {
  final List<double> points;
  final Color lineColor;

  SparklineAreaChartPainter({required this.points, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final path = Path();
    final fillPath = Path();
    final stepX = size.width / (points.length - 1);

    for (int i = 0; i < points.length; i++) {
      final x = i * stepX;
      final y = size.height - (points[i].clamp(0.0, 1.0) * (size.height - 10));
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    final grad = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        lineColor.withValues(alpha: 0.45),
        lineColor.withValues(alpha: 0.02),
      ],
    );
    canvas.drawPath(
      fillPath,
      Paint()..shader = grad.createShader(Offset.zero & size),
    );

    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );

    for (int i = 0; i < points.length; i++) {
      final x = i * stepX;
      final y = size.height - (points[i].clamp(0.0, 1.0) * (size.height - 10));
      canvas.drawCircle(Offset(x, y), 3.2, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant SparklineAreaChartPainter oldDelegate) => true;
}