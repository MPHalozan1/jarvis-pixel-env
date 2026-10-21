import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../frontend/ultron_bubble_painter.dart';
import 'memory_learning_usage_service.dart';
import 'plugin_manager_service.dart';

//**********************************************************************
// ULTRON BRAIN ROUTER // LIVE VS CODE WRITER & CENTER STREAMER        *
// - Streams conversational answers to the center borderless stage     *
// - Automatically opens the VS Code window & live-writes code blocks  *
//   directly into the active file buffer as Qwen 14B generates them   *
//**********************************************************************

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
  String gitStatusBadge;
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

class UltronBrainRouter extends ChangeNotifier {
  final MemoryLearningUsageService memoryService = MemoryLearningUsageService();
  final PluginManagerService pluginService = PluginManagerService();

  String ollamaBaseUrl = 'http://127.0.0.1:11434';
  String activeLocalModel = 'qwen2.5-coder:14b';
  List<String> installedOllamaModels = ['qwen2.5-coder:14b'];

  final String githubWebUrl = 'https://github.com/';
  final String vsCodeDesktopPath = '/usr/share/applications/code-oss.desktop';

  bool isOllamaOnline = false;
  bool isGithubConnected = false;
  bool isStreamingResponse = false;

  String githubUsername = 'MPHalozan1';
  int githubRateLimitRemaining = 60;
  int githubRateLimitTotal = 60;
  String? githubDeviceUserCode;
  String currentGitBranch = 'main';
  String lastGitCommandOutput = 'Git ready.';

  // Orb & Center Stage State
  OrbState orbState = OrbState.standby;
  bool isOrbCompactTop = false; // Shrinks orb to top-center when chatting!
  double subtleKeystrokePulse = 0.0;
  Timer? _errorResetTimer;

  String statusBanner = 'ULTRON NEURAL CORE READY';
  String? lastErrorBanner;
  String currentPromptLabel = '';
  String currentCenterResponseText = '';

  final List<ChatTurnRecord> chatHistory = [];
  final List<String> modifiedFilesInSession = [];

  // Workspace & VS Code Live Writer State
  late final String userHome;
  late final String desktopProjectsDir;
  String workspaceRootPath = '';
  String? pinnedFolderPath;
  String? pinnedFilePath;
  String searchQuery = '';
  List<FileSystemEntity> currentFolderEntities = [];
  List<GitHubRepoEntry> githubRepos = [];

  bool isResponseWindowOpen = false; // History drawer toggle
  bool isVsCodeWindowOpen = false;
  bool autoApplyEdits = true; // Enabled so Ultron writes directly to VS Code!
  int activeStreamingLineInEditor = -1;

  final List<OpenEditorTab> openTabs = [];
  int activeTabIndex = 0;
  final List<DiffHunkProposal> pendingDiffHunks = [];

  OpenEditorTab? get activeTab =>
      (activeTabIndex >= 0 && activeTabIndex < openTabs.length)
          ? openTabs[activeTabIndex]
          : null;

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
    await _detectGitBranch();
    await checkLocalOllamaHealth();
    await _checkSavedGithubAuth();
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
      subtleKeystrokePulse = (subtleKeystrokePulse - dt * 3.5).clamp(0.0, 1.0);
    }
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
    _errorResetTimer?.cancel();
    _errorResetTimer = Timer(const Duration(milliseconds: 1200), () {
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
  // 1. LOCAL OLLAMA HEALTH & MODEL DISCOVERY                          *
  //********************************************************************
  Future<bool> checkLocalOllamaHealth() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 3);
      final req = await client.getUrl(Uri.parse('$ollamaBaseUrl/api/tags'));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      client.close();

      if (resp.statusCode == 200) {
        final map = jsonDecode(body) as Map<String, dynamic>;
        final models = (map['models'] as List<dynamic>? ?? []);
        final names = models
            .map((m) => ((m as Map<String, dynamic>)['name'] ?? '').toString())
            .where((n) => n.isNotEmpty)
            .toList();

        if (names.isNotEmpty) {
          installedOllamaModels = names;
          if (names.any((n) => n.contains('qwen2.5-coder:14b'))) {
            activeLocalModel =
                names.firstWhere((n) => n.contains('qwen2.5-coder:14b'));
          } else if (!names.contains(activeLocalModel)) {
            activeLocalModel = names.first;
          }
        }
        isOllamaOnline = true;
        _syncConnectionsMetadataFile();
        _showToastBanner('ONLINE // ${activeLocalModel.toUpperCase()} READY');
        return true;
      }
    } catch (_) {}

    isOllamaOnline = false;
    _showToastBanner('OLLAMA OFFLINE // CHECK $ollamaBaseUrl');
    return false;
  }

  void selectLocalOllamaModel(String modelName) {
    activeLocalModel = modelName;
    _syncConnectionsMetadataFile();
    _showToastBanner('MODEL: ${modelName.toUpperCase()}');
  }

  //********************************************************************
  // 2. SNAPPY CENTER STREAMING + LIVE VS CODE WINDOW CODE WRITING     *
  //********************************************************************
  Future<void> executeUltronPrompt(String rawInput) async {
    final input = rawInput.trim();
    if (input.isEmpty || isStreamingResponse) return;

    // Move Orb to top-center so Ultron's borderless response floats in the middle!
    isOrbCompactTop = true;
    currentPromptLabel = input;

    if (input.toLowerCase() == '/learn status') {
      currentCenterResponseText = memoryService.getLearnStatusSummary();
      _showToastBanner('DISPLAYED /learn STATUS');
      return;
    }

    if (input.toLowerCase() == '/learn reset') {
      memoryService.resetLearnedNotes();
      currentCenterResponseText =
          'Learned notes reset to baseline in ultron_memory/learned/.';
      _showToastBanner('LEARNED NOTES RESET');
      return;
    }

    if (input.toLowerCase() == '/learn') {
      await learnFromProjectsAndChats();
      return;
    }

    if (input.toLowerCase() == '/pull') {
      await gitPull();
      return;
    }

    if (input.toLowerCase().startsWith('/commit')) {
      final msg = input.length > 7
          ? input.substring(7).trim()
          : 'feat: update via Ultron Neural Core';
      await gitCommitAndPush(commitMessage: msg, pushAfter: false);
      return;
    }

    if (input.toLowerCase() == '/push') {
      await gitPush();
      return;
    }

    if (memoryService.isDoneTriggerPhrase(input)) {
      final savedName = await memoryService.saveConversationToDisk(
        turns: chatHistory,
        modifiedFiles: modifiedFilesInSession,
        shortTitleSlug:
            chatHistory.isNotEmpty ? chatHistory.first.text.takeWords(4) : 'session',
      );
      currentCenterResponseText =
          'Session archived to ultron_memory/chats/$savedName';
      _showToastBanner('CHAT SAVED // $savedName');
      return;
    }

    _appendTurn(
      sender: 'USER',
      model: activeLocalModel,
      level: 'LOCAL',
      text: input,
    );

    if (!isOllamaOnline) {
      final ok = await checkLocalOllamaHealth();
      if (!ok) {
        triggerErrorState('Ollama server offline at $ollamaBaseUrl');
        return;
      }
    }

    isStreamingResponse = true;
    orbState = OrbState.thinking;
    currentCenterResponseText = '';
    _showToastBanner('${activeLocalModel.toUpperCase()} THINKING...');

    final learnedContext =
        memoryService.retrieveRelevantLearnedContext(input, maxChars: 3200);
    final pluginContext = pluginService.buildLazyLoadedPluginContext(input);

    String activeFileContext = '';
    if (activeTab != null) {
      final snippet = activeTab!.lines.take(90).join('\n');
      activeFileContext =
          '\n[OPEN FILE IN VS CODE WINDOW: ${activeTab!.filePath}]:\n```\n$snippet\n```';
    }

    final systemPrompt =
        'You are Ultron, an advanced AI system and coding architect running locally on CachyOS (Intel Arc B570).\n'
        'Speak concisely, directly, and with sharp technical clarity.\n'
        'Whenever you write or modify code, wrap the code in a standard ```language ... ``` block. '
        'If the user specifies a file name (or if you are creating a new file), put "// file: relative/path.ext" on the first line inside the code block so it writes directly into the VS Code window.\n'
        'Learned preferences:\n$learnedContext\n'
        '$pluginContext'
        '$activeFileContext';

    final responseTurn = ChatTurnRecord(
      timestamp: DateTime.now(),
      sender: 'ULTRON',
      modelUsed: activeLocalModel,
      thinkingLevel: 'STREAMING',
      text: '',
    );
    chatHistory.add(responseTurn);

    final stopwatch = Stopwatch()..start();
    int evalCount = 0;
    int promptEvalCount = (systemPrompt.length + input.length) ~/ 4;
    final StringBuffer fullRawBuffer = StringBuffer();

    bool liveEditorPreparedForThisStream = false;
    List<String> preStreamEditorPrefixLines = [];

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      final req = await client.postUrl(Uri.parse('$ollamaBaseUrl/api/chat'));
      req.headers.set('Content-Type', 'application/json');

      final recentMessages = <Map<String, String>>[
        {'role': 'system', 'content': systemPrompt},
      ];
      final startIdx = (chatHistory.length - 7).clamp(0, chatHistory.length - 1);
      for (int i = startIdx; i < chatHistory.length - 1; i++) {
        final h = chatHistory[i];
        recentMessages.add({
          'role': h.sender == 'USER' ? 'user' : 'assistant',
          'content': h.text,
        });
      }

      req.add(
        utf8.encode(
          jsonEncode({
            'model': activeLocalModel,
            'messages': recentMessages,
            'stream': true,
          }),
        ),
      );

      final resp = await req.close();
      if (resp.statusCode != 200) {
        final errBody = await resp.transform(utf8.decoder).join();
        client.close();
        throw Exception('Ollama HTTP ${resp.statusCode}:$errBody');
      }

      orbState = OrbState.answering;
      memoryService.updateLiveStreamingSpeed(0.0, generating: true);

      await for (final chunk
          in resp.transform(utf8.decoder).transform(const LineSplitter())) {
        if (chunk.trim().isEmpty) continue;
        try {
          final data = jsonDecode(chunk) as Map<String, dynamic>;
          final msg = data['message'] as Map<String, dynamic>?;
          final tokenPiece = (msg?['content'] ?? '').toString();

          if (tokenPiece.isNotEmpty) {
            fullRawBuffer.write(tokenPiece);
            evalCount++;

            final elapsedSec =
                (stopwatch.elapsedMilliseconds / 1000.0).clamp(0.05, 3600.0);
            final liveTps = evalCount / elapsedSec;
            memoryService.updateLiveStreamingSpeed(liveTps, generating: true);

            final rawSoFar = fullRawBuffer.toString();

            // Check if Ultron is streaming a code block -> Write it LIVE into the VS Code Window!
            final fenceStart = rawSoFar.indexOf('```');
            if (fenceStart != -1) {
              final afterFence = rawSoFar.substring(fenceStart + 3);
              final firstNewline = afterFence.indexOf('\n');
              if (firstNewline != -1) {
                var codeBody = afterFence.substring(firstNewline + 1);
                final closingFence = codeBody.indexOf('```');
                if (closingFence != -1) {
                  codeBody = codeBody.substring(0, closingFence);
                }

                if (!liveEditorPreparedForThisStream) {
                  liveEditorPreparedForThisStream = true;
                  await _prepareTargetTabForLiveCodeStream(codeBody);
                  if (activeTab != null) {
                    _createPreEditBackupSnapshot(activeTab!);
                    preStreamEditorPrefixLines = List<String>.from(activeTab!.lines);
                  }
                }

                // Write the incoming code lines directly into the VS Code window tab!
                if (activeTab != null && autoApplyEdits) {
                  final incomingCodeLines = codeBody.split('\n');
                  // If the code specifies "// file: ...", replace file content cleanly; otherwise append/update
                  final isFullFileWrite =
                      codeBody.trimLeft().startsWith('// file:') ||
                      codeBody.contains('void main(') ||
                      codeBody.contains('import \'package:');
                  if (isFullFileWrite) {
                    activeTab!.lines = incomingCodeLines;
                  } else {
                    activeTab!.lines = [
                      ...preStreamEditorPrefixLines,
                      '',
                      ...incomingCodeLines,
                    ];
                  }
                  activeTab!.gitStatusBadge = 'M';
                  activeStreamingLineInEditor = activeTab!.lines.length - 1;
                }
              }
            }

            // Keep the center floating text clean (strip giant code blocks and show live editor badge)
            currentCenterResponseText = _formatCleanCenterText(
              rawSoFar,
              activeFileName: activeTab?.fileName ?? 'workspace buffer',
            );
            responseTurn.text = rawSoFar;
            subtleKeystrokePulse = 0.45;
            notifyListeners();
          }

          if (data['done'] == true) {
            promptEvalCount =
                (data['prompt_eval_count'] as num?)?.toInt() ?? promptEvalCount;
            evalCount = (data['eval_count'] as num?)?.toInt() ?? evalCount;
          }
        } catch (_) {}
      }
      client.close();

      stopwatch.stop();
      final totalSec =
          (stopwatch.elapsedMilliseconds / 1000.0).clamp(0.1, 3600.0);
      final finalTps = evalCount / totalSec;

      final finalRaw = fullRawBuffer.toString().trim();
      responseTurn.text = finalRaw;
      responseTurn.thinkingLevel = '${finalTps.toStringAsFixed(1)} tok/s';
      currentCenterResponseText = _formatCleanCenterText(
        finalRaw,
        activeFileName: activeTab?.fileName ?? 'workspace buffer',
      );

      // Persist live-written code to disk if Ultron wrote code into the VS Code window
      if (liveEditorPreparedForThisStream && activeTab != null) {
        if (autoApplyEdits) {
          File(activeTab!.filePath)
              .writeAsStringSync(activeTab!.lines.join('\n'));
          if (!modifiedFilesInSession.contains(activeTab!.fileName)) {
            modifiedFilesInSession.add(activeTab!.fileName);
          }
        } else {
          final extracted = extractFirstCodeBlock(finalRaw);
          if (extracted != null) {
            proposeCodeBlockAsDiffHunk(
              codeBlock: extracted,
              description: 'Generated by $activeLocalModel',
            );
          }
        }
      }

      activeStreamingLineInEditor = -1;
      memoryService.recordLocalOllamaUsage(
        promptTokens: promptEvalCount,
        completionTokens: evalCount,
        tokensPerSec: finalTps,
      );

      orbState = OrbState.standby;
      isStreamingResponse = false;
      _showToastBanner(
        'COMPLETE // ${finalTps.toStringAsFixed(1)} TOK/S',
      );
    } catch (e) {
      isStreamingResponse = false;
      activeStreamingLineInEditor = -1;
      memoryService.updateLiveStreamingSpeed(0.0, generating: false);
      triggerErrorState(e.toString());
    }
  }

  // Ensures a target file tab is open in the VS Code Window when Ultron starts writing code
  Future<void> _prepareTargetTabForLiveCodeStream(String initialCode) async {
    isVsCodeWindowOpen = true;
    final firstLine = initialCode.split('\n').first.trim();
    if (firstLine.startsWith('// file:')) {
      final relPath = firstLine.replaceFirst('// file:', '').trim();
      if (relPath.isNotEmpty) {
        final fullPath = '$workspaceRootPath/$relPath';
        final f = File(fullPath);
        if (isPathInsideWorkspace(fullPath)) {
          if (!f.existsSync()) {
            f.parent.createSync(recursive: true);
            f.writeAsStringSync('');
          }
          await openFileInEditorTab(fullPath, autoOpenWindow: true);
          return;
        }
      }
    }

    if (openTabs.isEmpty) {
      final fallback = File('$workspaceRootPath/lib/main.dart').existsSync()
          ? '$workspaceRootPath/lib/main.dart'
          : '$workspaceRootPath/README.md';
      await openFileInEditorTab(fallback, autoOpenWindow: true);
    }
  }

  // Replaces bulky code blocks in the center floating view with a clean live-writing indicator
  String _formatCleanCenterText(
    String rawMarkdown, {
    required String activeFileName,
  }) {
    final closedHandled = rawMarkdown.replaceAll(
      RegExp(r'```(?:[a-zA-Z0-9_+-]+)?\n[\s\S]*?```'),
      '\n⚡ [CODE WRITTEN LIVE TO VS CODE WINDOW -> $activeFileName]\n',
    );
    final openFenceIdx = closedHandled.indexOf('```');
    if (openFenceIdx != -1) {
      return '${closedHandled.substring(0, openFenceIdx).trim()}\n\n⚡ [STREAMING CODE LIVE INTO VS CODE WINDOW -> $activeFileName...]';
    }
    return closedHandled.replaceAll('**', '').trim();
  }

  String? extractFirstCodeBlock(String markdown) {
    final reg = RegExp(r'```(?:[a-zA-Z0-9_+-]+)?\n([\s\S]*?)```');
    final match = reg.firstMatch(markdown);
    return match?.group(1);
  }

  void proposeCodeBlockAsDiffHunk({
    required String codeBlock,
    required String description,
  }) {
    if (openTabs.isEmpty) {
      final fallback = File('$workspaceRootPath/lib/main.dart').existsSync()
          ? '$workspaceRootPath/lib/main.dart'
          : '$workspaceRootPath/README.md';
      openFileInEditorTab(fallback, autoOpenWindow: true);
    }
    final tab = activeTab;
    if (tab == null) return;

    final proposedLines = codeBlock.trimRight().split('\n');
    final startLine = (tab.lines.length > 4) ? tab.lines.length - 2 : 1;
    final orig = tab.lines.sublist(startLine - 1);

    final hunk = DiffHunkProposal(
      id: 'hunk_${DateTime.now().millisecondsSinceEpoch}',
      filePath: tab.filePath,
      startLine: startLine,
      originalLines: orig,
      proposedLines: [...orig, '', ...proposedLines],
      description: description,
    );

    if (autoApplyEdits) {
      acceptDiffHunk(hunk);
    } else {
      pendingDiffHunks.insert(0, hunk);
      isVsCodeWindowOpen = true;
      notifyListeners();
    }
  }

  //********************************************************************
  // 3. /learn PROJECT CODE SCANNER                                    *
  //********************************************************************
  Future<void> learnFromProjectsAndChats() async {
    orbState = OrbState.thinking;
    isOrbCompactTop = true;
    currentPromptLabel = '/learn';
    currentCenterResponseText =
        'Scanning workspace source files (.dart, .c, .cpp, .cs, .go, .rs, .ts)...';
    _showToastBanner('SCANNING PROJECT CODE FOR /learn...');

    final result = memoryService.runIncrementalLearnPass(
      activePluginNames: pluginService.installedPlugins
          .where((p) => p.isEnabled)
          .map((p) => p.name)
          .toList(),
      projectDirectoriesToScan: [
        workspaceRootPath,
        '$userHome/Projects',
        desktopProjectsDir,
      ],
    );

    orbState = OrbState.standby;
    final summary =
        'Codebase & Chat Learning Complete\n\n'
        '• Source code files analyzed: ${result['scannedCodeFiles']}\n'
        '• Languages indexed: ${result['languages']}\n'
        '• Newly processed chat archives: ${result['newlyProcessedChats']}\n'
        '• Patterns saved to ultron_memory/learned/projects.md & preferences.md';

    currentCenterResponseText = summary;
    _appendTurn(
      sender: 'ULTRON',
      model: activeLocalModel,
      level: 'CODE LEARNER',
      text: summary,
    );
    _showToastBanner(
      '/learn COMPLETE // ${result['scannedCodeFiles']} FILES INDEXED',
    );
  }

  //********************************************************************
  // 4. GIT AUTOMATION (git pull, git commit, git push)                *
  //********************************************************************
  Future<void> _detectGitBranch() async {
    try {
      final res = await Process.run(
        'git',
        ['rev-parse', '--abbrev-ref', 'HEAD'],
        workingDirectory: workspaceRootPath,
      );
      if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
        currentGitBranch = res.stdout.toString().trim();
      }
    } catch (_) {}
    notifyListeners();
  }

  Future<void> gitPull() async {
    orbState = OrbState.thinking;
    isOrbCompactTop = true;
    currentPromptLabel = 'git pull';
    _showToastBanner('EXECUTING: git pull...');
    try {
      final res = await Process.run(
        'git',
        ['pull'],
        workingDirectory: workspaceRootPath,
      );
      final out = '${res.stdout}\n${res.stderr}'.trim();
      lastGitCommandOutput = out.isEmpty ? 'Already up to date.' : out;
      currentCenterResponseText = lastGitCommandOutput;
      orbState = OrbState.standby;
      refreshDirectoryEntities(workspaceRootPath);
      _showToastBanner('GIT PULL COMPLETE ($currentGitBranch)');
    } catch (e) {
      triggerErrorState('git pull failed: $e');
    }
  }

  Future<void> gitCommitAndPush({
    required String commitMessage,
    bool pushAfter = true,
  }) async {
    final msg = commitMessage.trim().isEmpty
        ? 'feat: update via Ultron Neural Core'
        : commitMessage.trim();
    orbState = OrbState.thinking;
    isOrbCompactTop = true;
    currentPromptLabel = pushAfter ? 'git commit & push' : 'git commit';
    _showToastBanner('COMMITTING: "$msg"...');

    try {
      await Process.run('git', ['add', '.'], workingDirectory: workspaceRootPath);
      final commitRes = await Process.run(
        'git',
        ['commit', '-m', msg],
        workingDirectory: workspaceRootPath,
      );
      final commitOut = '${commitRes.stdout}\n${commitRes.stderr}'.trim();
      lastGitCommandOutput = commitOut;

      if (pushAfter) {
        final pushRes = await Process.run(
          'git',
          ['push', 'origin', currentGitBranch],
          workingDirectory: workspaceRootPath,
        );
        final pushOut = '${pushRes.stdout}\n${pushRes.stderr}'.trim();
        lastGitCommandOutput = '$commitOut\n$pushOut'.trim();
      }

      currentCenterResponseText = lastGitCommandOutput;
      orbState = OrbState.standby;
      _showToastBanner(
        pushAfter ? 'GIT COMMIT & PUSH COMPLETE' : 'GIT COMMIT COMPLETE',
      );
    } catch (e) {
      triggerErrorState('Git operation failed: $e');
    }
  }

  Future<void> gitPush() async {
    orbState = OrbState.thinking;
    isOrbCompactTop = true;
    currentPromptLabel = 'git push';
    _showToastBanner('PUSHING TO origin/$currentGitBranch...');
    try {
      final res = await Process.run(
        'git',
        ['push', 'origin', currentGitBranch],
        workingDirectory: workspaceRootPath,
      );
      final out = '${res.stdout}\n${res.stderr}'.trim();
      lastGitCommandOutput = out.isEmpty ? 'Push succeeded.' : out;
      currentCenterResponseText = lastGitCommandOutput;
      orbState = OrbState.standby;
      _showToastBanner('GIT PUSH COMPLETE ($currentGitBranch)');
    } catch (e) {
      triggerErrorState('git push failed: $e');
    }
  }

  Future<void> _checkSavedGithubAuth() async {
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
      await fetchGithubRepos(githubUsername);
    }
  }

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
          await client.getUrl(Uri.parse('https://api.github.com/user'));
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

  Future<void> startGithubDeviceFlow(String oauthClientId) async {
    final cid = oauthClientId.trim();
    if (cid.isEmpty) {
      triggerErrorState('Enter a GitHub OAuth Client ID or paste a PAT.');
      return;
    }

    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      final req = await client.postUrl(
        Uri.parse('https://github.com/login/device/code'),
      );
      req.headers.set('Accept', 'application/json');
      req.headers.set('Content-Type', 'application/json');
      req.add(
          utf8.encode(jsonEncode({'client_id': cid, 'scope': 'repo read:user'})));
      final resp = await req.close();
      final body = await resp.transform(utf8.decoder).join();
      client.close();

      final map = jsonDecode(body) as Map<String, dynamic>;
      if (map.containsKey('user_code')) {
        githubDeviceUserCode = map['user_code'].toString();
        final uri = (map['verification_uri'] ?? 'https://github.com/login/device')
            .toString();
        await openWebUrl(uri);
        _showToastBanner('GITHUB DEVICE CODE: $githubDeviceUserCode');
      } else {
        triggerErrorState('GitHub Device Flow error: $body');
      }
    } catch (e) {
      triggerErrorState('Device Flow failed: $e');
    }
  }

  Future<void> fetchGithubRateLimit() async {
    final token = await memoryService.readSecret('github_token');
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 6);
      final req =
          await client.getUrl(Uri.parse('https://api.github.com/rate_limit'));
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
            (rate['remaining'] as num?)?.toInt() ?? 60;
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
          ? Uri.parse('https://api.github.com/user/repos?sort=updated&per_page=30')
          : Uri.parse(
              'https://api.github.com/users/$user/repos?sort=updated&per_page=30',
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
        _syncConnectionsMetadataFile();
      }
      client.close();
    } catch (_) {}
    notifyListeners();
  }

  void _syncConnectionsMetadataFile() {
    memoryService.saveNonSecretConnectionsMetadata(
      ollamaConnected: isOllamaOnline,
      activeLocalModel: activeLocalModel,
      githubConnected: isGithubConnected,
      githubUsername: githubUsername,
      repoNames: githubRepos.map((r) => r.fullName).toList(),
    );
  }

  void startNewChatSession() {
    chatHistory.clear();
    currentPromptLabel = '';
    currentCenterResponseText = '';
    isOrbCompactTop = false;
    _showToastBanner('NEW SESSION STARTED');
  }

  void loadSavedChatArchiveIntoView(SavedChatArchive archive) {
    final turns = memoryService.loadArchivedConversation(archive.filePath);
    if (turns.isNotEmpty) {
      chatHistory
        ..clear()
        ..addAll(turns);
      isOrbCompactTop = true;
      currentPromptLabel = archive.fileName;
      currentCenterResponseText = turns.last.text;
      isResponseWindowOpen = false;
      _showToastBanner('LOADED ARCHIVE: ${archive.fileName}');
    }
  }

  //********************************************************************
  // 5. WORKSPACE FILE SYSTEM & MULTI-TAB CODE EDITOR                  *
  //********************************************************************
  bool isPathInsideWorkspace(String candidatePath) {
    try {
      final normRoot = Directory(workspaceRootPath).absolute.path;
      final normTarget = File(candidatePath).absolute.path;
      return normTarget.startsWith(normRoot) ||
          normTarget.startsWith(memoryService.memoryRootDir.path) ||
          normTarget.startsWith('$userHome/Projects') ||
          normTarget.startsWith(desktopProjectsDir);
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
    return dirs.where((p) => Directory(p).existsSync()).toSet().toList();
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
    _detectGitBranch();
    notifyListeners();
  }

  void pinFolderOnTop(String folderPath) {
    pinnedFolderPath = folderPath;
    pinnedFilePath = null;
    workspaceRootPath = folderPath;
    searchQuery = '';
    refreshDirectoryEntities(folderPath);
    _showToastBanner(
      'PINNED PROJECT: ${folderPath.split(Platform.pathSeparator).last}',
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
    _showToastBanner('STACK RETURNED TO HOME');
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
    _showToastBanner('SAVED ${tab.fileName}');
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
    _showToastBanner('RESTORED ${tab.fileName} FROM BACKUP');
  }

  void acceptDiffHunk(DiffHunkProposal hunk) {
    final tabIdx = openTabs.indexWhere((t) => t.filePath == hunk.filePath);
    if (tabIdx >= 0) {
      final tab = openTabs[tabIdx];
      _createPreEditBackupSnapshot(tab);
      final prefix = tab.lines
          .sublist(0, (hunk.startLine - 1).clamp(0, tab.lines.length));
      tab.lines = [...prefix, ...hunk.proposedLines];
      tab.gitStatusBadge = 'M';
      File(tab.filePath).writeAsStringSync(tab.lines.join('\n'));
      if (!modifiedFilesInSession.contains(tab.fileName)) {
        modifiedFilesInSession.add(tab.fileName);
      }
    }
    hunk.isAccepted = true;
    pendingDiffHunks.remove(hunk);
    _showToastBanner('DIFF ACCEPTED & WRITTEN TO DISK');
  }

  void rejectDiffHunk(DiffHunkProposal hunk) {
    hunk.isRejected = true;
    pendingDiffHunks.remove(hunk);
    _showToastBanner('DIFF REJECTED');
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
    _showToastBanner('CLONING ${repo.fullName}...');
    try {
      final root = Directory(desktopProjectsDir);
      if (!root.existsSync()) root.createSync(recursive: true);
      if (!Directory(target).existsSync()) {
        await Process.run(
            'git', ['clone', '--depth', '1', repo.cloneUrl, target]);
      }
      repo.isCloned = true;
      repo.localPath = target;
      pinFolderOnTop(target);
      isVsCodeWindowOpen = true;
      _showToastBanner('CLONED & MOUNTED ${repo.name}');
    } catch (e) {
      triggerErrorState('Git clone failed: $e');
    }
  }

  void _appendTurn({
    required String sender,
    required String model,
    required String level,
    required String text,
  }) {
    chatHistory.add(
      ChatTurnRecord(
        timestamp: DateTime.now(),
        sender: sender,
        modelUsed: model,
        thinkingLevel: level,
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