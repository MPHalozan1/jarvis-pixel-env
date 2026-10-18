import 'dart:math';
import 'package:flutter/material.dart';
import '../backend/connections_manager.dart';
import '../backend/office_orchestrator.dart';
import 'connections_window.dart';
import 'pixel_art_engine.dart';

//**********************************************************************
// JARVIS_V2 FRONT-END // MAIN WORKSPACE UI                            *
// Hosts the 16-bit Pixel Office, Inspector, and opens the             *
// Connections, Model Mapper & GitHub Desktop Cloner Window.           *
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

  int _selectedAgentId = 1;
  String _activeTopTab = 'CTRL';
  String _stateFilter = 'All';
  bool _activeOnly = false;
  bool _showConnectionsWindow = false;
  Size _lastViewportSize = Size.zero;

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
    super.dispose();
  }

  void _centerOfficeInViewport(Size viewport) {
    if (viewport.isEmpty) return;
    final scaleX = (viewport.width - 540) / OfficeOrchestrator.mapSize.width;
    final scaleY = (viewport.height - 90) / OfficeOrchestrator.mapSize.height;
    final scale = min(scaleX, scaleY).clamp(0.60, 1.15);

    final dx =
        (viewport.width - OfficeOrchestrator.mapSize.width * scale) / 2 - 40;
    final dy =
        (viewport.height - OfficeOrchestrator.mapSize.height * scale) / 2 - 10;

    _cameraController.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDarkMode;
    final bgColor = isDark ? const Color(0xFF080A0F) : const Color(0xFFE2E8F0);
    final panelColor = isDark
        ? const Color(0xFF12151F).withValues(alpha: 0.95)
        : const Color(0xFFFFFFFF).withValues(alpha: 0.95);
    final borderColor =
        isDark ? const Color(0xFF262B3D) : const Color(0xFFCBD5E1);

    return ListenableBuilder(
      listenable: Listenable.merge([widget.orchestrator, widget.connections]),
      builder: (context, _) {
        final orch = widget.orchestrator;
        final selectedAgent = orch.agents.firstWhere(
          (a) => a.id == _selectedAgentId,
          orElse: () => orch.agents.first,
        );

        return Scaffold(
          backgroundColor: bgColor,
          body: Column(
            children: [
              // 1. TOP BAR WITH CONNECTIONS & GITHUB BUTTON
              _buildTopBar(orch, isDark, borderColor),

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
                        // 16-BIT PIXEL OFFICE CANVAS
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
                                builder: (context, _) {
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

                        // TOP TAB DRAWER
                        if (_activeTopTab != 'CTRL')
                          Positioned(
                            top: 14,
                            left: 265,
                            right: 360,
                            height: 255,
                            child: _buildTopTabDrawer(
                              orch,
                              panelColor,
                              borderColor,
                            ),
                          ),

                        // QUESTION BANNER WHEN AGENT VISITS YOUR VIP OFFICE
                        if (orch.pendingQuestionForDirector != null &&
                            orch.isDirectorAvailable)
                          Positioned(
                            top: 14,
                            left: 265,
                            right: 360,
                            child: _buildDirectorQuestionBanner(orch, isDark),
                          ),

                        // LEFT GROUPS PANEL
                        Positioned(
                          left: 12,
                          top: 12,
                          width: 245,
                          child: _buildLeftGroupsPanel(
                            orch,
                            panelColor,
                            borderColor,
                          ),
                        ),

                        // RIGHT AGENT INSPECTOR
                        Positioned(
                          right: 12,
                          top: 12,
                          bottom: 66,
                          width: 340,
                          child: _buildRightInspector(
                            orch,
                            selectedAgent,
                            isDark,
                            panelColor,
                            borderColor,
                          ),
                        ),

                        // CONNECTIONS, MODEL MAPPER & GITHUB CLONER WINDOW
                        if (_showConnectionsWindow)
                          Center(
                            child: ConnectionsManagementWindow(
                              connections: widget.connections,
                              isDarkMode: isDark,
                              onClose: () => setState(
                                () => _showConnectionsWindow = false,
                              ),
                            ),
                          ),

                        // BOTTOM FLOATING DOCK
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _buildBottomDock(
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

              // 3. BOTTOM STATUS BAR
              _buildBottomStatusBar(orch, isDark, borderColor),
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

  Widget _buildTopBar(
    OfficeOrchestrator orch,
    bool isDark,
    Color borderColor,
  ) {
    final tabs = [
      ('CTRL', ' Pixel Map'),
      ('TERMINAL', ' (${orch.globalTerminalLogs.length})'),
      ('PROBLEMS', ' (${orch.problemsList.length})'),
      ('GITLENS', ' (${orch.gitCommitHistory.length})'),
      ('TOKENS', ' (CFO)'),
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D0F17) : const Color(0xFFF1F5F9),
        border: Border(bottom: BorderSide(color: borderColor)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                ...tabs.map((t) {
                  final isSel = _activeTopTab == t.$1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: InkWell(
                      onTap: () => setState(() => _activeTopTab = t.$1),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isSel
                              ? const Color(0xFF2563EB).withValues(alpha: 0.2)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                            color: isSel
                                ? const Color(0xFF38BDF8)
                                : Colors.transparent,
                          ),
                        ),
                        child: Text(
                          '${t.$1}${t.$2}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                isSel ? FontWeight.bold : FontWeight.normal,
                            color: isSel
                                ? const Color(0xFF38BDF8)
                                : (isDark ? Colors.white70 : Colors.black87),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(width: 6),
                // Prominent Button to Open Connections, Model Mapper & GitHub Cloner
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0D9488),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: () => setState(
                    () => _showConnectionsWindow = !_showConnectionsWindow,
                  ),
                  icon: const Icon(Icons.hub, size: 14),
                  label: const Text(
                    'Connections, Models & GitHub',
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 250,
                  height: 28,
                  child: TextField(
                    controller: _taskInputController,
                    onSubmitted: (v) {
                      orch.dispatchMission(v);
                      _taskInputController.clear();
                    },
                    style: const TextStyle(fontSize: 11),
                    decoration: InputDecoration(
                      hintText: 'Assign task to active repo...',
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                      ),
                      filled: true,
                      fillColor: isDark
                          ? const Color(0xFF171A26)
                          : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(5),
                        borderSide: BorderSide(color: borderColor),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    minimumSize: const Size(0, 28),
                  ),
                  onPressed: () {
                    orch.dispatchMission(_taskInputController.text);
                    _taskInputController.clear();
                  },
                  icon: const Icon(Icons.play_arrow, size: 14),
                  label: const Text(
                    'Dispatch',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          // Active Cloned Workspace & Role Summary Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_open, size: 13, color: Color(0xFF22C55E)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Desktop Workspace: ${orch.sshProjectPath} (${orch.activeGitBranch})  |  Final: ${orch.agents[6].name} [${orch.agents[6].modelName}]  |  AFK: ${orch.agents[7].name} [${orch.agents[7].modelName}]',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: orch.toggleDirectorAvailability,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: orch.isDirectorAvailable
                          ? const Color(0xFF22C55E).withValues(alpha: 0.2)
                          : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: orch.isDirectorAvailable
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFF59E0B),
                      ),
                    ),
                    child: Text(
                      orch.isDirectorAvailable
                          ? 'YOU: AVAILABLE'
                          : 'YOU: AFK (-> ${orch.agents[7].name})',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: orch.isDirectorAvailable
                            ? const Color(0xFF22C55E)
                            : const Color(0xFFF59E0B),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftGroupsPanel(
    OfficeOrchestrator orch,
    Color panelColor,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Configured Office Groups',
            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          _buildGroupSection(
            'Reviewers & CFO (Top Wing)',
            const Color(0xFF38BDF8),
            orch.agents.where((a) => a.group == 'reviewers').toList(),
          ),
          const SizedBox(height: 8),
          _buildGroupSection(
            'Coding & Critic Squad (4)',
            const Color(0xFF10B981),
            orch.agents.where((a) => a.group == 'dev-squad').toList(),
          ),
          const SizedBox(height: 8),
          _buildGroupSection(
            'Overflow & Git Bot',
            const Color(0xFFA855F7),
            orch.agents.where((a) => a.group == 'git-ops').toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSection(
    String title,
    Color color,
    List<OfficeAgent> list,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, color: color),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ...list.map((a) {
          final isSel = a.id == _selectedAgentId;
          return InkWell(
            onTap: () => setState(() => _selectedAgentId = a.id),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2.5, horizontal: 4),
              child: Row(
                children: [
                  Text(
                    '#${a.id}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: a.badgeColor,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      a.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            isSel ? FontWeight.bold : FontWeight.normal,
                        color: isSel ? const Color(0xFF38BDF8) : null,
                      ),
                    ),
                  ),
                  Text(
                    a.providerName,
                    style: TextStyle(fontSize: 8.5, color: a.badgeColor),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildRightInspector(
    OfficeOrchestrator orch,
    OfficeAgent selected,
    bool isDark,
    Color panelColor,
    Color borderColor,
  ) {
    final filteredAgents = orch.agents.where((a) {
      if (_activeOnly && a.state != AgentState.active) return false;
      if (_stateFilter == 'Att') return a.state == AgentState.attention;
      if (_stateFilter == 'Act') return a.state == AgentState.active;
      if (_stateFilter == 'Idl') return a.state == AgentState.idle;
      if (_stateFilter == 'Don') return a.state == AgentState.done;
      if (_stateFilter == 'Slp') return a.state == AgentState.sleeping;
      return true;
    }).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'v Agents (${filteredAgents.length}/${orch.agents.length})',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Switch(
                value: _activeOnly,
                onChanged: (v) => setState(() => _activeOnly = v),
              ),
              const Text('Active only', style: TextStyle(fontSize: 10)),
            ],
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _buildFilterChip('All', const Color(0xFF94A3B8)),
              _buildFilterChip('Att', const Color(0xFFF59E0B)),
              _buildFilterChip('Act', const Color(0xFF22C55E)),
              _buildFilterChip('Idl', const Color(0xFF64748B)),
              _buildFilterChip('Don', const Color(0xFF38BDF8)),
              _buildFilterChip('Slp', const Color(0xFFA855F7)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 26,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: filteredAgents.length,
              itemBuilder: (_, i) {
                final a = filteredAgents[i];
                final isSel = a.id == selected.id;
                return Padding(
                  padding: const EdgeInsets.only(right: 5),
                  child: InkWell(
                    onTap: () => setState(() => _selectedAgentId = a.id),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSel
                            ? a.badgeColor.withValues(alpha: 0.28)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: a.badgeColor),
                      ),
                      child: Text(
                        '#${a.id} ${a.name}',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1A1E2E)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(6),
              border: Border(
                left: BorderSide(color: selected.badgeColor, width: 3),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#${selected.id} ${selected.name} — ${selected.role}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Provider: ${selected.providerName}  •  Model: ${selected.modelName}',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: selected.tokenRatio,
                  minHeight: 5,
                  valueColor: AlwaysStoppedAnimation(selected.badgeColor),
                ),
                const SizedBox(height: 3),
                Text(
                  'Tokens: ${selected.tokensUsed} / ${selected.tokenLimit} (~\$${selected.costUsd})',
                  style: const TextStyle(fontSize: 9.5),
                ),
              ],
            ),
          ),
          const Divider(height: 14),
          Text(
            'Live Stream (${selected.logs.length})',
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF22C55E),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              itemCount: selected.logs.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  selected.logs[i],
                  style: const TextStyle(fontSize: 10, height: 1.35),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, Color color) {
    final isSel = _stateFilter == label;
    return InkWell(
      onTap: () => setState(() => _stateFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isSel ? 0.3 : 0.08),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: color.withValues(alpha: isSel ? 1.0 : 0.35),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _buildTopTabDrawer(
    OfficeOrchestrator orch,
    Color panelColor,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF38BDF8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$_activeTopTab // ${orch.sshProjectPath}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF38BDF8),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () => setState(() => _activeTopTab = 'CTRL'),
                child: const Text('Close (X)', style: TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const Divider(height: 10),
          Expanded(
            child: _activeTopTab == 'TERMINAL'
                ? ListView.builder(
                    itemCount: orch.globalTerminalLogs.length,
                    itemBuilder: (_, i) => Text(
                      orch.globalTerminalLogs[i],
                      style: const TextStyle(fontSize: 10.5, height: 1.4),
                    ),
                  )
                : _activeTopTab == 'PROBLEMS'
                    ? (orch.problemsList.isEmpty
                        ? const Center(
                            child: Text(
                              '0 Problems detected in workspace.',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF22C55E),
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: orch.problemsList.length,
                            itemBuilder: (_, i) => Text(
                              orch.problemsList[i],
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFFEF4444),
                              ),
                            ),
                          ))
                    : _activeTopTab == 'GITLENS'
                        ? ListView.builder(
                            itemCount: orch.gitCommitHistory.length,
                            itemBuilder: (_, i) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text(
                                '• ${orch.gitCommitHistory[i]}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFC084FC),
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: orch.agents.length,
                            itemBuilder: (_, i) {
                              final a = orch.agents[i];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 165,
                                      child: Text(
                                        '#${a.id} ${a.name} (${a.modelName})',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 10.5),
                                      ),
                                    ),
                                    Expanded(
                                      child: LinearProgressIndicator(
                                        value: a.tokenRatio,
                                        minHeight: 7,
                                        valueColor: AlwaysStoppedAnimation(
                                          a.badgeColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      '${a.tokensUsed}/${a.tokenLimit} (\$${a.costUsd})',
                                      style: const TextStyle(fontSize: 10),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildDirectorQuestionBanner(OfficeOrchestrator orch, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171B29) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF22D3EE), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'AGENT IN YOUR SHINY VIP OFFICE // QUESTION FOR DIRECTOR',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFF22D3EE),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            orch.pendingQuestionForDirector ?? '',
            style: const TextStyle(fontSize: 11.5),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton(
                onPressed: () =>
                    orch.resolveDirectorQuestion('Option 1: Async Stream'),
                child: const Text(
                  '1. Async Stream',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () =>
                    orch.resolveDirectorQuestion('Option 2: Local Cache'),
                child: const Text(
                  '2. Local Cache',
                  style: TextStyle(fontSize: 11),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  orch.toggleDirectorAvailability();
                  orch.resolveDirectorQuestion(
                    'Delegated to Offline Reviewer (${orch.agents[7].name})',
                  );
                },
                child: Text(
                  'Go AFK -> Send to ${orch.agents[7].name}',
                  style: const TextStyle(fontSize: 10.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomDock(
    OfficeOrchestrator orch,
    Size viewport,
    Color panelColor,
    Color borderColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _dockBtn(
            icon: Icons.hub,
            color: const Color(0xFF38BDF8),
            label: 'Connections & Git',
            onTap: () => setState(
              () => _showConnectionsWindow = !_showConnectionsWindow,
            ),
          ),
          _dockBtn(
            icon: orch.isDirectorAvailable ? Icons.person : Icons.cloud_sync,
            color: orch.isDirectorAvailable
                ? const Color(0xFF22C55E)
                : const Color(0xFFF59E0B),
            label: orch.isDirectorAvailable
                ? 'Available'
                : 'AFK (${orch.agents[7].name})',
            onTap: orch.toggleDirectorAvailability,
          ),
          _dockBtn(
            icon: Icons.bolt,
            color: const Color(0xFFA855F7),
            label: orch.simulateTokenExhaustion
                ? 'Overflow Sim: ON'
                : 'Overflow Sim: OFF',
            onTap: () => setState(
              () => orch.simulateTokenExhaustion =
                  !orch.simulateTokenExhaustion,
            ),
          ),
          _dockBtn(
            icon: Icons.call_split,
            color: const Color(0xFF818CF8),
            label: 'Git Commit',
            onTap: orch.triggerManualGitCommit,
          ),
          _dockBtn(
            icon: Icons.center_focus_strong,
            label: 'Center Map',
            onTap: () => _centerOfficeInViewport(viewport),
          ),
          _dockBtn(
            icon: widget.isDarkMode ? Icons.dark_mode : Icons.light_mode,
            label: widget.isDarkMode ? 'Dark' : 'Light',
            onTap: widget.onToggleTheme,
          ),
          _dockBtn(
            icon: Icons.play_arrow,
            color: const Color(0xFF22C55E),
            label: 'Run Workflow',
            onTap: () => orch.dispatchMission(
              'Build feature in ${orch.sshProjectPath}',
            ),
          ),
        ],
      ),
    );
  }

  Widget _dockBtn({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(height: 3),
            Text(label, style: const TextStyle(fontSize: 9.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomStatusBar(
    OfficeOrchestrator orch,
    bool isDark,
    Color borderColor,
  ) {
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF07080C) : const Color(0xFFCBD5E1),
        border: Border(top: BorderSide(color: borderColor)),
      ),
      child: Row(
        children: [
          Text(
            'Stage: ${orch.stage.name.toUpperCase()}',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Color(0xFF38BDF8),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              widget.connections.statusMessage,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 10),
            ),
          ),
          const Text(
            'Open-Source Provider-Agnostic Engine',
            style: TextStyle(fontSize: 10, color: Color(0xFF22C55E)),
          ),
        ],
      ),
    );
  }
}