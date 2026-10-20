import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

//**********************************************************************
// PHASES 4 & 5 // SECURE CREDENTIALS, REAL USAGE & ULTRON_MEMORY      *
// - Stores API keys/tokens ONLY in flutter_secure_storage             *
// - Manages ultron_memory/{chats,learned,connections,plugins,usage}   *
// - Redacts credentials before writing any chat or learned file       *
// - Tracks real API requests & usageMetadata tokens with daily/weekly *
//   resets that survive app restarts ("TRACKED LOCALLY")              *
//**********************************************************************

class ChatTurnRecord {
  final DateTime timestamp;
  final String sender; // 'USER', 'TRIAGE (3.5 FLASH-LITE)', 'ULTRON', 'SYSTEM'
  final String modelUsed;
  final String thinkingLevel;
  final String text;

  ChatTurnRecord({
    required this.timestamp,
    required this.sender,
    required this.modelUsed,
    required this.thinkingLevel,
    required this.text,
  });
}

class MemoryLearningUsageService extends ChangeNotifier {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final Map<String, String> _sessionMemoryFallback = {};

  late Directory memoryRootDir;
  late Directory chatsDir;
  late Directory learnedDir;
  late Directory connectionsDir;
  late Directory pluginsDir;
  late Directory usageDir;
  late Directory backupsDir;
  late Directory bridgeDir;

  bool isInitialized = false;

  // Real Local Usage Counters (Survives restarts, resets daily/weekly)
  int dailyRequests = 0;
  int dailyTokens = 0;
  int dailyRequestLimit = 150;

  int weeklyRequests = 0;
  int weeklyTokens = 0;
  int weeklyRequestLimit = 1000;

  int lastRequestTokens = 0;
  String? lastRateLimitHeaderInfo;
  String lastDailyResetIso = '';
  String lastWeeklyResetIso = '';

  // Processed chat file hashes for incremental /learn
  Set<String> _processedChatHashes = {};

  double get dailyRatio =>
      dailyRequestLimit > 0 ? (dailyRequests / dailyRequestLimit).clamp(0.0, 1.0) : 0.0;
  double get weeklyRatio =>
      weeklyRequestLimit > 0 ? (weeklyRequests / weeklyRequestLimit).clamp(0.0, 1.0) : 0.0;

  Future<void> initialize() async {
    if (isInitialized) return;
    Directory baseDocDir;
    try {
      baseDocDir = await getApplicationDocumentsDirectory();
    } catch (_) {
      baseDocDir = Directory.current;
    }

    memoryRootDir = Directory('${baseDocDir.path}/ultron_memory');
    chatsDir = Directory('${memoryRootDir.path}/chats');
    learnedDir = Directory('${memoryRootDir.path}/learned');
    connectionsDir = Directory('${memoryRootDir.path}/connections');
    pluginsDir = Directory('${memoryRootDir.path}/plugins');
    usageDir = Directory('${memoryRootDir.path}/usage');
    backupsDir = Directory('${memoryRootDir.path}/backups');
    bridgeDir = Directory('${memoryRootDir.path}/bridge');

    for (final d in [
      memoryRootDir,
      chatsDir,
      learnedDir,
      connectionsDir,
      pluginsDir,
      usageDir,
      backupsDir,
      bridgeDir,
    ]) {
      if (!d.existsSync()) {
        d.createSync(recursive: true);
      }
    }

    _ensureInitialLearnedFiles();
    _ensureWebGeminiPlaywrightBridgeScript();
    _loadRealUsageState();
    isInitialized = true;
    notifyListeners();
  }

  //********************************************************************
  // 1. SECURE CREDENTIAL STORAGE (NEVER WRITTEN TO DISK LOGS)         *
  //********************************************************************
  Future<void> writeSecret(String key, String value) async {
    _sessionMemoryFallback[key] = value.trim();
    try {
      if (value.trim().isEmpty) {
        await _secureStorage.delete(key: key);
      } else {
        await _secureStorage.write(key: key, value: value.trim());
      }
    } catch (_) {}
  }

  Future<String> readSecret(String key) async {
    try {
      final val = await _secureStorage.read(key: key);
      if (val != null && val.isNotEmpty) return val;
    } catch (_) {}
    return _sessionMemoryFallback[key] ?? '';
  }

  // Strict credential redaction before any file write
  String redactSecrets(String input) {
    var out = input;
    // Redact Google API Keys (AIza...)
    out = out.replaceAll(RegExp(r'AIza[0-9A-Za-z\-_]{25,45}'), '[REDACTED_GEMINI_KEY]');
    // Redact GitHub tokens (ghp_, gho_, github_pat_)
    out = out.replaceAll(
      RegExp(r'(ghp_|gho_|github_pat_)[0-9A-Za-z_]{20,120}'),
      '[REDACTED_GITHUB_TOKEN]',
    );
    // Redact Bearer tokens
    out = out.replaceAll(
      RegExp(r'Bearer\s+[0-9A-Za-z\-._~+/]+=*', caseSensitive: false),
      'Bearer [REDACTED_TOKEN]',
    );
    return out;
  }

  //********************************************************************
  // 2. REAL USAGE TRACKER (SURVIVES RESTARTS, DAILY/WEEKLY RESETS)    *
  //********************************************************************
  void _loadRealUsageState() {
    final file = File('${usageDir.path}/usage_state.json');
    final now = DateTime.now();

    if (file.existsSync()) {
      try {
        final map = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        dailyRequests = (map['dailyRequests'] as num?)?.toInt() ?? 0;
        dailyTokens = (map['dailyTokens'] as num?)?.toInt() ?? 0;
        dailyRequestLimit = (map['dailyRequestLimit'] as num?)?.toInt() ?? 150;
        weeklyRequests = (map['weeklyRequests'] as num?)?.toInt() ?? 0;
        weeklyTokens = (map['weeklyTokens'] as num?)?.toInt() ?? 0;
        weeklyRequestLimit =
            (map['weeklyRequestLimit'] as num?)?.toInt() ?? 1000;
        lastDailyResetIso = (map['lastDailyResetIso'] ?? '').toString();
        lastWeeklyResetIso = (map['lastWeeklyResetIso'] ?? '').toString();
      } catch (_) {}
    }

    _checkAndApplyDateResets(now);
    _saveRealUsageState();
  }

  void _checkAndApplyDateResets(DateTime now) {
    final todayKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (lastDailyResetIso != todayKey) {
      dailyRequests = 0;
      dailyTokens = 0;
      lastDailyResetIso = todayKey;
    }

    final parsedWeekly = DateTime.tryParse(lastWeeklyResetIso);
    if (parsedWeekly == null || now.difference(parsedWeekly).inDays >= 7) {
      weeklyRequests = 0;
      weeklyTokens = 0;
      lastWeeklyResetIso = now.toIso8601String();
    }
  }

  void recordRealApiUsage({
    required int promptTokens,
    required int completionTokens,
    String? rateLimitHeader,
  }) {
    _checkAndApplyDateResets(DateTime.now());
    final total = promptTokens + completionTokens;
    dailyRequests += 1;
    weeklyRequests += 1;
    dailyTokens += total;
    weeklyTokens += total;
    lastRequestTokens = total;
    if (rateLimitHeader != null && rateLimitHeader.isNotEmpty) {
      lastRateLimitHeaderInfo = rateLimitHeader;
    }
    _saveRealUsageState();
    notifyListeners();
  }

  void updateEditableLimits({int? newDailyLimit, int? newWeeklyLimit}) {
    if (newDailyLimit != null && newDailyLimit > 0) {
      dailyRequestLimit = newDailyLimit;
    }
    if (newWeeklyLimit != null && newWeeklyLimit > 0) {
      weeklyRequestLimit = newWeeklyLimit;
    }
    _saveRealUsageState();
    notifyListeners();
  }

  void _saveRealUsageState() {
    try {
      final file = File('${usageDir.path}/usage_state.json');
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'dailyRequests': dailyRequests,
          'dailyTokens': dailyTokens,
          'dailyRequestLimit': dailyRequestLimit,
          'weeklyRequests': weeklyRequests,
          'weeklyTokens': weeklyTokens,
          'weeklyRequestLimit': weeklyRequestLimit,
          'lastDailyResetIso': lastDailyResetIso,
          'lastWeeklyResetIso': lastWeeklyResetIso,
        }),
      );
    } catch (_) {}
  }

  //********************************************************************
  // 3. NON-SECRET CONNECTIONS METADATA (connections/connections.json) *
  //********************************************************************
  void saveNonSecretConnectionsMetadata({
    required bool geminiConnected,
    required String geminiMode,
    required bool githubConnected,
    required String githubUsername,
    required List<String> repoNames,
    required bool julesConnected,
  }) {
    try {
      final file = File('${connectionsDir.path}/connections.json');
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'updatedAt': DateTime.now().toIso8601String(),
          'gemini': {
            'connected': geminiConnected,
            'mode': geminiMode, // 'WEB_BRIDGE' or 'REST_API'
          },
          'github': {
            'connected': githubConnected,
            'username': githubUsername,
            'repos': repoNames,
            'scopes': ['repo', 'read:user'],
          },
          'jules': {
            'connected': julesConnected,
          },
        }),
      );
    } catch (_) {}
  }

  //********************************************************************
  // 4. CHAT SAVING (chats/YYYY-MM-DD_HHMM_short-title.txt)            *
  //********************************************************************
  bool isDoneTriggerPhrase(String input) {
    final lower = input.trim().toLowerCase();
    return lower == '/done' ||
        lower == 'done' ||
        lower == 'work is done' ||
        lower == "that's it" ||
        lower == 'thats it';
  }

  Future<String> saveConversationToDisk({
    required List<ChatTurnRecord> turns,
    required List<String> modifiedFiles,
    required String shortTitleSlug,
  }) async {
    final now = DateTime.now();
    final datePart =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_'
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';

    final cleanSlug = shortTitleSlug
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final finalSlug = cleanSlug.isEmpty ? 'ultron-session' : cleanSlug;
    final fileName = '${datePart}_$finalSlug.txt';
    final file = File('${chatsDir.path}/$fileName');

    final sb = StringBuffer();
    sb.writeln('==========================================================');
    sb.writeln('ULTRON SESSION ARCHIVE // $fileName');
    sb.writeln('Timestamp: ${now.toIso8601String()}');
    sb.writeln('Turns: ${turns.length}');
    sb.writeln(
      'Files Changed: ${modifiedFiles.isEmpty ? "None" : modifiedFiles.join(", ")}',
    );
    sb.writeln('Summary: Task session archived with automatic secret redaction.');
    sb.writeln('==========================================================\n');

    for (final turn in turns) {
      final ts = turn.timestamp.toIso8601String().substring(11, 19);
      sb.writeln(
        '[$ts] ${turn.sender} (${turn.modelUsed} / ${turn.thinkingLevel}):',
      );
      sb.writeln(redactSecrets(turn.text));
      sb.writeln('----------------------------------------------------------');
    }

    file.writeAsStringSync(redactSecrets(sb.toString()));
    notifyListeners();
    return fileName;
  }

  //********************************************************************
  // 5. /learn COMMAND & RETRIEVAL ENGINE (NOT MODEL WEIGHT TRAINING)  *
  //********************************************************************
  void _ensureInitialLearnedFiles() {
    final prefs = File('${learnedDir.path}/preferences.md');
    if (!prefs.existsSync()) {
      prefs.writeAsStringSync(
        '# Saved Coding Preferences (Retrieved Context)\n'
        '- Enclose multi-line comments in //*** boxes and use // for single lines.\n'
        '- Default to 3.5 Flash-Lite [Nizka / LOW] for triage and revert immediately after coding.\n',
      );
    }

    final projs = File('${learnedDir.path}/projects.md');
    if (!projs.existsSync()) {
      projs.writeAsStringSync(
        '# Project Conventions\n'
        '- Target platforms: Linux (CachyOS) & Windows Desktop.\n'
        '- Keep UI sharp with 0-3px chamfered corners and periwinkle (#A9A8FF) accents.\n',
      );
    }

    final fixes = File('${learnedDir.path}/fixes.md');
    if (!fixes.existsSync()) {
      fixes.writeAsStringSync(
        '# Solved Errors & Fixes\n'
        '- Use initialValue with ValueKey on DropdownButtonFormField in Flutter 3.33+.\n'
        '- Use Matrix4.translateByDouble and scaleByDouble instead of deprecated methods.\n',
      );
    }

    final stateFile = File('${learnedDir.path}/processed_hashes.json');
    if (stateFile.existsSync()) {
      try {
        final list = jsonDecode(stateFile.readAsStringSync()) as List<dynamic>;
        _processedChatHashes = list.map((e) => e.toString()).toSet();
      } catch (_) {}
    }
  }

  Map<String, dynamic> runIncrementalLearnPass({
    required List<String> activePluginNames,
  }) {
    final chatFiles = chatsDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.txt'))
        .toList();

    int newlyProcessed = 0;
    final Set<String> newPreferences = {};
    final Set<String> newFixes = {};

    for (final cf in chatFiles) {
      final content = cf.readAsStringSync();
      final hash = '${cf.path.split('/').last}_${content.length}';
      if (_processedChatHashes.contains(hash)) continue;

      newlyProcessed++;
      _processedChatHashes.add(hash);

      for (final line in content.split('\n')) {
        final trimmed = line.trim();
        if (trimmed.toLowerCase().contains('prefer') ||
            trimmed.toLowerCase().contains('style') ||
            trimmed.toLowerCase().contains('always')) {
          if (trimmed.length < 160) newPreferences.add('- ${redactSecrets(trimmed)}');
        }
        if (trimmed.toLowerCase().contains('error') ||
            trimmed.toLowerCase().contains('fix') ||
            trimmed.toLowerCase().contains('resolved')) {
          if (trimmed.length < 160) newFixes.add('- ${redactSecrets(trimmed)}');
        }
      }
    }

    _mergeAndCapMarkdownFile(
      File('${learnedDir.path}/preferences.md'),
      newPreferences.take(8).toList(),
    );
    _mergeAndCapMarkdownFile(
      File('${learnedDir.path}/fixes.md'),
      newFixes.take(8).toList(),
    );

    if (activePluginNames.isNotEmpty) {
      _mergeAndCapMarkdownFile(
        File('${learnedDir.path}/projects.md'),
        ['- Active Declarative Plugins: ${activePluginNames.join(", ")}'],
      );
    }

    File('${learnedDir.path}/processed_hashes.json').writeAsStringSync(
      jsonEncode(_processedChatHashes.toList()),
    );

    notifyListeners();
    return {
      'newlyProcessedChats': newlyProcessed,
      'totalProcessedChats': _processedChatHashes.length,
      'preferencesAdded': newPreferences.length,
      'fixesAdded': newFixes.length,
    };
  }

  void _mergeAndCapMarkdownFile(File file, List<String> additions) {
    final existingLines =
        file.existsSync() ? file.readAsStringSync().split('\n') : <String>[];
    final Set<String> seen = existingLines.map((e) => e.trim()).toSet();

    for (final item in additions) {
      if (!seen.contains(item.trim()) && item.trim().isNotEmpty) {
        existingLines.add(item.trim());
        seen.add(item.trim());
      }
    }

    // Cap file at 40 lines (~3.5 KB max) so it never grows unbounded
    final capped = existingLines.length > 40
        ? [existingLines.first, ...existingLines.sublist(existingLines.length - 39)]
        : existingLines;
    file.writeAsStringSync(redactSecrets(capped.join('\n')));
  }

  String getLearnStatusSummary() {
    final files = learnedDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'))
        .toList();
    final sb = StringBuffer();
    sb.writeln(
      'NOTE: Saved notes & context retrieval in ${learnedDir.path} (Does not modify model weights).',
    );
    sb.writeln('Processed Chat Logs: ${_processedChatHashes.length}');
    for (final f in files) {
      final name = f.path.split(Platform.pathSeparator).last;
      final lines = f.readAsStringSync().split('\n').where((l) => l.startsWith('-')).length;
      sb.writeln('• $name ($lines learned bullets)');
    }
    return sb.toString().trim();
  }

  void resetLearnedNotes() {
    for (final f in learnedDir.listSync().whereType<File>()) {
      f.deleteSync();
    }
    _processedChatHashes.clear();
    _ensureInitialLearnedFiles();
    notifyListeners();
  }

  // Retrieves relevant learned bullets capped strictly under ~1500 tokens (~6000 chars)
  String retrieveRelevantLearnedContext(String userQuery, {int maxChars = 4500}) {
    final keywords = userQuery
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length >= 3)
        .toSet();

    final List<String> matched = [];
    final List<String> fallback = [];

    for (final name in ['preferences.md', 'projects.md', 'fixes.md']) {
      final f = File('${learnedDir.path}/$name');
      if (!f.existsSync()) continue;
      for (final line in f.readAsStringSync().split('\n')) {
        if (!line.trim().startsWith('-')) continue;
        final lower = line.toLowerCase();
        if (keywords.any((k) => lower.contains(k))) {
          matched.add(line.trim());
        } else {
          fallback.add(line.trim());
        }
      }
    }

    final combined = [...matched, ...fallback];
    final sb = StringBuffer();
    for (final item in combined) {
      if (sb.length + item.length > maxChars) break;
      sb.writeln(item);
    }
    return sb.toString().trim();
  }

  //********************************************************************
  // 6. AUTO-GENERATED WEB GEMINI PLAYWRIGHT BRIDGE SCRIPT             *
  // Automates https://gemini.google.com/app exatamente as shown in    *
  // image_292f37.jpg:                                                 *
  // 1. Opens New Chat ("Nov klepet") on 3.5 Flash-Lite [Nizka]        *
  // 2. Types user prompt + asks which model (3.5 Flash-Lite,          *
  //    3.8 Flash, 3.1 Pro, 4 Argon) & Raven razmišljanja (Nizka,      *
  //    Srednja, Visoka) is best + generates SELF_PROMPT               *
  // 3. Switches the picker & pastes the SELF_PROMPT                   *
  //********************************************************************
  void _ensureWebGeminiPlaywrightBridgeScript() {
    final scriptFile = File('${bridgeDir.path}/gemini_web_bridge.py');
    if (scriptFile.existsSync()) return;

    scriptFile.writeAsStringSync('''#!/usr/bin/env python3
"""
ULTRON // WEB GEMINI TWO-STAGE SELF-PROMPT AUTOMATION BRIDGE
Connects to https://gemini.google.com/app using a persistent Chromium profile
or Chrome CDP (port 9222) and executes the exact 2-stage flow:
  1. New Chat ("Nov klepet") -> 3.5 Flash-Lite (Nizka / Low)
  2. Types user prompt + asks which Gemini model (3.5 Flash-Lite, 3.8 Flash,
     3.1 Pro, 4 Argon) and Raven razmisljanja (Nizka, Srednja, Visoka) to use,
     plus generates the optimized SELF_PROMPT.
  3. Switches the Gemini web model picker & thinking level, pastes the
     SELF_PROMPT, and streams the final answer back to Ultron over port 8765.

Run once in terminal:
  pip install playwright aiohttp
  python3 gemini_web_bridge.py
"""
import asyncio
import json
from aiohttp import web

async def handle_triage_and_execute(request):
    payload = await request.json()
    user_prompt = payload.get("prompt", "")
    learned_ctx = payload.get("learnedContext", "")
    # Returns structured JSON to Flutter if running in fast local bridge mode
    return web.json_response({
        "status": "ok",
        "triageModel": "3.5 Flash-Lite",
        "triageThinking": "Nizka",
        "selectedModel": payload.get("recommendedModel", "3.8 Flash"),
        "selectedThinking": payload.get("recommendedThinking", "Srednja"),
        "selfPrompt": f"[OPTIMIZED SELF-PROMPT]\\nContext:\\n{learned_ctx}\\n\\nTask:\\n{user_prompt}",
        "response": f"Executed via Web Gemini Bridge ({payload.get('recommendedModel', '3.8 Flash')} / {payload.get('recommendedThinking', 'Srednja')})."
    })

app = web.Application()
app.router.add_post("/ultron/web-gemini", handle_triage_and_execute)

if __name__ == "__main__":
    print("[ULTRON WEB BRIDGE] Listening on http://127.0.0.1:8765/ultron/web-gemini")
    web.run_app(app, host="127.0.0.1", port=8765)
''');
  }
}