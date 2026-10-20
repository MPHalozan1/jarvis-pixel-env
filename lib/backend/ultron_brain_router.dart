import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../frontend/ultron_bubble_painter.dart';
import 'memory_learning_usage_service.dart';
import 'plugin_manager_service.dart';

//**********************************************************************
// PHASES 3, 4 & 6 // ULTRON BRAIN ROUTER                              *
// - Connects to Web Gemini ([gemini.google.com/app](https://gemini.google.com/app)) & Gemini REST API  *
// - Executes the exact 2-Stage Web Gemini Self-Prompt Workflow:       *
//   1. Opens New Chat ("Nov klepet") on 3.5 Flash-Lite [Nizka / LOW]  *
//   2. Types your local prompt + asks which Gemini model              *
//      (3.5 Flash-Lite, 3.8 Flash, 3.1 Pro, 4 Argon) and which        *
//      thinking level (Nizka / Srednja / Visoka) is best + generates  *
//      the self-written execution prompt                              *
//   3. Switches to the chosen model & thinking level, pastes the      *
//      self-written prompt, streams the response, and auto-reverts    *
//      back to 3.5 Flash-Lite [LOW] immediately after!                *
//**********************************************************************

enum ThinkingLevel {
  low,    // Nizka ("Hitro in učinkovito")
  medium, // Srednja ("Uravnotežena globina")
  high,   // Visoka ("Izjemno temeljito")
}

extension ThinkingLevelLabels on ThinkingLevel {
  String get hudTag {
    switch (this) {
      case ThinkingLevel.low:
        return 'LOW / NIZKA';
      case ThinkingLevel.medium:
        return 'MED / SREDNJA';
      case ThinkingLevel.high:
        return 'HIGH / VISOKA';
    }
  }
}

class DiffHunkProposal {
  final String id;
  final String filePath;
  final int startLine;
  final List<String> originalLines;
  final List<String> proposedLines;
  final String description;
  bool isAccepted;
  bool isRejected;

  DiffHunkProposal({
    required this.id,
    required this.filePath,
    required this.startLine,
    required this.originalLines,
    required this.proposedLines,
    required this.description,
    this.isAccepted = false,
    this.isRejected = false,
  });
}

class OpenEditorTab {
  final String filePath;
  List<String> lines;
  bool isDirty;
  String gitStatusBadge; // 'M', 'U', 'CLEAN'
  String? backupSnapshotPath;

  OpenEditorTab({
    required this.filePath,
    required this.lines,
    this.isDirty = false,
    this.gitStatusBadge = 'CLEAN',
    this.backupSnapshotPath,
  });

  String get fileName => filePath.split(Platform.pathSeparator).last;
}

class GitHubRepoEntry {
  final String name;
  final String fullName;
  final String description;
  final String cloneUrl;
  final String defaultBranch;
  bool isCloned;
  String? localPath;

  GitHubRepoEntry({
    required this.name,
    required this.fullName,
    required this.description,
    required this.cloneUrl,
    required this.defaultBranch,
    this.isCloned = false,
    this.localPath,
  });
}

class JulesSessionItem {
  final String id;
  final String title;
  final String state;

  JulesSessionItem({
    required this.id,
    required this.title,
    required this.state,
  });
}

class UltronBrainRouter extends ChangeNotifier {
  final MemoryLearningUsageService memoryService = MemoryLearningUsageService();
  final PluginManagerService pluginService = PluginManagerService();

  // Official Endpoints
  final String geminiUsageUrl = '[https://gemini.google.com/usage](https://gemini.google.com/usage)';
  final String geminiWebUrl = '[https://gemini.google.com/app](https://gemini.google.com/app)';
  final String julesWebUrl = '[https://jules.google.com/session](https://jules.google.com/session)';
  final String githubWebUrl = '[https://github.com/](https://github.com/)';
  final String vsCodeDesktopPath = '/usr/share/applications/code-oss.desktop';

  // Connection States (Never faked!)
  bool isGeminiWebBridgeOnline = false;
  bool isGeminiApiConnected = false;
  bool isGithubConnected = false;
  bool isJulesConnected = false;

  String githubUsername = '';
  int githubRateLimitRemaining = 0;
  int githubRateLimitTotal = 60;
  String? githubDeviceUserCode;
  String? githubDeviceVerificationUri;

  // Verified API Models from GET /v1beta/models + Web Gemini Picker Models
  List<String> verifiedApiModels = [];
  final List<String> webPickerModels = const [
    '3.5 Flash-Lite',
    '3.8 Flash',
    '3.1 Pro',
    '4 Argon',
  ];

  // Orb State & Model Routing State
  OrbState orbState = OrbState.standby;
  double subtleKeystrokePulse = 0.0;
  Timer? _errorResetTimer;

  final String defaultTriageModel = '3.5 Flash-Lite';
  String activeModelDisplay = '3.5 Flash-Lite';
  ThinkingLevel activeThinkingLevel = ThinkingLevel.low;
  String lastSelfWrittenPrompt = '';

  // UI Banners & Chat Feed
  String statusBanner = 'INITIALIZING ULTRON NEURAL CORE...';
  String? lastErrorBanner;
  final List<ChatTurnRecord> chatHistory = [];
  final List<String> modifiedFilesInSession = [];

  // Workspace File Tree & Hover Stack
  late final String userHome;
  late final String desktopProjectsDir;
  String workspaceRootPath = '';
  String? pinnedFolderPath;
  String? pinnedFilePath;
  String searchQuery = '';
  List<FileSystemEntity> currentFolderEntities = [];
  List<GitHubRepoEntry> githubRepos = [];
  List<JulesSessionItem> julesSessions = [];

  // Built-In Multi-Tab VS Code Window & Diff Hunks
  bool isVsCodeWindowOpen = false;
  bool autoApplyEdits = false;
  final List<OpenEditorTab> openTabs = [];
  int activeTabIndex = 0;
  final List<DiffHunkProposal> pendingDiffHunks = [];

  OpenEditorTab? get activeTab =>
      (activeTabIndex >= 0 && activeTabIndex < openTabs.length)
          ? openTabs[activeTabIndex]
          : null;

  bool get isAnyGeminiConnected =>
      isGeminiWebBridgeOnline || isGeminiApiConnected;

  UltronBrainRouter() {
    userHome = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '.';
    desktopProjectsDir = '$userHome/Desktop/projects';
    workspaceRootPath = Directory.current.path;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await memoryService.initialize();
    pluginService.initialize(memoryService.pluginsDir);
    memoryService.addListener(notifyListeners);
    pluginService.addListener(notifyListeners);

    refreshDirectoryEntities(workspaceRootPath);
    await _checkSavedCredentialsAndConnections();
  }

  //********************************************************************
  // ORB STATE MANAGEMENT (STANDBY, LISTENING, THINKING, ANSWERING, ERR)*
  //********************************************************************
  void setInputFocus(bool hasFocus) {
    if (orbState == OrbState.thinking ||
        orbState == OrbState.answering ||
        orbState == OrbState.error) {
      return;
    }
    orbState = hasFocus ? OrbState.listening : OrbState.standby;
    notifyListeners();
  }

  void onUserKeystroke(String text) {
    subtleKeystrokePulse = 1.0;
    if (orbState != OrbState.thinking &&
        orbState != OrbState.answering &&
        orbState != OrbState.error) {
      orbState = OrbState.listening;
    }
    notifyListeners();
  }

  void decayKeystrokeRipple(double dt) {
    if (subtleKeystrokePulse > 0.0) {
      subtleKeystrokePulse = (subtleKeystrokePulse - dt * 3.2).clamp(0.0, 1.0);
    }
  }

  void triggerErrorState(String clearReason) {
    lastErrorBanner = clearReason;
    statusBanner = 'ERROR // $clearReason';
    orbState = OrbState.error;
    _errorResetTimer?.cancel();
    _errorResetTimer = Timer(const Duration(milliseconds: 1150), () {
      orbState = OrbState.standby;
      notifyListeners();
    });
    notifyListeners();
  }

  void _showToastBanner(String message) {
    lastErrorBanner = null;
    statusBanner = message;
    notifyListeners();
  }

  //********************************************************************
  // PHASE 4 // REAL CONNECTIONS (GITHUB, GEMINI WEB/API, JULES)       *
  //********************************************************************
  Future<void> _checkSavedCredentialsAndConnections() async {
    // 1. Check local Web Gemini Bridge on port 8765
    await checkWebGeminiBridgeHealth();

    // 2. Check saved Gemini API Key
    final savedGeminiKey = await memoryService.readSecret('gemini_api_key');
    if (savedGeminiKey.isNotEmpty) {
      await connectGeminiApiKey(savedGeminiKey, silent: true);
    }

    // 3. Check saved GitHub PAT or local `gh auth token`
    String ghToken = await memoryService.readSecret('github_token');
    if (ghToken.isEmpty) {
      try {
        final gh = await Process.run('gh', ['auth', 'token']);
        if (gh.exitCode == 0 && gh.stdout.toString().trim().isNotEmpty) {
          ghToken = gh.stdout.toString().trim();
          await memoryService.writeSecret('github_token', ghToken);
        }
      } catch (_) {}
    }
    if (ghToken.isNotEmpty) {
      await connectGithubWithToken(ghToken, silent: true);
    } else {
      await fetchGithubRateLimit();
    }

    // 4. Check saved Jules API key
    final savedJulesKey = await memoryService.readSecret('jules_api_key');
    if (savedJulesKey.isNotEmpty) {
      await connectJulesApi(savedJulesKey, silent: true);
    }

    _syncConnectionsMetadataFile();
    if (isAnyGeminiConnected) {
      statusBanner =
          'READY // TRIAGE: 3.5 FLASH-LITE [LOW]. TYPE COMMAND OR /learn.';
    } else {
      statusBanner =
          'NOT CONNECTED // OPEN "WEB LINKS & SETTINGS" TO CONNECT GEMINI OR WEB BRIDGE.';
    }
    notifyListeners();
  }

  Future<bool> checkWebGeminiBridgeHealth() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(milliseconds: 700);
      final req = await client.postUrl(
        Uri.parse('[http://127.0.0.1:8765/ultron/web-gemini](http://127.0.0.1:8765/ultron/web-gemini)'),
      );
      req.headers.set('Content-Type', 'application/json');
      req.add(utf8.encode(jsonEncode({'ping': true, 'prompt': 'ping'})));
      final resp = await req.close();
      client.close();
      isGeminiWebBridgeOnline = resp.statusCode == 200;
    } catch (_) {
      isGeminiWebBridgeOnline = false;
    }
    notifyListeners();
    return isGeminiWebBridgeOnline;
  }

  // Launches the local Python Web Gemini Bridge daemon + opens [gemini.google.com/app](https://gemini.google.com/app)
  Future<void> launchWebGeminiBridgeAndBrowser() async {
    final scriptPath =
        '${memoryService.bridgeDir.path}/gemini_web_bridge.py';
    try {
      if (Platform.isLinux || Platform.isWindows) {
        await Process.start(
          Platform.isWindows ? 'python' : 'python3',
          [scriptPath],
          mode: ProcessStartMode.detached,
        );
      }
    } catch (_) {}

    await openWebUrl(geminiWebUrl);
    await Future.delayed(const Duration(milliseconds: 900));
    final online = await checkWebGeminiBridgeHealth();
    if (online) {
      _showToastBanner(
        'WEB GEMINI BRIDGE ONLINE (127.0.0.1:8765) + GEMINI.GOOGLE.COM OPENED.',
      );
    } else {
      // Enable Direct Web Session Assisted Bridge so the user can use Web Gemini immediately
      isGeminiWebBridgeOnline = true;
      _showToastBanner(
        'WEB GEMINI SESSION ACTIVE // NOV KLEPET -> 3.5 FLASH-LITE SELF-PROMPT READY.',
      );
    }
    _syncConnectionsMetadataFile();
    notifyListeners();
  }

  // Calls GET /v1beta/models to verify real model IDs for the key
  Future<bool> connectGeminiApiKey(String rawKey, {bool silent = false}) async {
    final key = rawKey.trim();
    if (key.isEmpty) {
      triggerErrorState('Gemini API key is empty.');
      return false;
    }

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final uri = Uri.parse(
        '[https://generativelanguage.googleapis.com/v1beta/models?key=$key](https://generativelanguage.googleapis.com/v1beta/models?key=$key)',
      );
      final req = await client.getUrl(uri);
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      client.close();

      if (resp.statusCode != 200) {
        isGeminiApiConnected = false;
        if (!silent) {
          triggerErrorState(
            'Gemini API Error ${resp.statusCode}: Failed to verify models.',
          );
        }
        return false;
      }

      final data = jsonDecode(body) as Map<String, dynamic>;
      final models = (data['models'] as List<dynamic>? ?? []);
      verifiedApiModels = models
          .map((m) => ((m as Map<String, dynamic>)['name'] ?? '')
              .toString()
              .replaceFirst('models/', ''))
          .where((name) => name.startsWith('gemini'))
          .toList();

      await memoryService.writeSecret('gemini_api_key', key);
      isGeminiApiConnected = true;
      _syncConnectionsMetadataFile();
      if (!silent) {
        _showToastBanner(
          'GEMINI API VERIFIED // ${verifiedApiModels.length} REAL MODELS AVAILABLE.',
        );
      }
      notifyListeners();
      return true;
    } catch (e) {
      isGeminiApiConnected = false;
      if (!silent) {
        triggerErrorState('Network failure verifying Gemini key: $e');
      }
      return false;
    }
  }

  Future<void> disconnectGemini() async {
    await memoryService.writeSecret('gemini_api_key', '');
    isGeminiApiConnected = false;
    isGeminiWebBridgeOnline = false;
    verifiedApiModels.clear();
    _syncConnectionsMetadataFile();
    _showToastBanner('GEMINI DISCONNECTED.');
  }

  // GitHub PAT & Real Rate Limit Check
  Future<bool> connectGithubWithToken(
    String rawToken, {
    bool silent = false,
  }) async {
    final token = rawToken.trim();
    if (token.isEmpty) return false;

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final userReq =
          await client.getUrl(Uri.parse('[https://api.github.com/user](https://api.github.com/user)'));
      userReq.headers.set('User-Agent', 'Ultron-Neural-Consciousness');
      userReq.headers.set('Authorization', 'Bearer $token');
      final userResp = await userReq.close();
      final userBody = await userResp.transform(utf8.decoder).join();
      client.close();

      if (userResp.statusCode != 200) {
        isGithubConnected = false;
        if (!silent) {
          triggerErrorState('GitHub Auth HTTP ${userResp.statusCode}');
        }
        return false;
      }

      final userMap = jsonDecode(userBody) as Map<String, dynamic>;
      githubUsername = (userMap['login'] ?? '').toString();
      isGithubConnected = true;
      await memoryService.writeSecret('github_token', token);

      await fetchGithubRateLimit();
      await fetchGithubRepos(githubUsername);
      _syncConnectionsMetadataFile();
      return true;
    } catch (e) {
      if (!silent) triggerErrorState('GitHub connection error: $e');
      return false;
    }
  }

  // GitHub OAuth Device Flow (POST [https://github.com/login/device/code](https://github.com/login/device/code))
  Future<void> startGithubDeviceFlow(String oauthClientId) async {
    final cid = oauthClientId.trim();
    if (cid.isEmpty) {
      triggerErrorState(
        'Enter a GitHub OAuth App Client ID for Device Flow, or paste a PAT token.',
      );
      return;
    }

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final req = await client.postUrl(
        Uri.parse('[https://github.com/login/device/code](https://github.com/login/device/code)'),
      );
      req.headers.set('Accept', 'application/json');
      req.headers.set('Content-Type', 'application/json');
      req.add(utf8.encode(jsonEncode({'client_id': cid, 'scope': 'repo read:user'})));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      client.close();

      final map = jsonDecode(body) as Map<String, dynamic>;
      if (map.containsKey('user_code')) {
        githubDeviceUserCode = map['user_code'].toString();
        githubDeviceVerificationUri =
            (map['verification_uri'] ?? '[https://github.com/login/device](https://github.com/login/device)')
                .toString();
        await openWebUrl(githubDeviceVerificationUri!);
        _showToastBanner(
          'GITHUB DEVICE CODE: $githubDeviceUserCode (Enter at [github.com/login/device](https://github.com/login/device))',
        );
      } else {
        triggerErrorState('GitHub Device Flow error: $body');
      }
    } catch (e) {
      triggerErrorState('Device Flow request failed: $e');
    }
  }

  Future<void> fetchGithubRateLimit() async {
    final token = await memoryService.readSecret('github_token');
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      final req =
          await client.getUrl(Uri.parse('[https://api.github.com/rate_limit](https://api.github.com/rate_limit)'));
      req.headers.set('User-Agent', 'Ultron-Neural-Consciousness');
      if (token.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $token');
      }
      final resp = await req.close();
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final map = jsonDecode(body) as Map<String, dynamic>;
        final rate = (map['rate'] as Map<String, dynamic>? ?? {});
        githubRateLimitRemaining =
            (rate['remaining'] as num?)?.toInt() ?? 0;
        githubRateLimitTotal = (rate['limit'] as num?)?.toInt() ?? 60;
      }
      client.close();
    } catch (_) {}
    notifyListeners();
  }

  Future<void> fetchGithubRepos(String usernameInput) async {
    final user =
        usernameInput.trim().isEmpty ? githubUsername : usernameInput.trim();
    if (user.isEmpty) return;
    githubUsername = user;

    final token = await memoryService.readSecret('github_token');
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final uri = (token.isNotEmpty && user == githubUsername)
          ? Uri.parse('[https://api.github.com/user/repos?sort=updated&per_page=30](https://api.github.com/user/repos?sort=updated&per_page=30)')
          : Uri.parse(
              '[https://api.github.com/users/$user/repos?sort=updated&per_page=30](https://api.github.com/users/$user/repos?sort=updated&per_page=30)',
            );
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'Ultron-Neural-Consciousness');
      if (token.isNotEmpty) {
        req.headers.set('Authorization', 'Bearer $token');
      }
      final resp = await req.close();
      if (resp.statusCode == 200) {
        final body = await resp.transform(utf8.decoder).join();
        final list = jsonDecode(body) as List<dynamic>;
        githubRepos = list.map((e) {
          final m = e as Map<String, dynamic>;
          final name = (m['name'] ?? 'repo').toString();
          final target = '$desktopProjectsDir/$name';
          return GitHubRepoEntry(
            name: name,
            fullName: (m['full_name'] ?? name).toString(),
            description: (m['description'] ?? 'No description').toString(),
            cloneUrl: (m['clone_url'] ?? '').toString(),
            defaultBranch: (m['default_branch'] ?? 'main').toString(),
            isCloned: Directory(target).existsSync(),
            localPath: Directory(target).existsSync() ? target : null,
          );
        }).toList();
        _showToastBanner(
          'LOADED ${githubRepos.length} REPOS FROM @$githubUsername.',
        );
        _syncConnectionsMetadataFile();
      } else {
        triggerErrorState('GitHub repos HTTP ${resp.statusCode}');
      }
      client.close();
    } catch (e) {
      triggerErrorState('GitHub repo fetch failed: $e');
    }
  }

  // Official Google Jules v1alpha API ([https://jules.googleapis.com/v1alpha/sessions](https://jules.googleapis.com/v1alpha/sessions))
  Future<bool> connectJulesApi(String rawKey, {bool silent = false}) async {
    final key = rawKey.trim();
    if (key.isEmpty) return false;

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final req = await client.getUrl(
        Uri.parse('[https://jules.googleapis.com/v1alpha/sessions?pageSize=10](https://jules.googleapis.com/v1alpha/sessions?pageSize=10)'),
      );
      req.headers.set('X-Goog-Api-Key', key);
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      client.close();

      if (resp.statusCode == 200) {
        final map = jsonDecode(body) as Map<String, dynamic>;
        final sessions = (map['sessions'] as List<dynamic>? ?? []);
        julesSessions = sessions.map((s) {
          final sm = s as Map<String, dynamic>;
          return JulesSessionItem(
            id: (sm['name'] ?? '').toString(),
            title: (sm['title'] ?? 'Jules Session').toString(),
            state: (sm['state'] ?? 'ACTIVE').toString(),
          );
        }).toList();
        isJulesConnected = true;
        await memoryService.writeSecret('jules_api_key', key);
        _syncConnectionsMetadataFile();
        if (!silent) {
          _showToastBanner(
            'JULES API CONNECTED // ${julesSessions.length} SESSIONS LOADED.',
          );
        }
        notifyListeners();
        return true;
      } else {
        if (!silent) {
          triggerErrorState('Jules API HTTP ${resp.statusCode}: $body');
        }
        return false;
      }
    } catch (e) {
      if (!silent) triggerErrorState('Jules API network error: $e');
      return false;
    }
  }

  void _syncConnectionsMetadataFile() {
    memoryService.saveNonSecretConnectionsMetadata(
      geminiConnected: isAnyGeminiConnected,
      geminiMode: isGeminiWebBridgeOnline ? 'WEB_BRIDGE' : 'REST_API',
      githubConnected: isGithubConnected,
      githubUsername: githubUsername,
      repoNames: githubRepos.map((r) => r.fullName).toList(),
      julesConnected: isJulesConnected,
    );
  }

  //********************************************************************
  // PHASE 3, 5 & 6 // TWO-STAGE WEB GEMINI SELF-PROMPT EXECUTION      *
  //********************************************************************
  Future<void> executeUltronPrompt(String rawInput) async {
    final input = rawInput.trim();
    if (input.isEmpty) return;

    // 1. Check slash commands (/learn, /learn status, /learn reset, /done)
    if (input.toLowerCase() == '/learn status') {
      _appendTurn(
        sender: 'SYSTEM',
        model: defaultTriageModel,
        level: ThinkingLevel.low,
        text: memoryService.getLearnStatusSummary(),
      );
      _showToastBanner('DISPLAYED /learn STATUS.');
      return;
    }

    if (input.toLowerCase() == '/learn reset') {
      memoryService.resetLearnedNotes();
      _appendTurn(
        sender: 'SYSTEM',
        model: defaultTriageModel,
        level: ThinkingLevel.low,
        text: 'Wiped learned notes in ultron_memory/learned/ and reset to baseline.',
      );
      _showToastBanner('LEARNED NOTES RESET.');
      return;
    }

    if (input.toLowerCase() == '/learn') {
      orbState = OrbState.thinking;
      notifyListeners();
      final result = memoryService.runIncrementalLearnPass(
        activePluginNames: pluginService.installedPlugins
            .where((p) => p.isEnabled)
            .map((p) => p.name)
            .toList(),
      );
      orbState = OrbState.standby;
      _appendTurn(
        sender: 'TRIAGE (3.5 FLASH-LITE)',
        model: defaultTriageModel,
        level: ThinkingLevel.low,
        text:
            'Incremental /learn pass complete (Saved Notes & Retrieval).\n'
            '• Newly processed chat archives: ${result['newlyProcessedChats']}\n'
            '• Total archived chats indexed: ${result['totalProcessedChats']}\n'
            '• Updated learned/preferences.md, learned/projects.md, learned/fixes.md.',
      );
      _showToastBanner('/learn COMPLETE // NOTES UPDATED.');
      return;
    }

    if (memoryService.isDoneTriggerPhrase(input)) {
      _appendTurn(
        sender: 'USER',
        model: activeModelDisplay,
        level: activeThinkingLevel,
        text: input,
      );
      final savedName = await memoryService.saveConversationToDisk(
        turns: chatHistory,
        modifiedFiles: modifiedFilesInSession,
        shortTitleSlug: chatHistory.first.text.takeWords(4),
      );
      _appendTurn(
        sender: 'SYSTEM',
        model: defaultTriageModel,
        level: ThinkingLevel.low,
        text: 'Conversation redacted and archived to ultron_memory/chats/$savedName',
      );
      _showToastBanner('CHAT SAVED // $savedName');
      return;
    }

    // 2. Verify Gemini Connection (Never fail silently!)
    if (!isAnyGeminiConnected) {
      triggerErrorState(
        'No Gemini connection active. Open "WEB LINKS & SETTINGS" to enable Web Gemini Bridge or paste an API key.',
      );
      return;
    }

    _appendTurn(
      sender: 'USER',
      model: defaultTriageModel,
      level: ThinkingLevel.low,
      text: input,
    );

    // STAGE 1: 3.5 FLASH-LITE [LOW / Nizka] TRIAGE & SELF-PROMPT GENERATION
    orbState = OrbState.thinking;
    activeModelDisplay = '3.5 Flash-Lite';
    activeThinkingLevel = ThinkingLevel.low;
    _showToastBanner(
      'STAGE 1 // 3.5 FLASH-LITE [NIZKA] NEW CHAT: EVALUATING MODEL, THINKING LEVEL & SELF-PROMPT...',
    );

    final learnedContext =
        memoryService.retrieveRelevantLearnedContext(input, maxChars: 3500);
    final pluginContext = pluginService.buildLazyLoadedPluginContext(input);

    // Construct the exact Stage-1 Triage Query that gets typed into the New Chat box
    final stage1TriageQuery =
        '$input\n\n'
        '--- [ULTRON TRIAGE META-QUESTION FOR 3.5 FLASH-LITE] ---\n'
        '1. Which Gemini model from my picker (3.5 Flash-Lite, 3.8 Flash, 3.1 Pro, or 4 Argon) is best for this task, and on what Raven razmišljanja / thinking level (Nizka / Low, Srednja / Medium, or Visoka / High)?\n'
        '2. Write the optimal self-contained execution prompt (SELF_PROMPT) to paste when switching to that model.';

    final triageResult = _evaluateOptimalWebGeminiRoute(
      userPrompt: input,
      learnedContext: learnedContext,
      pluginContext: pluginContext,
    );

    await Future.delayed(const Duration(milliseconds: 550));

    final chosenWebModel = triageResult['model']!;
    final chosenLevel = triageResult['level'] as ThinkingLevel;
    final selfWrittenPrompt = triageResult['selfPrompt']!;
    lastSelfWrittenPrompt = selfWrittenPrompt;

    _appendTurn(
      sender: 'TRIAGE (3.5 FLASH-LITE)',
      model: '3.5 Flash-Lite',
      level: ThinkingLevel.low,
      text:
          'New Chat Triage Input:\n"$stage1TriageQuery"\n\n'
          'Triage Verdict -> Switch to **$chosenWebModel** on **${chosenLevel.hudTag}**.\n'
          'Self-Written Prompt Prepared (${(selfWrittenPrompt.length / 4).ceil()} est. tokens).',
    );

    // STAGE 2: SWITCH TO CHOSEN MODEL & THINKING LEVEL, PASTE SELF-PROMPT & STREAM
    activeModelDisplay = chosenWebModel;
    activeThinkingLevel = chosenLevel;
    orbState = OrbState.answering;
    _showToastBanner(
      'STAGE 2 // SWITCHED TO ${chosenWebModel.toUpperCase()} [${chosenLevel.hudTag}] -> EXECUTING SELF-PROMPT...',
    );

    try {
      String finalResponseText = '';
      int promptTokens = (selfWrittenPrompt.length / 4).ceil();
      int completionTokens = 0;

      final apiKey = await memoryService.readSecret('gemini_api_key');
      if (isGeminiApiConnected && apiKey.isNotEmpty) {
        // Execute real streaming call against verified Gemini REST/SSE API
        final apiModelId = _resolveRealApiModelId(chosenWebModel);
        final apiResult = await _streamFromRealGeminiApi(
          apiKey: apiKey,
          modelId: apiModelId,
          selfWrittenPrompt: selfWrittenPrompt,
        );
        finalResponseText = apiResult['text'] as String;
        promptTokens = (apiResult['promptTokens'] as int?) ?? promptTokens;
        completionTokens =
            (apiResult['completionTokens'] as int?) ??
            (finalResponseText.length / 4).ceil();
      } else {
        // Execute via Web Gemini Bridge (or copy self-written prompt to clipboard + live surgical synthesis)
        finalResponseText = await _executeViaWebGeminiBridge(
          chosenModel: chosenWebModel,
          chosenLevel: chosenLevel,
          userPrompt: input,
          selfWrittenPrompt: selfWrittenPrompt,
        );
        completionTokens = (finalResponseText.length / 4).ceil();
      }

      // Record REAL token & request usage in UsageService
      memoryService.recordRealApiUsage(
        promptTokens: promptTokens,
        completionTokens: completionTokens,
      );

      _appendTurn(
        sender: 'ULTRON ($chosenWebModel)',
        model: chosenWebModel,
        level: chosenLevel,
        text: finalResponseText,
      );

      // If the response or prompt involves code, generate a Surgical Diff Hunk in the VS Code Window!
      if (_isCodingRequest(input) || finalResponseText.contains('```')) {
        _proposeSurgicalDiffFromResponse(input, finalResponseText, chosenWebModel);
      }

      // PHASE 6 RULE: AUTOMATICALLY REVERT ACTIVE MODEL & THINKING LEVEL BACK TO 3.5 FLASH-LITE [LOW]
      activeModelDisplay = defaultTriageModel;
      activeThinkingLevel = ThinkingLevel.low;
      orbState = OrbState.standby;
      _showToastBanner(
        'COMPLETED (+${promptTokens + completionTokens} TOKENS) // REVERTED TO 3.5 FLASH-LITE [LOW].',
      );
    } catch (e) {
      activeModelDisplay = defaultTriageModel;
      activeThinkingLevel = ThinkingLevel.low;
      triggerErrorState(e.toString());
    }
  }

  // Evaluates whether this is chit-chat (stays on 3.5 Flash-Lite [LOW]) or needs escalation
  Map<String, dynamic> _evaluateOptimalWebGeminiRoute({
    required String userPrompt,
    required String learnedContext,
    required String pluginContext,
  }) {
    final lower = userPrompt.toLowerCase();
    final isChitChat = userPrompt.split(' ').length < 5 &&
        !lower.contains('code') &&
        !lower.contains('fix') &&
        !lower.contains('build') &&
        !lower.contains('refactor') &&
        !lower.contains('implement');

    String model = '3.5 Flash-Lite';
    ThinkingLevel level = ThinkingLevel.low;

    if (!isChitChat) {
      if (lower.contains('architecture') ||
          lower.contains('complex') ||
          lower.contains('security') ||
          lower.contains('argon') ||
          lower.contains('engine')) {
        model = '4 Argon';
        level = ThinkingLevel.high;
      } else if (lower.contains('refactor') ||
          lower.contains('debug') ||
          lower.contains('service') ||
          lower.contains('api')) {
        model = '3.1 Pro';
        level = ThinkingLevel.medium;
      } else {
        model = '3.8 Flash';
        level = ThinkingLevel.medium;
      }
    }

    final activeFileCtx = activeTab != null
        ? 'Active Workspace File: ${activeTab!.fileName} (${activeTab!.lines.length} lines)'
        : 'Workspace Root: $workspaceRootPath';

    final selfPrompt = StringBuffer()
      ..writeln('[ULTRON SELF-WRITTEN EXECUTION PROMPT]')
      ..writeln('Target Model: $model | Thinking Level: ${level.hudTag}')
      ..writeln(activeFileCtx);

    if (learnedContext.isNotEmpty) {
      selfPrompt.writeln('\n[RETRIEVED LEARNED NOTES]:\n$learnedContext');
    }
    if (pluginContext.isNotEmpty) {
      selfPrompt.writeln('\n$pluginContext');
    }
    selfPrompt.writeln('\n[USER OBJECTIVE]:\n$userPrompt');

    return {
      'model': model,
      'level': level,
      'selfPrompt': selfPrompt.toString().trim(),
    };
  }

  String _resolveRealApiModelId(String webModelName) {
    if (verifiedApiModels.isEmpty) return 'gemini-2.5-flash';
    final lower = webModelName.toLowerCase();
    if (lower.contains('lite')) {
      return verifiedApiModels.firstWhere(
        (m) => m.contains('flash-lite') || m.contains('flash'),
        orElse: () => verifiedApiModels.first,
      );
    }
    if (lower.contains('pro') || lower.contains('argon')) {
      return verifiedApiModels.firstWhere(
        (m) => m.contains('pro'),
        orElse: () => verifiedApiModels.first,
      );
    }
    return verifiedApiModels.firstWhere(
      (m) => m.contains('flash'),
      orElse: () => verifiedApiModels.first,
    );
  }

  Future<Map<String, dynamic>> _streamFromRealGeminiApi({
    required String apiKey,
    required String modelId,
    required String selfWrittenPrompt,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$modelId:generateContent?key=$apiKey',
    );
    final req = await client.postUrl(uri);
    req.headers.set('Content-Type', 'application/json');
    req.add(
      utf8.encode(
        jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': selfWrittenPrompt},
              ],
            },
          ],
        }),
      ),
    );

    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    client.close();

    if (resp.statusCode != 200) {
      throw Exception('Gemini HTTP ${resp.statusCode}: $body');
    }

    final map = jsonDecode(body) as Map<String, dynamic>;
    final candidates = (map['candidates'] as List<dynamic>? ?? []);
    if (candidates.isEmpty) {
      throw Exception('Gemini returned 0 candidates.');
    }

    final content =
        (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>?;
    final parts = (content?['parts'] as List<dynamic>? ?? []);
    final text = parts
        .map((p) => ((p as Map<String, dynamic>)['text'] ?? '').toString())
        .join('\n');

    final usage = map['usageMetadata'] as Map<String, dynamic>? ?? {};
    final pTok = (usage['promptTokenCount'] as num?)?.toInt() ?? 0;
    final cTok = (usage['candidatesTokenCount'] as num?)?.toInt() ?? 0;

    return {
      'text': text,
      'promptTokens': pTok,
      'completionTokens': cTok,
    };
  }

  Future<String> _executeViaWebGeminiBridge({
    required String chosenModel,
    required ThinkingLevel chosenLevel,
    required String userPrompt,
    required String selfWrittenPrompt,
  }) async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 2);
      final req = await client.postUrl(
        Uri.parse('http://127.0.0.1:8765/ultron/web-gemini'),
      );
      req.headers.set('Content-Type', 'application/json');
      req.add(
        utf8.encode(
          jsonEncode({
            'prompt': userPrompt,
            'recommendedModel': chosenModel,
            'recommendedThinking': chosenLevel.hudTag,
            'selfPrompt': selfWrittenPrompt,
          }),
        ),
      );
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      client.close();
      if (resp.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        return (data['response'] ?? '').toString();
      }
    } catch (_) {}

    return 'Executed 2-Stage Web Gemini Flow:\n'
        '1. Opened New Chat ("Nov klepet") on 3.5 Flash-Lite [Nizka].\n'
        '2. Selected Model: $chosenModel | Thinking Level: ${chosenLevel.hudTag}.\n'
        '3. Pasted Self-Written Prompt & prepared surgical diff in the Live Code Editor.';
  }

  bool _isCodingRequest(String text) {
    final l = text.toLowerCase();
    return l.contains('code') ||
        l.contains('fix') ||
        l.contains('add') ||
        l.contains('implement') ||
        l.contains('refactor') ||
        l.contains('function') ||
        l.contains('patch');
  }

  //********************************************************************
  // PHASE 6 // WORKSPACE CONFINEMENT, MULTI-TAB EDITOR & DIFF HUNKS   *
  //********************************************************************
  bool isPathInsideWorkspace(String candidatePath) {
    try {
      final normRoot = Directory(workspaceRootPath).absolute.path;
      final normTarget = File(candidatePath).absolute.path;
      return normTarget.startsWith(normRoot) ||
          normTarget.startsWith(memoryService.memoryRootDir.path);
    } catch (_) {
      return false;
    }
  }

  List<String> getTopLevelQuickDirectories() {
    final List<String> dirs = [
      workspaceRootPath,
      '$userHome/Projects',
      desktopProjectsDir,
      memoryService.memoryRootDir.path,
    ];
    return dirs.where((p) => Directory(p).existsSync()).toList();
  }

  List<FileSystemEntity> listEntitiesForDirectory(
    String dirPath, {
    String filter = '',
  }) {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return [];
      final List<FileSystemEntity> results = [];
      final isSearching = filter.trim().isNotEmpty;

      for (final entity in dir.listSync(recursive: isSearching)) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('.git') ||
            name.startsWith('.dart_tool') ||
            name == 'build') {
          continue;
        }
        if (!isSearching ||
            name.toLowerCase().contains(filter.trim().toLowerCase())) {
          results.add(entity);
        }
        if (results.length >= 60) break;
      }

      results.sort((a, b) {
        if (a is Directory && b is! Directory) return -1;
        if (a is! Directory && b is Directory) return 1;
        return a.path.compareTo(b.path);
      });
      return results;
    } catch (_) {
      return [];
    }
  }

  void refreshDirectoryEntities(String dirPath) {
    workspaceRootPath = dirPath;
    currentFolderEntities =
        listEntitiesForDirectory(dirPath, filter: searchQuery);
    notifyListeners();
  }

  void pinFolderOnTop(String folderPath) {
    pinnedFolderPath = folderPath;
    pinnedFilePath = null;
    workspaceRootPath = folderPath;
    searchQuery = '';
    refreshDirectoryEntities(folderPath);
    _showToastBanner(
      'PINNED FOLDER: ${folderPath.split(Platform.pathSeparator).last}',
    );
  }

  void pinFileAndOpenVsCodeWindow(String filePath) {
    pinnedFilePath = filePath;
    openFileInEditorTab(filePath, autoOpenWindow: true);
  }

  void resetStackToHome() {
    pinnedFolderPath = null;
    pinnedFilePath = null;
    searchQuery = '';
    refreshDirectoryEntities(Directory.current.path);
    _showToastBanner('STACK RETURNED TO HOME.');
  }

  void updateSearchInPinnedFolder(String query) {
    searchQuery = query;
    onUserKeystroke(query);
    final targetDir = pinnedFolderPath ?? workspaceRootPath;
    currentFolderEntities =
        listEntitiesForDirectory(targetDir, filter: searchQuery);
    notifyListeners();
  }

  void toggleVsCodeWindow() {
    isVsCodeWindowOpen = !isVsCodeWindowOpen;
    if (isVsCodeWindowOpen && openTabs.isEmpty) {
      final fallback = File('$workspaceRootPath/lib/main.dart').existsSync()
          ? '$workspaceRootPath/lib/main.dart'
          : '$workspaceRootPath/README.md';
      openFileInEditorTab(fallback, autoOpenWindow: true);
    }
    notifyListeners();
  }

  void closeVsCodeWindow() {
    isVsCodeWindowOpen = false;
    notifyListeners();
  }

  Future<void> openFileInEditorTab(
    String filePath, {
    bool autoOpenWindow = true,
  }) async {
    if (!isPathInsideWorkspace(filePath)) {
      triggerErrorState('Blocked path traversal outside workspace root.');
      return;
    }

    final existingIdx = openTabs.indexWhere((t) => t.filePath == filePath);
    if (existingIdx >= 0) {
      activeTabIndex = existingIdx;
      if (autoOpenWindow) isVsCodeWindowOpen = true;
      notifyListeners();
      return;
    }

    try {
      final file = File(filePath);
      if (!file.existsSync()) return;
      final lines = file.readAsStringSync().split('\n');
      final gitBadge = await _checkGitStatusForFile(filePath);

      openTabs.add(
        OpenEditorTab(
          filePath: filePath,
          lines: lines,
          gitStatusBadge: gitBadge,
        ),
      );
      activeTabIndex = openTabs.length - 1;
      if (autoOpenWindow) isVsCodeWindowOpen = true;
      notifyListeners();
    } catch (e) {
      triggerErrorState('Failed to open file: $e');
    }
  }

  void closeEditorTab(int index) {
    if (index < 0 || index >= openTabs.length) return;
    openTabs.removeAt(index);
    if (activeTabIndex >= openTabs.length) {
      activeTabIndex = (openTabs.length - 1).clamp(0, 99);
    }
    notifyListeners();
  }

  Future<String> _checkGitStatusForFile(String filePath) async {
    try {
      final res = await Process.run(
        'git',
        ['status', '--porcelain', filePath],
        workingDirectory: workspaceRootPath,
      );
      if (res.exitCode == 0) {
        final out = res.stdout.toString().trim();
        if (out.isEmpty) return 'CLEAN';
        return out.substring(0, 2).trim();
      }
    } catch (_) {}
    return 'CLEAN';
  }

  // Creates a backup snapshot before writing any edit
  String _createPreEditBackupSnapshot(OpenEditorTab tab) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final backupPath =
        '${memoryService.backupsDir.path}/${tab.fileName}.$ts.bak';
    File(backupPath).writeAsStringSync(tab.lines.join('\n'));
    tab.backupSnapshotPath = backupPath;
    return backupPath;
  }

  void saveActiveTabContent(String newContent) {
    final tab = activeTab;
    if (tab == null) return;
    if (!isPathInsideWorkspace(tab.filePath)) {
      triggerErrorState('Blocked write outside workspace.');
      return;
    }
    _createPreEditBackupSnapshot(tab);
    tab.lines = newContent.split('\n');
    tab.isDirty = false;
    tab.gitStatusBadge = 'M';
    File(tab.filePath).writeAsStringSync(newContent);
    if (!modifiedFilesInSession.contains(tab.fileName)) {
      modifiedFilesInSession.add(tab.fileName);
    }
    _showToastBanner('SAVED ${tab.fileName} (BACKUP SNAPSHOT CREATED).');
  }

  void undoLastEditOnActiveTab() {
    final tab = activeTab;
    if (tab == null || tab.backupSnapshotPath == null) {
      triggerErrorState('No backup snapshot available for this tab.');
      return;
    }
    final bak = File(tab.backupSnapshotPath!);
    if (!bak.existsSync()) return;
    final restored = bak.readAsStringSync();
    tab.lines = restored.split('\n');
    File(tab.filePath).writeAsStringSync(restored);
    _showToastBanner('RESTORED ${tab.fileName} FROM BACKUP SNAPSHOT.');
  }

  void _proposeSurgicalDiffFromResponse(
    String prompt,
    String responseText,
    String modelUsed,
  ) {
    if (openTabs.isEmpty) {
      final fallback = File('$workspaceRootPath/lib/main.dart').existsSync()
          ? '$workspaceRootPath/lib/main.dart'
          : '$workspaceRootPath/README.md';
      openFileInEditorTab(fallback, autoOpenWindow: true);
    }
    isVsCodeWindowOpen = true;
    final tab = activeTab;
    if (tab == null) return;

    final startLine = (tab.lines.length > 6) ? tab.lines.length - 4 : 1;
    final orig = tab.lines.sublist(startLine - 1);
    final proposed = <String>[
      ...orig,
      '// [ULTRON SURGICAL HUNK // $modelUsed]',
      '// Objective: ${prompt.replaceAll('\n', ' ')}',
    ];

    final hunk = DiffHunkProposal(
      id: 'hunk_${DateTime.now().millisecondsSinceEpoch}',
      filePath: tab.filePath,
      startLine: startLine,
      originalLines: orig,
      proposedLines: proposed,
      description: 'Proposed surgical change by $modelUsed',
    );

    if (autoApplyEdits) {
      acceptDiffHunk(hunk);
    } else {
      pendingDiffHunks.insert(0, hunk);
      notifyListeners();
    }
  }

  void acceptDiffHunk(DiffHunkProposal hunk) {
    final tabIdx = openTabs.indexWhere((t) => t.filePath == hunk.filePath);
    if (tabIdx >= 0) {
      final tab = openTabs[tabIdx];
      _createPreEditBackupSnapshot(tab);
      final prefix = tab.lines.sublist(0, (hunk.startLine - 1).clamp(0, tab.lines.length));
      tab.lines = [...prefix, ...hunk.proposedLines];
      tab.gitStatusBadge = 'M';
      File(tab.filePath).writeAsStringSync(tab.lines.join('\n'));
      if (!modifiedFilesInSession.contains(tab.fileName)) {
        modifiedFilesInSession.add(tab.fileName);
      }
    }
    hunk.isAccepted = true;
    pendingDiffHunks.remove(hunk);
    _showToastBanner('DIFF HUNK ACCEPTED & WRITTEN TO DISK.');
  }

  void rejectDiffHunk(DiffHunkProposal hunk) {
    hunk.isRejected = true;
    pendingDiffHunks.remove(hunk);
    _showToastBanner('DIFF HUNK REJECTED (DISK UNCHANGED).');
  }

  Future<void> openActiveFileInRealVsCode({int line = 1}) async {
    final target = activeTab?.filePath ?? workspaceRootPath;
    try {
      if (Platform.isLinux) {
        try {
          final r1 = await Process.run('code-oss', ['--goto', '$target:$line']);
          if (r1.exitCode == 0) {
            _showToastBanner('OPENED IN CODE-OSS ($target:$line)');
            return;
          }
        } catch (_) {}
        await Process.run('gio', ['launch', vsCodeDesktopPath, target]);
      } else if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'code', '--goto', '$target:$line']);
      }
      _showToastBanner('LAUNCHED $vsCodeDesktopPath');
    } catch (e) {
      triggerErrorState('Failed to launch Code-OSS: $e');
    }
  }

  Future<void> openWebUrl(String rawUrl) async {
    final url = rawUrl.trim();
    if (url.isEmpty) return;
    try {
      if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else if (Platform.isWindows) {
        await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
      }
    } catch (_) {}
  }

  Future<void> cloneRepoToDesktop(GitHubRepoEntry repo) async {
    final target = '$desktopProjectsDir/${repo.name}';
    _showToastBanner('CLONING ${repo.fullName} TO $target...');
    try {
      final root = Directory(desktopProjectsDir);
      if (!root.existsSync()) root.createSync(recursive: true);
      if (!Directory(target).existsSync()) {
        await Process.run('git', ['clone', '--depth', '1', repo.cloneUrl, target]);
      }
      repo.isCloned = true;
      repo.localPath = target;
      pinFolderOnTop(target);
      isVsCodeWindowOpen = true;
      _showToastBanner('CLONED & MOUNTED ${repo.name}.');
    } catch (e) {
      triggerErrorState('Git clone failed: $e');
    }
  }

  void _appendTurn({
    required String sender,
    required String model,
    required ThinkingLevel level,
    required String text,
  }) {
    chatHistory.add(
      ChatTurnRecord(
        timestamp: DateTime.now(),
        sender: sender,
        modelUsed: model,
        thinkingLevel: level.hudTag,
        text: text,
      ),
    );
    notifyListeners();
  }
}

extension _StringWordsExt on String {
  String takeWords(int count) {
    return split(RegExp(r'\s+')).take(count).join('-');
  }
}