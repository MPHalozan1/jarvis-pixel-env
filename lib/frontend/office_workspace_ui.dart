import 'dart:math';
import 'package:flutter/material.dart';
import '../backend/connections_manager.dart';
import '../backend/office_orchestrator.dart';
import 'connections_window.dart';
import 'pixel_art_engine.dart';

//**********************************************************************
// JARVIS PIXEL ENV FRONT-END // WORKFLOW WIZARD & LIVE CODE GRAPH     *
// Features:                                                           *
// - Top-Right "Start New Workflow" Button & Project Source Modal      *
//   (Choose Local Folder OR Git Repo -> clones to ~/Desktop/projects) *
// - 3.1 Pro Work Plan Confirmation Banner (or auto-confirms @ Argon)  *
// - Live Bottom-Left Graph tracking +Lines Added, -Deleted & !Errors  *
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
  final TextEditingController _interceptController = TextEditingController();

  // Start New Workflow Modal State
  bool _showNewWorkflowModal = false;
  bool _workflowUseGitRepo = true; // true = Git Repo -> ~/Desktop/projects, false = Local Folder
  String _selectedLocalFolder = '';
  int _selectedRepoIndex = 0;
  final TextEditingController _customGitUrlController = TextEditingController();
  final TextEditingController _customLocalPathController =
      TextEditingController();
  final TextEditingController _workflowPromptController = TextEditingController(
    text: 'Add live system telemetry widget & refactor backend socket handler',
  );

  int _selectedAgentId = 8; // Default inspect #8 (3.1 Pro Planner)
  String _activeTopTab = 'CTRL';
  bool _showConnectionsWindow = false;
  int _connectionsInitialTab = 0;
  Size _lastViewportSize = Size.zero;

  static const Color _navyCard = Color(0xFF191E31);
  static const Color _navyBorder = Color(0xFF2E3654);
  static const Color _neonPink = Color(0xFFF43F5E);
  static const Color _neonCyan = Color(0xFF00D2FF);
  static const Color _neonPurple = Color(0xFFA855F7);

  @override
  void initState() {
    super.initState();
    final folders = widget.connections.discoverLocalFolders();
    if (folders.isNotEmpty) {
      _selectedLocalFolder = folders.first;
      _customLocalPathController.text = folders.first;
    }

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
    _interceptController.dispose();
    _customGitUrlController.dispose();
    _customLocalPathController.dispose();
    _workflowPromptController.dispose();
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

  void _openStartWorkflowModal() {
    final folders = widget.connections.discoverLocalFolders();
    setState(() {
      if (folders.isNotEmpty && _selectedLocalFolder.isEmpty) {
        _selectedLocalFolder = folders.first;
        _customLocalPathController.text = folders.first;
      }
      _showConnectionsWindow = false;
      _showNewWorkflowModal = true;
    });
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
              // 1. SLEEK TOP HEADER WITH "START NEW WORKFLOW" BUTTON
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

                        // 3.1 PRO WORK PLAN CONFIRMATION BANNER (When Director is Available)
                        if (orch.pendingWorkPlan != null &&
                            orch.stage ==
                                WorkflowStage.awaitingPlanConfirmation &&
                            orch.isDirectorAvailable)
                          Positioned(
                            top: 14,
                            left: 275,
                            right: 375,
                            child: _buildWorkPlanConfirmationBanner(orch),
                          ),

                        // MID-WORK QUESTION BANNER
                        if (orch.pendingQuestionForDirector != null &&
                            orch.isDirectorAvailable)
                          Positioned(
                            top: 14,
                            left: 275,
                            right: 375,
                            child: _buildDirectorQuestionBanner(orch),
                          ),

                        // LEFT SLEEK SIDEBAR + LIVE CODE TELEMETRY GRAPH
                        Positioned(
                          left: 14,
                          top: 14,
                          bottom: 72,
                          width: 255,
                          child: _buildLeftSleekSidebar(
                            orch,
                            panelColor,
                            borderColor,
                          ),
                        ),

                        // RIGHT SLEEK INSPECTOR
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

                        // START NEW WORKFLOW WIZARD MODAL (LOCAL FOLDER OR GIT REPO)
                        if (_showNewWorkflowModal)
                          Center(
                            child: _buildStartNewWorkflowModal(orch),
                          ),

                        // CONNECTIONS, MODELS, GITHUB & SLIDERS WINDOW
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
  // SLEEK TOP HEADER BAR WITH "START NEW WORKFLOW" BUTTON             *
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
              _showNewWorkflowModal = false;
              _connectionsInitialTab = 0;
              _showConnectionsWindow = !_showConnectionsWindow;
            }),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFF1F253D),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _neonPink),
              ),
              child: const Row(
                children: [
                  Icon(Icons.person_outline, size: 15, color: _neonPink),
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

          // Active Workspace Pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1B2035),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                const Icon(Icons.folder_open, size: 14, color: _neonCyan),
                const SizedBox(width: 6),
                Text(
                  'Project: ${orch.sshProjectPath.split('/').last}  •  Stage: ${orch.stage.name}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFCBD5E1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Prominent Top-Right "Start New Workflow" Button
          InkWell(
            onTap: _openStartWorkflowModal,
            borderRadius: BorderRadius.circular(22),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00D2FF), Color(0xFFEC4899)],
                ),
                borderRadius: BorderRadius.circular(22),
                boxShadow: [
                  BoxShadow(
                    color: _neonCyan.withValues(alpha: 0.35),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: const Row(
                children: [
                  Icon(Icons.rocket_launch, size: 15, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Start New Workflow',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  //********************************************************************
  // START NEW WORKFLOW MODAL (CHOOSE LOCAL FOLDER OR GIT REPO)        *
  //********************************************************************
  Widget _buildStartNewWorkflowModal(OfficeOrchestrator orch) {
    final conn = widget.connections;
    final localFolders = conn.discoverLocalFolders();
    final planner = orch.agents[7]; // #8 3.1 Pro
    final confirmer =
        orch.isDirectorAvailable ? 'YOU (VIP Suite)' : orch.agents[6].name;

    return Container(
      width: 680,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF171B2D).withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _neonCyan, width: 1.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.7),
            blurRadius: 36,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _neonCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.rocket_launch,
                  color: _neonCyan,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Start New Workflow',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      '1. Choose Local Folder or Git Repo (~/Desktop/projects)  ->  2. 3.1 Pro Scans & Plans  ->  3. Plan Confirmed',
                      style: TextStyle(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => setState(() => _showNewWorkflowModal = false),
                icon: const Icon(Icons.close, color: _neonPink),
              ),
            ],
          ),
          const Divider(height: 24, color: _navyBorder),

          // Step 1: Choose Project Source Toggle (Git Repo vs Local Folder)
          const Text(
            'STEP 1 // CHOOSE PROJECT SOURCE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _neonCyan,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _workflowUseGitRepo = true),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 11,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: _workflowUseGitRepo
                          ? _neonPink.withValues(alpha: 0.2)
                          : const Color(0xFF1F253D),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _workflowUseGitRepo ? _neonPink : _navyBorder,
                        width: 1.5,
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_download, size: 17, color: _neonPink),
                        SizedBox(width: 8),
                        Text(
                          'Git Repository (Clones to ~/Desktop/projects)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _workflowUseGitRepo = false),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 11,
                      horizontal: 12,
                    ),
                    decoration: BoxDecoration(
                      color: !_workflowUseGitRepo
                          ? _neonCyan.withValues(alpha: 0.2)
                          : const Color(0xFF1F253D),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: !_workflowUseGitRepo ? _neonCyan : _navyBorder,
                        width: 1.5,
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.folder_copy, size: 17, color: _neonCyan),
                        SizedBox(width: 8),
                        Text(
                          'Local Folder on PC',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Source Selection Area
          if (_workflowUseGitRepo) ...[
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('wf_repo_$_selectedRepoIndex'),
                    initialValue:
                        _selectedRepoIndex < conn.repositories.length
                            ? _selectedRepoIndex
                            : 0,
                    isExpanded: true,
                    isDense: true,
                    decoration: InputDecoration(
                      labelText:
                          'Select GitHub Repo (Target: ~/Desktop/projects/<repo>)',
                      filled: true,
                      fillColor: const Color(0xFF131726),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    items: List.generate(conn.repositories.length, (idx) {
                      final r = conn.repositories[idx];
                      return DropdownMenuItem(
                        value: idx,
                        child: Text(
                          '${r.fullName} (${r.defaultBranch})',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedRepoIndex = val);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 10),
                InkWell(
                  onTap: () => conn.connectAndFetchGithubRepos(
                    username: conn.githubUsername,
                    token: conn.githubToken,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1F253D),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _neonCyan),
                    ),
                    child: Text(
                      conn.isFetchingRepos ? 'Syncing...' : 'Refresh Repos',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _customGitUrlController,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                labelText:
                    'Or paste any Git Repo URL to clone into ~/Desktop/projects',
                hintText: 'https://github.com/MPHalozan1/jarvis-pixel-env.git',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF131726),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ] else ...[
            DropdownButtonFormField<String>(
              key: ValueKey('wf_local_$_selectedLocalFolder'),
              initialValue: localFolders.contains(_selectedLocalFolder)
                  ? _selectedLocalFolder
                  : localFolders.first,
              isExpanded: true,
              isDense: true,
              decoration: InputDecoration(
                labelText: 'Discovered Local Folders (~/Projects & ~/Desktop/projects)',
                filled: true,
                fillColor: const Color(0xFF131726),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              items: localFolders
                  .map(
                    (f) => DropdownMenuItem(
                      value: f,
                      child: Text(
                        f,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) {
                  setState(() {
                    _selectedLocalFolder = val;
                    _customLocalPathController.text = val;
                  });
                }
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _customLocalPathController,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                labelText: 'Custom Local Folder Path',
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF131726),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Step 2: Task Request for 3.1 Pro Work Planner
          Text(
            'STEP 2 // REQUEST FOR ${planner.name.toUpperCase()} (${planner.modelName})',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _neonPink,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _workflowPromptController,
            maxLines: 2,
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              hintText:
                  'Describe what you want built or fixed. 3.1 Pro will scan the files and create a Work Plan...',
              filled: true,
              fillColor: const Color(0xFF131726),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Workflow Route Preview Box
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF1F253D),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _navyBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.route, size: 16, color: _neonCyan),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pipeline: ${planner.name} scans files & builds plan  ->  Confirms plan with $confirmer  ->  #1 & #3 start coding!',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFCBD5E1),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Launch Button Row
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() => _showNewWorkflowModal = false),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 10),
              InkWell(
                onTap: () {
                  final customGit = _customGitUrlController.text.trim();
                  final chosenRepo = conn.repositories.isNotEmpty
                      ? conn.repositories[_selectedRepoIndex.clamp(
                          0,
                          conn.repositories.length - 1,
                        )]
                      : null;

                  setState(() => _showNewWorkflowModal = false);
                  orch.startNewWorkflow(
                    isGitRepo: _workflowUseGitRepo,
                    selectedRepo: customGit.isEmpty ? chosenRepo : null,
                    customGitUrl: customGit.isNotEmpty ? customGit : null,
                    localFolderPath: _customLocalPathController.text,
                    promptRequest: _workflowPromptController.text,
                  );
                },
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFEC4899), Color(0xFFE11D48)],
                    ),
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.play_arrow, size: 16, color: Colors.white),
                      SizedBox(width: 6),
                      Text(
                        'Scan Files & Create Work Plan',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  //********************************************************************
  // 3.1 PRO WORK PLAN CONFIRMATION BANNER (WHEN DIRECTOR IS AVAILABLE)*
  //********************************************************************
  Widget _buildWorkPlanConfirmationBanner(OfficeOrchestrator orch) {
    final plan = orch.pendingWorkPlan!;
    final planner = orch.agents[7]; // #8 3.1 Pro
    final argon = orch.agents[6];   // #7 Argon High

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _navyCard.withValues(alpha: 0.98),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _neonCyan, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.55),
            blurRadius: 20,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.assignment_turned_in, color: _neonCyan, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${planner.name.toUpperCase()} (${planner.modelName}) CREATED WORK PLAN // CONFIRM BEFORE CODERS START',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: _neonCyan,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Scanned ${plan.totalFilesScanned} files in ${plan.projectPath} (${plan.keyFilesFound.take(3).join(", ")})',
            style: const TextStyle(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '• Front-End (#1 ${orch.agents[0].name}): ${plan.frontendPlanForAgent1}\n'
            '• Back-End (#3 ${orch.agents[2].name}): ${plan.backendPlanForAgent3}',
            style: const TextStyle(fontSize: 11.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _neonCyan,
                  foregroundColor: Colors.black,
                ),
                onPressed: () => orch.confirmWorkPlanAndStartCoding(
                  confirmedBy: 'Director (VIP Suite)',
                ),
                icon: const Icon(Icons.check, size: 16),
                label: const Text(
                  'Confirm Plan & Start Coders',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  orch.toggleDirectorAvailability();
                  orch.confirmWorkPlanAndStartCoding(
                    confirmedBy: '${argon.name} [${argon.modelName}] (AFK Auto)',
                  );
                },
                child: Text(
                  'Go AFK -> Let ${argon.name} Confirm Plan',
                  style: const TextStyle(fontSize: 11, color: _neonPink),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  //********************************************************************
  // LEFT SLEEK SIDEBAR + LIVE CODE TELEMETRY GRAPH (+LINES/-LINES/ERR)*
  //********************************************************************
  Widget _buildLeftSleekSidebar(
    OfficeOrchestrator orch,
    Color panelColor,
    Color borderColor,
  ) {
    final conn = widget.connections;

    return Column(
      children: [
        // Top Card: Squad List
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
                  overflow: TextOverflow.ellipsis,
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

        // Bottom Card: Live Code & Error Telemetry Graph
        Container(
          height: 195,
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
                'Overall Progress & Code Graph',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              // Live Counters for +Lines Added, -Lines Deleted, and !Errors
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildMetricPill(
                    '+${conn.totalLinesAdded}',
                    'Added',
                    _neonCyan,
                  ),
                  _buildMetricPill(
                    '-${conn.totalLinesDeleted}',
                    'Deleted',
                    _neonPurple,
                  ),
                  _buildMetricPill(
                    '!${conn.totalErrorsEncountered}',
                    'Errors',
                    _neonPink,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SizedBox(
                  width: double.infinity,
                  child: CustomPaint(
                    painter: LiveCodeTelemetryChartPainter(
                      addedSeries: conn.addedLinesHistory,
                      deletedSeries: conn.deletedLinesHistory,
                      errorSeries: conn.errorsHistory,
                      addedColor: _neonCyan,
                      deletedColor: _neonPurple,
                      errorColor: _neonPink,
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

  Widget _buildMetricPill(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(fontSize: 9, color: Color(0xFF94A3B8)),
          ),
        ],
      ),
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
                  _showNewWorkflowModal = false;
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
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
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
              _showNewWorkflowModal = false;
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
              _showNewWorkflowModal = false;
              _connectionsInitialTab = 3;
              _showConnectionsWindow = true;
            }),
          ),
          const SizedBox(width: 8),
          _neonDockButton(
            icon: orch.isDirectorAvailable ? Icons.person : Icons.auto_mode,
            label: orch.isDirectorAvailable ? 'Available' : 'AFK (Argon Plan)',
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
            icon: Icons.rocket_launch,
            label: 'Start New Workflow',
            filledColor: _neonCyan,
            onTap: _openStartWorkflowModal,
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
// LIVE CODE TELEMETRY CHART PAINTER (+ADDED, -DELETED, !ERRORS)       *
//**********************************************************************
class LiveCodeTelemetryChartPainter extends CustomPainter {
  final List<double> addedSeries;
  final List<double> deletedSeries;
  final List<double> errorSeries;
  final Color addedColor;
  final Color deletedColor;
  final Color errorColor;

  LiveCodeTelemetryChartPainter({
    required this.addedSeries,
    required this.deletedSeries,
    required this.errorSeries,
    required this.addedColor,
    required this.deletedColor,
    required this.errorColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawSeries(canvas, size, addedSeries, addedColor, fillArea: true);
    _drawSeries(canvas, size, deletedSeries, deletedColor, fillArea: false);
    _drawSeries(canvas, size, errorSeries, errorColor, fillArea: false);
  }

  void _drawSeries(
    Canvas canvas,
    Size size,
    List<double> pts,
    Color color, {
    required bool fillArea,
  }) {
    if (pts.length < 2) return;

    final path = Path();
    final fillPath = Path();
    final stepX = size.width / (pts.length - 1);

    for (int i = 0; i < pts.length; i++) {
      final x = i * stepX;
      final y = size.height - (pts[i].clamp(0.0, 1.0) * (size.height - 8));
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }

    if (fillArea) {
      fillPath.lineTo(size.width, size.height);
      fillPath.close();
      final grad = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.38),
          color.withValues(alpha: 0.02),
        ],
      );
      canvas.drawPath(
        fillPath,
        Paint()..shader = grad.createShader(Offset.zero & size),
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = fillArea ? 2.2 : 1.6,
    );

    // Draw vertex dot on latest point
    final lastX = (pts.length - 1) * stepX;
    final lastY = size.height - (pts.last.clamp(0.0, 1.0) * (size.height - 8));
    canvas.drawCircle(Offset(lastX, lastY), 3.0, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant LiveCodeTelemetryChartPainter oldDelegate) =>
      true;
}