import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import '../frontend/ultron_bubble_painter.dart';
import 'memory_learning_usage_service.dart';
import 'plugin_manager_service.dart';
import 'project_workspace_service.dart';
import 'ultron_telemetry_service.dart';

//**************
// Načini izpisovanja odgovorov v glavnem oknu ULTRON *
//**************
enum UltronTypingMode {
  adaptiveSmooth,
  waitFullThenType,
  instant,
}

//**************
// Stopnje globine razmišljanja in konteksta glede na zahtevnost ukaza *
//**************
enum UltronPromptEffort {
  casualFast,
  standardTask,
  deepWorkspace,
}

class LocalLlmModelInfo {
  final String name;
  final String sizeLabel;
  final String parameterSize;
  final String quantization;
  final String provider;
  final String storageLocation;
  final bool isLiveInServer;

  const LocalLlmModelInfo({
    required this.name,
    this.sizeLabel = '',
    this.parameterSize = '',
    this.quantization = '',
    this.provider = 'Ollama',
    this.storageLocation = '',
    this.isLiveInServer = true,
  });

  String get displaySubtitle {
    final parts = <String>[
      if (parameterSize.isNotEmpty) parameterSize,
      if (quantization.isNotEmpty) quantization,
      if (sizeLabel.isNotEmpty) sizeLabel,
      if (!isLiveInServer && storageLocation.isNotEmpty)
        'Disk: $storageLocation',
    ];
    return parts.isEmpty ? provider : parts.join(' · ');
  }
}

class AttachedFilePayload {
  final String path;
  final String name;
  final String extension;
  final int sizeBytes;
  final String extractedText;
  final String? base64Image;
  final String kindLabel;
  final bool isFolder;

  const AttachedFilePayload({
    required this.path,
    required this.name,
    required this.extension,
    required this.sizeBytes,
    required this.extractedText,
    this.base64Image,
    required this.kindLabel,
    this.isFolder = false,
  });

  String get humanSize {
    if (isFolder) {
      return '${(extractedText.length / 1024).toStringAsFixed(1)} KB konteksta';
    }
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

//**************
// Sporočilo v osrednjem klepetu z metapodatki za Korak 3 (tok/s, trajanje, priponke) *
//**************
class ChatMessageItem {
  final String id;
  final String role;
  String content;
  final String modelName;
  final List<String> attachedFileNames;
  final List<AttachedFilePayload> attachedPayloads;
  final List<WorkspaceActionRecord> workspaceActions;
  final List<WorkspaceWriteDirective> pendingWriteProposals;
  final DateTime timestamp;
  final bool isStreaming;
  double tokensPerSec;
  int generationDurationMs;

  final ValueNotifier<String> liveTargetText;
  final ValueNotifier<bool> networkDone;
  final ValueNotifier<int> bufferedCharsCount;

  ChatMessageItem({
    required this.id,
    required this.role,
    required this.content,
    required this.modelName,
    this.attachedFileNames = const [],
    this.attachedPayloads = const [],
    List<WorkspaceActionRecord>? workspaceActions,
    List<WorkspaceWriteDirective>? pendingWriteProposals,
    required this.timestamp,
    this.isStreaming = false,
    this.tokensPerSec = 0.0,
    this.generationDurationMs = 0,
  })  : workspaceActions = workspaceActions ?? [],
        pendingWriteProposals = pendingWriteProposals ?? [],
        liveTargetText = ValueNotifier<String>(content),
        networkDone = ValueNotifier<bool>(!isStreaming),
        bufferedCharsCount = ValueNotifier<int>(content.length);
}

class LiveCodeIssue {
  final String id;
  final int lineNumber;
  final String description;
  final String brokenLine;
  final String surgicalFixLine;
  bool isFixed;

  LiveCodeIssue({
    required this.id,
    required this.lineNumber,
    required this.description,
    required this.brokenLine,
    required this.surgicalFixLine,
    this.isFixed = false,
  });
}

class OpenEditorTab {
  final String filePath;
  final String fileName;
  List<String> lines;
  List<String>? previousLinesSnapshot;
  bool isDirty;
  int externalSyncRevision;

  OpenEditorTab({
    required this.filePath,
    required this.fileName,
    required this.lines,
    this.previousLinesSnapshot,
    this.isDirty = false,
    this.externalSyncRevision = 0,
  });
}

class DiffHunkProposal {
  final String id;
  final int startLine;
  final List<String> oldLines;
  final List<String> newLines;

  const DiffHunkProposal({
    required this.id,
    required this.startLine,
    required this.oldLines,
    required this.newLines,
  });
}

class GitHubRepoEntry {
  final String name;
  final String fullName;
  final String description;
  final String language;
  final int stargazersCount;
  final String defaultBranch;
  final String updatedAtIso;
  final String cloneUrl;
  final String htmlUrl;
  final bool isPrivate;

  const GitHubRepoEntry({
    required this.name,
    required this.fullName,
    this.description = '',
    this.language = '',
    this.stargazersCount = 0,
    this.defaultBranch = 'main',
    this.updatedAtIso = '',
    required this.cloneUrl,
    required this.htmlUrl,
    this.isPrivate = false,
  });
}

class TriageDecision {
  final String selectedModel;
  final String reason;

  const TriageDecision({
    required this.selectedModel,
    required this.reason,
  });
}

//**************
// Osrednji možganski usmerjevalnik aplikacije ULTRON *
//**************
class UltronBrainRouter extends ChangeNotifier {
  final MemoryLearningUsageService memoryService = MemoryLearningUsageService();
  final PluginManagerService pluginService = PluginManagerService();
  final ProjectWorkspaceService workspaceService = ProjectWorkspaceService();
  final UltronProcessTelemetryService telemetryService =
      UltronProcessTelemetryService();

  OrbState orbState = OrbState.standby;
  bool isGenerating = false;
  bool isScanningModels = false;
  String liveAgentStatus = '';
  HttpClient? _activeStreamClient;

  String ollamaBaseUrl = 'http://127.0.0.1:11434';
  bool isOllamaOnline = false;
  String activeLocalModel = 'gemma2-gpu';
  int customNumGpuLayers = 0;
  int contextWindowTokens = 6144;
  String? detectedDiskModelsFolder;

  UltronTypingMode typingMode = UltronTypingMode.adaptiveSmooth;
  double typingSpeedMultiplier = 1.2;
  int accentPresetIndex = 0;
  double customCutRadius = 9.0;
  double orbGlowMultiplier = 1.0;

  final List<LocalLlmModelInfo> discoveredModels = [];
  List<String> get installedOllamaModels =>
      discoveredModels.map((m) => m.name).toList();

  final List<ChatMessageItem> messages = [];
  final List<AttachedFilePayload> pendingAttachments = [];
  final List<ChatTurnRecord> _sessionHistory = [];

  String currentChatSessionId = '';

  String currentBrowserDirectory = Directory.current.path;
  String activeProjectPath = '';
  bool isWorkspaceModeEnabled = false;
  bool autoApplyProjectWrites = true;
  int workspaceRevision = 0;
  List<String> availableSystemRoots = [];

  bool isVsCodeWindowOpen = false;
  bool isStreamingCode = false;
  String activeExecutionModel = 'gemma2-gpu';
  int activeCursorLine = 0;
  final List<OpenEditorTab> openTabs = [];
  int activeTabIndex = 0;
  final List<LiveCodeIssue> detectedIssues = [];
  final List<DiffHunkProposal> pendingDiffHunks = [];

  String githubUsername = '';
  String githubDisplayName = '';
  String githubAvatarUrl = '';
  String githubBio = '';
  int githubPublicReposCount = 0;
  int githubPrivateReposCount = 0;
  String githubToken = '';
  String githubOAuthClientId = '';

  bool isGithubConnected = false;
  bool isGithubAuthenticating = false;
  bool isFetchingRepos = false;
  String githubAuthStatus = '';
  String githubAuthError = '';
  String githubDeviceUserCode = '';
  String githubDeviceVerificationUri = 'https://github.com/login/device';

  int githubRateLimitRemaining = 60;
  int githubRateLimitTotal = 60;
  final List<GitHubRepoEntry> githubRepos = [];
  String? cloningRepoFullName;

  // Lokalni Git status za aktivni projekt ali trenutno mapo brskalnika
  String localGitBranch = '';
  int localGitChangedCount = 0;
  int localGitAheadCount = 0;
  int localGitBehindCount = 0;
  final List<String> localGitChangedFiles = [];
  bool isSyncingLocalGit = false;
  String lastGitActionSummary = '';
  bool isJulesConnected = false;

  bool _deviceFlowCancelled = false;
  Process? _activeAuthProcess;
  late File _routerConfigFile;

  bool isOrbCompactTop = false;
  String currentPromptLabel = '';
  String currentCenterResponseText = '';
  String? lastErrorBanner;
  String statusBanner = 'ULTRON NEURAL CORE READY';

  bool get hasActiveProject =>
      isWorkspaceModeEnabled && activeProjectPath.trim().isNotEmpty;

  String get effectiveGitDirectory =>
      hasActiveProject ? activeProjectPath : currentBrowserDirectory;

  String get currentBrowserFolderName => _basename(currentBrowserDirectory);

  OpenEditorTab? get activeTab =>
      (activeTabIndex >= 0 && activeTabIndex < openTabs.length)
          ? openTabs[activeTabIndex]
          : null;

  String get activeFilePath => activeTab?.filePath ?? '';
  List<String> get activeFileLines => activeTab?.lines ?? const [];

  String get activeProjectName =>
      hasActiveProject ? _basename(activeProjectPath) : 'Brez projekta';

  String get typingModeLabel {
    switch (typingMode) {
      case UltronTypingMode.adaptiveSmooth:
        return 'Smooth Live';
      case UltronTypingMode.waitFullThenType:
        return 'Wait & Type';
      case UltronTypingMode.instant:
        return 'Instant';
    }
  }

  Future<void> initialize() async {
    await memoryService.initialize();
    await pluginService.initialize();

    final memDir = Directory(
        '${Directory.current.path}${Platform.pathSeparator}ultron_memory');
    if (!await memDir.exists()) {
      await memDir.create(recursive: true);
    }
    _routerConfigFile =
        File('${memDir.path}${Platform.pathSeparator}router_config.json');

    await _loadRouterConfig();
    await refreshSystemRoots();

    unawaited(telemetryService.start(ollamaBaseUrl: ollamaBaseUrl));

    if (githubToken.isNotEmpty) {
      unawaited(connectGithubWithToken(githubToken, silentRefresh: true));
    }
    unawaited(refreshLocalGitStatus());

    notifyListeners();
    await scanAllLocalLlms();
  }

  @override
  void dispose() {
    _deviceFlowCancelled = true;
    _activeAuthProcess?.kill();
    _activeStreamClient?.close(force: true);
    telemetryService.dispose();
    super.dispose();
  }

  void startNewChatSession() {
    currentChatSessionId = '';
    messages.clear();
    _sessionHistory.clear();
    currentCenterResponseText = '';
    currentPromptLabel = '';
    isOrbCompactTop = false;
    orbState = OrbState.standby;
    notifyListeners();
  }

  Future<void> loadSavedChatArchiveIntoView(SavedChatArchive archive) async {
    final session =
        await memoryService.loadChatSessionFromDisk(archive.sessionId);
    if (session != null) {
      currentChatSessionId = archive.sessionId;
      _sessionHistory
        ..clear()
        ..addAll(session.turns);
      messages.clear();

      for (final turn in session.turns) {
        messages.add(
          ChatMessageItem(
            id: 't_${turn.timestamp.microsecondsSinceEpoch}_${math.Random().nextInt(10000)}',
            role: turn.role,
            content: turn.content,
            modelName: turn.modelUsed,
            attachedFileNames: turn.attachedFiles,
            timestamp: turn.timestamp,
            tokensPerSec: turn.tokensPerSec,
            generationDurationMs: turn.generationDurationMs,
          ),
        );
      }

      if (archive.hasProject && archive.projectPath.isNotEmpty) {
        await setActiveProjectFolder(archive.projectPath);
      }

      if (session.turns.isNotEmpty) {
        currentCenterResponseText = session.turns.last.content;
      }
      currentPromptLabel = 'Naložena seja: ${archive.title}';
      isOrbCompactTop = true;
      orbState = OrbState.standby;
      notifyListeners();
    }
  }

  //**************
  // Korak 3: Uredi uporabnikovo sporočilo in na novo generiraj pogovor od te točke naprej *
  //**************
  Future<void> editAndResubmitUserMessage(
    String messageId,
    String updatedPrompt,
  ) async {
    final cleanText = updatedPrompt.trim();
    if (cleanText.isEmpty) return;

    if (isGenerating) {
      stopGeneration();
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }

    final idx = messages.indexWhere((m) => m.id == messageId);
    if (idx == -1) return;

    final previousPayloads =
        List<AttachedFilePayload>.from(messages[idx].attachedPayloads);

    messages.removeRange(idx, messages.length);

    // Sinhroniziramo zgodovino sej s preostalimi sporočili
    _sessionHistory.clear();
    for (final m in messages) {
      _sessionHistory.add(
        ChatTurnRecord(
          role: m.role,
          content: m.content,
          modelUsed: m.modelName,
          attachedFiles: m.attachedFileNames,
          timestamp: m.timestamp,
          tokensPerSec: m.tokensPerSec,
          generationDurationMs: m.generationDurationMs,
        ),
      );
    }

    if (previousPayloads.isNotEmpty) {
      for (final p in previousPayloads) {
        if (!pendingAttachments.any((a) => a.path == p.path)) {
          pendingAttachments.add(p);
        }
      }
    }

    notifyListeners();
    await executeUltronPrompt(cleanText);
  }

  //**************
  // Korak 3: Odpri poljuben kodni blok iz klepeta neposredno v vgrajenem urejevalniku *
  //**************
  Future<String> openCodeSnippetInEditor({
    required String code,
    String language = 'txt',
    String? suggestedPath,
  }) async {
    String? candidate = suggestedPath?.trim();

    // Preverimo, ali prva vrstica vsebuje komentar s potjo (npr. // filepath: lib/foo.dart)
    if (candidate == null || candidate.isEmpty) {
      final firstEnd = code.indexOf('\n');
      final firstLine =
          (firstEnd == -1 ? code : code.substring(0, firstEnd)).trim();
      final m = RegExp(
        r'^(?://|#|--|/\*)\s*(?:filepath|file|path)\s*:\s*([A-Za-z0-9_.\-/\\]+)',
        caseSensitive: false,
      ).firstMatch(firstLine);
      if (m != null) {
        candidate = m.group(1)?.trim();
      }
    }

    if (candidate != null && candidate.isNotEmpty) {
      final resolved = hasActiveProject
          ? workspaceService.resolveSafePath(candidate, mustStayInRoot: false)
          : candidate;
      if (resolved != null && File(resolved).existsSync()) {
        await openFileInEditorTab(resolved);
        return resolved;
      }
    }

    // Ustvarimo delovni zavihek v ultron_memory/snippets za takojšnje urejanje
    final extClean = language
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    final ext = extClean.isEmpty ? 'txt' : extClean;
    final snippetsDir = Directory(
        '${Directory.current.path}${Platform.pathSeparator}ultron_memory${Platform.pathSeparator}snippets');
    if (!await snippetsDir.exists()) {
      await snippetsDir.create(recursive: true);
    }
    final fileName =
        'izpisek_${DateTime.now().millisecondsSinceEpoch % 100000}.$ext';
    final snippetFile =
        File('${snippetsDir.path}${Platform.pathSeparator}$fileName');
    await snippetFile.writeAsString(code);
    await openFileInEditorTab(snippetFile.path);
    return snippetFile.path;
  }

  //**************
  // Korak 3: Shrani ULTRON izpisek v datoteko na disku ali v aktivni projekt *
  //**************
  Future<String?> saveAssistantOutputToFile({
    required String content,
    required String relativeOrFullPath,
  }) async {
    final trimmed = relativeOrFullPath.trim();
    if (trimmed.isEmpty) return null;

    try {
      String fullPath;
      final isAbs = File(trimmed).isAbsolute;
      if (isAbs) {
        fullPath = trimmed;
      } else {
        final baseDir =
            hasActiveProject ? activeProjectPath : currentBrowserDirectory;
        final sep = Platform.pathSeparator;
        fullPath =
            '$baseDir$sep${trimmed.replaceAll('/', sep).replaceAll('\\', sep)}';
      }

      final outFile = File(fullPath);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsString(content);

      if (hasActiveProject &&
          MemoryLearningUsageService.normalizeProjectPath(fullPath).startsWith(
              MemoryLearningUsageService.normalizeProjectPath(
                  activeProjectPath))) {
        await workspaceService.indexProjectFolder(activeProjectPath);
        await refreshLocalGitStatus();
      }
      workspaceRevision++;
      notifyListeners();
      return outFile.path;
    } catch (_) {
      return null;
    }
  }

  //**************
  // Korak 3: 1-klik pretvorba sporočila ali ULTRON izpiska v trajno pravilo (Learn Vault) *
  //**************
  Future<bool> learnFromMessageContent({
    required String title,
    required String contentOrRule,
    required bool isGlobal,
    required bool extractViaLlm,
    String sourceLabel = 'izpisek klepeta',
  }) async {
    final targetProject = isGlobal ? '' : activeProjectPath;

    if (!extractViaLlm || !isOllamaOnline) {
      await memoryService.addManualRule(
        title: title.trim().isEmpty ? 'Pravilo iz klepeta' : title.trim(),
        rule: contentOrRule.trim(),
        category: 'chat_rule',
        projectPath: targetProject,
        source: sourceLabel,
        pinned: true,
      );
      notifyListeners();
      return true;
    }

    final clipped = contentOrRule.length > 3500
        ? contentOrRule.substring(0, 3500)
        : contentOrRule;
    final synthesisPrompt = '''
Iz spodnjega sporočila izlušči 1 ali 2 jedrnati tehnični pravili oz. navodili, ki si jih mora ULTRON trajno zapomniti.
Odgovori IZKLJUČNO v obliki:
RULE|chat_rule|Kratek naslov|Jedrnato pravilo v enem stavku v slovenščini

Sporočilo:
$clipped
''';

    final raw = await _runOneShotLearnSynthesis(synthesisPrompt);
    int added = 0;
    if (raw != null && raw.trim().isNotEmpty) {
      for (final line in raw.split('\n')) {
        final t = line.trim();
        if (!t.startsWith('RULE|')) continue;
        final parts = t.split('|');
        if (parts.length >= 4) {
          final parsedTitle = parts[2].trim();
          final parsedRule = parts.sublist(3).join('|').trim();
          if (parsedRule.isNotEmpty) {
            await memoryService.addManualRule(
              title: parsedTitle.isEmpty ? title : parsedTitle,
              rule: parsedRule,
              category: parts[1].trim().isEmpty ? 'chat_rule' : parts[1].trim(),
              projectPath: targetProject,
              source: '$sourceLabel (LLM sinteza)',
              pinned: true,
            );
            added++;
          }
        }
      }
    }

    if (added == 0) {
      // Varen fallback na neposredni zapis, če model ne vrne predpisane oblike
      final fallbackRule = contentOrRule.length > 260
          ? '${contentOrRule.substring(0, 260).replaceAll('\n', ' ')}...'
          : contentOrRule.replaceAll('\n', ' ');
      await memoryService.addManualRule(
        title: title.trim().isEmpty ? 'Pravilo iz klepeta' : title.trim(),
        rule: fallbackRule,
        category: 'chat_rule',
        projectPath: targetProject,
        source: sourceLabel,
        pinned: true,
      );
    }
    notifyListeners();
    return true;
  }

  void resetCenterStageToStandbyOrb() {
    isOrbCompactTop = false;
    currentPromptLabel = '';
    currentCenterResponseText = '';
    orbState = OrbState.standby;
    notifyListeners();
  }

  void triggerErrorState(String clearReason) {
    lastErrorBanner = clearReason;
    statusBanner = 'ERROR // $clearReason';
    orbState = OrbState.error;
    Timer(const Duration(milliseconds: 1200), () {
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

  Future<void> _loadRouterConfig() async {
    if (!await _routerConfigFile.exists()) return;
    try {
      final map = jsonDecode(await _routerConfigFile.readAsString());
      if (map is Map<String, dynamic>) {
        ollamaBaseUrl =
            map['ollamaBaseUrl']?.toString() ?? 'http://127.0.0.1:11434';
        activeLocalModel = map['activeLocalModel']?.toString() ?? 'gemma2-gpu';
        customNumGpuLayers = (map['customNumGpuLayers'] as num?)?.toInt() ?? 0;
        contextWindowTokens =
            ((map['contextWindowTokens'] as num?)?.toInt() ?? 6144)
                .clamp(2048, 32768);
        githubToken = map['githubToken']?.toString() ?? '';
        githubUsername = map['githubUsername']?.toString() ?? '';
        githubDisplayName = map['githubDisplayName']?.toString() ?? '';
        githubAvatarUrl = map['githubAvatarUrl']?.toString() ?? '';
        githubOAuthClientId = map['githubOAuthClientId']?.toString() ?? '';
        isGithubConnected = githubToken.isNotEmpty;
        autoApplyProjectWrites = map['autoApplyProjectWrites'] != false;

        final savedMode = map['typingMode']?.toString() ?? '';
        if (savedMode == UltronTypingMode.waitFullThenType.name) {
          typingMode = UltronTypingMode.waitFullThenType;
        } else if (savedMode == UltronTypingMode.instant.name) {
          typingMode = UltronTypingMode.instant;
        } else {
          typingMode = UltronTypingMode.adaptiveSmooth;
        }

        typingSpeedMultiplier =
            ((map['typingSpeedMultiplier'] as num?)?.toDouble() ?? 1.2)
                .clamp(0.5, 3.0);
        accentPresetIndex =
            ((map['accentPresetIndex'] as num?)?.toInt() ?? 0).clamp(0, 4);
        customCutRadius =
            ((map['customCutRadius'] as num?)?.toDouble() ?? 9.0)
                .clamp(4.0, 16.0);
        orbGlowMultiplier =
            ((map['orbGlowMultiplier'] as num?)?.toDouble() ?? 1.0)
                .clamp(0.4, 1.8);

        final savedDir = map['currentBrowserDirectory']?.toString();
        if (savedDir != null && Directory(savedDir).existsSync()) {
          currentBrowserDirectory = savedDir;
        }
        activeProjectPath = '';
        isWorkspaceModeEnabled = false;
      }
    } catch (_) {}
  }

  Future<void> saveRouterConfig() async {
    try {
      await _routerConfigFile.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'ollamaBaseUrl': ollamaBaseUrl,
          'activeLocalModel': activeLocalModel,
          'customNumGpuLayers': customNumGpuLayers,
          'contextWindowTokens': contextWindowTokens,
          'githubToken': githubToken,
          'githubUsername': githubUsername,
          'githubDisplayName': githubDisplayName,
          'githubAvatarUrl': githubAvatarUrl,
          'githubOAuthClientId': githubOAuthClientId,
          'currentBrowserDirectory': currentBrowserDirectory,
          'autoApplyProjectWrites': autoApplyProjectWrites,
          'typingMode': typingMode.name,
          'typingSpeedMultiplier': typingSpeedMultiplier,
          'accentPresetIndex': accentPresetIndex,
          'customCutRadius': customCutRadius,
          'orbGlowMultiplier': orbGlowMultiplier,
        }),
      );
    } catch (_) {}
  }

  void setTypingMode(UltronTypingMode mode) {
    typingMode = mode;
    saveRouterConfig();
    notifyListeners();
  }

  void cycleTypingMode() {
    if (typingMode == UltronTypingMode.adaptiveSmooth) {
      setTypingMode(UltronTypingMode.waitFullThenType);
    } else if (typingMode == UltronTypingMode.waitFullThenType) {
      setTypingMode(UltronTypingMode.instant);
    } else {
      setTypingMode(UltronTypingMode.adaptiveSmooth);
    }
  }

  void updateAppearanceSettings({
    int? accentIndex,
    double? cutRadius,
    double? orbGlow,
    double? typingSpeed,
  }) {
    if (accentIndex != null) accentPresetIndex = accentIndex.clamp(0, 4);
    if (cutRadius != null) customCutRadius = cutRadius.clamp(4.0, 16.0);
    if (orbGlow != null) orbGlowMultiplier = orbGlow.clamp(0.4, 1.8);
    if (typingSpeed != null) {
      typingSpeedMultiplier = typingSpeed.clamp(0.5, 3.0);
    }
    saveRouterConfig();
    notifyListeners();
  }

  Future<void> refreshSystemRoots() async {
    final roots = <String>[];
    if (Platform.isWindows) {
      for (int code = 67; code <= 90; code++) {
        final drive = '${String.fromCharCode(code)}:\\';
        try {
          if (Directory(drive).existsSync()) {
            roots.add(drive);
          }
        } catch (_) {}
      }
      if (roots.isEmpty) roots.add('C:\\');
    } else {
      roots.add('/');
      final home = Platform.environment['HOME'];
      if (home != null && Directory(home).existsSync()) {
        roots.add(home);
      }
      if (Directory('/mnt').existsSync()) roots.add('/mnt');
      if (Directory('/run/media').existsSync()) roots.add('/run/media');
    }
    availableSystemRoots = roots;
    notifyListeners();
  }

  void setCurrentBrowserDirectory(String path) {
    final dir = Directory(path);
    if (!dir.existsSync()) return;
    currentBrowserDirectory = dir.path;
    saveRouterConfig();
    unawaited(refreshLocalGitStatus());
    notifyListeners();
  }

  Future<void> setActiveProjectFolder(
    String path, {
    bool syncBrowser = true,
  }) async {
    final dir = Directory(path);
    if (!await dir.exists()) return;
    activeProjectPath = dir.absolute.path;
    isWorkspaceModeEnabled = true;
    if (syncBrowser) {
      currentBrowserDirectory = activeProjectPath;
    }

    await memoryService.ensureProjectRegistered(activeProjectPath);

    notifyListeners();
    await workspaceService.indexProjectFolder(activeProjectPath);
    await refreshLocalGitStatus();
    workspaceRevision++;
    await saveRouterConfig();
    notifyListeners();
  }

  void clearActiveProject() {
    activeProjectPath = '';
    isWorkspaceModeEnabled = false;
    workspaceService.indexedFiles.clear();
    workspaceService.indexedFolders.clear();
    workspaceRevision++;
    unawaited(refreshLocalGitStatus());
    notifyListeners();
  }

  Future<void> rescanActiveProject() async {
    if (!hasActiveProject) return;
    await workspaceService.indexProjectFolder(activeProjectPath);
    await refreshLocalGitStatus();
    workspaceRevision++;
    notifyListeners();
  }

  void toggleWorkspaceMode(bool enabled) {
    if (enabled && activeProjectPath.trim().isEmpty) return;
    isWorkspaceModeEnabled = enabled;
    notifyListeners();
  }

  void toggleAutoApplyProjectWrites(bool enabled) {
    autoApplyProjectWrites = enabled;
    saveRouterConfig();
    notifyListeners();
  }

  Future<bool> createNewFileInDirectory({
    required String baseDirectory,
    required String relativeName,
    String initialContent = '',
    bool openInEditor = true,
  }) async {
    final cleaned = relativeName.trim();
    if (cleaned.isEmpty) return false;
    try {
      final sep = Platform.pathSeparator;
      final fullPath =
          '$baseDirectory$sep${cleaned.replaceAll('/', sep).replaceAll('\\', sep)}';
      final file = File(fullPath);
      await file.parent.create(recursive: true);
      if (!await file.exists()) {
        await file.writeAsString(initialContent);
      }
      if (hasActiveProject && fullPath.startsWith(activeProjectPath)) {
        await workspaceService.indexProjectFolder(activeProjectPath);
      }
      await refreshLocalGitStatus();
      workspaceRevision++;
      if (openInEditor) {
        await openFileInEditorTab(file.path);
      } else {
        notifyListeners();
      }
      return true;
    } catch (e) {
      debugPrint('Napaka pri ustvarjanju datoteke: $e');
      return false;
    }
  }

  Future<bool> createNewFolderInDirectory({
    required String baseDirectory,
    required String relativeName,
  }) async {
    final cleaned = relativeName.trim();
    if (cleaned.isEmpty) return false;
    try {
      final sep = Platform.pathSeparator;
      final fullPath =
          '$baseDirectory$sep${cleaned.replaceAll('/', sep).replaceAll('\\', sep)}';
      await Directory(fullPath).create(recursive: true);
      if (hasActiveProject && fullPath.startsWith(activeProjectPath)) {
        await workspaceService.indexProjectFolder(activeProjectPath);
      }
      workspaceRevision++;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Napaka pri ustvarjanju mape: $e');
      return false;
    }
  }

  Future<bool> attachFolderFromPath(String folderPath) async {
    try {
      final dir = Directory(folderPath);
      if (!await dir.exists()) return false;
      if (pendingAttachments.any((a) => a.path == dir.path)) return true;

      final extracted = await workspaceService.extractFullFolderPayload(
        dir.path,
        maxChars: 18000,
      );
      pendingAttachments.add(
        AttachedFilePayload(
          path: dir.path,
          name: _basename(dir.path),
          extension: '',
          sizeBytes: extracted.length,
          extractedText: extracted,
          kindLabel: 'MAPA',
          isFolder: true,
        ),
      );
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Napaka pri pripenjanju mape: $e');
      return false;
    }
  }

  Future<void> applyProposalDirective(
    ChatMessageItem message,
    WorkspaceWriteDirective directive,
  ) async {
    if (!hasActiveProject) {
      await setActiveProjectFolder(currentBrowserDirectory, syncBrowser: false);
    }

    WorkspaceActionRecord record;
    if (directive.isDirectory) {
      record = await workspaceService.createFolderInProject(directive.path);
    } else {
      record = await workspaceService.writeFileInProject(
        directive.path,
        directive.content,
      );
      if (record.success) {
        await _syncWrittenFileWithEditor(record.fullPath);
      }
    }

    message.pendingWriteProposals.remove(directive);
    message.workspaceActions.add(record);
    if (hasActiveProject) {
      await workspaceService.indexProjectFolder(activeProjectPath);
    }
    await refreshLocalGitStatus();
    workspaceRevision++;
    notifyListeners();
  }

  Future<void> scanAllLocalLlms() async {
    if (isScanningModels) return;
    isScanningModels = true;
    notifyListeners();

    final foundMap = <String, LocalLlmModelInfo>{};
    bool serverReachable = false;

    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 2200);
    try {
      final cleanBase = ollamaBaseUrl.endsWith('/')
          ? ollamaBaseUrl.substring(0, ollamaBaseUrl.length - 1)
          : ollamaBaseUrl;
      final req = await client.getUrl(Uri.parse('$cleanBase/api/tags'));
      final res = await req.close().timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        serverReachable = true;
        final body = await res.transform(utf8.decoder).join();
        final data = jsonDecode(body);
        final list = (data['models'] as List<dynamic>?) ?? const [];
        for (final item in list) {
          if (item is! Map<String, dynamic>) continue;
          final name = item['name']?.toString() ?? '';
          if (name.isEmpty) continue;
          final cleanName = name.endsWith(':latest')
              ? name.substring(0, name.length - 7)
              : name;
          final sizeBytes = (item['size'] as num?)?.toInt() ?? 0;
          final details =
              (item['details'] as Map<String, dynamic>?) ?? const {};

          foundMap[cleanName] = LocalLlmModelInfo(
            name: name.endsWith(':latest') && !name.contains(':')
                ? cleanName
                : name,
            sizeLabel: sizeBytes > 0
                ? '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
                : '',
            parameterSize: details['parameter_size']?.toString() ?? '',
            quantization: details['quantization_level']?.toString() ?? '',
            provider: 'Ollama',
            isLiveInServer: true,
          );
        }
      }
    } catch (_) {
      serverReachable = false;
    } finally {
      client.close();
    }

    try {
      final cliRes = await Process.run(
        'ollama',
        ['list'],
        runInShell: true,
      ).timeout(const Duration(seconds: 3));
      if (cliRes.exitCode == 0) {
        final lines = cliRes.stdout.toString().split('\n');
        for (int i = 1; i < lines.length; i++) {
          final line = lines[i].trim();
          if (line.isEmpty) continue;
          final cols = line.split(RegExp(r'\s{2,}'));
          if (cols.isNotEmpty) {
            final rawName = cols[0].trim();
            final key = rawName.endsWith(':latest')
                ? rawName.substring(0, rawName.length - 7)
                : rawName;
            if (!foundMap.containsKey(key) && !foundMap.containsKey(rawName)) {
              foundMap[key] = LocalLlmModelInfo(
                name: rawName,
                sizeLabel: cols.length >= 3 ? cols[2].trim() : '',
                provider: 'Ollama CLI',
                isLiveInServer: serverReachable,
              );
            }
          }
        }
      }
    } catch (_) {}

    final candidateModelDirs = <String>{};
    final envModels = Platform.environment['OLLAMA_MODELS'];
    if (envModels != null && envModels.isNotEmpty) {
      candidateModelDirs.add(envModels);
    }
    final userProfile = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '';
    if (userProfile.isNotEmpty) {
      candidateModelDirs.add(
          '$userProfile${Platform.pathSeparator}.ollama${Platform.pathSeparator}models');
    }
    if (Platform.isWindows) {
      for (final root in availableSystemRoots) {
        candidateModelDirs.add('${root}OllamaModels');
        candidateModelDirs.add('${root}Ollama${Platform.pathSeparator}models');
      }
    } else {
      candidateModelDirs.add('/usr/share/ollama/.ollama/models');
    }

    for (final baseModelsPath in candidateModelDirs) {
      final manifestsRoot =
          Directory('$baseModelsPath${Platform.pathSeparator}manifests');
      if (!manifestsRoot.existsSync()) continue;
      detectedDiskModelsFolder ??= baseModelsPath;

      try {
        await for (final entity
            in manifestsRoot.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          final rel = entity.path
              .substring(manifestsRoot.path.length)
              .replaceAll('\\', '/');
          final segs = rel.split('/').where((s) => s.isNotEmpty).toList();
          if (segs.length >= 2) {
            final modelName = segs[segs.length - 2];
            final tag = segs.last;
            final fullTag = tag == 'latest' ? modelName : '$modelName:$tag';

            final alreadyPresent = foundMap.values.any((m) =>
                m.name == fullTag ||
                m.name == '$modelName:$tag' ||
                (tag == 'latest' && m.name == '$modelName:latest'));

            if (!alreadyPresent) {
              foundMap[fullTag] = LocalLlmModelInfo(
                name: fullTag,
                provider: 'Ollama Disk',
                storageLocation: baseModelsPath,
                isLiveInServer: serverReachable &&
                    (envModels?.toLowerCase() == baseModelsPath.toLowerCase()),
              );
            }
          }
        }
      } catch (_) {}
    }

    final lmClient = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 650);
    try {
      final req =
          await lmClient.getUrl(Uri.parse('http://127.0.0.1:1234/v1/models'));
      final res =
          await req.close().timeout(const Duration(milliseconds: 900));
      if (res.statusCode == 200) {
        final data = jsonDecode(await res.transform(utf8.decoder).join());
        final items = (data['data'] as List<dynamic>?) ?? const [];
        for (final m in items) {
          if (m is Map<String, dynamic>) {
            final id = m['id']?.toString() ?? '';
            if (id.isNotEmpty) {
              foundMap['lmstudio:$id'] = LocalLlmModelInfo(
                name: 'lmstudio:$id',
                provider: 'LM Studio',
                isLiveInServer: true,
              );
            }
          }
        }
      }
    } catch (_) {
    } finally {
      lmClient.close();
    }

    isOllamaOnline = serverReachable;
    discoveredModels
      ..clear()
      ..addAll(foundMap.values);

    if (discoveredModels.isNotEmpty) {
      final exactMatch =
          discoveredModels.any((m) => m.name == activeLocalModel);
      if (!exactMatch) {
        const preferredOrder = [
          'gemma2-gpu',
          'gemma2-gpu:latest',
          'qwen2.5-coder:14b',
          'gemma2:9b',
          'qwen2.5-coder:7b',
        ];
        String? chosen;
        for (final pref in preferredOrder) {
          final hit = discoveredModels.where((m) => m.name == pref);
          if (hit.isNotEmpty) {
            chosen = hit.first.name;
            break;
          }
        }
        activeLocalModel = chosen ?? discoveredModels.first.name;
        activeExecutionModel = activeLocalModel;
        await saveRouterConfig();
      }
    }

    isScanningModels = false;
    notifyListeners();
  }

  Future<void> checkLocalOllamaHealth({String? newBaseUrl}) async {
    if (newBaseUrl != null && newBaseUrl.trim().isNotEmpty) {
      ollamaBaseUrl = newBaseUrl.trim();
      telemetryService.updateOllamaUrl(ollamaBaseUrl);
      await saveRouterConfig();
    }
    await scanAllLocalLlms();
  }

  Future<void> startLocalOllamaServer({String? customModelsPath}) async {
    try {
      final env = Map<String, String>.from(Platform.environment);
      final folder = customModelsPath ?? detectedDiskModelsFolder;
      if (folder != null && folder.isNotEmpty) {
        env['OLLAMA_MODELS'] = folder;
      }
      await Process.start(
        'ollama',
        ['serve'],
        environment: env,
        mode: ProcessStartMode.detached,
        runInShell: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      await scanAllLocalLlms();
    } catch (e) {
      debugPrint('Zagon Ollama strežnika ni uspel: $e');
    }
  }

  void selectLocalOllamaModel(String modelName) {
    activeLocalModel = modelName;
    activeExecutionModel = modelName;
    saveRouterConfig();
    notifyListeners();
  }

  void updateGpuSettings({int? numGpu, int? numCtx}) {
    if (numGpu != null) customNumGpuLayers = numGpu;
    if (numCtx != null) contextWindowTokens = numCtx.clamp(2048, 32768);
    saveRouterConfig();
    notifyListeners();
  }

  void setInputFocus(bool hasFocus) {
    if (orbState == OrbState.thinking ||
        orbState == OrbState.answering ||
        orbState == OrbState.error) {
      return;
    }
    orbState = hasFocus ? OrbState.listening : OrbState.standby;
    notifyListeners();
  }

  void notifyUserTyping() {
    if (!isGenerating && orbState != OrbState.listening) {
      orbState = OrbState.listening;
      notifyListeners();
      Future<void>.delayed(const Duration(milliseconds: 1200), () {
        if (!isGenerating && orbState == OrbState.listening) {
          orbState = OrbState.standby;
          notifyListeners();
        }
      });
    }
  }

  Future<bool> attachFileFromPath(String filePath) async {
    try {
      if (Directory(filePath).existsSync()) {
        return await attachFolderFromPath(filePath);
      }
      final file = File(filePath);
      if (!await file.exists()) return false;
      if (pendingAttachments.any((a) => a.path == file.path)) return true;

      final stat = await file.stat();
      final name = _basename(file.path);
      final ext = _extension(file.path);
      final payload = await _extractAnyFile(file, name, ext, stat.size);

      pendingAttachments.add(payload);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Napaka pri pripenjanju datoteke: $e');
      return false;
    }
  }

  void removeAttachment(String path) {
    pendingAttachments.removeWhere((a) => a.path == path);
    notifyListeners();
  }

  void clearAttachments() {
    pendingAttachments.clear();
    notifyListeners();
  }

  Future<AttachedFilePayload> _extractAnyFile(
    File file,
    String name,
    String ext,
    int sizeBytes,
  ) async {
    const imageExts = {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'};
    const officeZipExts = {'.docx', '.odt', '.xlsx', '.pptx'};

    if (imageExts.contains(ext)) {
      final bytes = await file.readAsBytes();
      final b64 = base64Encode(bytes);
      return AttachedFilePayload(
        path: file.path,
        name: name,
        extension: ext,
        sizeBytes: sizeBytes,
        extractedText:
            '[Priložena slika: $name (${(sizeBytes / 1024).toStringAsFixed(1)} KB)]',
        base64Image: b64,
        kindLabel: 'Slika',
      );
    }

    if (officeZipExts.contains(ext)) {
      final bytes = await file.readAsBytes();
      final extracted = _extractOfficeDocumentText(bytes, ext);
      return AttachedFilePayload(
        path: file.path,
        name: name,
        extension: ext,
        sizeBytes: sizeBytes,
        extractedText: _capText(extracted, 22000),
        kindLabel: ext.substring(1).toUpperCase(),
      );
    }

    if (ext == '.pdf') {
      final bytes = await file.readAsBytes();
      final pdfText = _extractPdfTextPureDart(bytes);
      return AttachedFilePayload(
        path: file.path,
        name: name,
        extension: ext,
        sizeBytes: sizeBytes,
        extractedText: _capText(pdfText, 22000),
        kindLabel: 'PDF',
      );
    }

    if (ext == '.zip') {
      final bytes = await file.readAsBytes();
      final zipSummary = _extractZipSummary(bytes);
      return AttachedFilePayload(
        path: file.path,
        name: name,
        extension: ext,
        sizeBytes: sizeBytes,
        extractedText: _capText(zipSummary, 20000),
        kindLabel: 'ZIP',
      );
    }

    final maxRead = sizeBytes > 1024 * 1024 ? 1024 * 1024 : sizeBytes;
    final bytes = await file
        .openRead(0, maxRead)
        .fold<List<int>>(<int>[], (prev, chunk) => prev..addAll(chunk));

    if (_looksLikePrintableText(bytes)) {
      final text = utf8.decode(bytes, allowMalformed: true);
      return AttachedFilePayload(
        path: file.path,
        name: name,
        extension: ext,
        sizeBytes: sizeBytes,
        extractedText: _capText(text, 22000),
        kindLabel: ext.isEmpty ? 'TXT' : ext.substring(1).toUpperCase(),
      );
    }

    final asciiStrings = _extractPrintableStringsFromBinary(bytes);
    return AttachedFilePayload(
      path: file.path,
      name: name,
      extension: ext,
      sizeBytes: sizeBytes,
      extractedText:
          'Binarna datoteka: $name ($sizeBytes bajtov)\nIzluščeni berljivi nizi:\n${_capText(asciiStrings, 10000)}',
      kindLabel: 'BIN',
    );
  }

  String _extractOfficeDocumentText(List<int> bytes, String ext) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final out = StringBuffer();

      if (ext == '.docx') {
        final docFile = archive.findFile('word/document.xml');
        if (docFile != null) {
          final xml =
              utf8.decode(docFile.content as List<int>, allowMalformed: true);
          out.writeln(_cleanXmlToText(
            xml
                .replaceAll('</w:p>', '\n')
                .replaceAll('<w:br/>', '\n')
                .replaceAll('<w:tab/>', '\t')
                .replaceAll('</w:tr>', '\n'),
          ));
        }
      } else if (ext == '.odt') {
        final contentFile = archive.findFile('content.xml');
        if (contentFile != null) {
          final xml = utf8.decode(
              contentFile.content as List<int>, allowMalformed: true);
          out.writeln(_cleanXmlToText(
            xml.replaceAll('</text:p>', '\n').replaceAll('</text:h>', '\n'),
          ));
        }
      } else if (ext == '.xlsx') {
        for (final f in archive.files) {
          if (f.isFile &&
              (f.name == 'xl/sharedStrings.xml' ||
                  f.name.startsWith('xl/worksheets/sheet'))) {
            final xml =
                utf8.decode(f.content as List<int>, allowMalformed: true);
            out.writeln(_cleanXmlToText(xml.replaceAll('</si>', '\n')));
          }
        }
      } else if (ext == '.pptx') {
        final slides = archive.files
            .where((f) => f.isFile && f.name.startsWith('ppt/slides/slide'))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        for (final slide in slides) {
          final xml =
              utf8.decode(slide.content as List<int>, allowMalformed: true);
          out.writeln('--- Diapozitiv ${slide.name} ---');
          out.writeln(_cleanXmlToText(xml.replaceAll('</a:p>', '\n')));
        }
      }

      final result = out.toString().trim();
      return result.isEmpty
          ? '(Dokument je prazen ali nima besedilne plasti)'
          : result;
    } catch (e) {
      return '(Napaka pri branju pisarniškega dokumenta: $e)';
    }
  }

  String _cleanXmlToText(String xml) {
    return xml
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String _extractPdfTextPureDart(List<int> bytes) {
    try {
      final rawLatin = latin1.decode(bytes, allowInvalid: true);
      final extracted = StringBuffer();
      final streamRegex = RegExp(r'stream[\r\n]+([\s\S]*?)[\r\n]+endstream');

      for (final match in streamRegex.allMatches(rawLatin)) {
        final chunk = match.group(1);
        if (chunk == null || chunk.isEmpty) continue;
        String decodedStream = chunk;

        try {
          final rawChunkBytes = latin1.encode(chunk);
          final inflated = zlib.decode(rawChunkBytes);
          decodedStream = utf8.decode(inflated, allowMalformed: true);
        } catch (_) {}

        for (final tj in RegExp(r'\(([^()\\]*(?:\\.[^()\\]*)*)\)\s*Tj')
            .allMatches(decodedStream)) {
          extracted.write('${tj.group(1) ?? ''} ');
        }
        for (final arr in RegExp(r'\[([\s\S]*?)\]\s*TJ')
            .allMatches(decodedStream)) {
          final inner = arr.group(1) ?? '';
          for (final sub
              in RegExp(r'\(([^()\\]*(?:\\.[^()\\]*)*)\)').allMatches(inner)) {
            extracted.write(sub.group(1) ?? '');
          }
          extracted.write(' ');
        }
      }

      final text = extracted
          .toString()
          .replaceAll(r'\n', '\n')
          .replaceAll(r'\(', '(')
          .replaceAll(r'\)', ')')
          .replaceAll(RegExp(r'\s{2,}'), ' ')
          .trim();

      if (text.length > 20) return text;
      return _extractPrintableStringsFromBinary(bytes);
    } catch (_) {
      return _extractPrintableStringsFromBinary(bytes);
    }
  }

  String _extractZipSummary(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final buf = StringBuffer()..writeln('Vsebina ZIP arhiva:');
      int includedTextFiles = 0;

      for (final f in archive.files) {
        if (!f.isFile) continue;
        buf.writeln('- ${f.name} (${f.size} B)');
      }
      buf.writeln();

      for (final f in archive.files) {
        if (!f.isFile || includedTextFiles >= 8 || f.size > 80 * 1024) continue;
        final contentBytes = f.content as List<int>;
        if (_looksLikePrintableText(contentBytes)) {
          includedTextFiles++;
          buf.writeln('=== ${f.name} ===');
          buf.writeln(_capText(
              utf8.decode(contentBytes, allowMalformed: true), 3000));
        }
      }
      return buf.toString();
    } catch (e) {
      return 'ZIP arhiva ni bilo mogoče razširiti: $e';
    }
  }

  bool _looksLikePrintableText(List<int> bytes) {
    if (bytes.isEmpty) return true;
    final sampleLen = bytes.length > 2048 ? 2048 : bytes.length;
    int suspicious = 0;
    for (int i = 0; i < sampleLen; i++) {
      final b = bytes[i];
      if (b == 0) return false;
      if (b < 9 || (b > 13 && b < 32)) suspicious++;
    }
    return (suspicious / sampleLen) < 0.08;
  }

  String _extractPrintableStringsFromBinary(List<int> bytes) {
    final out = StringBuffer();
    final current = StringBuffer();
    final limit = bytes.length > 150000 ? 150000 : bytes.length;

    for (int i = 0; i < limit; i++) {
      final b = bytes[i];
      if (b >= 32 && b <= 126) {
        current.writeCharCode(b);
      } else {
        if (current.length >= 5) {
          out.writeln(current.toString());
        }
        current.clear();
      }
    }
    if (current.length >= 5) out.writeln(current.toString());
    return out.toString();
  }

  String _capText(String input, int maxChars) {
    if (input.length <= maxChars) return input;
    return '${input.substring(0, maxChars)}\n...[Besedilo skrajšano na $maxChars znakov zaradi varovanja pomnilnika]...';
  }

  UltronPromptEffort _classifyPromptEffort(
    String userPrompt,
    List<AttachedFilePayload> attachments,
  ) {
    if (attachments.isNotEmpty) {
      return hasActiveProject
          ? UltronPromptEffort.deepWorkspace
          : UltronPromptEffort.standardTask;
    }

    // Če uporabnik uporabi @omembo datoteke, vključimo globoko projektno branje
    if (hasActiveProject && userPrompt.contains('@')) {
      return UltronPromptEffort.deepWorkspace;
    }

    final clean = userPrompt.trim().toLowerCase();
    const greetings = {
      'hej',
      'hey',
      'hi',
      'hello',
      'yo',
      'živjo',
      'zivjo',
      'zdravo',
      'oj',
      'ojla',
      'dober dan',
      'kako si',
      'kaj dogaja',
      'hvala',
      'ok',
      'okej',
      'super',
      'test',
      'kdo si',
    };

    if (greetings.contains(clean.replaceAll(RegExp(r'[!?.]+$'), '').trim())) {
      return UltronPromptEffort.casualFast;
    }

    final hasCodeOrProjectKeywords = RegExp(
      r'(projekt|project|datotek|file|folder|map[aeo]|kod[aeo]|code|class|funkcij|func|bug|napak|error|fix|poprav|ustvar|creat|dodaj|add|spremen|edit|read|preber|analiz|lib/|src/|\.dart|\.cs|\.py|\.js|\.ts|\.cpp|\.json|\.yaml)',
      caseSensitive: false,
    ).hasMatch(clean);

    if (!hasCodeOrProjectKeywords && clean.length < 42) {
      return UltronPromptEffort.casualFast;
    }

    if (hasActiveProject && hasCodeOrProjectKeywords) {
      return UltronPromptEffort.deepWorkspace;
    }

    return UltronPromptEffort.standardTask;
  }

  void _appendSystemFeedbackMessage(String title, String body) {
    messages.add(
      ChatMessageItem(
        id: 'sys_${DateTime.now().microsecondsSinceEpoch}',
        role: 'assistant',
        content: '**$title**\n$body',
        modelName: 'ULTRON Sistem',
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  //**************
  // Glavna metoda za pošiljanje sporočila z merjenjem časa in tok/s *
  //**************
  Future<void> executeUltronPrompt(String rawPrompt) async {
    final trimmed = rawPrompt.trim();
    if (trimmed.isEmpty && pendingAttachments.isEmpty) return;
    if (isGenerating) return;

    isOrbCompactTop = true;
    currentPromptLabel = trimmed;

    if (trimmed.toLowerCase() == '/learn status') {
      final summary = memoryService.getLearnStatusSummary();
      currentCenterResponseText = summary;
      _appendSystemFeedbackMessage('Learn Vault Status', summary);
      return;
    }

    if (trimmed.toLowerCase() == '/learn reset') {
      await memoryService.resetLearnedNotes();
      currentCenterResponseText = 'Naučena pravila so bila ponastavljena.';
      _appendSystemFeedbackMessage(
          'Learn Vault', 'Vsa naučena pravila so bila ponastavljena.');
      return;
    }

    if (trimmed.toLowerCase() == '/learn') {
      final count = await triggerLearnPass();
      _appendSystemFeedbackMessage(
        'Learn analiza zaključena',
        count > 0
            ? 'Izluščenih **$count** novih pravil v `Learn Vault`.'
            : 'Znanje posodobljeno (${memoryService.learnedEntries.length} pravil).',
      );
      return;
    }

    if (trimmed.toLowerCase() == '/pull') {
      final ok = await pullCurrentGitWorkspace();
      _appendSystemFeedbackMessage(
        ok ? 'Git Pull uspešen' : 'Git Pull ni uspel',
        '```text\n$lastGitActionSummary\n```',
      );
      return;
    }

    if (trimmed.toLowerCase().startsWith('/commit')) {
      final msg = trimmed.length > 7
          ? trimmed.substring(7).trim()
          : 'feat: posodobitev prek ULTRON';
      final ok = await commitCurrentGitWorkspace(msg, pushAfter: false);
      _appendSystemFeedbackMessage(
        ok ? 'Git Commit uspešen' : 'Git Commit opozorilo',
        '```text\n$lastGitActionSummary\n```',
      );
      return;
    }

    if (trimmed.toLowerCase() == '/push') {
      final ok = await pushCurrentGitWorkspace();
      _appendSystemFeedbackMessage(
        ok ? 'Git Push uspešen' : 'Git Push ni uspel',
        '```text\n$lastGitActionSummary\n```',
      );
      return;
    }

    if (memoryService.isDoneTriggerPhrase(trimmed)) {
      if (_sessionHistory.isNotEmpty) {
        if (currentChatSessionId.isEmpty) {
          currentChatSessionId =
              'session_${DateTime.now().millisecondsSinceEpoch}';
        }
        final archive = await memoryService.saveChatSessionToDisk(
          sessionId: currentChatSessionId,
          turns: _sessionHistory,
          projectPath: hasActiveProject ? activeProjectPath : '',
          projectName: hasActiveProject ? activeProjectName : '',
        );
        currentCenterResponseText =
            'Seja shranjena: ${archive?.title ?? currentChatSessionId}';
      }
      startNewChatSession();
      return;
    }

    final attachmentsSnapshot =
        List<AttachedFilePayload>.from(pendingAttachments);
    pendingAttachments.clear();

    final userDisplay = trimmed.isEmpty
        ? 'Analiziraj priložene elemente (${attachmentsSnapshot.map((e) => e.name).join(", ")}).'
        : trimmed;

    final effort = _classifyPromptEffort(userDisplay, attachmentsSnapshot);

    messages.add(
      ChatMessageItem(
        id: 'u_${DateTime.now().microsecondsSinceEpoch}',
        role: 'user',
        content: userDisplay,
        modelName: 'Uporabnik',
        attachedFileNames: attachmentsSnapshot.map((a) => a.name).toList(),
        attachedPayloads: attachmentsSnapshot,
        timestamp: DateTime.now(),
      ),
    );

    final assistantMsg = ChatMessageItem(
      id: 'a_${DateTime.now().microsecondsSinceEpoch}',
      role: 'assistant',
      content: '',
      modelName: activeLocalModel,
      timestamp: DateTime.now(),
      isStreaming: true,
    );
    messages.add(assistantMsg);

    isGenerating = true;
    orbState = OrbState.thinking;
    activeExecutionModel = activeLocalModel;
    liveAgentStatus = effort == UltronPromptEffort.deepWorkspace
        ? 'Pregledujem projektno mapo $activeProjectName...'
        : (effort == UltronPromptEffort.casualFast
            ? 'Hitri odziv ($activeLocalModel)...'
            : 'Pripravljam odgovor ($activeLocalModel)...');
    notifyListeners();

    final int effectiveCtxTokens = effort == UltronPromptEffort.casualFast
        ? 2048
        : (effort == UltronPromptEffort.standardTask
            ? math.min(contextWindowTokens, 4096)
            : contextWindowTokens.clamp(2048, 32768));

    final int workspaceBudgetChars =
        (effectiveCtxTokens * 1.60).clamp(6000, 19500).toInt();

    final fullUserContext = StringBuffer();
    final excludedPaths = <String>{};

    if (attachmentsSnapshot.isNotEmpty) {
      fullUserContext.writeln('PRILOŽENE DATOTEKE IN MAPE:');
      for (final att in attachmentsSnapshot) {
        excludedPaths.add(att.path);
        fullUserContext.writeln(
            '=== ${att.isFolder ? "MAPA" : "DATOTEKA"}: ${att.name} (${att.kindLabel}, ${att.humanSize}) ===');
        fullUserContext.writeln(att.extractedText);
        fullUserContext.writeln('=== KONEC: ${att.name} ===\n');
      }
    }

    if (effort != UltronPromptEffort.casualFast &&
        activeTab != null &&
        !excludedPaths.contains(activeTab!.filePath)) {
      excludedPaths.add(activeTab!.filePath);
      final editorSnippet = _capText(activeTab!.lines.join('\n'), 8000);
      fullUserContext.writeln(
          'TRENUTNO ODPRTA DATOTEKA V UREJEVALNIKU (${activeTab!.fileName}):\n$editorSnippet\n');
    }

    final bool useWorkspaceEngine =
        effort == UltronPromptEffort.deepWorkspace && hasActiveProject;

    if (useWorkspaceEngine) {
      final lastIdx = workspaceService.lastIndexedAt;
      if (lastIdx == null ||
          workspaceService.activeRootPath != activeProjectPath ||
          DateTime.now().difference(lastIdx).inSeconds > 15) {
        await workspaceService.indexProjectFolder(activeProjectPath);
      }

      final autoReads = <WorkspaceActionRecord>[];
      final workspaceContext =
          await workspaceService.buildWorkspacePromptContext(
        userPrompt: userDisplay,
        maxCharsBudget: workspaceBudgetChars,
        excludeFullPaths: excludedPaths,
        recordedAutoReads: autoReads,
      );
      assistantMsg.workspaceActions.addAll(autoReads);
      fullUserContext.writeln(workspaceContext);
    }

    if (effort == UltronPromptEffort.casualFast) {
      fullUserContext.write(userDisplay);
    } else {
      fullUserContext.writeln('UPORABNIKOVO NAVODILO:\n$userDisplay');
    }

    final learnedContext = effort == UltronPromptEffort.casualFast
        ? ''
        : memoryService.buildLearnedSystemContext(
            userDisplay,
            activeProjectPath: activeProjectPath,
          );
    final pluginContext = effort == UltronPromptEffort.casualFast
        ? ''
        : pluginService.buildLazyLoadedPluginContext();

    final systemPrompt = [
      'Ti si ULTRON, hiter in natančen lokalni inženirski AI asistent.',
      'Odgovarjaj jedrnato, naravno in v jeziku uporabnika.',
      if (effort != UltronPromptEffort.casualFast)
        'Pri pisanju kode pazi na pravilne velike in male začetnice ter uporabi // za enovrstične komentarje in okvir //************** z znakom * na koncu srednjih vrstic za večvrstične komentarje.',
      if (useWorkspaceEngine)
        '''DOSTOP DO CELOTNE PROJEKTNE MAPE ($activeProjectPath):
Imaš 100% neposreden dostop za branje celotne projektne mape ter dodajanje novih map in datotek.
1. Celotna drevesna struktura vseh map in datotek ter ključna izvorna koda sta že priloženi v kontekstu.
2. Če potrebuješ celotno vsebino še katere dodatne datoteke ali podmape iz drevesa, zapiši:
<ultron_read path="relativna/pot/do/datoteke" />
3. Ko ti uporabnik naroči ustvarjanje nove mape v projektu, zapiši:
<ultron_mkdir path="relativna/pot/nove_mape" />
4. Ko ti uporabnik naroči dodajanje nove datoteke ali posodobitev datoteke v projektu, zapiši celotno veljavno kodo datoteke v oznako (brez trojnih narekovajev ``` znotraj oznake):
<ultron_write path="relativna/pot/datoteke.dart">
// celotna izvorna koda datoteke
</ultron_write>
Oznaki <ultron_mkdir> in <ultron_write> uporabi SAMO takrat, ko uporabnik želi dodati, ustvariti ali spremeniti mape oz. datoteke.''',
      if (learnedContext.isNotEmpty) learnedContext,
      if (pluginContext.isNotEmpty) pluginContext,
    ].join('\n\n');

    final imagesBase64 = attachmentsSnapshot
        .where((a) => a.base64Image != null)
        .map((a) => a.base64Image!)
        .toList();

    _sessionHistory.add(
      ChatTurnRecord(
        role: 'user',
        content: userDisplay,
        modelUsed: activeLocalModel,
        attachedFiles: attachmentsSnapshot.map((a) => a.name).toList(),
        timestamp: DateTime.now(),
      ),
    );

    final apiMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    final int maxHist = effort == UltronPromptEffort.casualFast ? 4 : 6;
    final historyCount = messages.length - 2;
    final startIdx = historyCount > maxHist ? historyCount - maxHist : 0;
    for (int i = startIdx; i < historyCount; i++) {
      final m = messages[i];
      if (m.content.trim().isEmpty) continue;
      apiMessages.add({'role': m.role, 'content': _capText(m.content, 3500)});
    }

    apiMessages.add({
      'role': 'user',
      'content': fullUserContext.toString(),
      if (imagesBase64.isNotEmpty) 'images': imagesBase64,
    });

    final turnStopwatch = Stopwatch()..start();

    try {
      final alreadyReadTargets = <String>{};
      final executedWrites = <String>{};
      final executedMkdirs = <String>{};
      final int maxAgentReadHops = useWorkspaceEngine ? 3 : 0;

      for (int hop = 0; hop <= maxAgentReadHops; hop++) {
        if (hop > 0) {
          liveAgentStatus =
              'Nadaljujem po branju projektnih datotek (korak ${hop + 1})...';
          notifyListeners();
        }

        String rawTurnOutput;
        if (activeLocalModel.startsWith('lmstudio:')) {
          rawTurnOutput = await _streamTurnFromLmStudio(
            modelId: activeLocalModel.substring('lmstudio:'.length),
            apiMessages: apiMessages,
            targetMsg: assistantMsg,
            formatWorkspaceTags: useWorkspaceEngine,
          );
        } else {
          rawTurnOutput = await _streamTurnFromOllama(
            modelName: activeLocalModel,
            apiMessages: apiMessages,
            effectiveCtxTokens: effectiveCtxTokens,
            targetMsg: assistantMsg,
            formatWorkspaceTags: useWorkspaceEngine,
          );
        }

        if (!useWorkspaceEngine) {
          assistantMsg.content = rawTurnOutput;
          assistantMsg.liveTargetText.value = rawTurnOutput;
          break;
        }

        final parsed = workspaceService.parseModelOutput(rawTurnOutput);

        await _processWorkspaceMutations(
          parsed: parsed,
          targetMsg: assistantMsg,
          executedMkdirs: executedMkdirs,
          executedWrites: executedWrites,
        );

        final newReads = parsed.readRequests
            .where((r) => !alreadyReadTargets.contains(r.toLowerCase()))
            .toList();

        if (newReads.isEmpty || hop == maxAgentReadHops) {
          final finalClean = parsed.cleanedDisplayContent.isEmpty
              ? rawTurnOutput
              : parsed.cleanedDisplayContent;
          assistantMsg.content = finalClean;
          assistantMsg.liveTargetText.value = finalClean;
          break;
        }

        final readFeedback = StringBuffer()
          ..writeln('ZAHTEVANE PROJEKTNE DATOTEKE SO PREBRANE:');

        for (final reqPath in newReads.take(5)) {
          alreadyReadTargets.add(reqPath.toLowerCase());
          liveAgentStatus = 'Berem projektno datoteko: $reqPath...';
          notifyListeners();

          final readResult = await workspaceService.readProjectTarget(reqPath);
          assistantMsg.workspaceActions.add(readResult.key);
          readFeedback.writeln(readResult.value);
          readFeedback.writeln();
        }

        readFeedback.writeln(
          'Zdaj uporabi prebrane podatke in podaj končni odgovor uporabniku (brez ponovnega klica <ultron_read> za že prebrane datoteke).',
        );

        apiMessages.add({'role': 'assistant', 'content': rawTurnOutput});
        apiMessages.add({'role': 'user', 'content': readFeedback.toString()});
        assistantMsg.content = '';
        assistantMsg.liveTargetText.value = '';
        assistantMsg.bufferedCharsCount.value = 0;
        orbState = OrbState.thinking;
        notifyListeners();
      }

      turnStopwatch.stop();
      assistantMsg.generationDurationMs = turnStopwatch.elapsedMilliseconds;
      if (memoryService.liveTokensPerSecond > 0) {
        assistantMsg.tokensPerSec = memoryService.liveTokensPerSecond;
      } else if (assistantMsg.generationDurationMs > 0 &&
          assistantMsg.content.isNotEmpty) {
        final approxTok = (assistantMsg.content.length / 4.0);
        assistantMsg.tokensPerSec =
            approxTok / (assistantMsg.generationDurationMs / 1000.0);
      }

      assistantMsg.networkDone.value = true;
      currentCenterResponseText = assistantMsg.content;

      _sessionHistory.add(
        ChatTurnRecord(
          role: 'assistant',
          content: assistantMsg.content,
          modelUsed: activeLocalModel,
          timestamp: DateTime.now(),
          tokensPerSec: assistantMsg.tokensPerSec,
          generationDurationMs: assistantMsg.generationDurationMs,
        ),
      );

      if (currentChatSessionId.isEmpty) {
        currentChatSessionId =
            'session_${DateTime.now().millisecondsSinceEpoch}';
      }

      await memoryService.saveChatSessionToDisk(
        sessionId: currentChatSessionId,
        turns: _sessionHistory,
        projectPath: hasActiveProject ? activeProjectPath : '',
        projectName: hasActiveProject ? activeProjectName : '',
      );

      if (memoryService.autoLearnEnabled &&
          effort != UltronPromptEffort.casualFast &&
          _sessionHistory.length % 8 == 0) {
        unawaited(triggerLearnPass(silent: true));
      }

      orbState = OrbState.standby;
    } catch (e) {
      turnStopwatch.stop();
      assistantMsg.generationDurationMs = turnStopwatch.elapsedMilliseconds;
      orbState = OrbState.error;
      final fallbackText = assistantMsg.content.isEmpty
          ? 'Povezava z lokalnim modelom "$activeLocalModel" ni uspela ($e).\nPreveri, ali Ollama teče na $ollamaBaseUrl ali v nastavitvah klikni "Zaženi Ollama strežnik".'
          : assistantMsg.content;
      assistantMsg.content = fallbackText;
      assistantMsg.liveTargetText.value = fallbackText;
      assistantMsg.networkDone.value = true;
      currentCenterResponseText = fallbackText;
    } finally {
      assistantMsg.networkDone.value = true;
      _activeStreamClient = null;
      isGenerating = false;
      isStreamingCode = false;
      liveAgentStatus = '';
      notifyListeners();
    }
  }

  Future<void> triggerTargetedLearn({
    required List<String> filePaths,
    required String instruction,
    bool isGlobal = false,
  }) async {
    final prevOrb = orbState;
    orbState = OrbState.thinking;
    liveAgentStatus = 'Ciljno učenje: analiziram datoteke...';
    notifyListeners();

    final count = await memoryService.runTargetedLearnPass(
      targetFilePaths: filePaths,
      instruction: instruction,
      currentProjectPath: activeProjectPath,
      isGlobal: isGlobal,
      llmExtractor: _runOneShotLearnSynthesis,
    );

    orbState = prevOrb;
    liveAgentStatus = '';
    _showToastBanner(count > 0
        ? 'Ciljno učenje uspešno! (+$count pravil)'
        : 'Ciljno učenje končano.');
    notifyListeners();
  }

  Future<void> _processWorkspaceMutations({
    required ParsedLlmWorkspaceDirectives parsed,
    required ChatMessageItem targetMsg,
    required Set<String> executedMkdirs,
    required Set<String> executedWrites,
  }) async {
    bool mutatedDisk = false;

    for (final dirPath in parsed.mkdirRequests) {
      if (!executedMkdirs.add(dirPath.toLowerCase())) continue;
      if (autoApplyProjectWrites) {
        liveAgentStatus = 'Ustvarjam mapo: $dirPath...';
        notifyListeners();
        final rec = await workspaceService.createFolderInProject(dirPath);
        targetMsg.workspaceActions.add(rec);
        if (rec.success) mutatedDisk = true;
      } else {
        targetMsg.pendingWriteProposals.add(
          WorkspaceWriteDirective(path: dirPath, isDirectory: true),
        );
      }
    }

    for (final writeReq in parsed.writeRequests) {
      final sig = '${writeReq.path.toLowerCase()}::${writeReq.content.length}';
      if (!executedWrites.add(sig)) continue;
      if (autoApplyProjectWrites) {
        liveAgentStatus = 'Zapisujem datoteko: ${writeReq.path}...';
        notifyListeners();
        final rec = await workspaceService.writeFileInProject(
          writeReq.path,
          writeReq.content,
        );
        targetMsg.workspaceActions.add(rec);
        if (rec.success) {
          mutatedDisk = true;
          await _syncWrittenFileWithEditor(rec.fullPath);
        }
      } else {
        targetMsg.pendingWriteProposals.add(writeReq);
      }
    }

    for (final fb in parsed.fallbackProposals) {
      final exists =
          targetMsg.pendingWriteProposals.any((p) => p.path == fb.path);
      if (!exists) {
        targetMsg.pendingWriteProposals.add(fb);
      }
    }

    if (mutatedDisk && hasActiveProject) {
      await workspaceService.indexProjectFolder(activeProjectPath);
      await refreshLocalGitStatus();
      workspaceRevision++;
      notifyListeners();
    }
  }

  Future<void> _syncWrittenFileWithEditor(String fullPath) async {
    try {
      final file = File(fullPath);
      if (!await file.exists()) return;
      final text = utf8.decode(await file.readAsBytes(), allowMalformed: true);
      final newLines = const LineSplitter().convert(text);

      final existingIdx = openTabs.indexWhere((t) => t.filePath == file.path);
      if (existingIdx != -1) {
        final tab = openTabs[existingIdx];
        tab.previousLinesSnapshot = List<String>.from(tab.lines);
        tab.lines = newLines.isEmpty ? [''] : newLines;
        tab.isDirty = false;
        tab.externalSyncRevision++;
        activeTabIndex = existingIdx;
        _scanActiveTabForSurgicalIssues();
      } else {
        openTabs.add(
          OpenEditorTab(
            filePath: file.path,
            fileName: _basename(file.path),
            lines: newLines.isEmpty ? [''] : newLines,
            externalSyncRevision: 1,
          ),
        );
        activeTabIndex = openTabs.length - 1;
        _scanActiveTabForSurgicalIssues();
      }
    } catch (_) {}
  }

  void stopGeneration() {
    _activeStreamClient?.close(force: true);
    _activeStreamClient = null;
    if (messages.isNotEmpty) {
      messages.last.networkDone.value = true;
    }
    isGenerating = false;
    liveAgentStatus = '';
    orbState = OrbState.standby;
    notifyListeners();
  }

  void clearConversation() {
    currentChatSessionId = '';
    messages.clear();
    _sessionHistory.clear();
    orbState = OrbState.standby;
    notifyListeners();
  }

  Future<String> _streamTurnFromOllama({
    required String modelName,
    required List<Map<String, dynamic>> apiMessages,
    required int effectiveCtxTokens,
    required ChatMessageItem targetMsg,
    required bool formatWorkspaceTags,
  }) async {
    final cleanBase = ollamaBaseUrl.endsWith('/')
        ? ollamaBaseUrl.substring(0, ollamaBaseUrl.length - 1)
        : ollamaBaseUrl;

    final options = <String, dynamic>{
      'num_ctx': effectiveCtxTokens,
      if (customNumGpuLayers > 0) 'num_gpu': customNumGpuLayers,
    };

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    _activeStreamClient = client;

    final req = await client.postUrl(Uri.parse('$cleanBase/api/chat'));
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode({
      'model': modelName,
      'messages': apiMessages,
      'stream': true,
      'options': options,
    })));

    final res = await req.close();
    if (res.statusCode != 200) {
      final errBody = await res.transform(utf8.decoder).join();
      throw Exception('HTTP ${res.statusCode}: $errBody');
    }

    isOllamaOnline = true;
    final rawTurnBuffer = StringBuffer();
    final throttleClock = Stopwatch()..start();

    await for (final line
        in res.transform(utf8.decoder).transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final chunk = jsonDecode(line) as Map<String, dynamic>;

      if (orbState != OrbState.answering) {
        orbState = OrbState.answering;
      }

      final msgObj = chunk['message'] as Map<String, dynamic>?;
      final token = msgObj?['content']?.toString() ?? '';
      if (token.isNotEmpty) {
        rawTurnBuffer.write(token);

        if (throttleClock.elapsedMilliseconds >= 34) {
          throttleClock.reset();
          final currentRaw = rawTurnBuffer.toString();
          final preview = formatWorkspaceTags
              ? workspaceService.formatLiveStreamingPreview(currentRaw)
              : currentRaw;

          targetMsg.content = preview;
          targetMsg.bufferedCharsCount.value = preview.length;

          if (typingMode == UltronTypingMode.adaptiveSmooth) {
            targetMsg.liveTargetText.value = preview;
            currentCenterResponseText = preview;
          }
        }
      }

      if (chunk['done'] == true) {
        final evalCount = (chunk['eval_count'] as num?)?.toInt() ?? 0;
        final evalDuration = (chunk['eval_duration'] as num?)?.toInt() ?? 0;
        await memoryService.recordLocalOllamaUsage(
          evalCount: evalCount,
          evalDurationNs: evalDuration,
        );
        if (evalDuration > 0 && evalCount > 0) {
          targetMsg.tokensPerSec = evalCount / (evalDuration / 1e9);
        }
      }
    }

    final finalRaw = rawTurnBuffer.toString();
    final finalPreview = formatWorkspaceTags
        ? workspaceService.formatLiveStreamingPreview(finalRaw)
        : finalRaw;
    targetMsg.content = finalPreview;
    targetMsg.bufferedCharsCount.value = finalPreview.length;
    if (typingMode == UltronTypingMode.adaptiveSmooth) {
      targetMsg.liveTargetText.value = finalPreview;
      currentCenterResponseText = finalPreview;
    }

    return finalRaw;
  }

  Future<String> _streamTurnFromLmStudio({
    required String modelId,
    required List<Map<String, dynamic>> apiMessages,
    required ChatMessageItem targetMsg,
    required bool formatWorkspaceTags,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    _activeStreamClient = client;

    final cleanMessages = apiMessages
        .map((m) => {'role': m['role'], 'content': m['content']})
        .toList();

    final req = await client
        .postUrl(Uri.parse('http://127.0.0.1:1234/v1/chat/completions'));
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode({
      'model': modelId,
      'stream': false,
      'messages': cleanMessages,
    })));

    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw Exception('LM Studio HTTP ${res.statusCode}');
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    final choices = (data['choices'] as List<dynamic>?) ?? const [];
    String rawText = '';
    if (choices.isNotEmpty) {
      orbState = OrbState.answering;
      rawText = choices.first['message']?['content']?.toString() ?? '';
      final preview = formatWorkspaceTags
          ? workspaceService.formatLiveStreamingPreview(rawText)
          : rawText;
      targetMsg.content = preview;
      targetMsg.bufferedCharsCount.value = preview.length;
      targetMsg.liveTargetText.value = preview;
      currentCenterResponseText = preview;
    }
    return rawText;
  }

  Future<String?> _runOneShotLearnSynthesis(String prompt) async {
    if (!isOllamaOnline || activeLocalModel.startsWith('lmstudio:')) {
      return null;
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final cleanBase = ollamaBaseUrl.endsWith('/')
          ? ollamaBaseUrl.substring(0, ollamaBaseUrl.length - 1)
          : ollamaBaseUrl;
      final req = await client.postUrl(Uri.parse('$cleanBase/api/generate'));
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({
        'model': activeLocalModel,
        'prompt': prompt,
        'stream': false,
        'options': {
          'temperature': 0.2,
          'num_ctx': 3072,
          if (customNumGpuLayers > 0) 'num_gpu': customNumGpuLayers,
        },
      })));
      final res = await req.close().timeout(const Duration(seconds: 45));
      if (res.statusCode == 200) {
        final decoded = jsonDecode(await res.transform(utf8.decoder).join());
        return decoded['response']?.toString();
      }
    } catch (_) {
    } finally {
      client.close();
    }
    return null;
  }

  Future<int> triggerLearnPass({
    String? customFolder,
    bool silent = false,
  }) async {
    final prevOrb = orbState;
    if (!silent && !isGenerating) {
      orbState = OrbState.thinking;
      notifyListeners();
    }

    final targetFolder = customFolder ??
        (hasActiveProject ? activeProjectPath : currentBrowserDirectory);

    final count = await memoryService.runIncrementalLearnPass(
      workspacePath: targetFolder,
      recentTurns: _sessionHistory,
      llmExtractor: _runOneShotLearnSynthesis,
    );

    if (!silent && !isGenerating) {
      orbState = prevOrb;
    }
    notifyListeners();
    return count;
  }

  void toggleVsCodeWindow() {
    isVsCodeWindowOpen = !isVsCodeWindowOpen;
    notifyListeners();
  }

  void closeVsCodeWindow() {
    isVsCodeWindowOpen = false;
    notifyListeners();
  }

  Future<void> openFileInEditorTab(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return;

      final existingIdx =
          openTabs.indexWhere((tab) => tab.filePath == file.path);
      if (existingIdx != -1) {
        activeTabIndex = existingIdx;
        isVsCodeWindowOpen = true;
        _scanActiveTabForSurgicalIssues();
        notifyListeners();
        return;
      }

      final bytes = await file.readAsBytes();
      final text = utf8.decode(bytes, allowMalformed: true);
      final lines = const LineSplitter().convert(text);

      openTabs.add(
        OpenEditorTab(
          filePath: file.path,
          fileName: _basename(file.path),
          lines: lines.isEmpty ? [''] : lines,
        ),
      );
      activeTabIndex = openTabs.length - 1;
      activeCursorLine = 0;
      isVsCodeWindowOpen = true;
      _scanActiveTabForSurgicalIssues();
      notifyListeners();
    } catch (e) {
      debugPrint('Napaka pri odpiranju datoteke v urejevalniku: $e');
    }
  }

  void selectEditorTab(int index) {
    if (index < 0 || index >= openTabs.length) return;
    activeTabIndex = index;
    _scanActiveTabForSurgicalIssues();
    notifyListeners();
  }

  void closeEditorTab(int index) {
    if (index < 0 || index >= openTabs.length) return;
    openTabs.removeAt(index);
    if (activeTabIndex >= openTabs.length) {
      activeTabIndex = openTabs.isEmpty ? 0 : openTabs.length - 1;
    }
    _scanActiveTabForSurgicalIssues();
    notifyListeners();
  }

  void updateActiveTabText(String updatedContent) {
    final tab = activeTab;
    if (tab == null) return;
    tab.previousLinesSnapshot ??= List<String>.from(tab.lines);
    tab.lines = const LineSplitter().convert(updatedContent);
    if (tab.lines.isEmpty) tab.lines = [''];
    tab.isDirty = true;
    _scanActiveTabForSurgicalIssues();
    notifyListeners();
  }

  Future<bool> saveActiveTabContent() async {
    final tab = activeTab;
    if (tab == null) return false;
    try {
      await File(tab.filePath).writeAsString(tab.lines.join('\n'));
      tab.isDirty = false;
      if (hasActiveProject && tab.filePath.startsWith(activeProjectPath)) {
        await workspaceService.indexProjectFolder(activeProjectPath);
        workspaceRevision++;
      }
      await refreshLocalGitStatus();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  void undoLastEditOnActiveTab() {
    final tab = activeTab;
    if (tab == null || tab.previousLinesSnapshot == null) return;
    tab.lines = List<String>.from(tab.previousLinesSnapshot!);
    tab.previousLinesSnapshot = null;
    tab.isDirty = true;
    tab.externalSyncRevision++;
    _scanActiveTabForSurgicalIssues();
    notifyListeners();
  }

  void _scanActiveTabForSurgicalIssues() {
    detectedIssues.clear();
    final tab = activeTab;
    if (tab == null) return;

    for (int i = 0; i < tab.lines.length; i++) {
      final line = tab.lines[i];
      if (line.contains('print(') && tab.fileName.endsWith('.dart')) {
        detectedIssues.add(
          LiveCodeIssue(
            id: 'issue_$i',
            lineNumber: i + 1,
            description:
                'Zamenjaj print() z debugPrint() za produkcijsko kodo',
            brokenLine: line,
            surgicalFixLine: line.replaceFirst('print(', 'debugPrint('),
          ),
        );
      } else if (line.contains('.withOpacity(') &&
          tab.fileName.endsWith('.dart')) {
        detectedIssues.add(
          LiveCodeIssue(
            id: 'opacity_$i',
            lineNumber: i + 1,
            description: 'Zastarel klic withOpacity()',
            brokenLine: line,
            surgicalFixLine:
                line.replaceFirst('.withOpacity(', '.alphaPct('),
          ),
        );
      }
    }
  }

  Future<void> fixIssueSurgicallyInPlace(LiveCodeIssue issue) async {
    final tab = activeTab;
    if (tab == null) return;
    final idx = issue.lineNumber - 1;
    if (idx < 0 || idx >= tab.lines.length) return;

    tab.previousLinesSnapshot = List<String>.from(tab.lines);
    tab.lines[idx] = issue.surgicalFixLine;
    tab.isDirty = true;
    tab.externalSyncRevision++;
    issue.isFixed = true;
    activeCursorLine = idx;
    await saveActiveTabContent();
    _scanActiveTabForSurgicalIssues();
    notifyListeners();
  }

  void acceptDiffHunk(String id) {
    pendingDiffHunks.removeWhere((h) => h.id == id);
    notifyListeners();
  }

  void rejectDiffHunk(String id) {
    pendingDiffHunks.removeWhere((h) => h.id == id);
    notifyListeners();
  }

  Future<void> openActiveFileInRealVsCode() async {
    final path = activeFilePath.isNotEmpty
        ? activeFilePath
        : (hasActiveProject ? activeProjectPath : currentBrowserDirectory);
    try {
      await Process.start('code', [path], runInShell: true);
    } catch (_) {}
  }

  Future<bool> connectGithubWithToken(
    String token, {
    bool silentRefresh = false,
  }) async {
    final cleaned = token.trim();
    if (cleaned.isEmpty) {
      if (!silentRefresh) {
        githubAuthError = 'Vnesi veljaven GitHub žeton.';
        notifyListeners();
      }
      return false;
    }

    if (!silentRefresh) {
      isGithubAuthenticating = true;
      githubAuthError = '';
      githubAuthStatus = 'Preverjam GitHub račun...';
      notifyListeners();
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(Uri.https('api.github.com', '/user'));
      req.headers.set('Authorization', 'Bearer $cleaned');
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'ULTRON');
      final res = await req.close().timeout(const Duration(seconds: 8));

      final rem = res.headers.value('x-ratelimit-remaining');
      final lim = res.headers.value('x-ratelimit-limit');
      if (rem != null) githubRateLimitRemaining = int.tryParse(rem) ?? 60;
      if (lim != null) githubRateLimitTotal = int.tryParse(lim) ?? 60;

      if (res.statusCode == 200) {
        final data = jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>;
        githubToken = cleaned;
        githubUsername = data['login']?.toString() ?? 'GitHub User';
        githubDisplayName = data['name']?.toString() ?? githubUsername;
        githubAvatarUrl = data['avatar_url']?.toString() ?? '';
        githubBio = data['bio']?.toString() ?? '';
        githubPublicReposCount =
            (data['public_repos'] as num?)?.toInt() ?? 0;
        githubPrivateReposCount =
            (data['total_private_repos'] as num?)?.toInt() ??
                (data['owned_private_repos'] as num?)?.toInt() ??
                0;

        isGithubConnected = true;
        githubDeviceUserCode = '';
        githubAuthError = '';
        githubAuthStatus = 'Uspešno prijavljen kot @$githubUsername';
        await saveRouterConfig();
        await fetchGithubRepos();
        return true;
      } else {
        if (!silentRefresh) {
          githubAuthError =
              'GitHub je zavrnil žeton (HTTP ${res.statusCode}). Preveri pravice (repo, read:user).';
          githubAuthStatus = '';
        }
        return false;
      }
    } catch (e) {
      if (!silentRefresh) {
        githubAuthError = 'Povezava z api.github.com ni uspela.';
        githubAuthStatus = '';
      }
      return false;
    } finally {
      client.close();
      isGithubAuthenticating = false;
      notifyListeners();
    }
  }

  Future<bool> connectGithubFromSystemCredentials() async {
    if (isGithubAuthenticating) return false;
    isGithubAuthenticating = true;
    githubAuthError = '';
    githubAuthStatus =
        'Iščem lokalno GitHub sejo (gh CLI / Git Credential Manager)...';
    notifyListeners();

    try {
      try {
        final ghRes = await Process.run(
          'gh',
          ['auth', 'token'],
          runInShell: true,
        ).timeout(const Duration(seconds: 3));
        if (ghRes.exitCode == 0) {
          final tok = ghRes.stdout.toString().trim();
          if (tok.isNotEmpty && !tok.contains(' ')) {
            isGithubAuthenticating = false;
            return await connectGithubWithToken(tok);
          }
        }
      } catch (_) {}

      githubAuthStatus =
          'Preverjam Git Credential Manager (po potrebi potrdi v brskalniku)...';
      notifyListeners();

      final proc = await Process.start(
        'git',
        ['credential', 'fill'],
        runInShell: true,
      );
      _activeAuthProcess = proc;
      proc.stdin.writeln('protocol=https');
      proc.stdin.writeln('host=github.com');
      proc.stdin.writeln();
      await proc.stdin.close();

      final out = await proc.stdout
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 75));
      _activeAuthProcess = null;

      String? extractedPassword;
      for (final line in const LineSplitter().convert(out)) {
        if (line.startsWith('password=')) {
          extractedPassword = line.substring('password='.length).trim();
          break;
        }
      }

      if (extractedPassword != null && extractedPassword.isNotEmpty) {
        isGithubAuthenticating = false;
        return await connectGithubWithToken(extractedPassword);
      }

      githubAuthError =
          'Sistemska Git seja ni bila najdena. Uporabi gumb "Ustvari žeton" ali Device Flow.';
      githubAuthStatus = '';
      return false;
    } catch (_) {
      githubAuthError =
          'Sistemska prijava je potekla ali bila preklicana. Poskusi z žetonom ali Device kodo.';
      githubAuthStatus = '';
      return false;
    } finally {
      _activeAuthProcess = null;
      isGithubAuthenticating = false;
      notifyListeners();
    }
  }

  Future<void> startGithubDeviceFlow({String? customClientId}) async {
    final effectiveId = (customClientId ?? githubOAuthClientId).trim();
    if (effectiveId.isEmpty) {
      await openGithubQuickTokenCreator();
      return;
    }

    githubOAuthClientId = effectiveId;
    await saveRouterConfig();

    _deviceFlowCancelled = false;
    isGithubAuthenticating = true;
    githubAuthError = '';
    githubDeviceUserCode = '';
    githubAuthStatus = 'Zahtevam prijavno kodo od GitHuba...';
    notifyListeners();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client
          .postUrl(Uri.https('github.com', '/login/device/code'));
      req.headers.set('Accept', 'application/json');
      req.headers.contentType = ContentType.json;
      req.headers.set('User-Agent', 'ULTRON');
      req.add(utf8.encode(jsonEncode({
        'client_id': effectiveId,
        'scope': 'repo read:user',
      })));

      final res = await req.close().timeout(const Duration(seconds: 8));
      final body = await res.transform(utf8.decoder).join();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final deviceCode = data['device_code']?.toString() ?? '';
      final userCode = data['user_code']?.toString() ?? '';
      final verifyUri = data['verification_uri']?.toString() ??
          'https://github.com/login/device';
      int intervalSec = (data['interval'] as num?)?.toInt() ?? 5;
      final expiresIn = (data['expires_in'] as num?)?.toInt() ?? 900;

      if (deviceCode.isEmpty || userCode.isEmpty) {
        githubAuthError = data['error_description']?.toString() ??
            'Preveri, ali ima tvoj OAuth Client ID vklopljen "Device Flow".';
        githubAuthStatus = '';
        isGithubAuthenticating = false;
        notifyListeners();
        return;
      }

      githubDeviceUserCode = userCode;
      githubDeviceVerificationUri = verifyUri;
      githubAuthStatus =
          'Vnesi kodo $userCode v brskalniku in potrdi prijavo...';
      notifyListeners();

      await openWebUrl(verifyUri);

      final deadline = DateTime.now().add(Duration(seconds: expiresIn));
      while (!_deviceFlowCancelled && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(Duration(seconds: intervalSec));
        if (_deviceFlowCancelled) break;

        final pollClient = HttpClient()
          ..connectionTimeout = const Duration(seconds: 6);
        try {
          final pReq = await pollClient.postUrl(
              Uri.https('github.com', '/login/oauth/access_token'));
          pReq.headers.set('Accept', 'application/json');
          pReq.headers.contentType = ContentType.json;
          pReq.headers.set('User-Agent', 'ULTRON');
          pReq.add(utf8.encode(jsonEncode({
            'client_id': effectiveId,
            'device_code': deviceCode,
            'grant_type': 'urn:ietf:params:oauth:grant-type:device_code',
          })));

          final pRes =
              await pReq.close().timeout(const Duration(seconds: 8));
          final pData =
              jsonDecode(await pRes.transform(utf8.decoder).join())
                  as Map<String, dynamic>;

          final accessToken = pData['access_token']?.toString() ?? '';
          if (accessToken.isNotEmpty) {
            githubDeviceUserCode = '';
            isGithubAuthenticating = false;
            await connectGithubWithToken(accessToken);
            return;
          }

          final err = pData['error']?.toString() ?? '';
          if (err == 'slow_down') {
            intervalSec += 5;
          } else if (err == 'access_denied' || err == 'expired_token') {
            githubAuthError =
                'Prijava v brskalniku je bila preklicana ali je potekla.';
            break;
          }
        } catch (_) {
        } finally {
          pollClient.close();
        }
      }
    } catch (_) {
      githubAuthError = 'Napaka pri vzpostavljanju GitHub Device Flow prijave.';
    } finally {
      client.close();
      if (!isGithubConnected) {
        githubDeviceUserCode = '';
        githubAuthStatus = '';
      }
      isGithubAuthenticating = false;
      notifyListeners();
    }
  }

  void cancelGithubAuthFlow() {
    _deviceFlowCancelled = true;
    _activeAuthProcess?.kill();
    _activeAuthProcess = null;
    isGithubAuthenticating = false;
    githubDeviceUserCode = '';
    githubAuthStatus = '';
    notifyListeners();
  }

  Future<void> openGithubQuickTokenCreator() async {
    await openWebUrl(
      'https://github.com/settings/tokens/new?description=ULTRON+Desktop+Studio&scopes=repo,read:user',
    );
  }

  Future<void> disconnectGithub() async {
    cancelGithubAuthFlow();
    githubToken = '';
    githubUsername = '';
    githubDisplayName = '';
    githubAvatarUrl = '';
    githubBio = '';
    githubPublicReposCount = 0;
    githubPrivateReposCount = 0;
    isGithubConnected = false;
    githubRepos.clear();
    githubAuthStatus = '';
    githubAuthError = '';
    await saveRouterConfig();
    notifyListeners();
  }

  Future<void> fetchGithubRepos() async {
    if (githubToken.isEmpty) return;
    isFetchingRepos = true;
    notifyListeners();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    try {
      final req = await client.getUrl(
        Uri.https('api.github.com', '/user/repos', {
          'sort': 'updated',
          'affiliation': 'owner,collaborator,organization_member',
          'per_page': '60',
        }),
      );
      req.headers.set('Authorization', 'Bearer $githubToken');
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'ULTRON');
      final res = await req.close().timeout(const Duration(seconds: 10));

      final rem = res.headers.value('x-ratelimit-remaining');
      final lim = res.headers.value('x-ratelimit-limit');
      if (rem != null) githubRateLimitRemaining = int.tryParse(rem) ?? 60;
      if (lim != null) githubRateLimitTotal = int.tryParse(lim) ?? 60;

      if (res.statusCode == 200) {
        final list =
            jsonDecode(await res.transform(utf8.decoder).join()) as List;
        githubRepos
          ..clear()
          ..addAll(list.whereType<Map<String, dynamic>>().map((r) {
            return GitHubRepoEntry(
              name: r['name']?.toString() ?? '',
              fullName: r['full_name']?.toString() ?? '',
              description: r['description']?.toString() ?? '',
              language: r['language']?.toString() ?? '',
              stargazersCount: (r['stargazers_count'] as num?)?.toInt() ?? 0,
              defaultBranch: r['default_branch']?.toString() ?? 'main',
              updatedAtIso: r['updated_at']?.toString() ?? '',
              cloneUrl: r['clone_url']?.toString() ?? '',
              htmlUrl: r['html_url']?.toString() ?? '',
              isPrivate: r['private'] == true,
            );
          }));
      }
    } catch (_) {
    } finally {
      client.close();
      isFetchingRepos = false;
      notifyListeners();
    }
  }

  Future<String?> cloneRepoAndOpenInUltron(
    GitHubRepoEntry repo, {
    bool openAsActiveProject = true,
  }) async {
    if (cloningRepoFullName != null) return null;
    cloningRepoFullName = repo.fullName;
    notifyListeners();

    try {
      final targetDir = Directory(
          '$currentBrowserDirectory${Platform.pathSeparator}${repo.name}');

      if (await targetDir.exists()) {
        await Process.run(
          'git',
          ['pull'],
          workingDirectory: targetDir.path,
          runInShell: true,
        );
        if (openAsActiveProject) {
          await setActiveProjectFolder(targetDir.path);
        }
        return targetDir.path;
      }

      String effectiveCloneUrl = repo.cloneUrl;
      if (repo.isPrivate &&
          githubToken.isNotEmpty &&
          effectiveCloneUrl.startsWith('https://github.com/')) {
        effectiveCloneUrl = effectiveCloneUrl.replaceFirst(
          'https://github.com/',
          'https://x-access-token:$githubToken@github.com/',
        );
      }

      final res = await Process.run(
        'git',
        ['clone', effectiveCloneUrl, targetDir.path],
        workingDirectory: currentBrowserDirectory,
        runInShell: true,
      );

      if (res.exitCode == 0 && await targetDir.exists()) {
        if (effectiveCloneUrl != repo.cloneUrl) {
          await Process.run(
            'git',
            ['remote', 'set-url', 'origin', repo.cloneUrl],
            workingDirectory: targetDir.path,
            runInShell: true,
          );
        }
        workspaceRevision++;
        if (openAsActiveProject) {
          await setActiveProjectFolder(targetDir.path);
        } else {
          notifyListeners();
        }
        return targetDir.path;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      cloningRepoFullName = null;
      notifyListeners();
    }
  }

  Future<bool> cloneRepoToDesktop(String cloneUrl) async {
    try {
      final res = await Process.run(
        'git',
        ['clone', cloneUrl],
        workingDirectory: currentBrowserDirectory,
        runInShell: true,
      );
      workspaceRevision++;
      notifyListeners();
      return res.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  //**************
  // Preveri lokalni Git status (veja, ahead/behind in spremenjene datoteke) *
  //**************
  Future<void> refreshLocalGitStatus() async {
    final targetDir = effectiveGitDirectory;
    if (targetDir.trim().isEmpty || !Directory(targetDir).existsSync()) {
      localGitBranch = '';
      localGitChangedCount = 0;
      localGitAheadCount = 0;
      localGitBehindCount = 0;
      localGitChangedFiles.clear();
      return;
    }

    try {
      final branchRes = await Process.run(
        'git',
        ['rev-parse', '--abbrev-ref', 'HEAD'],
        workingDirectory: targetDir,
        runInShell: true,
      ).timeout(const Duration(seconds: 2));

      if (branchRes.exitCode != 0) {
        localGitBranch = '';
        localGitChangedCount = 0;
        localGitAheadCount = 0;
        localGitBehindCount = 0;
        localGitChangedFiles.clear();
        notifyListeners();
        return;
      }

      localGitBranch = branchRes.stdout.toString().trim();

      final statusRes = await Process.run(
        'git',
        ['status', '--porcelain', '-b'],
        workingDirectory: targetDir,
        runInShell: true,
      ).timeout(const Duration(seconds: 2));

      if (statusRes.exitCode == 0) {
        final lines = statusRes.stdout
            .toString()
            .split('\n')
            .map((l) => l.trimRight())
            .where((l) => l.trim().isNotEmpty)
            .toList();

        int ahead = 0;
        int behind = 0;
        final changed = <String>[];

        for (final line in lines) {
          if (line.startsWith('##')) {
            final aheadMatch = RegExp(r'ahead\s+(\d+)').firstMatch(line);
            final behindMatch = RegExp(r'behind\s+(\d+)').firstMatch(line);
            if (aheadMatch != null) {
              ahead = int.tryParse(aheadMatch.group(1)!) ?? 0;
            }
            if (behindMatch != null) {
              behind = int.tryParse(behindMatch.group(1)!) ?? 0;
            }
          } else {
            changed.add(line);
          }
        }

        localGitAheadCount = ahead;
        localGitBehindCount = behind;
        localGitChangedFiles
          ..clear()
          ..addAll(changed);
        localGitChangedCount = changed.length;
      }
      notifyListeners();
    } catch (_) {
      localGitBranch = '';
      localGitChangedCount = 0;
      localGitAheadCount = 0;
      localGitBehindCount = 0;
      localGitChangedFiles.clear();
    }
  }

  Future<bool> pullCurrentGitWorkspace() async {
    final targetDir = effectiveGitDirectory;
    if (targetDir.trim().isEmpty) return false;

    isSyncingLocalGit = true;
    notifyListeners();
    try {
      final res = await Process.run(
        'git',
        ['pull'],
        workingDirectory: targetDir,
        runInShell: true,
      ).timeout(const Duration(seconds: 30));

      final out = '${res.stdout}\n${res.stderr}'.trim();
      lastGitActionSummary = out.isEmpty ? 'Že posodobljeno (up to date).' : out;

      if (hasActiveProject) {
        await workspaceService.indexProjectFolder(activeProjectPath);
      }
      await refreshLocalGitStatus();
      workspaceRevision++;
      return res.exitCode == 0;
    } catch (e) {
      lastGitActionSummary = 'Git pull napaka: $e';
      return false;
    } finally {
      isSyncingLocalGit = false;
      notifyListeners();
    }
  }

  Future<bool> commitCurrentGitWorkspace(
    String commitMessage, {
    bool pushAfter = false,
  }) async {
    final targetDir = effectiveGitDirectory;
    if (targetDir.trim().isEmpty) return false;
    final msg = commitMessage.trim().isEmpty
        ? 'feat: posodobitev prek ULTRON'
        : commitMessage.trim();

    isSyncingLocalGit = true;
    notifyListeners();
    try {
      await Process.run(
        'git',
        ['add', '-A'],
        workingDirectory: targetDir,
        runInShell: true,
      ).timeout(const Duration(seconds: 15));

      final commitRes = await Process.run(
        'git',
        ['commit', '-m', msg],
        workingDirectory: targetDir,
        runInShell: true,
      ).timeout(const Duration(seconds: 20));

      final commitOut = '${commitRes.stdout}\n${commitRes.stderr}'.trim();
      lastGitActionSummary = commitOut;

      bool ok = commitRes.exitCode == 0;

      if (pushAfter && ok) {
        isSyncingLocalGit = false;
        final pushOk = await pushCurrentGitWorkspace();
        lastGitActionSummary = '$commitOut\n$lastGitActionSummary'.trim();
        return pushOk;
      }

      await refreshLocalGitStatus();
      return ok;
    } catch (e) {
      lastGitActionSummary = 'Git commit napaka: $e';
      return false;
    } finally {
      isSyncingLocalGit = false;
      notifyListeners();
    }
  }

  Future<bool> pushCurrentGitWorkspace() async {
    final targetDir = effectiveGitDirectory;
    if (targetDir.trim().isEmpty) return false;

    isSyncingLocalGit = true;
    notifyListeners();
    try {
      var res = await Process.run(
        'git',
        ['push'],
        workingDirectory: targetDir,
        runInShell: true,
      ).timeout(const Duration(seconds: 35));

      var out = '${res.stdout}\n${res.stderr}'.trim();

      if (res.exitCode != 0 &&
          localGitBranch.isNotEmpty &&
          out.toLowerCase().contains('upstream')) {
        res = await Process.run(
          'git',
          ['push', '-u', 'origin', localGitBranch],
          workingDirectory: targetDir,
          runInShell: true,
        ).timeout(const Duration(seconds: 35));
        out = '${res.stdout}\n${res.stderr}'.trim();
      }

      lastGitActionSummary = out.isEmpty ? 'Git Push uspešno izveden.' : out;
      await refreshLocalGitStatus();
      return res.exitCode == 0;
    } catch (e) {
      lastGitActionSummary = 'Git push napaka: $e';
      return false;
    } finally {
      isSyncingLocalGit = false;
      notifyListeners();
    }
  }

  void connectJulesApi(String key) {
    isJulesConnected = key.trim().isNotEmpty;
    notifyListeners();
  }

  Future<void> openWebUrl(String url) async {
    try {
      if (Platform.isWindows) {
        await Process.run('cmd', ['/c', 'start', '', url], runInShell: true);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [url]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [url]);
      }
    } catch (_) {}
  }

  String _basename(String path) {
    final cleaned = path.endsWith(Platform.pathSeparator) && path.length > 3
        ? path.substring(0, path.length - 1)
        : path;
    final idx = cleaned.lastIndexOf(Platform.pathSeparator);
    return idx == -1 ? cleaned : cleaned.substring(idx + 1);
  }

  String _extension(String path) {
    final dot = path.lastIndexOf('.');
    final sep = path.lastIndexOf(Platform.pathSeparator);
    if (dot == -1 || dot < sep) return '';
    return path.substring(dot).toLowerCase();
  }
}