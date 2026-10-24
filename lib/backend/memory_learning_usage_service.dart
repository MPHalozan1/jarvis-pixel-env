import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

//**************
// Posamezno naučeno pravilo ali arhitekturni vzorec v spominu Ultrona *
// Shranjuje se na disk in se samodejno vključuje v sistemski kontekst LLM-ja *
//**************
class LearningEntry {
  final String id;
  final String category;
  final String title;
  final String rule;
  final String source;
  final bool pinned;
  final double confidence;
  final DateTime updatedAt;

  const LearningEntry({
    required this.id,
    required this.category,
    required this.title,
    required this.rule,
    required this.source,
    this.pinned = false,
    this.confidence = 0.85,
    required this.updatedAt,
  });

  LearningEntry copyWith({
    String? category,
    String? title,
    String? rule,
    String? source,
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
      pinned: json['pinned'] == true,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.85,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

//**************
// Zapis posamezne izmenjave v pogovoru za arhiviranje in učenje *
//**************
class ChatTurnRecord {
  final String role;
  final String content;
  final String modelUsed;
  final List<String> attachedFiles;
  final DateTime timestamp;

  const ChatTurnRecord({
    required this.role,
    required this.content,
    required this.modelUsed,
    this.attachedFiles = const [],
    required this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'role': role,
        'content': content,
        'modelUsed': modelUsed,
        'attachedFiles': attachedFiles,
        'timestamp': timestamp.toIso8601String(),
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
    );
  }
}

//**************
// Povzetek shranjene seje pogovora v mapi ultron_memory/chats *
//**************
class SavedChatArchive {
  final String filePath;
  final String title;
  final int messageCount;
  final DateTime savedAt;

  const SavedChatArchive({
    required this.filePath,
    required this.title,
    required this.messageCount,
    required this.savedAt,
  });
}

//**************
// Servis za dejansko učenje (Learn), trajni spomin in telemetrijo rabe *
// Analizira izvorno kodo, popravke in pogovore ter gradi aktivno bazo znanja *
//**************
class MemoryLearningUsageService extends ChangeNotifier {
  late Directory _vaultDir;
  late Directory _learnedDir;
  late Directory _chatsDir;
  late File _knowledgeFile;
  late File _telemetryFile;

  bool _initialized = false;
  bool isLearningNow = false;
  String lastLearnSummary = 'Pripravljen na učenje';

  int dailyRequests = 0;
  int totalTokensGenerated = 0;
  double liveTokensPerSecond = 0.0;
  bool autoLearnEnabled = true;

  final List<LearningEntry> learnedEntries = [];
  final List<SavedChatArchive> savedChatArchives = [];

  // Inicializira lokalni trezor znanja ultron_memory
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final basePath = Directory.current.path;
      _vaultDir =
          Directory('$basePath${Platform.pathSeparator}ultron_memory');
      _learnedDir = Directory(
          '${_vaultDir.path}${Platform.pathSeparator}learned');
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

      await _loadKnowledgeFromDisk();
      await _loadTelemetryFromDisk();
      await _refreshSavedChatArchives();
      _initialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('Napaka pri inicializaciji spomina: $e');
    }
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

  // Izvozi berljivo Markdown datoteko z vsem naučenim znanjem
  Future<void> _exportMarkdownPlaybook() async {
    final mdFile = File(
        '${_learnedDir.path}${Platform.pathSeparator}ultron_playbook.md');
    final buf = StringBuffer()
      ..writeln('# Ultron Learned Playbook')
      ..writeln(
          'Posodobljeno: ${DateTime.now().toIso8601String()}\n');

    for (final entry in learnedEntries) {
      final pinTag = entry.pinned ? '[PRIPETO] ' : '';
      buf.writeln('## $pinTag${entry.title} (${entry.category})');
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

  // Zabeleži dejansko hitrost in porabo lokalnega modela
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

  // Ročno dodajanje pravila s strani uporabnika
  Future<void> addManualRule({
    required String title,
    required String rule,
    String category = 'user_preference',
    bool pinned = true,
  }) async {
    final trimmedRule = rule.trim();
    if (trimmedRule.isEmpty) return;

    _mergeOrInsertEntry(
      LearningEntry(
        id: 'manual_${DateTime.now().microsecondsSinceEpoch}',
        category: category,
        title: title.trim().isEmpty ? 'Uporabniško pravilo' : title.trim(),
        rule: trimmedRule,
        source: 'ročni vnos',
        pinned: pinned,
        confidence: 1.0,
        updatedAt: DateTime.now(),
      ),
    );
    await _saveKnowledgeToDisk();
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

  // Združi podobna pravila brez podvajanja
  bool _mergeOrInsertEntry(LearningEntry incoming) {
    final normIncoming = incoming.rule.toLowerCase().trim();
    if (normIncoming.length < 6) return false;

    final existingIdx = learnedEntries.indexWhere(
      (e) =>
          e.rule.toLowerCase().trim() == normIncoming ||
          (e.title.toLowerCase().trim() == incoming.title.toLowerCase().trim() &&
              e.category == incoming.category),
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
      if (learnedEntries.length > 80) {
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
  // Dejanski postopek učenja (Learn): *
  // 1. Preišče izvorno kodo izbrane mape za slogovne vzorce in ogrodja *
  // 2. Uporabi lokalni LLM (če je na voljo) za ekstrakcijo pravil iz kode in klepeta *
  // 3. Trajno shrani pravila in jih uporabi pri vseh naslednjih odgovorih *
  //**************
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

      // 1. Skeniranje izvorne kode v izbrani mapi
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

      // Deterministična ekstrakcija dejanskih slogovnih vzorcev
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
            confidence: 0.90,
            updatedAt: DateTime.now(),
          ),
        )) {
          addedOrUpdated++;
        }
      }

      // Ekstrakcija eksplicitnih uporabniških navodil iz pogovora
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
                confidence: 0.92,
                updatedAt: DateTime.now(),
              ),
            )) {
              addedOrUpdated++;
            }
          }
        }
      }

      // 2. Globoka sinteza znanja prek aktivnega lokalnega LLM modela
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

  // Zgradi jedrnat sistemski kontekst iz naučenih pravil za vsak klic LLM-ja
  String buildLearnedSystemContext(String currentPrompt) {
    if (learnedEntries.isEmpty) return '';

    final queryWords = currentPrompt
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3)
        .toSet();

    final scored = learnedEntries.map((entry) {
      double score = entry.pinned ? 10.0 : entry.confidence;
      final hay = '${entry.title} ${entry.rule}'.toLowerCase();
      for (final w in queryWords) {
        if (hay.contains(w)) score += 1.5;
      }
      return MapEntry(entry, score);
    }).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final selected = scored.take(10).map((e) => e.key).toList();
    final buf = StringBuffer()
      ..writeln('NAUČENA PRAVILA IN VZORCI UPORABNIKA (upoštevaj pri odgovoru):');
    for (final item in selected) {
      buf.writeln('- [${item.title}]: ${item.rule}');
    }
    return buf.toString();
  }

  // Shrani pogovor na disk v ultron_memory/chats
  Future<void> saveConversationToDisk(
    List<ChatTurnRecord> turns, {
    String? customTitle,
  }) async {
    if (turns.isEmpty) return;
    await initialize();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final file = File(
        '${_chatsDir.path}${Platform.pathSeparator}chat_$stamp.json');
    final firstUser = turns.firstWhere(
      (t) => t.role == 'user',
      orElse: () => turns.first,
    );
    final title = customTitle ??
        (firstUser.content.length > 42
            ? '${firstUser.content.substring(0, 42)}...'
            : firstUser.content);

    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'title': title,
        'savedAt': DateTime.now().toIso8601String(),
        'turns': turns.map((t) => t.toJson()).toList(),
      }),
    );
    await _refreshSavedChatArchives();
    notifyListeners();
  }

  Future<void> _refreshSavedChatArchives() async {
    savedChatArchives.clear();
    if (!await _chatsDir.exists()) return;
    await for (final entity in _chatsDir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final data = jsonDecode(await entity.readAsString());
        if (data is Map<String, dynamic>) {
          final turns = (data['turns'] as List<dynamic>?) ?? const [];
          savedChatArchives.add(
            SavedChatArchive(
              filePath: entity.path,
              title: data['title']?.toString() ?? _nameOf(entity.path),
              messageCount: turns.length,
              savedAt:
                  DateTime.tryParse(data['savedAt']?.toString() ?? '') ??
                      DateTime.now(),
            ),
          );
        }
      } catch (_) {}
    }
    savedChatArchives.sort((a, b) => b.savedAt.compareTo(a.savedAt));
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
}