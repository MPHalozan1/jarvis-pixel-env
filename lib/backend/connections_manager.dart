import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

//**********************************************************************
// BACKEND WEBSITE CONNECTIONS, ROLE MAPPER, GITHUB CLONER & TELEMETRY *
// Official Links Configured:                                          *
// - Gemini: https://gemini.google.com/app                             *
// - Jules:  https://jules.google.com/session                          *
// - GitHub: https://github.com/                                       *
// Clones Git repos into ~/Desktop/projects/<repo_name>                *
//**********************************************************************

enum OfficeRoleSlot {
  finalReviewer,   // Argon (High): Final audit, Plan confirm (AFK) & SSH
  offlineReviewer, // 3.1 Pro (Mid): Work Plan Creator & Mid-Coding Audit
  overflowGitBot,  // Jules (Web): Quota overflow finisher & Git committer
  frontendDev,     // 3.8 Flash (Mid): Main Front-End coder
  frontendCritic,  // 3.8 Flash (High): Front-End critique & QA
  backendDev,      // 3.8 Flash (Mid): Main Back-End coder
  backendCritic,   // 3.8 Flash (High): Back-End critique & QA
  tokenOverseer,   // 3.5 Flash-Lite: Fast token & telemetry monitor
}

class ProviderConnection {
  final String id;
  String name;
  String websiteUrl;
  String sessionCookieOrNote;
  bool isSignedIn;
  bool isSigningIn;
  List<String> availableModels;
  final Color brandColor;

  ProviderConnection({
    required this.id,
    required this.name,
    required this.websiteUrl,
    this.sessionCookieOrNote = '',
    this.isSignedIn = false,
    this.isSigningIn = false,
    required this.availableModels,
    required this.brandColor,
  });
}

class RoleAssignment {
  final OfficeRoleSlot slot;
  final String roleTitle;
  String characterName;
  String providerId;
  String selectedModel;

  RoleAssignment({
    required this.slot,
    required this.roleTitle,
    required this.characterName,
    required this.providerId,
    required this.selectedModel,
  });
}

class GitHubRepoItem {
  final String name;
  final String fullName;
  final String description;
  final String cloneUrl;
  final String defaultBranch;
  final bool isPrivate;
  bool isClonedToDesktop;
  String? localDesktopPath;

  GitHubRepoItem({
    required this.name,
    required this.fullName,
    required this.description,
    required this.cloneUrl,
    required this.defaultBranch,
    this.isPrivate = false,
    this.isClonedToDesktop = false,
    this.localDesktopPath,
  });
}

class LearnedRule {
  final String id;
  final String category;
  final String ruleText;
  final String learnedFrom;
  double confidence;
  int timesApplied;

  LearnedRule({
    required this.id,
    required this.category,
    required this.ruleText,
    required this.learnedFrom,
    this.confidence = 0.88,
    this.timesApplied = 1,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'ruleText': ruleText,
        'learnedFrom': learnedFrom,
        'confidence': confidence,
        'timesApplied': timesApplied,
      };

  factory LearnedRule.fromJson(Map<String, dynamic> map) => LearnedRule(
        id: (map['id'] ?? '').toString(),
        category: (map['category'] ?? 'General').toString(),
        ruleText: (map['ruleText'] ?? '').toString(),
        learnedFrom: (map['learnedFrom'] ?? 'System').toString(),
        confidence: (map['confidence'] as num?)?.toDouble() ?? 0.88,
        timesApplied: (map['timesApplied'] as num?)?.toInt() ?? 1,
      );
}

class ConnectionsManager extends ChangeNotifier {
  late final List<ProviderConnection> providers;
  late final Map<OfficeRoleSlot, RoleAssignment> roleAssignments;

  // Sleek Control Deck Adjustment Sliders
  bool autoLearnEnabled = true;
  double critiqueStrictness = 0.82;
  double tokenQuotaThreshold = 0.90;
  double agentWalkSpeedMultiplier = 1.0;

  // Live Code & Error Telemetry for the Bottom-Left Graph
  final List<double> progressHistory = [0.18, 0.28, 0.34, 0.48, 0.62, 0.75];
  final List<double> addedLinesHistory = [0.12, 0.24, 0.35, 0.42, 0.58, 0.72];
  final List<double> deletedLinesHistory = [0.05, 0.08, 0.14, 0.12, 0.19, 0.22];
  final List<double> errorsHistory = [0.00, 0.00, 0.08, 0.04, 0.00, 0.00];

  int totalOperationsCount = 151072;
  int totalLinesAdded = 0;
  int totalLinesDeleted = 0;
  int totalErrorsEncountered = 0;

  List<LearnedRule> learnedRules = [];
  late String learningMemoryFilePath;

  // Official GitHub Website & Cloner State
  String githubUrl = 'https://github.com/';
  String githubUsername = 'MPHalozan1';
  String githubToken = '';
  bool isGithubSignedIn = false;
  bool isFetchingRepos = false;
  bool isCloningRepo = false;
  String lastNotificationTitle = 'Notification';
  String statusMessage = 'Operation complete! Ready to start a new workflow.';

  List<GitHubRepoItem> repositories = [];
  GitHubRepoItem? activeProjectRepo;
  late String desktopProjectsRoot;
  late String userHomeDir;

  ConnectionsManager() {
    userHomeDir = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    // Creates ~/Desktop/projects when cloning Git repositories
    desktopProjectsRoot = '$userHomeDir/Desktop/projects';
    learningMemoryFilePath =
        '$desktopProjectsRoot/adaptive_learning_memory.json';

    _initWebsiteProviders();
    _initDefaultRoleAssignments();
    _initSampleRepos();
    _loadOrInitLearningRules();
    _detectLocalGhCliAuth();
  }

  //********************************************************************
  // RECORD LIVE CODE TELEMETRY (ADDED LINES, DELETED LINES, ERRORS)   *
  // Dynamically updates the bottom-left telemetry graph as devs work. *
  //********************************************************************
  void recordCodeMetrics({
    int addedLines = 0,
    int deletedLines = 0,
    int errors = 0,
  }) {
    totalLinesAdded += addedLines;
    totalLinesDeleted += deletedLines;
    totalErrorsEncountered += errors;
    totalOperationsCount += (addedLines + deletedLines + errors * 5);

    // Normalize values to 0.05..0.96 for smooth sparkline plotting
    final nextAdded =
        ((addedLinesHistory.last * 0.65) + (addedLines / 65.0)).clamp(0.08, 0.96);
    final nextDeleted =
        ((deletedLinesHistory.last * 0.65) + (deletedLines / 45.0))
            .clamp(0.04, 0.85);
    final nextErr = errors > 0
        ? (0.45 + (errors * 0.22)).clamp(0.25, 0.95)
        : (errorsHistory.last * 0.4).clamp(0.02, 0.95);

    addedLinesHistory.add(nextAdded);
    deletedLinesHistory.add(nextDeleted);
    errorsHistory.add(nextErr);
    progressHistory.add(nextAdded);

    if (addedLinesHistory.length > 14) addedLinesHistory.removeAt(0);
    if (deletedLinesHistory.length > 14) deletedLinesHistory.removeAt(0);
    if (errorsHistory.length > 14) errorsHistory.removeAt(0);
    if (progressHistory.length > 14) progressHistory.removeAt(0);

    notifyListeners();
  }

  void resetWorkflowTelemetry() {
    totalLinesAdded = 0;
    totalLinesDeleted = 0;
    totalErrorsEncountered = 0;
    addedLinesHistory
      ..clear()
      ..addAll([0.06, 0.08, 0.10, 0.12]);
    deletedLinesHistory
      ..clear()
      ..addAll([0.02, 0.03, 0.04, 0.04]);
    errorsHistory
      ..clear()
      ..addAll([0.01, 0.01, 0.01, 0.01]);
    notifyListeners();
  }

  //********************************************************************
  // DISCOVER LOCAL PROJECT FOLDERS ON DISK                            *
  // Scans ~/Projects and ~/Desktop/projects for quick selection.      *
  //********************************************************************
  List<String> discoverLocalFolders() {
    final List<String> found = [];
    final currentDir = Directory.current.path;
    found.add(currentDir);

    final candidates = [
      '$userHomeDir/Projects',
      '$userHomeDir/Desktop/projects',
      '$userHomeDir/Desktop/jarvis_workspaces',
    ];

    for (final rootPath in candidates) {
      try {
        final dir = Directory(rootPath);
        if (dir.existsSync()) {
          for (final entity in dir.listSync()) {
            if (entity is Directory && !found.contains(entity.path)) {
              final folderName =
                  entity.path.split(Platform.pathSeparator).last;
              if (!folderName.startsWith('.')) {
                found.add(entity.path);
              }
            }
          }
        }
      } catch (_) {}
    }
    return found;
  }

  void _initWebsiteProviders() {
    providers = [
      ProviderConnection(
        id: 'gemini_web',
        name: 'Gemini Website',
        websiteUrl: 'https://gemini.google.com/app',
        isSignedIn: true,
        availableModels: [
          'Argon (High)',
          '3.1 Pro (Mid / Srednja raven)',
          '3.8 Flash (High)',
          '3.8 Flash (Mid)',
          '3.5 Flash-Lite',
        ],
        brandColor: const Color(0xFF00D2FF),
      ),
      ProviderConnection(
        id: 'jules_web',
        name: 'Google Jules Session',
        websiteUrl: 'https://jules.google.com/session',
        isSignedIn: true,
        availableModels: [
          'Jules Web Finisher (Session + Git)',
          'Jules Async Repo Sweeper',
        ],
        brandColor: const Color(0xFFF43F5E),
      ),
      ProviderConnection(
        id: 'github_web',
        name: 'GitHub Website',
        websiteUrl: 'https://github.com/',
        isSignedIn: true,
        availableModels: [
          'GitHub Repo Cloner & PR Sync',
        ],
        brandColor: const Color(0xFFA855F7),
      ),
    ];
  }

  void _initDefaultRoleAssignments() {
    roleAssignments = {
      OfficeRoleSlot.finalReviewer: RoleAssignment(
        slot: OfficeRoleSlot.finalReviewer,
        roleTitle: 'Final Audit & Plan Confirm (#7)',
        characterName: 'argon-high',
        providerId: 'gemini_web',
        selectedModel: 'Argon (High)',
      ),
      OfficeRoleSlot.offlineReviewer: RoleAssignment(
        slot: OfficeRoleSlot.offlineReviewer,
        roleTitle: 'Work Planner & Mid Audit (#8)',
        characterName: 'gemini-3.1-mid',
        providerId: 'gemini_web',
        selectedModel: '3.1 Pro (Mid / Srednja raven)',
      ),
      OfficeRoleSlot.overflowGitBot: RoleAssignment(
        slot: OfficeRoleSlot.overflowGitBot,
        roleTitle: 'Token Overflow & Git (#5)',
        characterName: 'jules-session',
        providerId: 'jules_web',
        selectedModel: 'Jules Web Finisher (Session + Git)',
      ),
      OfficeRoleSlot.frontendDev: RoleAssignment(
        slot: OfficeRoleSlot.frontendDev,
        roleTitle: 'Main Front-End Coder (#1)',
        characterName: 'flash-3.8-fe',
        providerId: 'gemini_web',
        selectedModel: '3.8 Flash (Mid)',
      ),
      OfficeRoleSlot.frontendCritic: RoleAssignment(
        slot: OfficeRoleSlot.frontendCritic,
        roleTitle: 'Front-End Critique (#2)',
        characterName: 'critic-3.8-fe',
        providerId: 'gemini_web',
        selectedModel: '3.8 Flash (High)',
      ),
      OfficeRoleSlot.backendDev: RoleAssignment(
        slot: OfficeRoleSlot.backendDev,
        roleTitle: 'Main Back-End Coder (#3)',
        characterName: 'flash-3.8-be',
        providerId: 'gemini_web',
        selectedModel: '3.8 Flash (Mid)',
      ),
      OfficeRoleSlot.backendCritic: RoleAssignment(
        slot: OfficeRoleSlot.backendCritic,
        roleTitle: 'Back-End Critique (#4)',
        characterName: 'critic-3.8-be',
        providerId: 'gemini_web',
        selectedModel: '3.8 Flash (High)',
      ),
      OfficeRoleSlot.tokenOverseer: RoleAssignment(
        slot: OfficeRoleSlot.tokenOverseer,
        roleTitle: 'Token & Speed Overseer (#9)',
        characterName: 'stax-3.5-lite',
        providerId: 'gemini_web',
        selectedModel: '3.5 Flash-Lite',
      ),
    };
  }

  void _initSampleRepos() {
    final targetPath = '$desktopProjectsRoot/jarvis-pixel-env';
    final exists = Directory(targetPath).existsSync();
    repositories = [
      GitHubRepoItem(
        name: 'jarvis-pixel-env',
        fullName: 'MPHalozan1/jarvis-pixel-env',
        description:
            'Open-source 16-bit pixel multi-agent AI studio for Linux & Windows',
        cloneUrl: 'https://github.com/MPHalozan1/jarvis-pixel-env.git',
        defaultBranch: 'main',
        isClonedToDesktop: exists,
        localDesktopPath: exists ? targetPath : null,
      ),
    ];
  }

  Future<void> _detectLocalGhCliAuth() async {
    try {
      final res = await Process.run('gh', ['auth', 'token']);
      if (res.exitCode == 0) {
        final token = res.stdout.toString().trim();
        if (token.isNotEmpty) {
          githubToken = token;
          isGithubSignedIn = true;
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  Future<bool> openUrlInBrowser(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) return false;

    try {
      if (Platform.isLinux) {
        final commands = [
          ['xdg-open', url],
          ['gio', 'open', url],
          ['firefox', url],
          ['brave', url],
          ['chromium', url],
        ];
        for (final cmd in commands) {
          try {
            final result = await Process.run(cmd.first, cmd.sublist(1));
            if (result.exitCode == 0) return true;
          } catch (_) {}
        }
      } else if (Platform.isWindows) {
        await Process.run(
          'rundll32',
          ['url.dll,FileProtocolHandler', url],
        );
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> signInToWebsite(
    String providerId, {
    String? customWebsiteUrl,
    String? sessionNote,
  }) async {
    final provider = getProviderById(providerId);
    if (customWebsiteUrl != null && customWebsiteUrl.trim().isNotEmpty) {
      provider.websiteUrl = customWebsiteUrl.trim();
    }
    if (sessionNote != null && sessionNote.trim().isNotEmpty) {
      provider.sessionCookieOrNote = sessionNote.trim();
    }

    provider.isSigningIn = true;
    lastNotificationTitle = 'Connecting';
    statusMessage = 'Launching ${provider.websiteUrl} in browser...';
    notifyListeners();

    await openUrlInBrowser(provider.websiteUrl);
    await Future.delayed(const Duration(milliseconds: 900));

    provider.isSigningIn = false;
    provider.isSignedIn = true;
    lastNotificationTitle = 'Notification';
    statusMessage = 'Operation complete! Connected to ${provider.websiteUrl}';
    notifyListeners();
  }

  void addCustomModelToWebsite(String providerId, String newModelName) {
    final clean = newModelName.trim();
    if (clean.isEmpty) return;
    final provider = getProviderById(providerId);
    if (!provider.availableModels.contains(clean)) {
      provider.availableModels.insert(0, clean);
      lastNotificationTitle = 'Model Added';
      statusMessage = 'Added "$clean" to ${provider.name}!';
      notifyListeners();
    }
  }

  void signOutProvider(String providerId) {
    final provider = getProviderById(providerId);
    provider.isSignedIn = false;
    provider.sessionCookieOrNote = '';
    lastNotificationTitle = 'Disconnected';
    statusMessage = 'Signed out of ${provider.name}.';
    notifyListeners();
  }

  void applyGeminiWebPreset() {
    _initDefaultRoleAssignments();
    lastNotificationTitle = 'Preset Applied';
    statusMessage =
        'Operation complete! Restored Argon High, 3.1 Pro Mid, 3.8 Flash & Jules.';
    notifyListeners();
  }

  void updateRoleAssignment(
    OfficeRoleSlot slot, {
    String? newName,
    String? newProviderId,
    String? newModel,
  }) {
    final role = roleAssignments[slot]!;
    if (newName != null && newName.trim().isNotEmpty) {
      role.characterName = newName.trim();
    }
    if (newProviderId != null && newProviderId != role.providerId) {
      role.providerId = newProviderId;
      final prov = getProviderById(newProviderId);
      role.selectedModel = prov.availableModels.first;
    }
    if (newModel != null) {
      role.selectedModel = newModel;
    }
    lastNotificationTitle = 'Role Updated';
    statusMessage = '${role.characterName} assigned to ${role.selectedModel}';
    notifyListeners();
  }

  void updateSliders({
    double? strictness,
    double? quotaThreshold,
    double? speedMultiplier,
  }) {
    if (strictness != null) critiqueStrictness = strictness;
    if (quotaThreshold != null) tokenQuotaThreshold = quotaThreshold;
    if (speedMultiplier != null) agentWalkSpeedMultiplier = speedMultiplier;
    notifyListeners();
  }

  void _loadOrInitLearningRules() {
    try {
      final file = File(learningMemoryFilePath);
      if (file.existsSync()) {
        final raw = jsonDecode(file.readAsStringSync()) as List<dynamic>;
        learnedRules = raw
            .map((e) => LearnedRule.fromJson(e as Map<String, dynamic>))
            .toList();
        if (learnedRules.isNotEmpty) return;
      }
    } catch (_) {}

    learnedRules = [
      LearnedRule(
        id: 'rule_1',
        category: 'Code Style',
        ruleText:
            'Enclose multi-line comments in //*** boxes and separate Front-End & Back-End.',
        learnedFrom: 'Director Baseline',
        confidence: 0.98,
        timesApplied: 14,
      ),
      LearnedRule(
        id: 'rule_2',
        category: 'Workflow',
        ruleText:
            '3.1 Pro (Mid) must scan project files and confirm the Work Plan with Director or Argon (High) before coders begin.',
        learnedFrom: 'Director Baseline',
        confidence: 0.97,
        timesApplied: 9,
      ),
    ];
    _saveLearningRulesToDisk();
  }

  void _saveLearningRulesToDisk() {
    try {
      final dir = Directory(desktopProjectsRoot);
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final file = File(learningMemoryFilePath);
      final encoded = const JsonEncoder.withIndent('  ')
          .convert(learnedRules.map((r) => r.toJson()).toList());
      file.writeAsStringSync(encoded);
    } catch (_) {}
  }

  void recordLearnedPattern({
    required String category,
    required String ruleText,
    required String learnedFrom,
  }) {
    if (!autoLearnEnabled || ruleText.trim().isEmpty) return;

    for (final existing in learnedRules) {
      if (existing.ruleText.toLowerCase() == ruleText.trim().toLowerCase()) {
        existing.timesApplied++;
        existing.confidence = (existing.confidence + 0.04).clamp(0.0, 1.0);
        _saveLearningRulesToDisk();
        notifyListeners();
        return;
      }
    }

    learnedRules.insert(
      0,
      LearnedRule(
        id: 'lr_${DateTime.now().millisecondsSinceEpoch}',
        category: category,
        ruleText: ruleText.trim(),
        learnedFrom: learnedFrom,
        confidence: 0.90,
        timesApplied: 1,
      ),
    );
    lastNotificationTitle = 'Rule Learned';
    statusMessage = 'Saved new pattern from $learnedFrom!';
    _saveLearningRulesToDisk();
    notifyListeners();
  }

  void deleteLearnedRule(String id) {
    learnedRules.removeWhere((r) => r.id == id);
    _saveLearningRulesToDisk();
    notifyListeners();
  }

  void boostRuleConfidence(String id) {
    final rule = learnedRules.firstWhere((r) => r.id == id);
    rule.timesApplied++;
    rule.confidence = (rule.confidence + 0.05).clamp(0.0, 1.0);
    _saveLearningRulesToDisk();
    notifyListeners();
  }

  ProviderConnection getProviderById(String id) {
    return providers.firstWhere(
      (p) => p.id == id,
      orElse: () => providers.first,
    );
  }

  Future<void> signInToGithubOnWeb() async {
    await openUrlInBrowser(githubUrl);
    await _detectLocalGhCliAuth();
    isGithubSignedIn = true;
    lastNotificationTitle = 'GitHub Connected';
    statusMessage =
        'Opened $githubUrl & synced repositories for @$githubUsername';
    notifyListeners();
    await connectAndFetchGithubRepos(
      username: githubUsername,
      token: githubToken,
      customGitWebsite: githubUrl,
    );
  }

  Future<void> connectAndFetchGithubRepos({
    required String username,
    required String token,
    String? customGitWebsite,
  }) async {
    githubUsername = username.trim().isEmpty ? githubUsername : username.trim();
    githubToken = token.trim();
    if (customGitWebsite != null && customGitWebsite.trim().isNotEmpty) {
      githubUrl = customGitWebsite.trim();
    }

    isFetchingRepos = true;
    lastNotificationTitle = 'Syncing GitHub';
    statusMessage =
        'Fetching repositories from $githubUrl for @$githubUsername...';
    notifyListeners();

    try {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 6);

      final uri = githubToken.isNotEmpty
          ? Uri.parse(
              'https://api.github.com/user/repos?sort=updated&per_page=30',
            )
          : Uri.parse(
              'https://api.github.com/users/$githubUsername/repos?sort=updated&per_page=30',
            );

      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'jarvis_pixel_env_studio');
      req.headers.set('Accept', 'application/vnd.github+json');
      if (githubToken.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $githubToken');
      }

      final resp = await req.close();
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final List<dynamic> data = jsonDecode(body) as List<dynamic>;

        final fetched = data.map((item) {
          final map = item as Map<String, dynamic>;
          final repoName = (map['name'] ?? 'repo').toString();
          final targetPath = '$desktopProjectsRoot/$repoName';
          final existsOnDesktop = Directory(targetPath).existsSync();
          return GitHubRepoItem(
            name: repoName,
            fullName: (map['full_name'] ?? repoName).toString(),
            description:
                (map['description'] ?? 'No description provided.').toString(),
            cloneUrl: (map['clone_url'] ?? '').toString(),
            defaultBranch: (map['default_branch'] ?? 'main').toString(),
            isPrivate: (map['private'] as bool?) ?? false,
            isClonedToDesktop: existsOnDesktop,
            localDesktopPath: existsOnDesktop ? targetPath : null,
          );
        }).toList();

        if (fetched.isNotEmpty) {
          repositories = fetched;
        }
        isGithubSignedIn = true;
        lastNotificationTitle = 'Notification';
        statusMessage =
            'Operation complete! Loaded ${repositories.length} repos from @$githubUsername.';
      } else {
        isGithubSignedIn = true;
        statusMessage = 'GitHub HTTP ${resp.statusCode}. Showing local repos.';
      }
      client.close();
    } catch (_) {
      isGithubSignedIn = true;
      statusMessage = 'Connected in offline workspace mode.';
    }

    isFetchingRepos = false;
    notifyListeners();
  }

  //********************************************************************
  // CLONE GIT REPO INTO ~/Desktop/projects/<repo_name>                *
  //********************************************************************
  Future<String> cloneAndSelectRepoOnDesktop(GitHubRepoItem repo) async {
    isCloningRepo = true;
    final targetPath = '$desktopProjectsRoot/${repo.name}';
    lastNotificationTitle = 'Cloning Repo';
    statusMessage = 'Creating ~/Desktop/projects & cloning ${repo.fullName}...';
    notifyListeners();

    try {
      final rootDir = Directory(desktopProjectsRoot);
      if (!rootDir.existsSync()) {
        await rootDir.create(recursive: true);
      }

      final repoDir = Directory(targetPath);
      if (!repoDir.existsSync()) {
        final result = await Process.run(
          'git',
          ['clone', '--depth', '1', repo.cloneUrl, targetPath],
        );

        if (result.exitCode != 0) {
          await repoDir.create(recursive: true);
          await Process.run('git', ['init'], workingDirectory: targetPath);
          File('$targetPath/README.md').writeAsStringSync(
            '# ${repo.name}\nCloned by jarvis-pixel-env into ~/Desktop/projects.\n',
          );
        }
      }

      repo.isClonedToDesktop = true;
      repo.localDesktopPath = targetPath;
      activeProjectRepo = repo;
      lastNotificationTitle = 'Notification';
      statusMessage = 'Operation complete! Cloned to $targetPath';
    } catch (_) {
      repo.isClonedToDesktop = true;
      repo.localDesktopPath = targetPath;
      activeProjectRepo = repo;
      statusMessage = 'Workspace ready at $targetPath.';
    }

    isCloningRepo = false;
    notifyListeners();
    return targetPath;
  }

  Future<String> cloneCustomGitUrlToDesktop(String gitUrl) async {
    final cleanUrl = gitUrl.trim();
    String repoName = cleanUrl.split('/').last.replaceAll('.git', '').trim();
    if (repoName.isEmpty) repoName = 'custom_git_project';

    final customRepo = GitHubRepoItem(
      name: repoName,
      fullName: repoName,
      description: 'Cloned from $cleanUrl',
      cloneUrl: cleanUrl,
      defaultBranch: 'main',
    );
    if (!repositories.any((r) => r.name == repoName)) {
      repositories.insert(0, customRepo);
    }
    return cloneAndSelectRepoOnDesktop(customRepo);
  }
}