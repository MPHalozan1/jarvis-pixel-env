import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

//**************
// Posamezno naučeno pravilo ali arhitekturni vzorec v spominu ULTRON-a *
// Shranjuje se na disk in se samodejno vključuje v sistemski kontekst LLM-ja *
//**************
class LearningEntry {
  final String id;
  final String category;
  final String title;
  final String rule;
  final String source;
  final String projectPath;
  final bool pinned;
  final double confidence;
  final DateTime updatedAt;

  const LearningEntry({
    required this.id,
    required this.category,
    required this.title,
    required this.rule,
    required this.source,
    this.projectPath = '',
    this.pinned = false,
    this.confidence = 0.85,
    required this.updatedAt,
  });

  bool get isGlobal => projectPath.trim().isEmpty;

  LearningEntry copyWith({
    String? category,
    String? title,
    String? rule,
    String? source,
    String? projectPath,
    bool? pinned,
    double? confidence,
    DateTime? updatedAt,
  }) {
    return LearningEntry(
      id: id,
      category: category ?? this.category,
      title: title ?? this.title,
      rule: rule ?? this.rule,
      source: source ?? this.source,
      projectPath: projectPath ?? this.projectPath,
      pinned: pinned ?? this.pinned,
      confidence: confidence ?? this.confidence,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'title': title,
        'rule': rule,
        'source': source,
        'projectPath': projectPath,
        'pinned': pinned,
        'confidence': confidence,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory LearningEntry.fromJson(Map<String, dynamic> json) {
    return LearningEntry(
      id: json['id']?.toString() ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      category: json['category']?.toString() ?? 'code_style',
      title: json['title']?.toString() ?? 'Naučeno pravilo',
      rule: json['rule']?.toString() ?? '',
      source: json['source']?.toString() ?? 'workspace',
      projectPath: json['projectPath']?.toString() ?? '',
      pinned: json['pinned'] == true,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.85,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

//**************
// Zapis posamezne izmenjave v pogovoru z metapodatki o hitrosti in trajanju *
//**************
class ChatTurnRecord {
  final String role;
  final String content;
  final String modelUsed;
  final List<String> attachedFiles;
  final DateTime timestamp;
  final double tokensPerSec;
  final int generationDurationMs;

  const ChatTurnRecord({
    required this.role,
    required this.content,
    required this.modelUsed,
    this.attachedFiles = const [],
    required this.timestamp,
    this.tokensPerSec = 0.0,
    this.generationDurationMs = 0,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'modelUsed': modelUsed,
        'attachedFiles': attachedFiles,
        'timestamp': timestamp.toIso8601String(),
        'tokensPerSec': tokensPerSec,
        'generationDurationMs': generationDurationMs,
      };

  factory ChatTurnRecord.fromJson(Map<String, dynamic> json) {
    return ChatTurnRecord(
      role: json['role']?.toString() ?? 'user',
      content: json['content']?.toString() ?? '',
      modelUsed: json['modelUsed']?.toString() ?? 'local',
      attachedFiles: (json['attachedFiles'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
      tokensPerSec: (json['tokensPerSec'] as num?)?.toDouble() ?? 0.0,
      generationDurationMs:
          (json['generationDurationMs'] as num?)?.toInt() ?? 0,
    );
  }
}

//**************
// Metapodatki projekta: ime projekta, ali je zaključen, ter izbirni rok oddaje *
//**************
class UltronProjectMeta {
  final String projectPath;
  final String projectName;
  final bool isCompleted;
  final String deadlineIso;
  final DateTime updatedAt;

  const UltronProjectMeta({
    required this.projectPath,
    required this.projectName,
    this.isCompleted = false,
    this.deadlineIso = '',
    required this.updatedAt,
  });

  bool get hasDeadline => deadlineIso.trim().isNotEmpty;

  DateTime? get deadlineDate =>
      hasDeadline ? DateTime.tryParse(deadlineIso.trim()) : null;

  int? get daysUntilDeadline {
    final d = deadlineDate;
    if (d == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(d.year, d.month, d.day);
    return target.difference(today).inDays;
  }

  String get formattedDeadline {
    final d = deadlineDate;
    if (d == null) return '';
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    return '$day. $month. ${d.year}';
  }

  String get statusLabel => isCompleted ? 'Zaključeno' : 'V delu';

  String get deadlineSummaryLabel {
    if (!hasDeadline) return '';
    if (isCompleted) return 'Rok: $formattedDeadline';
    final days = daysUntilDeadline ?? 0;
    if (days == 0) return 'Rok: danes!';
    if (days == 1) return 'Rok: jutri';
    if (days > 1 && days <= 14) return 'Čez $days dni · $formattedDeadline';
    if (days < 0) return 'Zamuda ${days.abs()}d · $formattedDeadline';
    return 'Rok: $formattedDeadline';
  }

  UltronProjectMeta copyWith({
    String? projectPath,
    String? projectName,
    bool? isCompleted,
    String? deadlineIso,
    DateTime? updatedAt,
  }) {
    return UltronProjectMeta(
      projectPath: projectPath ?? this.projectPath,
      projectName: projectName ?? this.projectName,
      isCompleted: isCompleted ?? this.isCompleted,
      deadlineIso: deadlineIso ?? this.deadlineIso,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'projectPath': projectPath,
        'projectName': projectName,
        'isCompleted': isCompleted,
        'deadlineIso': deadlineIso,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory UltronProjectMeta.fromJson(Map<String, dynamic> json) {
    final rawPath = json['projectPath']?.toString() ?? '';
    return UltronProjectMeta(
      projectPath: MemoryLearningUsageService.normalizeProjectPath(rawPath),
      projectName: json['projectName']?.toString() ?? 'Projekt',
      isCompleted: json['isCompleted'] == true,
      deadlineIso: json['deadlineIso']?.toString() ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

//**************
// Povzetek shranjene seje pogovora v mapi ultron_memory/chats *
//**************
class SavedChatArchive {
  final String sessionId;
  final String filePath;
  final String title;
  final String projectPath;
  final String projectName;
  final bool pinned;
  final bool customTitled;
  final String previewSnippet;
  final int messageCount;
  final DateTime createdAt;
  final DateTime savedAt;

  const SavedChatArchive({
    required this.sessionId,
    required this.filePath,
    required this.title,
    this.projectPath = '',
    this.projectName = '',
    this.pinned = false,
    this.customTitled = false,
    this.previewSnippet = '',
    required this.messageCount,
    required this.createdAt,
    required this.savedAt,
  });

  bool get hasProject => projectPath.trim().isNotEmpty;

  SavedChatArchive copyWith({
    String? title,
    String? projectPath,
    String? projectName,
    bool? pinned,
    bool? customTitled,
    String? previewSnippet,
    int? messageCount,
    DateTime? savedAt,
  }) {
    return SavedChatArchive(
      sessionId: sessionId,
      filePath: filePath,
      title: title ?? this.title,
      projectPath: projectPath ?? this.projectPath,
      projectName: projectName ?? this.projectName,
      pinned: pinned ?? this.pinned,
      customTitled: customTitled ?? this.customTitled,
      previewSnippet: previewSnippet ?? this.previewSnippet,
      messageCount: messageCount ?? this.messageCount,
      createdAt: createdAt,
      savedAt: savedAt ?? this.savedAt,
    );
  }
}

class LoadedChatSession {
  final SavedChatArchive archive;
  final List<ChatTurnRecord> turns;

  const LoadedChatSession({
    required this.archive,
    required this.turns,
  });
}

//**************
// Servis za učenje (Learn), zgodovino projektnih sej, register projektov in telemetrijo *
//**************
class MemoryLearningUsageService extends ChangeNotifier {
  late Directory _vaultDir;
  late Directory _learnedDir;
  late Directory _chatsDir;
  late File _knowledgeFile;
  late File _telemetryFile;
  late File _projectsFile;

  bool _initialized = false;
  bool isLearningNow = false;
  String lastLearnSummary = 'Pripravljen na učenje';

  int dailyRequests = 0;
  int totalTokensGenerated = 0;
  double liveTokensPerSecond = 0.0;
  bool autoLearnEnabled = true;

  final List<LearningEntry> learnedEntries = [];
  final List<SavedChatArchive> savedChatArchives = [];
  final List<UltronProjectMeta> projectRegistry = [];

  static String normalizeProjectPath(String raw) {
    String p = raw.trim();
    if (p.isEmpty) return '';
    p = p
        .replaceAll('/', Platform.pathSeparator)
        .replaceAll('\\', Platform.pathSeparator);
    while (p.length > 3 && p.endsWith(Platform.pathSeparator)) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  static bool isSameProjectPath(String a, String b) {
    final na = normalizeProjectPath(a);
    final nb = normalizeProjectPath(b);
    if (na.isEmpty || nb.isEmpty) return na == nb;
    return Platform.isWindows
        ? na.toLowerCase() == nb.toLowerCase()
        : na == nb;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final basePath = Directory.current.path;
      _vaultDir =
          Directory('$basePath${Platform.pathSeparator}ultron_memory');
      _learnedDir =
          Directory('${_vaultDir.path}${Platform.pathSeparator}learned');
      _chatsDir =
          Directory('${_vaultDir.path}${Platform.pathSeparator}chats');

      if (!await _vaultDir.exists()) {
        await _vaultDir.create(recursive: true);
      }
      if (!await _learnedDir.exists()) {
        await _learnedDir.create(recursive: true);
      }
      if (!await _chatsDir.exists()) {
        await _chatsDir.create(recursive: true);
      }

      _knowledgeFile = File(
          '${_vaultDir.path}${Platform.pathSeparator}learned_knowledge.json');
      _telemetryFile = File(
          '${_vaultDir.path}${Platform.pathSeparator}usage_telemetry.json');
      _projectsFile = File(
          '${_vaultDir.path}${Platform.pathSeparator}project_registry.json');

      await _loadKnowledgeFromDisk();
      await _loadTelemetryFromDisk();
      await _loadProjectsFromDisk();
      await _refreshSavedChatArchives();
      _initialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Napaka pri inicializaciji spomina: $e');
    }
  }

  Future<void> _loadProjectsFromDisk() async {
    if (!await _projectsFile.exists()) return;
    try {
      final decoded = jsonDecode(await _projectsFile.readAsString());
      if (decoded is List) {
        projectRegistry
          ..clear()
          ..addAll(decoded
              .whereType<Map<String, dynamic>>()
              .map(UltronProjectMeta.fromJson)
              .where((p) => p.projectPath.isNotEmpty));
        _sortProjects();
      }
    } catch (_) {}
  }

  Future<void> _saveProjectsToDisk() async {
    try {
      final encoded = const JsonEncoder.withIndent('  ')
          .convert(projectRegistry.map((p) => p.toJson()).toList());
      await _projectsFile.writeAsString(encoded);
    } catch (_) {}
  }

  void _sortProjects() {
    projectRegistry.sort((a, b) {
      if (a.isCompleted != b.isCompleted) {
        return a.isCompleted ? 1 : -1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  UltronProjectMeta? getProjectMeta(String rawPath) {
    final norm = normalizeProjectPath(rawPath);
    if (norm.isEmpty) return null;
    for (final p in projectRegistry) {
      if (isSameProjectPath(p.projectPath, norm)) return p;
    }
    return null;
  }

  Future<UltronProjectMeta> ensureProjectRegistered(
    String rawPath, {
    String? fallbackName,
  }) async {
    await initialize();
    final norm = normalizeProjectPath(rawPath);
    final existing = getProjectMeta(norm);
    if (existing != null) return existing;

    final meta = UltronProjectMeta(
      projectPath: norm,
      projectName: (fallbackName != null && fallbackName.trim().isNotEmpty)
          ? fallbackName.trim()
          : _nameOf(norm),
      isCompleted: false,
      deadlineIso: '',
      updatedAt: DateTime.now(),
    );
    projectRegistry.insert(0, meta);
    _sortProjects();
    await _saveProjectsToDisk();
    notifyListeners();
    return meta;
  }

  Future<UltronProjectMeta?> updateProjectMeta({
    required String projectPath,
    String? projectName,
    bool? isCompleted,
    String? deadlineIso,
  }) async {
    await initialize();
    final norm = normalizeProjectPath(projectPath);
    if (norm.isEmpty) return null;

    int idx = projectRegistry
        .indexWhere((p) => isSameProjectPath(p.projectPath, norm));
    UltronProjectMeta updated;

    if (idx == -1) {
      updated = UltronProjectMeta(
        projectPath: norm,
        projectName: (projectName != null && projectName.trim().isNotEmpty)
            ? projectName.trim()
            : _nameOf(norm),
        isCompleted: isCompleted ?? false,
        deadlineIso: deadlineIso?.trim() ?? '',
        updatedAt: DateTime.now(),
      );
      projectRegistry.add(updated);
    } else {
      final old = projectRegistry[idx];
      updated = old.copyWith(
        projectName: (projectName != null && projectName.trim().isNotEmpty)
            ? projectName.trim()
            : old.projectName,
        isCompleted: isCompleted ?? old.isCompleted,
        deadlineIso: deadlineIso != null ? deadlineIso.trim() : old.deadlineIso,
        updatedAt: DateTime.now(),
      );
      projectRegistry[idx] = updated;
    }

    if (projectName != null && projectName.trim().isNotEmpty) {
      for (int i = 0; i < savedChatArchives.length; i++) {
        final c = savedChatArchives[i];
        if (isSameProjectPath(c.projectPath, norm)) {
          savedChatArchives[i] =
              c.copyWith(projectName: updated.projectName);
        }
      }
    }

    _sortProjects();
    await _saveProjectsToDisk();
    notifyListeners();
    return updated;
  }

  Future<void> removeProjectFromRegistry(String rawPath) async {
    projectRegistry
        .removeWhere((p) => isSameProjectPath(p.projectPath, rawPath));
    await _saveProjectsToDisk();
    notifyListeners();
  }

  Future<void> _loadKnowledgeFromDisk() async {
    if (!await _knowledgeFile.exists()) return;
    try {
      final raw = await _knowledgeFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        learnedEntries
          ..clear()
          ..addAll(decoded
              .whereType<Map<String, dynamic>>()
              .map(LearningEntry.fromJson));
      }
    } catch (_) {}
  }

  Future<void> _saveKnowledgeToDisk() async {
    try {
      final encoded = const JsonEncoder.withIndent('  ')
          .convert(learnedEntries.map((e) => e.toJson()).toList());
      await _knowledgeFile.writeAsString(encoded);
      await _exportMarkdownPlaybook();
    } catch (e) {
      debugPrint('Napaka pri shranjevanju znanja: $e');
    }
  }

  Future<void> _exportMarkdownPlaybook() async {
    final mdFile = File(
        '${_learnedDir.path}${Platform.pathSeparator}ultron_playbook.md');
    final buf = StringBuffer()
      ..writeln('# ULTRON Learned Playbook')
      ..writeln('Posodobljeno: ${DateTime.now().toIso8601String()}\n');

    for (final entry in learnedEntries) {
      final pinTag = entry.pinned ? '[PRIPETO] ' : '';
      final scope =
          entry.isGlobal ? 'Globalno' : 'Projekt: ${entry.projectPath}';
      buf.writeln('## $pinTag${entry.title} (${entry.category}) [$scope]');
      buf.writeln('- Pravilo: ${entry.rule}');
      buf.writeln('- Vir: `${entry.source}`\n');
    }
    await mdFile.writeAsString(buf.toString());
  }

  Future<void> _loadTelemetryFromDisk() async {
    if (!await _telemetryFile.exists()) return;
    try {
      final map = jsonDecode(await _telemetryFile.readAsString());
      if (map is Map<String, dynamic>) {
        final savedDate = map['date']?.toString() ?? '';
        final today = DateTime.now().toIso8601String().substring(0, 10);
        dailyRequests = savedDate == today ? (map['dailyRequests'] ?? 0) : 0;
        totalTokensGenerated = map['totalTokensGenerated'] ?? 0;
        autoLearnEnabled = map['autoLearnEnabled'] ?? true;
      }
    } catch (_) {}
  }

  Future<void> _saveTelemetryToDisk() async {
    try {
      final today = DateTime.now().toIso8601String().substring(0, 10);
      await _telemetryFile.writeAsString(
        jsonEncode({
          'date': today,
          'dailyRequests': dailyRequests,
          'totalTokensGenerated': totalTokensGenerated,
          'autoLearnEnabled': autoLearnEnabled,
        }),
      );
    } catch (_) {}
  }

  Future<void> recordLocalOllamaUsage({
    required int evalCount,
    required int evalDurationNs,
  }) async {
    dailyRequests += 1;
    totalTokensGenerated += evalCount;
    if (evalDurationNs > 0 && evalCount > 0) {
      liveTokensPerSecond = evalCount / (evalDurationNs / 1e9);
    }
    await _saveTelemetryToDisk();
    notifyListeners();
  }

  void setAutoLearn(bool value) {
    autoLearnEnabled = value;
    _saveTelemetryToDisk();
    notifyListeners();
  }

  Future<void> addManualRule({
    required String title,
    required String rule,
    String category = 'user_preference',
    String projectPath = '',
    String source = 'ročni vnos',
    bool pinned = true,
  }) async {
    final trimmedRule = rule.trim();
    if (trimmedRule.isEmpty) return;
    await initialize();

    _mergeOrInsertEntry(
      LearningEntry(
        id: 'manual_${DateTime.now().microsecondsSinceEpoch}',
        category: category,
        title: title.trim().isEmpty ? 'Uporabniško pravilo' : title.trim(),
        rule: trimmedRule,
        source: source,
        projectPath: normalizeProjectPath(projectPath),
        pinned: pinned,
        confidence: 1.0,
        updatedAt: DateTime.now(),
      ),
    );
    await _saveKnowledgeToDisk();
    lastLearnSummary = 'Shranjeno pravilo: ${title.trim().isEmpty ? "Novo pravilo" : title.trim()}';
    notifyListeners();
  }

  Future<void> togglePinEntry(String id) async {
    final idx = learnedEntries.indexWhere((e) => e.id == id);
    if (idx == -1) return;
    learnedEntries[idx] =
        learnedEntries[idx].copyWith(pinned: !learnedEntries[idx].pinned);
    await _saveKnowledgeToDisk();
    notifyListeners();
  }

  Future<void> deleteEntry(String id) async {
    learnedEntries.removeWhere((e) => e.id == id);
    await _saveKnowledgeToDisk();
    notifyListeners();
  }

  bool _mergeOrInsertEntry(LearningEntry incoming) {
    final normIncoming = incoming.rule.toLowerCase().trim();
    if (normIncoming.length < 4) return false;

    final existingIdx = learnedEntries.indexWhere(
      (e) =>
          isSameProjectPath(e.projectPath, incoming.projectPath) &&
          (e.rule.toLowerCase().trim() == normIncoming ||
              (e.title.toLowerCase().trim() ==
                      incoming.title.toLowerCase().trim() &&
                  e.category == incoming.category)),
    );

    if (existingIdx != -1) {
      final old = learnedEntries[existingIdx];
      learnedEntries[existingIdx] = old.copyWith(
        rule: incoming.rule,
        source: incoming.source,
        confidence: (old.confidence + 0.05).clamp(0.0, 1.0),
        updatedAt: DateTime.now(),
      );
      return false;
    } else {
      learnedEntries.insert(0, incoming);
      if (learnedEntries.length > 100) {
        final removableIdx =
            learnedEntries.lastIndexWhere((element) => !element.pinned);
        if (removableIdx != -1) {
          learnedEntries.removeAt(removableIdx);
        }
      }
      return true;
    }
  }

  //**************
  // Ciljno učenje iz izbranih datotek ali izpiskov s točnim navodilom uporabnika *
  //**************
  Future<int> runTargetedLearnPass({
    required List<String> targetFilePaths,
    required String instruction,
    required String currentProjectPath,
    required bool isGlobal,
    required Future<String?> Function(String synthesisPrompt)? llmExtractor,
  }) async {
    if (isLearningNow || llmExtractor == null) return 0;
    isLearningNow = true;
    lastLearnSummary = 'Analiziram ciljne datoteke...';
    notifyListeners();

    int addedOrUpdated = 0;
    try {
      await initialize();
      final codeSamples = StringBuffer();

      for (final path in targetFilePaths) {
        final file = File(path);
        if (await file.exists()) {
          try {
            final content =
                utf8.decode(await file.readAsBytes(), allowMalformed: true);
            final snippet =
                content.length > 8000 ? content.substring(0, 8000) : content;
            codeSamples
                .writeln('--- Datoteka: ${_nameOf(path)} ---\n$snippet\n');
          } catch (_) {}
        } else if (Directory(path).existsSync()) {
          int count = 0;
          await for (final f
              in Directory(path).list(recursive: true, followLinks: false)) {
            if (f is! File || count >= 6) continue;
            try {
              final raw =
                  utf8.decode(await f.readAsBytes(), allowMalformed: true);
              final clip = raw.length > 2200 ? raw.substring(0, 2200) : raw;
              codeSamples
                  .writeln('--- Datoteka: ${_nameOf(f.path)} ---\n$clip\n');
              count++;
            } catch (_) {}
          }
        }
      }

      final prompt = '''
Uporabnik zahteva, da se naučiš točno določeno pravilo iz priložene vsebine.
Navodilo uporabnika: "$instruction"

Izlušči od 1 do 3 konkretna tehnična pravila ali arhitekturne vzorce, ki ustrezajo temu navodilu.
Odgovori IZKLJUČNO v obliki vrstic formata:
RULE|Kategorija|Kratek naslov|Konkretno pravilo v enem stavku v slovenščini

Vsebina:
$codeSamples
''';

      final rawLlm = await llmExtractor(prompt);
      if (rawLlm != null && rawLlm.trim().isNotEmpty) {
        for (final rawLine in rawLlm.split('\n')) {
          final line = rawLine.trim();
          if (!line.startsWith('RULE|')) continue;
          final parts = line.split('|');
          if (parts.length >= 4) {
            final category = parts[1].trim().toLowerCase();
            final title = parts[2].trim();
            final ruleText = parts.sublist(3).join('|').trim();
            if (ruleText.isNotEmpty) {
              final inserted = _mergeOrInsertEntry(
                LearningEntry(
                  id: 'targeted_${DateTime.now().millisecondsSinceEpoch % 100000}',
                  category: category.isEmpty ? 'insight' : category,
                  title: title,
                  rule: ruleText,
                  source: targetFilePaths.isNotEmpty
                      ? 'Ciljno učenje: ${_nameOf(targetFilePaths.first)}'
                      : 'Ciljno učenje',
                  projectPath:
                      isGlobal ? '' : normalizeProjectPath(currentProjectPath),
                  confidence: 0.95,
                  pinned: true,
                  updatedAt: DateTime.now(),
                ),
              );
              if (inserted) addedOrUpdated++;
            }
          }
        }
      }

      await _saveKnowledgeToDisk();
      lastLearnSummary = addedOrUpdated > 0
          ? 'Ciljno učenje končano (+$addedOrUpdated pravil)'
          : 'Pravila so že posodobljena';
      return addedOrUpdated;
    } catch (e) {
      lastLearnSummary = 'Napaka pri ciljnem učenju: $e';
      return 0;
    } finally {
      isLearningNow = false;
      notifyListeners();
    }
  }

  Future<int> runIncrementalLearnPass({
    required String workspacePath,
    required List<ChatTurnRecord> recentTurns,
    Future<String?> Function(String synthesisPrompt)? llmExtractor,
  }) async {
    if (isLearningNow) return 0;
    isLearningNow = true;
    lastLearnSummary = 'Analiziram kodo in pogovor...';
    notifyListeners();

    int addedOrUpdated = 0;

    try {
      await initialize();
      final codeSamples = StringBuffer();
      final detectedExtensions = <String, int>{};
      bool usesBoxComments = false;
      bool usesFlutter = false;
      bool usesDotNet = false;

      final dir = Directory(workspacePath);
      if (await dir.exists()) {
        int scannedFiles = 0;
        await for (final entity
            in dir.list(recursive: true, followLinks: false)) {
          if (scannedFiles >= 22) break;
          if (entity is! File) continue;

          final pathLower = entity.path.toLowerCase();
          if (pathLower.contains('.git') ||
              pathLower.contains('.dart_tool') ||
              pathLower.contains('${Platform.pathSeparator}build') ||
              pathLower.contains('node_modules') ||
              pathLower.contains('${Platform.pathSeparator}bin') ||
              pathLower.contains('${Platform.pathSeparator}obj') ||
              pathLower.contains('ultron_memory')) {
            continue;
          }

          final ext = _extOf(entity.path);
          if (!const {
            '.dart',
            '.cs',
            '.py',
            '.cpp',
            '.h',
            '.go',
            '.js',
            '.ts',
            '.sql',
            '.yaml',
          }.contains(ext)) {
            continue;
          }

          try {
            final stat = await entity.stat();
            if (stat.size > 120 * 1024) continue;
            final content =
                utf8.decode(await entity.readAsBytes(), allowMalformed: true);
            scannedFiles++;
            detectedExtensions[ext] = (detectedExtensions[ext] ?? 0) + 1;

            if (content.contains('//**************')) {
              usesBoxComments = true;
            }
            if (content.contains('package:flutter/')) {
              usesFlutter = true;
            }
            if (ext == '.cs' || content.contains('using System')) {
              usesDotNet = true;
            }

            if (codeSamples.length < 5500) {
              final snippet = content.length > 700
                  ? content.substring(0, 700)
                  : content;
              codeSamples.writeln(
                  '--- Datoteka: ${_nameOf(entity.path)} ---\n$snippet\n');
            }
          } catch (_) {}
        }
      }

      if (usesBoxComments) {
        if (_mergeOrInsertEntry(
          LearningEntry(
            id: 'style_box_comments',
            category: 'code_style',
            title: 'Slog večvrstičnih komentarjev',
            rule:
                'Uporabljaj // za enovrstične komentarje ter okvir //************** z znakom * na koncu srednjih vrstic za večvrstične komentarje.',
            source: workspacePath,
            pinned: true,
            confidence: 0.98,
            updatedAt: DateTime.now(),
          ),
        )) {
          addedOrUpdated++;
        }
      }

      if (detectedExtensions.isNotEmpty) {
        final sortedLangs = detectedExtensions.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final summaryLangs =
            sortedLangs.map((e) => '${e.key} (${e.value})').join(', ');
        final stackNote = [
          if (usesFlutter) 'Flutter/Dart namizna arhitektura',
          if (usesDotNet) 'C# / .NET zaledje',
        ].join(' + ');

        if (_mergeOrInsertEntry(
          LearningEntry(
            id: 'stack_${workspacePath.hashCode.abs()}',
            category: 'architecture',
            title: 'Tehnološki sklad mape ${_nameOf(workspacePath)}',
            rule:
                'Prevladujoče datoteke v mapi ${_nameOf(workspacePath)}: $summaryLangs${stackNote.isNotEmpty ? " ($stackNote)" : ""}.',
            source: workspacePath,
            projectPath: normalizeProjectPath(workspacePath),
            confidence: 0.90,
            updatedAt: DateTime.now(),
          ),
        )) {
          addedOrUpdated++;
        }
      }

      final recentTranscript = StringBuffer();
      final tailTurns = recentTurns.length > 8
          ? recentTurns.sublist(recentTurns.length - 8)
          : recentTurns;

      for (final turn in tailTurns) {
        final clipped = turn.content.length > 500
            ? turn.content.substring(0, 500)
            : turn.content;
        recentTranscript.writeln('[${turn.role}]: $clipped');

        if (turn.role == 'user') {
          final lower = turn.content.toLowerCase();
          if (lower.contains('vedno ') ||
              lower.contains(' zapomni') ||
              lower.contains('ne uporabljaj') ||
              lower.contains('pazi na')) {
            if (_mergeOrInsertEntry(
              LearningEntry(
                id: 'pref_${turn.timestamp.millisecondsSinceEpoch}',
                category: 'user_preference',
                title: 'Uporabniška usmeritev iz klepeta',
                rule: clipped.replaceAll('\n', ' ').trim(),
                source: 'pogovor',
                projectPath: normalizeProjectPath(workspacePath),
                confidence: 0.92,
                updatedAt: DateTime.now(),
              ),
            )) {
              addedOrUpdated++;
            }
          }
        }
      }

      if (llmExtractor != null &&
          (codeSamples.isNotEmpty || recentTranscript.isNotEmpty)) {
        final prompt = '''
Analiziraj spodnje izseke kode in pogovora ter izlušči od 2 do 4 konkretna tehnična pravila, uporabnikove preference ali vzorce kode, ki si jih mora AI asistent zapomniti za prihodnje odgovore.
Odgovori IZKLJUČNO v obliki vrstic formata:
RULE|Kategorija|Kratek naslov|Konkretno pravilo v enem stavku v slovenščini

Pogovor:
$recentTranscript

Izseki kode:
$codeSamples
''';

        final rawLlm = await llmExtractor(prompt);
        if (rawLlm != null && rawLlm.trim().isNotEmpty) {
          for (final rawLine in rawLlm.split('\n')) {
            final line = rawLine.trim();
            if (!line.startsWith('RULE|')) continue;
            final parts = line.split('|');
            if (parts.length >= 4) {
              final category = parts[1].trim().toLowerCase();
              final title = parts[2].trim();
              final ruleText = parts.sublist(3).join('|').trim();
              if (ruleText.isNotEmpty) {
                final inserted = _mergeOrInsertEntry(
                  LearningEntry(
                    id: 'llm_${title.hashCode.abs()}_${DateTime.now().millisecondsSinceEpoch % 10000}',
                    category: category.isEmpty ? 'insight' : category,
                    title: title,
                    rule: ruleText,
                    source: 'LLM Learn sinteza',
                    projectPath: normalizeProjectPath(workspacePath),
                    confidence: 0.88,
                    updatedAt: DateTime.now(),
                  ),
                );
                if (inserted) addedOrUpdated++;
              }
            }
          }
        }
      }

      await _saveKnowledgeToDisk();
      lastLearnSummary = addedOrUpdated > 0
          ? 'Naučenih $addedOrUpdated novih vzorcev (skupaj ${learnedEntries.length})'
          : 'Znanje posodobljeno (${learnedEntries.length} aktivnih pravil)';
      return addedOrUpdated;
    } catch (e) {
      lastLearnSummary = 'Napaka pri učenju: $e';
      return 0;
    } finally {
      isLearningNow = false;
      notifyListeners();
    }
  }

  String buildLearnedSystemContext(
    String currentPrompt, {
    String activeProjectPath = '',
  }) {
    if (learnedEntries.isEmpty) return '';

    final normActiveProj = normalizeProjectPath(activeProjectPath);
    final eligible = learnedEntries.where((e) {
      if (e.isGlobal) return true;
      if (normActiveProj.isEmpty) return false;
      return isSameProjectPath(e.projectPath, normActiveProj);
    }).toList();

    if (eligible.isEmpty) return '';

    final queryWords = currentPrompt
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3)
        .toSet();

    final scored = eligible.map((entry) {
      double score = entry.pinned ? 10.0 : entry.confidence;
      if (normActiveProj.isNotEmpty &&
          isSameProjectPath(entry.projectPath, normActiveProj)) {
        score += 3.5;
      }
      final hay = '${entry.title} ${entry.rule}'.toLowerCase();
      for (final w in queryWords) {
        if (hay.contains(w)) score += 1.5;
      }
      return MapEntry(entry, score);
    }).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final selected = scored.take(10).map((e) => e.key).toList();
    final buf = StringBuffer()
      ..writeln(
          'NAUČENA PRAVILA IN VZORCI UPORABNIKA (upoštevaj pri odgovoru):');
    for (final item in selected) {
      buf.writeln('- [${item.title}]: ${item.rule}');
    }
    return buf.toString();
  }

  Future<SavedChatArchive?> saveChatSessionToDisk({
    required String sessionId,
    required List<ChatTurnRecord> turns,
    String projectPath = '',
    String projectName = '',
    String? customTitle,
    DateTime? createdAt,
  }) async {
    if (turns.isEmpty) return null;
    await initialize();

    final cleanId =
        sessionId.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
    final normProj = normalizeProjectPath(projectPath);

    final existingIdx =
        savedChatArchives.indexWhere((a) => a.sessionId == cleanId);
    final existing = existingIdx != -1 ? savedChatArchives[existingIdx] : null;

    final file = existing != null
        ? File(existing.filePath)
        : File(
            '${_chatsDir.path}${Platform.pathSeparator}chat_$cleanId.json');

    final firstUser = turns.firstWhere(
      (t) => t.role == 'user',
      orElse: () => turns.first,
    );
    final autoTitle = _cleanSingleLine(firstUser.content, maxLen: 46);

    final bool keepExistingCustomTitle =
        existing != null && existing.customTitled && customTitle == null;
    final String resolvedTitle = keepExistingCustomTitle
        ? existing.title
        : ((customTitle != null && customTitle.trim().isNotEmpty)
            ? customTitle.trim()
            : autoTitle);

    final String resolvedProjName = normProj.isEmpty
        ? ''
        : (projectName.trim().isNotEmpty
            ? projectName.trim()
            : (getProjectMeta(normProj)?.projectName ?? _nameOf(normProj)));

    final now = DateTime.now();
    final created = existing?.createdAt ?? createdAt ?? now;
    final pinned = existing?.pinned ?? false;
    final isCustom = keepExistingCustomTitle ||
        (customTitle != null && customTitle.trim().isNotEmpty);
    final preview = _cleanSingleLine(turns.last.content, maxLen: 92);

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'sessionId': cleanId,
        'title': resolvedTitle,
        'projectPath': normProj,
        'projectName': resolvedProjName,
        'pinned': pinned,
        'customTitled': isCustom,
        'createdAt': created.toIso8601String(),
        'savedAt': now.toIso8601String(),
        'turns': turns.map((t) => t.toJson()).toList(),
      }),
    );

    final archive = SavedChatArchive(
      sessionId: cleanId,
      filePath: file.path,
      title: resolvedTitle,
      projectPath: normProj,
      projectName: resolvedProjName,
      pinned: pinned,
      customTitled: isCustom,
      previewSnippet: preview,
      messageCount: turns.length,
      createdAt: created,
      savedAt: now,
    );

    if (existingIdx != -1) {
      savedChatArchives[existingIdx] = archive;
    } else {
      savedChatArchives.insert(0, archive);
    }
    _sortChatArchives();
    notifyListeners();
    return archive;
  }

  Future<void> saveConversationToDisk(
    List<ChatTurnRecord> turns, {
    String? customTitle,
  }) async {
    final stampId = DateTime.now().millisecondsSinceEpoch.toString();
    await saveChatSessionToDisk(
      sessionId: stampId,
      turns: turns,
      customTitle: customTitle,
    );
  }

  Future<LoadedChatSession?> loadChatSessionFromDisk(String sessionId) async {
    await initialize();
    final idx = savedChatArchives.indexWhere((a) => a.sessionId == sessionId);
    if (idx == -1) return null;

    final archive = savedChatArchives[idx];
    final file = File(archive.filePath);
    if (!await file.exists()) return null;

    try {
      final data = jsonDecode(await file.readAsString());
      if (data is! Map<String, dynamic>) return null;
      final rawTurns = (data['turns'] as List<dynamic>?) ?? const [];
      final turns = rawTurns
          .whereType<Map<String, dynamic>>()
          .map(ChatTurnRecord.fromJson)
          .toList();
      return LoadedChatSession(archive: archive, turns: turns);
    } catch (_) {
      return null;
    }
  }

  Future<void> renameChatSession(String sessionId, String newTitle) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;

    final idx = savedChatArchives.indexWhere((a) => a.sessionId == sessionId);
    if (idx == -1) return;

    final current = savedChatArchives[idx];
    final file = File(current.filePath);
    if (await file.exists()) {
      try {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        data['title'] = trimmed;
        data['customTitled'] = true;
        await file
            .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      } catch (_) {}
    }

    savedChatArchives[idx] = current.copyWith(
      title: trimmed,
      customTitled: true,
    );
    notifyListeners();
  }

  Future<void> togglePinChatSession(String sessionId) async {
    final idx = savedChatArchives.indexWhere((a) => a.sessionId == sessionId);
    if (idx == -1) return;

    final current = savedChatArchives[idx];
    final nextPinned = !current.pinned;
    final file = File(current.filePath);
    if (await file.exists()) {
      try {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        data['pinned'] = nextPinned;
        await file
            .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      } catch (_) {}
    }

    savedChatArchives[idx] = current.copyWith(pinned: nextPinned);
    _sortChatArchives();
    notifyListeners();
  }

  Future<void> bindChatSessionToProject(
    String sessionId, {
    required String projectPath,
    required String projectName,
  }) async {
    final idx = savedChatArchives.indexWhere((a) => a.sessionId == sessionId);
    if (idx == -1) return;

    final normProj = normalizeProjectPath(projectPath);
    final resolvedName = normProj.isEmpty
        ? ''
        : (projectName.trim().isNotEmpty ? projectName.trim() : _nameOf(normProj));

    final current = savedChatArchives[idx];
    final file = File(current.filePath);
    if (await file.exists()) {
      try {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        data['projectPath'] = normProj;
        data['projectName'] = resolvedName;
        await file
            .writeAsString(const JsonEncoder.withIndent('  ').convert(data));
      } catch (_) {}
    }

    savedChatArchives[idx] = current.copyWith(
      projectPath: normProj,
      projectName: resolvedName,
    );
    notifyListeners();
  }

  Future<void> deleteChatSession(String sessionId) async {
    final idx = savedChatArchives.indexWhere((a) => a.sessionId == sessionId);
    if (idx == -1) return;
    final target = savedChatArchives.removeAt(idx);
    try {
      final f = File(target.filePath);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
    notifyListeners();
  }

  List<SavedChatArchive> chatsForProject(String projectPath) {
    final norm = normalizeProjectPath(projectPath);
    if (norm.isEmpty) {
      return savedChatArchives.where((c) => !c.hasProject).toList();
    }
    return savedChatArchives
        .where((c) => isSameProjectPath(c.projectPath, norm))
        .toList();
  }

  Future<void> _refreshSavedChatArchives() async {
    savedChatArchives.clear();
    if (!await _chatsDir.exists()) return;

    await for (final entity in _chatsDir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final data = jsonDecode(await entity.readAsString());
        if (data is! Map<String, dynamic>) continue;

        final turns = (data['turns'] as List<dynamic>?) ?? const [];
        final baseFileName = _nameOf(entity.path);
        final fallbackId = baseFileName.endsWith('.json')
            ? baseFileName.substring(0, baseFileName.length - 5)
            : baseFileName;

        final sessionId = data['sessionId']?.toString() ?? fallbackId;
        final projPath =
            normalizeProjectPath(data['projectPath']?.toString() ?? '');
        final projName = projPath.isEmpty
            ? ''
            : (data['projectName']?.toString() ??
                getProjectMeta(projPath)?.projectName ??
                _nameOf(projPath));

        String preview = '';
        if (turns.isNotEmpty && turns.last is Map<String, dynamic>) {
          final lastContent =
              (turns.last as Map<String, dynamic>)['content']?.toString() ?? '';
          preview = _cleanSingleLine(lastContent, maxLen: 92);
        }

        final savedAt =
            DateTime.tryParse(data['savedAt']?.toString() ?? '') ??
                DateTime.now();
        final createdAt =
            DateTime.tryParse(data['createdAt']?.toString() ?? '') ?? savedAt;

        savedChatArchives.add(
          SavedChatArchive(
            sessionId: sessionId,
            filePath: entity.path,
            title: data['title']?.toString() ?? baseFileName,
            projectPath: projPath,
            projectName: projName,
            pinned: data['pinned'] == true,
            customTitled: data['customTitled'] == true,
            previewSnippet: preview,
            messageCount: turns.length,
            createdAt: createdAt,
            savedAt: savedAt,
          ),
        );
      } catch (_) {}
    }
    _sortChatArchives();
  }

  void _sortChatArchives() {
    savedChatArchives.sort((a, b) {
      if (a.pinned != b.pinned) {
        return a.pinned ? -1 : 1;
      }
      return b.savedAt.compareTo(a.savedAt);
    });
  }

  String _cleanSingleLine(String text, {required int maxLen}) {
    final single = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (single.isEmpty) return 'Nov klepet';
    if (single.length <= maxLen) return single;
    return '${single.substring(0, maxLen)}...';
  }

  String _extOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1 || dot < path.lastIndexOf(Platform.pathSeparator)) return '';
    return path.substring(dot).toLowerCase();
  }

  String _nameOf(String path) {
    final cleaned = path.endsWith(Platform.pathSeparator) && path.length > 3
        ? path.substring(0, path.length - 1)
        : path;
    final idx = cleaned.lastIndexOf(Platform.pathSeparator);
    return idx == -1 ? cleaned : cleaned.substring(idx + 1);
  }

  bool isDoneTriggerPhrase(String input) {
    final lower = input.trim().toLowerCase();
    return lower == '/done' ||
        lower == 'done' ||
        lower == 'work is done' ||
        lower == "that's it" ||
        lower == 'thats it';
  }

  String getLearnStatusSummary() {
    if (learnedEntries.isEmpty) {
      return 'Baza znanja je prazna.';
    }
    final buf = StringBuffer()..writeln('ZAPISANA PRAVILA IN VZORCI:');
    for (final e in learnedEntries) {
      final scope = e.isGlobal ? 'Globalno' : 'Projekt: ${e.projectPath}';
      buf.writeln('- [$scope] ${e.title}: ${e.rule}');
    }
    return buf.toString();
  }

  Future<void> resetLearnedNotes() async {
    learnedEntries.clear();
    await _saveKnowledgeToDisk();
    notifyListeners();
  }
}