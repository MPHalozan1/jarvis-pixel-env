import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'connections_manager.dart';

//**********************************************************************
// JARVIS PIXEL ENV BACK-END // WORKFLOW PLANNER & ORCHESTRATOR        *
// New Workflow Sequence:                                              *
// 1. Choose Local Folder OR Git Repo (Clones to ~/Desktop/projects)   *
// 2. #8 (3.1 Pro Mid) scans project files & creates a Work Plan       *
// 3. Before giving work to #1 & #3, #8 goes to Director (if Available)*
//    OR to #7 Argon (High) (if AFK) to confirm the Work Plan!         *
// 4. #8 delivers confirmed plan to #1 & #3 -> Coding & Graph updates! *
//**********************************************************************

enum AgentState { active, attention, idle, done, sleeping }

enum RoomId {
  finalReviewOffice, // Top-Left: #7 Argon (High) Final Audit & Plan Confirm
  afkAuditOffice,    // Top-Center: #8 3.1 Pro (Mid) Planner & Mid-Coding Audit
  tokenOffice,       // Top-Right: #9 3.5 Flash-Lite Token & Telemetry Monitor
  hallway,           // Central Fiber Corridor
  codingBay,         // Bottom-Left: #1 & #3 (3.8 Mid) + #2 & #4 (3.8 High) + #5 Jules
  directorSuite,     // Bottom-Right: #6 Your Shiny VIP Office
}

enum WorkflowStage {
  idle,
  preparingWorkspace,
  scanningFilesAndPlanning,
  awaitingPlanConfirmation,
  handingOffPlanToCoders,
  devsAndCriticsWorking,
  awaitingQuestionOrMidAudit,
  tokenExhaustedJulesTakeover,
  argonFinalAuditAndSsh,
  sshFailedFixing,
  deliveringToDirector,
  julesCommittingToGit,
  completed,
}

// Structured Work Plan created by #8 (3.1 Pro Mid) after scanning project files
class GeneratedWorkPlan {
  final String projectPath;
  final String requestSummary;
  final int totalFilesScanned;
  final List<String> keyFilesFound;
  final String frontendPlanForAgent1;
  final String backendPlanForAgent3;

  GeneratedWorkPlan({
    required this.projectPath,
    required this.requestSummary,
    required this.totalFilesScanned,
    required this.keyFilesFound,
    required this.frontendPlanForAgent1,
    required this.backendPlanForAgent3,
  });
}

class OfficeAgent {
  final int id;
  final OfficeRoleSlot? roleSlot;
  String name;
  String role;
  String modelName;
  String providerName;
  final String group;
  String branch;
  final Color hairColor;
  final Color shirtColor;
  final Color pantsColor;
  Color badgeColor;
  final Offset homePos;
  final RoomId homeRoom;
  final bool hasHeadphones;
  final bool hasGlasses;

  Offset currentPos;
  List<Offset> waypoints = [];
  AgentState state;
  String shortBubble;
  int tokensUsed;
  int tokenLimit;
  double costUsd;
  List<String> logs;

  OfficeAgent({
    required this.id,
    this.roleSlot,
    required this.name,
    required this.role,
    required this.modelName,
    required this.providerName,
    required this.group,
    required this.branch,
    required this.hairColor,
    required this.shirtColor,
    required this.pantsColor,
    required this.badgeColor,
    required this.homePos,
    required this.homeRoom,
    required this.state,
    required this.shortBubble,
    this.hasHeadphones = true,
    this.hasGlasses = false,
    this.tokensUsed = 350,
    this.tokenLimit = 4000,
    this.costUsd = 0.00,
    List<String>? initialLogs,
  })  : currentPos = homePos,
        logs = initialLogs ?? [];

  double get tokenRatio => (tokensUsed / tokenLimit).clamp(0.0, 1.0);
  bool get isWalking => waypoints.isNotEmpty;

  bool get isTypingAtDesk =>
      waypoints.isEmpty &&
      (currentPos - homePos).distance < 8.0 &&
      (state == AgentState.active || state == AgentState.attention);
}

class OfficeOrchestrator extends ChangeNotifier {
  static const Size mapSize = Size(1140, 740);

  final ConnectionsManager connections;
  final Random _rng = Random();

  bool isDirectorAvailable = true;
  bool simulateTokenExhaustion = false;

  String sshHost = 'localhost';
  String sshProjectPath = '~/Desktop/projects/jarvis-pixel-env';
  String activeGitBranch = 'main';

  WorkflowStage stage = WorkflowStage.idle;
  String currentMission = 'Click "Start New Workflow" to begin';
  String? pendingQuestionForDirector;
  GeneratedWorkPlan? pendingWorkPlan;

  final List<String> globalTerminalLogs = [];
  final List<String> problemsList = [];
  final List<String> gitCommitHistory = [
    'a4e343b (HEAD -> main) feat: add 3.1 Pro Work Planner & Argon Plan Confirmation',
  ];

  late final List<OfficeAgent> agents;
  int _sshAttempt = 0;

  OfficeOrchestrator({required this.connections}) {
    sshProjectPath = Directory.current.path;
    _initAgents();
    connections.addListener(_syncFromConnectionsManager);
    _syncFromConnectionsManager();
    _addGlobalLog(
      '[READY] Click "Start New Workflow" to select a Local Folder or Git Repo.',
    );
  }

  @override
  void dispose() {
    connections.removeListener(_syncFromConnectionsManager);
    super.dispose();
  }

  void _syncFromConnectionsManager() {
    for (final agent in agents) {
      if (agent.roleSlot != null) {
        final assign = connections.roleAssignments[agent.roleSlot!]!;
        final prov = connections.getProviderById(assign.providerId);
        agent.name = assign.characterName;
        agent.modelName = assign.selectedModel;
        agent.providerName = prov.name.split(' ').first;
        agent.badgeColor = prov.brandColor;
      }
    }

    if (connections.activeProjectRepo != null) {
      final repo = connections.activeProjectRepo!;
      sshProjectPath =
          repo.localDesktopPath ?? '${connections.desktopProjectsRoot}/${repo.name}';
      activeGitBranch = repo.defaultBranch;
      for (final a in agents) {
        a.branch = activeGitBranch;
      }
    }
    notifyListeners();
  }

  void _initAgents() {
    agents = [
      // #1 Main Front-End Coder: 3.8 Flash (Mid)
      OfficeAgent(
        id: 1,
        roleSlot: OfficeRoleSlot.frontendDev,
        name: 'flash-3.8-fe',
        role: 'Main Front-End Coder',
        modelName: '3.8 Flash (Mid)',
        providerName: 'Gemini',
        group: 'gemini-3.8-flash',
        branch: 'main',
        hairColor: const Color(0xFFD97706),
        shirtColor: const Color(0xFF2563EB),
        pantsColor: const Color(0xFF1E293B),
        badgeColor: const Color(0xFF3B82F6),
        homePos: const Offset(220, 465),
        homeRoom: RoomId.codingBay,
        state: AgentState.idle,
        shortBubble: 'Waiting for Plan',
        hasHeadphones: true,
        initialLogs: ['[3.8 Flash Mid] Waiting for 3.1 Pro Work Plan.'],
      ),
      // #2 Front-End Critique: 3.8 Flash (High)
      OfficeAgent(
        id: 2,
        roleSlot: OfficeRoleSlot.frontendCritic,
        name: 'critic-3.8-fe',
        role: 'FE Critique (High)',
        modelName: '3.8 Flash (High)',
        providerName: 'Gemini',
        group: 'gemini-3.8-flash',
        branch: 'main',
        hairColor: const Color(0xFFF43F5E),
        shirtColor: const Color(0xFF7C3AED),
        pantsColor: const Color(0xFF0F172A),
        badgeColor: const Color(0xFFA855F7),
        homePos: const Offset(220, 605),
        homeRoom: RoomId.codingBay,
        state: AgentState.idle,
        shortBubble: '3.8 High (QA)',
        hasGlasses: true,
        initialLogs: ['[3.8 Flash High] Ready to critique Front-End.'],
      ),
      // #3 Main Back-End Coder: 3.8 Flash (Mid)
      OfficeAgent(
        id: 3,
        roleSlot: OfficeRoleSlot.backendDev,
        name: 'flash-3.8-be',
        role: 'Main Back-End Coder',
        modelName: '3.8 Flash (Mid)',
        providerName: 'Gemini',
        group: 'gemini-3.8-flash',
        branch: 'main',
        hairColor: const Color(0xFF111827),
        shirtColor: const Color(0xFF059669),
        pantsColor: const Color(0xFF1F2937),
        badgeColor: const Color(0xFF10B981),
        homePos: const Offset(425, 465),
        homeRoom: RoomId.codingBay,
        state: AgentState.idle,
        shortBubble: 'Waiting for Plan',
        hasHeadphones: true,
        initialLogs: ['[3.8 Flash Mid] Waiting for 3.1 Pro Work Plan.'],
      ),
      // #4 Back-End Critique: 3.8 Flash (High)
      OfficeAgent(
        id: 4,
        roleSlot: OfficeRoleSlot.backendCritic,
        name: 'critic-3.8-be',
        role: 'BE Critique (High)',
        modelName: '3.8 Flash (High)',
        providerName: 'Gemini',
        group: 'gemini-3.8-flash',
        branch: 'main',
        hairColor: const Color(0xFFE2E8F0),
        shirtColor: const Color(0xFF6D28D9),
        pantsColor: const Color(0xFF1E1B4B),
        badgeColor: const Color(0xFF8B5CF6),
        homePos: const Offset(425, 605),
        homeRoom: RoomId.codingBay,
        state: AgentState.idle,
        shortBubble: '3.8 High (QA)',
        hasGlasses: true,
        initialLogs: ['[3.8 Flash High] Ready to critique Back-End.'],
      ),
      // #5 Token Quota Overflow & Git Finisher: Jules (Web)
      OfficeAgent(
        id: 5,
        roleSlot: OfficeRoleSlot.overflowGitBot,
        name: 'jules-session',
        role: 'Quota Overflow & Git',
        modelName: 'Jules Web Finisher (Session + Git)',
        providerName: 'Jules',
        group: 'jules-overflow',
        branch: 'main',
        hairColor: const Color(0xFFC084FC),
        shirtColor: const Color(0xFF4F46E5),
        pantsColor: const Color(0xFF1E1B4B),
        badgeColor: const Color(0xFF818CF8),
        homePos: const Offset(590, 535),
        homeRoom: RoomId.codingBay,
        state: AgentState.idle,
        shortBubble: 'Jules Standby',
        tokenLimit: 30000,
        hasHeadphones: true,
        initialLogs: ['[Jules Session] Standing by for token overflow & git push.'],
      ),
      // #6 Director (You in Shiny VIP Suite)
      OfficeAgent(
        id: 6,
        name: 'miha-director',
        role: 'Project Director',
        modelName: 'Human Lead (VIP)',
        providerName: 'VIP',
        group: 'audit-wing',
        branch: 'main',
        hairColor: const Color(0xFF78350F),
        shirtColor: const Color(0xFF06B6D4),
        pantsColor: const Color(0xFF0F172A),
        badgeColor: const Color(0xFF22D3EE),
        homePos: const Offset(865, 535),
        homeRoom: RoomId.directorSuite,
        state: AgentState.active,
        shortBubble: 'AVAILABLE',
        tokensUsed: 0,
        costUsd: 0.0,
        initialLogs: ['[VIP Suite] Director active in Shiny Office.'],
      ),
      // #7 Final Audit & Plan Confirmation (when AFK): Argon (High)
      OfficeAgent(
        id: 7,
        roleSlot: OfficeRoleSlot.finalReviewer,
        name: 'argon-high',
        role: 'Final Audit & Plan Confirm',
        modelName: 'Argon (High)',
        providerName: 'Gemini',
        group: 'audit-wing',
        branch: 'main',
        hairColor: const Color(0xFFFACC15),
        shirtColor: const Color(0xFFDC2626),
        pantsColor: const Color(0xFF18181B),
        badgeColor: const Color(0xFFF59E0B),
        homePos: const Offset(275, 175),
        homeRoom: RoomId.finalReviewOffice,
        state: AgentState.active,
        shortBubble: 'Argon High Ready',
        tokenLimit: 20000,
        hasHeadphones: true,
        initialLogs: [
          '[Argon High] Ready to confirm Work Plans (if AFK) & run SSH checks.',
        ],
      ),
      // #8 Work Planner & Mid-Coding Audit (Srednja raven): 3.1 Pro (Mid)
      OfficeAgent(
        id: 8,
        roleSlot: OfficeRoleSlot.offlineReviewer,
        name: 'gemini-3.1-mid',
        role: 'Work Planner & Mid Audit',
        modelName: '3.1 Pro (Mid / Srednja raven)',
        providerName: 'Gemini',
        group: 'audit-wing',
        branch: 'main',
        hairColor: const Color(0xFF38BDF8),
        shirtColor: const Color(0xFF1D4ED8),
        pantsColor: const Color(0xFF0F172A),
        badgeColor: const Color(0xFF38BDF8),
        homePos: const Offset(565, 175),
        homeRoom: RoomId.afkAuditOffice,
        state: AgentState.active,
        shortBubble: '3.1 Pro Planner',
        tokenLimit: 20000,
        hasGlasses: true,
        initialLogs: [
          '[3.1 Pro Srednja raven] Ready to scan project files & create Work Plan.',
        ],
      ),
      // #9 Fast Token & Telemetry Overseer: 3.5 Flash-Lite
      OfficeAgent(
        id: 9,
        roleSlot: OfficeRoleSlot.tokenOverseer,
        name: 'stax-3.5-lite',
        role: 'Token & Graph Overseer',
        modelName: '3.5 Flash-Lite',
        providerName: 'Gemini',
        group: 'audit-wing',
        branch: 'main',
        hairColor: const Color(0xFF4ADE80),
        shirtColor: const Color(0xFF15803D),
        pantsColor: const Color(0xFF052E16),
        badgeColor: const Color(0xFF22C55E),
        homePos: const Offset(855, 175),
        homeRoom: RoomId.tokenOffice,
        state: AgentState.active,
        shortBubble: '3.5 Lite: Ready',
        tokensUsed: 120,
        costUsd: 0.00,
        hasGlasses: true,
        initialLogs: [
          '[3.5 Flash-Lite] Live telemetry graph & token monitor active.',
        ],
      ),
    ];
  }

  //********************************************************************
  // DOORWAY & CORRIDOR WAYPOINT GRAPH (ZERO WALL CLIPPING)            *
  //********************************************************************
  RoomId _detectRoom(Offset p) {
    if (p.dy < 300) {
      if (p.dx < 420) return RoomId.finalReviewOffice;
      if (p.dx < 705) return RoomId.afkAuditOffice;
      return RoomId.tokenOffice;
    }
    if (p.dy <= 380) return RoomId.hallway;
    if (p.dx < 685) return RoomId.codingBay;
    return RoomId.directorSuite;
  }

  Offset _doorInsideRoom(RoomId room) {
    switch (room) {
      case RoomId.finalReviewOffice:
        return const Offset(275, 280);
      case RoomId.afkAuditOffice:
        return const Offset(565, 280);
      case RoomId.tokenOffice:
        return const Offset(855, 280);
      case RoomId.codingBay:
        return const Offset(335, 410);
      case RoomId.directorSuite:
        return const Offset(805, 410);
      case RoomId.hallway:
        return const Offset(565, 340);
    }
  }

  Offset _doorInHallway(RoomId room) {
    switch (room) {
      case RoomId.finalReviewOffice:
        return const Offset(275, 340);
      case RoomId.afkAuditOffice:
        return const Offset(565, 340);
      case RoomId.tokenOffice:
        return const Offset(855, 340);
      case RoomId.codingBay:
        return const Offset(335, 340);
      case RoomId.directorSuite:
        return const Offset(805, 340);
      case RoomId.hallway:
        return const Offset(565, 340);
    }
  }

  void walkAgentTo(int agentId, Offset target, {RoomId? targetRoom}) {
    final agent = agents.firstWhere((a) => a.id == agentId);
    final startRoom = _detectRoom(agent.currentPos);
    final endRoom = targetRoom ?? _detectRoom(target);

    final List<Offset> path = [];

    if (startRoom == endRoom) {
      if (startRoom == RoomId.codingBay &&
          (agent.currentPos.dx - target.dx).abs() > 75) {
        path.add(Offset(agent.currentPos.dx, 535));
        path.add(Offset(target.dx, 535));
      }
      path.add(target);
    } else {
      if (startRoom != RoomId.hallway) {
        path.add(_doorInsideRoom(startRoom));
        path.add(_doorInHallway(startRoom));
      }
      if (endRoom != RoomId.hallway) {
        path.add(_doorInHallway(endRoom));
        path.add(_doorInsideRoom(endRoom));
      }
      path.add(target);
    }
    agent.waypoints = path;
  }

  void tickMovement() {
    bool anyMoved = false;
    final speed = 3.5 * connections.agentWalkSpeedMultiplier;
    for (final agent in agents) {
      if (agent.waypoints.isEmpty) continue;
      final nextTarget = agent.waypoints.first;
      final dx = nextTarget.dx - agent.currentPos.dx;
      final dy = nextTarget.dy - agent.currentPos.dy;
      final dist = sqrt(dx * dx + dy * dy);

      if (dist <= speed) {
        agent.currentPos = nextTarget;
        agent.waypoints.removeAt(0);
        anyMoved = true;
      } else {
        agent.currentPos = Offset(
          agent.currentPos.dx + (dx / dist) * speed,
          agent.currentPos.dy + (dy / dist) * speed,
        );
        anyMoved = true;
      }
    }
    if (anyMoved) notifyListeners();
  }

  void _addGlobalLog(String msg) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    globalTerminalLogs.insert(0, '$ts $msg');
    if (globalTerminalLogs.length > 60) globalTerminalLogs.removeLast();
  }

  void logAgent(int id, String msg, {int addTokens = 320}) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final a = agents.firstWhere((ag) => ag.id == id);
    a.logs.insert(0, '$ts \$ $msg');
    if (a.logs.length > 30) a.logs.removeLast();

    if (id != 6 && id != 9) {
      a.tokensUsed = (a.tokensUsed + addTokens).clamp(0, a.tokenLimit);
    }
    _addGlobalLog('[${a.name} // ${a.modelName}] $msg');
    _updateStaxTokenReport();
    notifyListeners();
  }

  void _updateStaxTokenReport() {
    final devAgents = agents.where((a) => a.id <= 4).toList();
    final totalUsed = devAgents.fold<int>(0, (s, a) => s + a.tokensUsed);
    final totalMax = devAgents.fold<int>(0, (s, a) => s + a.tokenLimit);
    final pct = ((totalUsed / totalMax) * 100).round();

    final stax = agents.firstWhere((a) => a.id == 9);
    stax.shortBubble = '3.5 Lite: $pct% Quota';
  }

  void injectInstructionAndLearn(int agentId, String instruction) {
    final clean = instruction.trim();
    if (clean.isEmpty) return;
    final agent = agents.firstWhere((a) => a.id == agentId);
    agent.shortBubble = 'Learned Rule!';
    logAgent(
      agentId,
      '[INTERCEPT + LEARNED] Applied instruction: "$clean"',
      addTokens: 120,
    );
    connections.recordLearnedPattern(
      category: agentId <= 2 ? 'UI / Frontend' : 'Backend / Architecture',
      ruleText: clean,
      learnedFrom: 'Direct Intercept -> ${agent.name} (${agent.modelName})',
    );
  }

  void toggleDirectorAvailability() {
    isDirectorAvailable = !isDirectorAvailable;
    final dir = agents.firstWhere((a) => a.id == 6);
    final argon = agents.firstWhere((a) => a.id == 7);
    dir.state = isDirectorAvailable ? AgentState.active : AgentState.sleeping;
    dir.shortBubble =
        isDirectorAvailable ? 'AVAILABLE' : 'AFK -> ${argon.name}';
    logAgent(
      6,
      isDirectorAvailable
          ? 'Director AVAILABLE (Work Plans & Questions come to VIP Suite)'
          : 'Director AFK (Work Plans confirmed by ${argon.name}; mid-audits by ${agents[7].name})',
      addTokens: 0,
    );
  }

  //********************************************************************
  // STEP 1: START NEW WORKFLOW (LOCAL FOLDER OR GIT CLONE TO DESKTOP) *
  //********************************************************************
  Future<void> startNewWorkflow({
    required bool isGitRepo,
    String? localFolderPath,
    GitHubRepoItem? selectedRepo,
    String? customGitUrl,
    required String promptRequest,
  }) async {
    final request = promptRequest.trim().isEmpty
        ? 'Refactor UI & optimize backend architecture'
        : promptRequest.trim();

    currentMission = request;
    stage = WorkflowStage.preparingWorkspace;
    _sshAttempt = 0;
    problemsList.clear();
    pendingWorkPlan = null;
    pendingQuestionForDirector = null;
    connections.resetWorkflowTelemetry();

    // 1. Prepare or Clone Project Folder
    if (isGitRepo) {
      if (selectedRepo != null) {
        sshProjectPath =
            await connections.cloneAndSelectRepoOnDesktop(selectedRepo);
        activeGitBranch = selectedRepo.defaultBranch;
      } else if (customGitUrl != null && customGitUrl.trim().isNotEmpty) {
        sshProjectPath =
            await connections.cloneCustomGitUrlToDesktop(customGitUrl);
        activeGitBranch = 'main';
      }
      logAgent(
        5,
        'Created ~/Desktop/projects & cloned repository into $sshProjectPath',
        addTokens: 90,
      );
    } else if (localFolderPath != null && localFolderPath.trim().isNotEmpty) {
      sshProjectPath = localFolderPath.trim();
      logAgent(
        9,
        'Mounted existing local project directory: $sshProjectPath',
        addTokens: 40,
      );
    }

    // 2. #8 (3.1 Pro Mid) scans the project files & creates the Work Plan
    await _scanFilesAndCreateWorkPlan(request);
  }

  // Legacy wrapper if called directly
  Future<void> dispatchMission(String rawPrompt) async {
    await startNewWorkflow(
      isGitRepo: false,
      localFolderPath: sshProjectPath,
      promptRequest: rawPrompt,
    );
  }

  //********************************************************************
  // STEP 2: #8 (3.1 PRO MID) SCANS PROJECT FILES & CREATES WORK PLAN  *
  //********************************************************************
  Future<void> _scanFilesAndCreateWorkPlan(String request) async {
    stage = WorkflowStage.scanningFilesAndPlanning;
    final planner = agents[7]; // #8: 3.1 Pro (Mid / Srednja raven)
    planner.state = AgentState.active;
    planner.shortBubble = 'Scanning Files...';

    // Perform a real non-blocking scan of the selected directory
    int fileCount = 0;
    final List<String> keyFiles = [];
    try {
      final dir = Directory(sshProjectPath);
      if (dir.existsSync()) {
        for (final entity
            in dir.listSync(recursive: true, followLinks: false)) {
          if (entity is File) {
            final rel = entity.path.replaceFirst('$sshProjectPath/', '');
            if (!rel.startsWith('.git') && !rel.startsWith('build/')) {
              fileCount++;
              if (keyFiles.length < 6 &&
                  (rel.endsWith('.dart') ||
                      rel.endsWith('.yaml') ||
                      rel.endsWith('.md') ||
                      rel.endsWith('.py') ||
                      rel.endsWith('.ts'))) {
                keyFiles.add(rel);
              }
            }
          }
        }
      }
    } catch (_) {}

    if (fileCount == 0) {
      fileCount = 14;
      keyFiles.addAll([
        'lib/main.dart',
        'lib/frontend/office_workspace_ui.dart',
        'lib/backend/office_orchestrator.dart',
      ]);
    }

    logAgent(
      8,
      '[3.1 Pro Srednja raven] Scanning $fileCount files in $sshProjectPath (${keyFiles.take(3).join(", ")})...',
      addTokens: 280,
    );

    await Future.delayed(const Duration(milliseconds: 2200));

    planner.shortBubble = 'Drafting Plan...';
    final plan = GeneratedWorkPlan(
      projectPath: sshProjectPath,
      requestSummary: request,
      totalFilesScanned: fileCount,
      keyFilesFound: keyFiles,
      frontendPlanForAgent1:
          'Update UI components, animations & state bindings for "$request"',
      backendPlanForAgent3:
          'Implement core services, error guards & data models for "$request"',
    );
    pendingWorkPlan = plan;

    logAgent(
      8,
      '[Work Plan Created] FE (#1 ${agents[0].name}): ${plan.frontendPlanForAgent1} | BE (#3 ${agents[2].name}): ${plan.backendPlanForAgent3}',
      addTokens: 310,
    );

    // 3. Before bringing the work to the 2 main coders, #8 must confirm the Work Plan!
    stage = WorkflowStage.awaitingPlanConfirmation;

    if (isDirectorAvailable) {
      // You are AVAILABLE: #8 (3.1 Pro) walks to your Shiny VIP Office (#6) to confirm the plan!
      planner.shortBubble = 'Confirm Plan @ VIP';
      walkAgentTo(8, const Offset(805, 515), targetRoom: RoomId.directorSuite);
      logAgent(
        8,
        'Walking Work Plan to Director Shiny VIP Office (#6) for confirmation...',
        addTokens: 60,
      );
    } else {
      // You are AFK: #8 (3.1 Pro) walks to #7 ARGON (HIGH) in Top-Left Room to confirm the plan!
      final argon = agents[6]; // #7 Argon (High)
      planner.shortBubble = 'Confirm @ Argon';
      argon.state = AgentState.active;
      argon.shortBubble = 'Reviewing Plan...';
      walkAgentTo(
        8,
        const Offset(315, 225),
        targetRoom: RoomId.finalReviewOffice,
      );
      logAgent(
        8,
        'Director is AFK. Walking to ${argon.name} [${argon.modelName}] to confirm Work Plan...',
        addTokens: 80,
      );

      await Future.delayed(const Duration(milliseconds: 3000));

      argon.shortBubble = 'Plan Confirmed!';
      logAgent(
        7,
        '[Argon High] Work Plan & file analysis confirmed! Authorized ${planner.name} to brief main coders.',
        addTokens: 240,
      );

      await Future.delayed(const Duration(milliseconds: 1000));
      await confirmWorkPlanAndStartCoding(
        confirmedBy: '${argon.name} [${argon.modelName}]',
      );
    }
  }

  //********************************************************************
  // STEP 3: WORK PLAN CONFIRMED -> #8 BRINGS WORK TO #1 & #3 CODERS   *
  //********************************************************************
  Future<void> confirmWorkPlanAndStartCoding({
    String confirmedBy = 'Director (VIP Suite)',
  }) async {
    final plan = pendingWorkPlan;
    pendingWorkPlan = null;
    stage = WorkflowStage.handingOffPlanToCoders;

    final planner = agents[7]; // #8: 3.1 Pro (Mid)
    planner.state = AgentState.active;
    planner.shortBubble = 'Delivering Plan...';

    logAgent(
      8,
      'Work Plan confirmed by $confirmedBy! Walking down to Coding Bay to brief #1 ${agents[0].name} & #3 ${agents[2].name}...',
      addTokens: 120,
    );

    // #8 walks down into the Coding Bay between Desk #1 and Desk #3
    walkAgentTo(8, const Offset(325, 485), targetRoom: RoomId.codingBay);
    await Future.delayed(const Duration(milliseconds: 3000));

    // #8 returns to its Top-Center seat while #1, #2, #3, #4 begin coding & critiquing!
    planner.shortBubble = '3.1 Pro Mid Audit';
    walkAgentTo(8, planner.homePos, targetRoom: RoomId.afkAuditOffice);

    stage = WorkflowStage.devsAndCriticsWorking;
    final rulesCount = connections.learnedRules.length;

    agents[0].state = AgentState.active;
    agents[0].shortBubble = '3.8 Mid Coding UI';
    agents[2].state = AgentState.active;
    agents[2].shortBubble = '3.8 Mid Coding BE';

    // 3.8 Flash (High) Critics (#2 & #4) walk up to audit #1 & #3
    agents[1].state = AgentState.active;
    agents[1].shortBubble = '3.8 High Critique';
    walkAgentTo(2, const Offset(220, 520), targetRoom: RoomId.codingBay);

    agents[3].state = AgentState.active;
    agents[3].shortBubble = '3.8 High Critique';
    walkAgentTo(4, const Offset(425, 520), targetRoom: RoomId.codingBay);

    logAgent(
      1,
      'Started FE Plan: "${plan?.frontendPlanForAgent1 ?? currentMission}" ($rulesCount learned rules active)',
    );
    logAgent(
      3,
      'Started BE Plan: "${plan?.backendPlanForAgent3 ?? currentMission}" ($rulesCount learned rules active)',
    );

    // Stream live code telemetry (+Added lines, -Deleted lines) to the Bottom-Left Graph!
    for (int step = 0; step < 5; step++) {
      await Future.delayed(const Duration(milliseconds: 520));
      connections.recordCodeMetrics(
        addedLines: 18 + _rng.nextInt(25),
        deletedLines: 4 + _rng.nextInt(9),
        errors: step == 2 ? 1 : 0, // Critic catches 1 minor syntax warning mid-stream
      );
      if (step == 2) {
        logAgent(
          2,
          '[3.8 Flash High Critique] Caught 1 unused import & refactored 8 lines in Front-End.',
          addTokens: 160,
        );
      }
    }

    await _triggerMidCodingAuditOrQuestion();
  }

  //********************************************************************
  // STEP 4: MID-CODING QUESTION / AUDIT & LIVE GRAPH UPDATES          *
  //********************************************************************
  Future<void> _triggerMidCodingAuditOrQuestion() async {
    stage = WorkflowStage.awaitingQuestionOrMidAudit;
    agents[2].state = AgentState.attention;
    final midAuditor = agents[7]; // #8: 3.1 Pro (Mid / Srednja raven)

    if (isDirectorAvailable) {
      pendingQuestionForDirector =
          '${agents[2].name} [3.8 Flash Mid] asks: Should we persist state via local JSON or SQLite (Decision will be saved to Adaptive Learning)?';
      agents[2].shortBubble = 'Asking Director';
      walkAgentTo(3, const Offset(805, 515), targetRoom: RoomId.directorSuite);
      logAgent(3, 'Walking to Director Shiny VIP Office for decision...');
    } else {
      agents[2].shortBubble = 'Mid Audit @ 3.1 Pro';
      midAuditor.state = AgentState.active;
      midAuditor.shortBubble = '3.1 Mid Auditing...';
      walkAgentTo(3, const Offset(565, 235), targetRoom: RoomId.afkAuditOffice);
      logAgent(
        3,
        'Director AFK. Walking to ${midAuditor.name} [${midAuditor.modelName}] for mid-coding audit...',
      );

      await Future.delayed(const Duration(milliseconds: 3200));
      logAgent(
        8,
        '[3.1 Pro Srednja raven] Mid-coding audit complete: Use local JSON with atomic writes.',
      );
      await resolveDirectorQuestion(
        'Atomic Local JSON (Audited by 3.1 Pro Mid)',
        learnedSource: '3.1 Pro (Mid / Srednja raven)',
      );
    }
  }

  Future<void> resolveDirectorQuestion(
    String decision, {
    String learnedSource = 'Director Decision',
  }) async {
    pendingQuestionForDirector = null;
    stage = WorkflowStage.devsAndCriticsWorking;

    connections.recordLearnedPattern(
      category: 'Architecture',
      ruleText: 'Prefer $decision for state persistence in $sshProjectPath',
      learnedFrom: learnedSource,
    );

    agents[2].state = AgentState.active;
    agents[2].shortBubble = '3.8 Mid Applying';
    agents[7].state = AgentState.active;
    agents[7].shortBubble = '3.1 Pro Mid Ready';
    walkAgentTo(3, agents[2].homePos, targetRoom: RoomId.codingBay);
    logAgent(3, 'Applied & learned architecture choice: $decision');

    // Stream second burst of live code additions/deletions to the Bottom-Left Graph
    for (int step = 0; step < 4; step++) {
      await Future.delayed(const Duration(milliseconds: 550));
      connections.recordCodeMetrics(
        addedLines: 22 + _rng.nextInt(28),
        deletedLines: 6 + _rng.nextInt(12),
        errors: 0,
      );
    }

    if (simulateTokenExhaustion ||
        agents[0].tokenRatio >= connections.tokenQuotaThreshold) {
      await _runJulesWebsiteTakeover();
    }

    agents[1].shortBubble = '3.8 High Approved!';
    agents[3].shortBubble = '3.8 High Approved!';
    walkAgentTo(2, agents[1].homePos, targetRoom: RoomId.codingBay);
    walkAgentTo(4, agents[3].homePos, targetRoom: RoomId.codingBay);
    logAgent(2, '[3.8 Flash High] Front-End passed strict critique.');
    logAgent(4, '[3.8 Flash High] Back-End passed strict critique.');

    await Future.delayed(const Duration(milliseconds: 1400));
    await _deliverToArgonHighAndRunSsh();
  }

  Future<void> _runJulesWebsiteTakeover() async {
    stage = WorkflowStage.tokenExhaustedJulesTakeover;
    final julesBot = agents[4];
    for (final id in [1, 2, 3, 4]) {
      final a = agents.firstWhere((ag) => ag.id == id);
      a.tokensUsed = a.tokenLimit;
      a.state = AgentState.sleeping;
      a.shortBubble = 'Quota 0% -> Jules';
    }
    _updateStaxTokenReport();
    agents[8].state = AgentState.attention;
    agents[8].shortBubble = '100% -> Paging Jules';
    logAgent(
      9,
      '[3.5 Flash-Lite] Gemini Web quota reached threshold! Handing over to ${julesBot.name}...',
      addTokens: 0,
    );

    julesBot.state = AgentState.active;
    julesBot.shortBubble = 'Jules Finishing!';
    walkAgentTo(5, const Offset(320, 490), targetRoom: RoomId.codingBay);
    logAgent(
      5,
      '[Jules Session] Completing remaining 3.8 Flash tasks & updating code telemetry...',
    );

    for (int i = 0; i < 3; i++) {
      await Future.delayed(const Duration(milliseconds: 700));
      connections.recordCodeMetrics(
        addedLines: 30 + _rng.nextInt(20),
        deletedLines: 8 + _rng.nextInt(6),
        errors: 0,
      );
    }

    walkAgentTo(5, julesBot.homePos, targetRoom: RoomId.codingBay);
    agents[8].state = AgentState.active;
  }

  Future<void> _deliverToArgonHighAndRunSsh() async {
    stage = WorkflowStage.argonFinalAuditAndSsh;
    final argonHigh = agents[6];

    agents[0].shortBubble = 'To Argon High';
    agents[2].shortBubble = 'To Argon High';
    walkAgentTo(1, const Offset(235, 235), targetRoom: RoomId.finalReviewOffice);
    walkAgentTo(3, const Offset(315, 235), targetRoom: RoomId.finalReviewOffice);

    argonHigh.state = AgentState.active;
    argonHigh.shortBubble = 'Argon SSH Audit...';
    logAgent(
      7,
      '[Argon High] Running final audit & local SSH test in $sshProjectPath...',
    );

    await Future.delayed(const Duration(milliseconds: 2800));

    String kernel = 'Linux';
    try {
      if (Platform.isLinux) {
        final r = await Process.run('uname', ['-sr']);
        if (r.exitCode == 0) kernel = r.stdout.toString().trim();
      }
    } catch (_) {}

    if (_sshAttempt == 0) {
      _sshAttempt++;
      stage = WorkflowStage.sshFailedFixing;
      problemsList.add(
        '[Argon High SSH Audit] Unhandled async exception in $sshProjectPath — Sent back to 3.8 Flash (Mid/High)',
      );
      // Record the error spike on the Bottom-Left Graph!
      connections.recordCodeMetrics(addedLines: 4, deletedLines: 2, errors: 2);

      argonHigh.state = AgentState.attention;
      argonHigh.shortBubble = 'Argon Reject! Fix';
      logAgent(
        7,
        '[$kernel][Argon High] Final SSH check caught 2 errors! Returning to 3.8 Flash squad & recording Learning Rule.',
      );

      connections.recordLearnedPattern(
        category: 'Critique Fix',
        ruleText:
            'Always wrap local Process.run and SSH socket calls in try/catch blocks.',
        learnedFrom: 'Argon (High) SSH Audit',
      );

      agents[0].state = AgentState.active;
      agents[2].state = AgentState.active;
      agents[0].shortBubble = '3.8 Mid Fixing';
      agents[2].shortBubble = '3.8 Mid Fixing';
      walkAgentTo(1, agents[0].homePos, targetRoom: RoomId.codingBay);
      walkAgentTo(3, agents[2].homePos, targetRoom: RoomId.codingBay);

      for (int i = 0; i < 3; i++) {
        await Future.delayed(const Duration(milliseconds: 800));
        connections.recordCodeMetrics(
          addedLines: 14 + _rng.nextInt(12),
          deletedLines: 10 + _rng.nextInt(8),
          errors: 0,
        );
      }

      problemsList.clear();
      logAgent(2, '[3.8 Flash High] Verified SSH hotfix.');
      logAgent(4, '[3.8 Flash High] Verified SSH hotfix.');

      await _deliverToArgonHighAndRunSsh();
      return;
    }

    agents[0].state = AgentState.done;
    agents[1].state = AgentState.done;
    agents[2].state = AgentState.done;
    agents[3].state = AgentState.done;
    agents[0].shortBubble = 'Done (3.8 Mid)';
    agents[2].shortBubble = 'Done (3.8 Mid)';
    walkAgentTo(1, agents[0].homePos, targetRoom: RoomId.codingBay);
    walkAgentTo(3, agents[2].homePos, targetRoom: RoomId.codingBay);

    stage = WorkflowStage.deliveringToDirector;
    argonHigh.shortBubble = 'Delivering Build!';
    walkAgentTo(7, const Offset(805, 495), targetRoom: RoomId.directorSuite);
    logAgent(
      7,
      '[$kernel][Argon High] Final Audit PASSED! Delivering verified app to Director Suite...',
    );

    await Future.delayed(const Duration(milliseconds: 3800));

    argonHigh.state = AgentState.done;
    argonHigh.shortBubble = 'Back to Seat';
    walkAgentTo(7, argonHigh.homePos, targetRoom: RoomId.finalReviewOffice);
    logAgent(7, 'Delivered build to Director. Returning to Argon High seat.');

    stage = WorkflowStage.julesCommittingToGit;
    final julesBot = agents[4];
    julesBot.state = AgentState.active;
    julesBot.shortBubble = 'Jules Git Push';
    walkAgentTo(5, const Offset(540, 495), targetRoom: RoomId.codingBay);

    final hash = (100000 + _rng.nextInt(899999)).toRadixString(16);
    gitCommitHistory.insert(
      0,
      '$hash (HEAD -> $activeGitBranch) feat: "$currentMission" [+${connections.totalLinesAdded}/-${connections.totalLinesDeleted}]',
    );
    logAgent(
      5,
      '[Jules Session] Committed & pushed $hash in $sshProjectPath ($activeGitBranch)',
    );

    await Future.delayed(const Duration(milliseconds: 2600));

    walkAgentTo(5, julesBot.homePos, targetRoom: RoomId.codingBay);
    julesBot.state = AgentState.done;
    julesBot.shortBubble = 'Pushed #$hash';
    argonHigh.state = AgentState.active;
    argonHigh.shortBubble = 'Argon High Ready';
    stage = WorkflowStage.completed;
    notifyListeners();
  }

  void triggerManualGitCommit() {
    final hash = (100000 + _rng.nextInt(899999)).toRadixString(16);
    gitCommitHistory.insert(
      0,
      '$hash (HEAD -> $activeGitBranch) chore: manual snapshot in $sshProjectPath',
    );
    agents[4].shortBubble = 'Pushed #$hash';
    logAgent(5, 'Manual git commit in $sshProjectPath ($activeGitBranch).');
  }
}