import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'connections_manager.dart';

//**********************************************************************
// JARVIS_V2 BACK-END // OPEN-SOURCE PROVIDER-AGNOSTIC ORCHESTRATOR    *
// Dynamically syncs agent names, providers, models, and active        *
// cloned Desktop repository paths from ConnectionsManager.            *
//**********************************************************************

enum AgentState { active, attention, idle, done, sleeping }

enum RoomId {
  finalReviewOffice, // Top-Left: Final Reviewer & Local SSH Runner
  afkAuditOffice,    // Top-Center: Offline (AFK) Reviewer
  tokenOffice,       // Top-Right: Token CFO Reporter
  hallway,           // Central Corridor
  codingBay,         // Bottom-Left: 4 Dev/Critic Tables + Overflow/Git Agent
  directorSuite,     // Bottom-Right: Your Shiny VIP Office
}

enum WorkflowStage {
  idle,
  devsAndCriticsWorking,
  awaitingQuestionOrAudit,
  tokenExhaustedOverflowTakeover,
  finalCheckAndSsh,
  sshFailedFixing,
  deliveringToDirector,
  committingToGit,
  completed,
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
    this.tokensUsed = 380,
    this.tokenLimit = 4000,
    this.costUsd = 0.04,
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

  bool isDirectorAvailable = true;
  bool simulateTokenExhaustion = false;

  String sshHost = 'localhost';
  String sshProjectPath = '~/Desktop/jarvis_workspaces/jarvis_v2';
  String activeGitBranch = 'main';

  WorkflowStage stage = WorkflowStage.idle;
  String currentMission = 'Select or clone a repo & dispatch a task';
  String? pendingQuestionForDirector;

  final List<String> globalTerminalLogs = [];
  final List<String> problemsList = [];
  final List<String> gitCommitHistory = [
    'init001 (HEAD -> main) chore: open-source multi-agent workspace ready',
  ];

  late final List<OfficeAgent> agents;
  int _sshAttempt = 0;

  OfficeOrchestrator({required this.connections}) {
    _initAgents();
    connections.addListener(_syncFromConnectionsManager);
    _syncFromConnectionsManager();
    _addGlobalLog('[SYSTEM] Open-Source Multi-Agent Orchestrator initialized.');
  }

  @override
  void dispose() {
    connections.removeListener(_syncFromConnectionsManager);
    super.dispose();
  }

  //********************************************************************
  // SYNC AGENT NAMES, PROVIDERS, MODELS & CLONED DESKTOP REPO         *
  //********************************************************************
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
      // #1 Front-End Dev
      OfficeAgent(
        id: 1,
        roleSlot: OfficeRoleSlot.frontendDev,
        name: 'nova-fe',
        role: 'Front-End Builder',
        modelName: 'codex-mini-latest',
        providerName: 'OpenAI',
        group: 'dev-squad',
        branch: 'main',
        hairColor: const Color(0xFFD97706),
        shirtColor: const Color(0xFF2563EB),
        pantsColor: const Color(0xFF1E293B),
        badgeColor: const Color(0xFF3B82F6),
        homePos: const Offset(220, 465),
        homeRoom: RoomId.codingBay,
        state: AgentState.active,
        shortBubble: 'Typing UI...',
        hasHeadphones: true,
        initialLogs: ['[Ready] Front-End agent online.'],
      ),
      // #2 Front-End Critic
      OfficeAgent(
        id: 2,
        roleSlot: OfficeRoleSlot.frontendCritic,
        name: 'vex-critic-fe',
        role: 'FE Critic & QA',
        modelName: 'claude-code-sonnet',
        providerName: 'Claude',
        group: 'dev-squad',
        branch: 'main',
        hairColor: const Color(0xFFF43F5E),
        shirtColor: const Color(0xFF7C3AED),
        pantsColor: const Color(0xFF0F172A),
        badgeColor: const Color(0xFFA855F7),
        homePos: const Offset(220, 605),
        homeRoom: RoomId.codingBay,
        state: AgentState.active,
        shortBubble: 'Auditing FE',
        hasGlasses: true,
        initialLogs: ['[Ready] Front-End critic online.'],
      ),
      // #3 Back-End Dev
      OfficeAgent(
        id: 3,
        roleSlot: OfficeRoleSlot.backendDev,
        name: 'kael-be',
        role: 'Back-End Builder',
        modelName: 'o3-mini-high',
        providerName: 'OpenAI',
        group: 'dev-squad',
        branch: 'main',
        hairColor: const Color(0xFF111827),
        shirtColor: const Color(0xFF059669),
        pantsColor: const Color(0xFF1F2937),
        badgeColor: const Color(0xFF10B981),
        homePos: const Offset(425, 465),
        homeRoom: RoomId.codingBay,
        state: AgentState.active,
        shortBubble: 'Typing Backend...',
        hasHeadphones: true,
        initialLogs: ['[Ready] Back-End agent online.'],
      ),
      // #4 Back-End Critic
      OfficeAgent(
        id: 4,
        roleSlot: OfficeRoleSlot.backendCritic,
        name: 'nyx-critic-be',
        role: 'BE Critic & QA',
        modelName: 'claude-code-sonnet',
        providerName: 'Claude',
        group: 'dev-squad',
        branch: 'main',
        hairColor: const Color(0xFFE2E8F0),
        shirtColor: const Color(0xFF6D28D9),
        pantsColor: const Color(0xFF1E1B4B),
        badgeColor: const Color(0xFF8B5CF6),
        homePos: const Offset(425, 605),
        homeRoom: RoomId.codingBay,
        state: AgentState.active,
        shortBubble: 'Auditing BE',
        hasGlasses: true,
        initialLogs: ['[Ready] Back-End critic online.'],
      ),
      // #5 Quota Overflow & Git Committer
      OfficeAgent(
        id: 5,
        roleSlot: OfficeRoleSlot.overflowGitBot,
        name: 'chronos-git',
        role: 'Overflow & Git Bot',
        modelName: 'jules-cloud-agent',
        providerName: 'Google',
        group: 'git-ops',
        branch: 'main',
        hairColor: const Color(0xFFC084FC),
        shirtColor: const Color(0xFF4F46E5),
        pantsColor: const Color(0xFF1E1B4B),
        badgeColor: const Color(0xFF818CF8),
        homePos: const Offset(590, 535),
        homeRoom: RoomId.codingBay,
        state: AgentState.active,
        shortBubble: 'Overflow & Git',
        tokenLimit: 30000,
        hasHeadphones: true,
        initialLogs: ['[Ready] Watching token overflow & git branch.'],
      ),
      // #6 Director (User in Shiny VIP Suite)
      OfficeAgent(
        id: 6,
        name: 'director-you',
        role: 'Project Director',
        modelName: 'Human Lead',
        providerName: 'Local',
        group: 'reviewers',
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
      // #7 Final Reviewer & SSH Integrator
      OfficeAgent(
        id: 7,
        roleSlot: OfficeRoleSlot.finalReviewer,
        name: 'atlas-final',
        role: 'Final Reviewer & SSH',
        modelName: 'claude-3-7-sonnet-high',
        providerName: 'Claude',
        group: 'reviewers',
        branch: 'main',
        hairColor: const Color(0xFFFACC15),
        shirtColor: const Color(0xFFDC2626),
        pantsColor: const Color(0xFF18181B),
        badgeColor: const Color(0xFFF59E0B),
        homePos: const Offset(275, 175),
        homeRoom: RoomId.finalReviewOffice,
        state: AgentState.active,
        shortBubble: 'Final SSH Reviewer',
        tokenLimit: 20000,
        hasHeadphones: true,
        initialLogs: ['[Ready] Final Reviewer & Local SSH Runner online.'],
      ),
      // #8 Offline / AFK Reviewer
      OfficeAgent(
        id: 8,
        roleSlot: OfficeRoleSlot.offlineReviewer,
        name: 'oracle-afk',
        role: 'Offline AFK Reviewer',
        modelName: 'gemini-3.1-pro-high',
        providerName: 'Google',
        group: 'reviewers',
        branch: 'main',
        hairColor: const Color(0xFF38BDF8),
        shirtColor: const Color(0xFF1D4ED8),
        pantsColor: const Color(0xFF0F172A),
        badgeColor: const Color(0xFF38BDF8),
        homePos: const Offset(565, 175),
        homeRoom: RoomId.afkAuditOffice,
        state: AgentState.active,
        shortBubble: 'AFK Auditor',
        tokenLimit: 20000,
        hasGlasses: true,
        initialLogs: ['[Ready] Offline Reviewer ready for AFK questions.'],
      ),
      // #9 Stax (Token CFO Reporter)
      OfficeAgent(
        id: 9,
        name: 'stax-token-cfo',
        role: 'Token Usage Reporter',
        modelName: 'Ledger-Bot',
        providerName: 'Metrics',
        group: 'reviewers',
        branch: 'main',
        hairColor: const Color(0xFF4ADE80),
        shirtColor: const Color(0xFF15803D),
        pantsColor: const Color(0xFF052E16),
        badgeColor: const Color(0xFF22C55E),
        homePos: const Offset(855, 175),
        homeRoom: RoomId.tokenOffice,
        state: AgentState.active,
        shortBubble: 'Quota: 19% Used',
        tokensUsed: 150,
        costUsd: 0.01,
        hasGlasses: true,
        initialLogs: ['[Stax] Tracking token usage across all configured models.'],
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
    for (final agent in agents) {
      if (agent.waypoints.isEmpty) continue;
      final nextTarget = agent.waypoints.first;
      final dx = nextTarget.dx - agent.currentPos.dx;
      final dy = nextTarget.dy - agent.currentPos.dy;
      final dist = sqrt(dx * dx + dy * dy);
      const speed = 3.5;

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

  void logAgent(int id, String msg, {int addTokens = 360}) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    final a = agents.firstWhere((ag) => ag.id == id);
    a.logs.insert(0, '$ts \$ $msg');
    if (a.logs.length > 30) a.logs.removeLast();

    if (id != 6 && id != 9) {
      a.tokensUsed = (a.tokensUsed + addTokens).clamp(0, a.tokenLimit);
      a.costUsd =
          double.parse((a.costUsd + addTokens * 0.00008).toStringAsFixed(2));
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
    stax.shortBubble = 'Quota: $pct% Used';
  }

  void toggleDirectorAvailability() {
    isDirectorAvailable = !isDirectorAvailable;
    final dir = agents.firstWhere((a) => a.id == 6);
    final afkRev = agents.firstWhere((a) => a.id == 8);
    dir.state = isDirectorAvailable ? AgentState.active : AgentState.sleeping;
    dir.shortBubble =
        isDirectorAvailable ? 'AVAILABLE' : 'AFK -> ${afkRev.name}';
    logAgent(
      6,
      isDirectorAvailable
          ? 'Director AVAILABLE (Agents ask me directly)'
          : 'Director AFK (Questions route to ${afkRev.name} [${afkRev.modelName}])',
      addTokens: 0,
    );
  }

  //********************************************************************
  // MULTI-AGENT WORKFLOW PIPELINE                                     *
  //********************************************************************
  Future<void> dispatchMission(String rawPrompt) async {
    final task = rawPrompt.trim().isEmpty
        ? 'Implement feature in $sshProjectPath'
        : rawPrompt.trim();

    currentMission = task;
    stage = WorkflowStage.devsAndCriticsWorking;
    _sshAttempt = 0;
    problemsList.clear();

    final finalRev = agents[6]; // #7 Final Reviewer
    logAgent(
      7,
      'Dispatched "$task" to ${agents[0].name} & ${agents[2].name} in $sshProjectPath',
    );

    agents[0].state = AgentState.active;
    agents[0].shortBubble = 'Typing UI...';
    agents[2].state = AgentState.active;
    agents[2].shortBubble = 'Typing Backend...';

    // Critics (#2 & #4) walk up to audit #1 & #3
    agents[1].state = AgentState.active;
    agents[1].shortBubble = 'Critiquing FE';
    walkAgentTo(2, const Offset(220, 520), targetRoom: RoomId.codingBay);

    agents[3].state = AgentState.active;
    agents[3].shortBubble = 'Critiquing BE';
    walkAgentTo(4, const Offset(425, 520), targetRoom: RoomId.codingBay);

    logAgent(1, 'Coding UI inside $sshProjectPath...');
    logAgent(3, 'Coding backend inside $sshProjectPath...');
    logAgent(
      7,
      '${finalRev.name} (${finalRev.modelName}) monitoring workspace...',
      addTokens: 80,
    );

    await Future.delayed(const Duration(milliseconds: 2600));
    await _triggerMidWorkAuditOrQuestion();
  }

  Future<void> _triggerMidWorkAuditOrQuestion() async {
    stage = WorkflowStage.awaitingQuestionOrAudit;
    agents[2].state = AgentState.attention;
    final afkRev = agents[7]; // #8 Offline Reviewer

    if (isDirectorAvailable) {
      pendingQuestionForDirector =
          '${agents[2].name} (${agents[2].modelName}) asks: Use async stream or local cache inside $sshProjectPath?';
      agents[2].shortBubble = 'Asking Director';
      walkAgentTo(3, const Offset(805, 515), targetRoom: RoomId.directorSuite);
      logAgent(3, 'Walking to Director Shiny VIP Office for decision...');
    } else {
      agents[2].shortBubble = 'Ask ${afkRev.name}';
      afkRev.state = AgentState.active;
      afkRev.shortBubble = 'Auditing Q...';
      walkAgentTo(3, const Offset(565, 235), targetRoom: RoomId.afkAuditOffice);
      logAgent(
        3,
        'Director AFK. Walking to Offline Reviewer ${afkRev.name} (${afkRev.modelName})...',
      );

      await Future.delayed(const Duration(milliseconds: 3400));
      logAgent(
        8,
        'Approved async stream with local cache fallback.',
      );
      await resolveDirectorQuestion(
        'Async Stream + Fallback (Approved by ${afkRev.name})',
      );
    }
  }

  Future<void> resolveDirectorQuestion(String decision) async {
    pendingQuestionForDirector = null;
    stage = WorkflowStage.devsAndCriticsWorking;

    agents[2].state = AgentState.active;
    agents[2].shortBubble = 'Typing Fix...';
    agents[7].state = AgentState.active;
    agents[7].shortBubble = 'AFK Auditor';
    walkAgentTo(3, agents[2].homePos, targetRoom: RoomId.codingBay);
    logAgent(3, 'Applied decision: $decision');

    await Future.delayed(const Duration(milliseconds: 2800));

    if (simulateTokenExhaustion || agents[0].tokenRatio >= 0.95) {
      await _runOverflowAgentTakeover();
    }

    agents[1].shortBubble = 'FE Approved!';
    agents[3].shortBubble = 'BE Approved!';
    walkAgentTo(2, agents[1].homePos, targetRoom: RoomId.codingBay);
    walkAgentTo(4, agents[3].homePos, targetRoom: RoomId.codingBay);
    logAgent(2, '${agents[1].name} approved Front-End changes.');
    logAgent(4, '${agents[3].name} approved Back-End changes.');

    await Future.delayed(const Duration(milliseconds: 1600));
    await _deliverToFinalReviewerAndRunSsh();
  }

  Future<void> _runOverflowAgentTakeover() async {
    stage = WorkflowStage.tokenExhaustedOverflowTakeover;
    final overflowBot = agents[4]; // #5 Overflow & Git Bot
    for (final id in [1, 2, 3, 4]) {
      final a = agents.firstWhere((ag) => ag.id == id);
      a.tokensUsed = a.tokenLimit;
      a.state = AgentState.sleeping;
      a.shortBubble = '0 Tokens Left!';
    }
    _updateStaxTokenReport();
    agents[8].state = AgentState.attention;
    agents[8].shortBubble = '100% -> ${overflowBot.name}';
    logAgent(
      9,
      'Main coding agents out of tokens! Paging ${overflowBot.name} (${overflowBot.modelName})...',
      addTokens: 0,
    );

    overflowBot.state = AgentState.active;
    overflowBot.shortBubble = 'Overflow Takeover';
    walkAgentTo(5, const Offset(320, 490), targetRoom: RoomId.codingBay);
    logAgent(
      5,
      'Taking over unfinished work using ${overflowBot.modelName}...',
    );

    await Future.delayed(const Duration(milliseconds: 2600));
    walkAgentTo(5, overflowBot.homePos, targetRoom: RoomId.codingBay);
    agents[8].state = AgentState.active;
  }

  Future<void> _deliverToFinalReviewerAndRunSsh() async {
    stage = WorkflowStage.finalCheckAndSsh;
    final finalRev = agents[6]; // #7 Final Reviewer

    agents[0].shortBubble = 'To ${finalRev.name}';
    agents[2].shortBubble = 'To ${finalRev.name}';
    walkAgentTo(1, const Offset(235, 235), targetRoom: RoomId.finalReviewOffice);
    walkAgentTo(3, const Offset(315, 235), targetRoom: RoomId.finalReviewOffice);

    finalRev.state = AgentState.active;
    finalRev.shortBubble = 'SSH Test Run...';
    logAgent(
      7,
      'Running merged build via local SSH in $sshProjectPath...',
    );

    await Future.delayed(const Duration(milliseconds: 3200));

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
        '[SSH Test Failure] Analyze warning in $sshProjectPath — Returned to ${agents[0].name}',
      );
      finalRev.state = AgentState.attention;
      finalRev.shortBubble = 'SSH Bug! Fix it';
      logAgent(
        7,
        '[$kernel] SSH test caught a bug! Sending agents back to desks to fix.',
      );

      agents[0].state = AgentState.active;
      agents[2].state = AgentState.active;
      agents[0].shortBubble = 'Typing SSH Fix';
      agents[2].shortBubble = 'Typing SSH Fix';
      walkAgentTo(1, agents[0].homePos, targetRoom: RoomId.codingBay);
      walkAgentTo(3, agents[2].homePos, targetRoom: RoomId.codingBay);

      await Future.delayed(const Duration(milliseconds: 3400));
      problemsList.clear();
      logAgent(2, 'Verified SSH hotfix.');
      logAgent(4, 'Verified SSH hotfix.');

      await _deliverToFinalReviewerAndRunSsh();
      return;
    }

    agents[0].state = AgentState.done;
    agents[1].state = AgentState.done;
    agents[2].state = AgentState.done;
    agents[3].state = AgentState.done;
    agents[0].shortBubble = 'Done (FE)';
    agents[2].shortBubble = 'Done (BE)';
    walkAgentTo(1, agents[0].homePos, targetRoom: RoomId.codingBay);
    walkAgentTo(3, agents[2].homePos, targetRoom: RoomId.codingBay);

    // Final Reviewer walks to Director Suite to deliver, then walks back to seat!
    stage = WorkflowStage.deliveringToDirector;
    finalRev.shortBubble = 'Delivering App!';
    walkAgentTo(7, const Offset(805, 495), targetRoom: RoomId.directorSuite);
    logAgent(
      7,
      '[$kernel] Local SSH PASSED! Delivering finished build to Director Suite...',
    );

    await Future.delayed(const Duration(milliseconds: 4200));

    finalRev.state = AgentState.done;
    finalRev.shortBubble = 'Back to Desk';
    walkAgentTo(7, finalRev.homePos, targetRoom: RoomId.finalReviewOffice);
    logAgent(7, 'Build delivered to Director. Returning to Final Reviewer seat.');

    // Overflow/Git Bot commits everything to the cloned repo branch
    stage = WorkflowStage.committingToGit;
    final gitBot = agents[4];
    gitBot.state = AgentState.active;
    gitBot.shortBubble = 'git commit & push';
    walkAgentTo(5, const Offset(540, 495), targetRoom: RoomId.codingBay);

    final hash = (100000 + Random().nextInt(899999)).toRadixString(16);
    gitCommitHistory.insert(
      0,
      '$hash (HEAD -> $activeGitBranch) feat: "$currentMission" [by ${gitBot.name}]',
    );
    logAgent(
      5,
      'Committed & pushed $hash in $sshProjectPath ($activeGitBranch)',
    );

    await Future.delayed(const Duration(milliseconds: 2800));

    walkAgentTo(5, gitBot.homePos, targetRoom: RoomId.codingBay);
    gitBot.state = AgentState.done;
    gitBot.shortBubble = 'Committed #$hash';
    finalRev.state = AgentState.active;
    finalRev.shortBubble = 'Final SSH Ready';
    stage = WorkflowStage.completed;
    notifyListeners();
  }

  void triggerManualGitCommit() {
    final hash = (100000 + Random().nextInt(899999)).toRadixString(16);
    gitCommitHistory.insert(
      0,
      '$hash (HEAD -> $activeGitBranch) chore: manual snapshot in $sshProjectPath',
    );
    agents[4].shortBubble = 'Pushed #$hash';
    logAgent(5, 'Manual git commit in $sshProjectPath ($activeGitBranch).');
  }
}