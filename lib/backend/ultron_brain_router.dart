import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import '../frontend/ultron_bubble_painter.dart';
import 'memory_learning_usage_service.dart';
import 'plugin_manager_service.dart';

//**************
// Podatki o zaznanem lokalnem LLM modelu na računalniku *
//**************
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

//**************
// Pripravljena datoteka poljubnega tipa za pošiljanje v kontekst LLM-ja *
//**************
class AttachedFilePayload {
  final String path;
  final String name;
  final String extension;
  final int sizeBytes;
  final String extractedText;
  final String? base64Image;
  final String kindLabel;

  const AttachedFilePayload({
    required this.path,
    required this.name,
    required this.extension,
    required this.sizeBytes,
    required this.extractedText,
    this.base64Image,
    required this.kindLabel,
  });

  String get humanSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

//**************
// Sporočilo v osrednjem klepetu Ultrona *
//**************
class ChatMessageItem {
  final String id;
  final String role;
  String content;
  final String modelName;
  final List<String> attachedFileNames;
  final DateTime timestamp;
  final bool isStreaming;

  ChatMessageItem({
    required this.id,
    required this.role,
    required this.content,
    required this.modelName,
    this.attachedFileNames = const [],
    required this.timestamp,
    this.isStreaming = false,
  });
}

//**************
// Zaznana težava v kodi za kirurški popravek v vgrajenem urejevalniku *
//**************
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

//**************
// Zavihek odprte datoteke v vgrajenem urejevalniku kode *
//**************
class OpenEditorTab {
  final String filePath;
  final String fileName;
  List<String> lines;
  List<String>? previousLinesSnapshot;
  bool isDirty;

  OpenEditorTab({
    required this.filePath,
    required this.fileName,
    required this.lines,
    this.previousLinesSnapshot,
    this.isDirty = false,
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
  final String cloneUrl;
  final String htmlUrl;
  final bool isPrivate;

  const GitHubRepoEntry({
    required this.name,
    required this.fullName,
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
// Osrednji možganski usmerjevalnik Ultrona: *
// - Skenira celoten PC za lokalne LLM modele (Ollama API, CLI, vsi diski, LM Studio) *
// - Ekstrahira vsebino vseh vrst datotek (.docx, .pdf, .xlsx, .pptx, slike, koda, binarne) *
// - Izvaja pretakanje (streaming) odgovorov z nastavljivimi GPU sloji (num_gpu) *
// - Povezuje File Manager, Learn sistem in vgrajeni urejevalnik kode *
//**************
class UltronBrainRouter extends ChangeNotifier {
  final MemoryLearningUsageService memoryService = MemoryLearningUsageService();
  final PluginManagerService pluginService = PluginManagerService();

  // Stanje krogle in pretakanja
  OrbState orbState = OrbState.standby;
  bool isGenerating = false;
  bool isScanningModels = false;
  HttpClient? _activeStreamClient;

  // Nastavitve lokalnega LLM strežnika in VRAM slojev
  String ollamaBaseUrl = 'http://127.0.0.1:11434';
  bool isOllamaOnline = false;
  String activeLocalModel = 'gemma2-gpu';
  int customNumGpuLayers = 0; // 0 = samodejno (ali Modelfile), >0 = ročna vsilitev
  int contextWindowTokens = 8192;
  String? detectedDiskModelsFolder;

  final List<LocalLlmModelInfo> discoveredModels = [];
  List<String> get installedOllamaModels =>
      discoveredModels.map((m) => m.name).toList();

  // Pogovor in univerzalne priponke
  final List<ChatMessageItem> messages = [];
  final List<AttachedFilePayload> pendingAttachments = [];
  final List<ChatTurnRecord> _sessionHistory = [];

  // Brskalnik datotek po celotnem računalniku
  String currentBrowserDirectory = Directory.current.path;
  List<String> availableSystemRoots = [];

  // Vgrajeni VS Code kirurški urejevalnik
  bool isVsCodeWindowOpen = false;
  bool isStreamingCode = false;
  String activeExecutionModel = 'gemma2-gpu';
  int activeCursorLine = 0;
  final List<OpenEditorTab> openTabs = [];
  int activeTabIndex = 0;
  final List<LiveCodeIssue> detectedIssues = [];
  final List<DiffHunkProposal> pendingDiffHunks = [];

  // GitHub povezava
  String githubUsername = '';
  String githubToken = '';
  bool isGithubConnected = false;
  bool isFetchingRepos = false;
  int githubRateLimitRemaining = 60;
  int githubRateLimitTotal = 60;
  final List<GitHubRepoEntry> githubRepos = [];
  bool isJulesConnected = false;

  late File _routerConfigFile;

  OpenEditorTab? get activeTab =>
      (activeTabIndex >= 0 && activeTabIndex < openTabs.length)
          ? openTabs[activeTabIndex]
          : null;

  String get activeFilePath => activeTab?.filePath ?? '';
  List<String> get activeFileLines => activeTab?.lines ?? const [];

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
    await scanAllLocalLlms();
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
            (map['contextWindowTokens'] as num?)?.toInt() ?? 8192;
        githubToken = map['githubToken']?.toString() ?? '';
        githubUsername = map['githubUsername']?.toString() ?? '';
        isGithubConnected = githubToken.isNotEmpty;
        final savedDir = map['currentBrowserDirectory']?.toString();
        if (savedDir != null && Directory(savedDir).existsSync()) {
          currentBrowserDirectory = savedDir;
        }
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
          'currentBrowserDirectory': currentBrowserDirectory,
        }),
      );
    } catch (_) {}
  }

  //**************
  // Zazna vse korenske diske na računalniku (C:\, D:\ itd. na Windowsih ali / na Linuxu) *
  //**************
  Future<void> refreshSystemRoots() async {
    final roots = <String>[];
    if (Platform.isWindows) {
      for (int code = 67; code <= 90; code++) {
        // Preverimo črke diskov od C do Z
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
    notifyListeners();
  }

  //**************
  // Celovit skener računalnika za lokalne LLM modele: *
  // 1. Preveri aktivni Ollama API (/api/tags) *
  // 2. Preveri ukazno vrstico (ollama list) *
  // 3. Preišče manifeste na vseh diskih (npr. D:\OllamaModels in .ollama) *
  // 4. Preveri morebitni lokalni LM Studio strežnik (vrata 1234) *
  //**************
  Future<void> scanAllLocalLlms() async {
    if (isScanningModels) return;
    isScanningModels = true;
    notifyListeners();

    final foundMap = <String, LocalLlmModelInfo>{};
    bool serverReachable = false;

    // 1. Preverimo Ollama HTTP API
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
          final cleanName =
              name.endsWith(':latest') ? name.substring(0, name.length - 7) : name;
          final sizeBytes = (item['size'] as num?)?.toInt() ?? 0;
          final details =
              (item['details'] as Map<String, dynamic>?) ?? const {};

          foundMap[cleanName] = LocalLlmModelInfo(
            name: name.endsWith(':latest') && !name.contains(':') ? cleanName : name,
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

    // 2. Preverimo CLI ukaz `ollama list`
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

    // 3. Skeniramo mape z manifesti na vseh diskih (npr. D:\OllamaModels)
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
      final manifestsRoot = Directory(
          '$baseModelsPath${Platform.pathSeparator}manifests');
      if (!manifestsRoot.existsSync()) continue;
      detectedDiskModelsFolder ??= baseModelsPath;

      try {
        await for (final entity
            in manifestsRoot.list(recursive: true, followLinks: false)) {
          if (entity is! File) continue;
          // Pot manifesta se običajno konča z .../library/<model>/<tag>
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

    // 4. Hitri pregled za LM Studio lokalni strežnik (127.0.0.1:1234)
    final lmClient = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 650);
    try {
      final req = await lmClient
          .getUrl(Uri.parse('http://127.0.0.1:1234/v1/models'));
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

    // Pametna privzeta izbira, če trenutni model ne obstaja na tej napravi
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

  // Ohranimo združljivost za obstoječe klice preverjanja zdravja
  Future<void> checkLocalOllamaHealth({String? newBaseUrl}) async {
    if (newBaseUrl != null && newBaseUrl.trim().isNotEmpty) {
      ollamaBaseUrl = newBaseUrl.trim();
      await saveRouterConfig();
    }
    await scanAllLocalLlms();
  }

  // Zažene lokalni Ollama strežnik z izbrano mapo modelov (npr. D:\OllamaModels)
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
    if (numCtx != null) contextWindowTokens = numCtx;
    saveRouterConfig();
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

  //**************
  // Univerzalni bralnik datotek vseh vrst: *
  // Podpira .docx, .odt, .xlsx, .pptx, .pdf, .zip, slike, izvorno kodo in binarne datoteke *
  //**************
  Future<bool> attachFileFromPath(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      if (pendingAttachments.any((a) => a.path == file.path)) {
        return true;
      }

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

    // 1. Slike (za multimodalne modele + metapodatki)
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

    // 2. Pisarniški dokumenti (.docx Word, .odt, .xlsx, .pptx)
    if (officeZipExts.contains(ext)) {
      final bytes = await file.readAsBytes();
      final extracted = _extractOfficeDocumentText(bytes, ext);
      return AttachedFilePayload(
        path: file.path,
        name: name,
        extension: ext,
        sizeBytes: sizeBytes,
        extractedText: _capText(extracted, 30000),
        kindLabel: ext.substring(1).toUpperCase(),
      );
    }

    // 3. PDF dokumenti
    if (ext == '.pdf') {
      final bytes = await file.readAsBytes();
      final pdfText = _extractPdfTextPureDart(bytes);
      return AttachedFilePayload(
        path: file.path,
        name: name,
        extension: ext,
        sizeBytes: sizeBytes,
        extractedText: _capText(pdfText, 30000),
        kindLabel: 'PDF',
      );
    }

    // 4. ZIP arhivi
    if (ext == '.zip') {
      final bytes = await file.readAsBytes();
      final zipSummary = _extractZipSummary(bytes);
      return AttachedFilePayload(
        path: file.path,
        name: name,
        extension: ext,
        sizeBytes: sizeBytes,
        extractedText: _capText(zipSummary, 28000),
        kindLabel: 'ZIP',
      );
    }

    // 5. Vse besedilne, kodne ali poljubne binarne datoteke (varno branje do 2 MB)
    final maxRead = sizeBytes > 2 * 1024 * 1024 ? 2 * 1024 * 1024 : sizeBytes;
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
        extractedText: _capText(text, 32000),
        kindLabel: ext.isEmpty ? 'TXT' : ext.substring(1).toUpperCase(),
      );
    }

    // 6. Poljubna binarna datoteka: izluščimo metapodatke in berljive ASCII nize
    final asciiStrings = _extractPrintableStringsFromBinary(bytes);
    return AttachedFilePayload(
      path: file.path,
      name: name,
      extension: ext,
      sizeBytes: sizeBytes,
      extractedText:
          'Binarna datoteka: $name ($sizeBytes bajtov)\nIzluščeni berljivi nizi:\n${_capText(asciiStrings, 14000)}',
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

  //**************
  // Glavna metoda za pošiljanje sporočila in pripetih datotek izbranemu LLM-ju *
  // Podpira sprotno pretakanje (streaming) in samodejno vključevanje naučenega znanja *
  //**************
  Future<void> executeUltronPrompt(String rawPrompt) async {
    final trimmed = rawPrompt.trim();
    if (trimmed.isEmpty && pendingAttachments.isEmpty) return;
    if (isGenerating) return;

    final attachmentsSnapshot = List<AttachedFilePayload>.from(pendingAttachments);
    pendingAttachments.clear();

    final userDisplay = trimmed.isEmpty
        ? 'Analiziraj priložene datoteke (${attachmentsSnapshot.map((e) => e.name).join(", ")}).'
        : trimmed;

    messages.add(
      ChatMessageItem(
        id: 'u_${DateTime.now().microsecondsSinceEpoch}',
        role: 'user',
        content: userDisplay,
        modelName: 'Uporabnik',
        attachedFileNames: attachmentsSnapshot.map((a) => a.name).toList(),
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
    notifyListeners();

    // Sestavimo celoten kontekst iz pripetih datotek in aktivnega urejevalnika
    final fullUserContext = StringBuffer();
    if (attachmentsSnapshot.isNotEmpty) {
      fullUserContext.writeln('PRILOŽENE DATOTEKE:');
      for (final att in attachmentsSnapshot) {
        fullUserContext.writeln(
            '=== DATOTEKA: ${att.name} (${att.kindLabel}, ${att.humanSize}) ===');
        fullUserContext.writeln(att.extractedText);
        fullUserContext.writeln('=== KONEC DATOTEKE: ${att.name} ===\n');
      }
    }

    if (activeTab != null &&
        attachmentsSnapshot.every((a) => a.path != activeTab!.filePath)) {
      final editorSnippet = _capText(activeTab!.lines.join('\n'), 10000);
      fullUserContext.writeln(
          'TRENUTNO ODPRTA DATOTEKA V UREJEVALNIKU (${activeTab!.fileName}):\n$editorSnippet\n');
    }

    fullUserContext.writeln('UPORABNIKOVO NAVODILO:\n$userDisplay');

    final learnedContext = memoryService.buildLearnedSystemContext(userDisplay);
    final pluginContext = pluginService.buildLazyLoadedPluginContext();

    final systemPrompt = [
      'Ti si Ultron, natančen lokalni inženirski AI asistent.',
      'Odgovarjaj jedrnato, tehnično točno in v jeziku uporabnika.',
      'Pri pisanju kode pazi na pravilne velike in male začetnice ter uporabi // za enovrstične komentarje in okvir //************** z znakom * na koncu srednjih vrstic za večvrstične komentarje.',
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

    try {
      if (activeLocalModel.startsWith('lmstudio:')) {
        await _streamFromLmStudio(
          modelId: activeLocalModel.substring('lmstudio:'.length),
          systemPrompt: systemPrompt,
          userContent: fullUserContext.toString(),
          targetMsg: assistantMsg,
        );
      } else {
        await _streamFromOllama(
          modelName: activeLocalModel,
          systemPrompt: systemPrompt,
          userContent: fullUserContext.toString(),
          imagesBase64: imagesBase64,
          targetMsg: assistantMsg,
        );
      }

      final idx = messages.indexWhere((m) => m.id == assistantMsg.id);
      if (idx != -1) {
        messages[idx] = ChatMessageItem(
          id: assistantMsg.id,
          role: 'assistant',
          content: assistantMsg.content,
          modelName: activeLocalModel,
          timestamp: assistantMsg.timestamp,
          isStreaming: false,
        );
      }

      _sessionHistory.add(
        ChatTurnRecord(
          role: 'assistant',
          content: assistantMsg.content,
          modelUsed: activeLocalModel,
          timestamp: DateTime.now(),
        ),
      );

      await memoryService.saveConversationToDisk(_sessionHistory);

      // Samodejno sprotno učenje ob daljših sejah, če je vklopljeno
      if (memoryService.autoLearnEnabled &&
          _sessionHistory.length % 6 == 0) {
        unawaited(triggerLearnPass(silent: true));
      }

      orbState = OrbState.standby;
    } catch (e) {
      orbState = OrbState.error;
      final idx = messages.indexWhere((m) => m.id == assistantMsg.id);
      if (idx != -1) {
        final fallbackText = assistantMsg.content.isEmpty
            ? 'Povezava z lokalnim modelom "$activeLocalModel" ni uspela ($e).\nPreveri, ali Ollama teče na $ollamaBaseUrl ali v nastavitvah klikni "Zaženi Ollama strežnik".'
            : assistantMsg.content;
        messages[idx] = ChatMessageItem(
          id: assistantMsg.id,
          role: 'assistant',
          content: fallbackText,
          modelName: activeLocalModel,
          timestamp: assistantMsg.timestamp,
          isStreaming: false,
        );
      }
    } finally {
      _activeStreamClient = null;
      isGenerating = false;
      isStreamingCode = false;
      notifyListeners();
    }
  }

  void stopGeneration() {
    _activeStreamClient?.close(force: true);
    _activeStreamClient = null;
    isGenerating = false;
    orbState = OrbState.standby;
    notifyListeners();
  }

  void clearConversation() {
    messages.clear();
    _sessionHistory.clear();
    notifyListeners();
  }

  Future<void> _streamFromOllama({
    required String modelName,
    required String systemPrompt,
    required String userContent,
    required List<String> imagesBase64,
    required ChatMessageItem targetMsg,
  }) async {
    final cleanBase = ollamaBaseUrl.endsWith('/')
        ? ollamaBaseUrl.substring(0, ollamaBaseUrl.length - 1)
        : ollamaBaseUrl;

    // Pripravimo kratko zgodovino zadnjih nekaj sporočil za kontekst klepeta
    final apiMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
    ];

    final historyCount = messages.length - 2;
    final startIdx = historyCount > 6 ? historyCount - 6 : 0;
    for (int i = startIdx; i < historyCount; i++) {
      final m = messages[i];
      if (m.content.trim().isEmpty) continue;
      apiMessages.add({'role': m.role, 'content': m.content});
    }

    final currentMsgMap = <String, dynamic>{
      'role': 'user',
      'content': userContent,
      if (imagesBase64.isNotEmpty) 'images': imagesBase64,
    };
    apiMessages.add(currentMsgMap);

    final options = <String, dynamic>{
      'num_ctx': contextWindowTokens,
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
    int uiThrottleCounter = 0;

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
        targetMsg.content += token;
        uiThrottleCounter++;
        if (uiThrottleCounter % 2 == 0) {
          notifyListeners();
        }
      }

      if (chunk['done'] == true) {
        final evalCount = (chunk['eval_count'] as num?)?.toInt() ?? 0;
        final evalDuration = (chunk['eval_duration'] as num?)?.toInt() ?? 0;
        await memoryService.recordLocalOllamaUsage(
          evalCount: evalCount,
          evalDurationNs: evalDuration,
        );
      }
    }
    notifyListeners();
  }

  Future<void> _streamFromLmStudio({
    required String modelId,
    required String systemPrompt,
    required String userContent,
    required ChatMessageItem targetMsg,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    _activeStreamClient = client;

    final req = await client
        .postUrl(Uri.parse('http://127.0.0.1:1234/v1/chat/completions'));
    req.headers.contentType = ContentType.json;
    req.add(utf8.encode(jsonEncode({
      'model': modelId,
      'stream': false,
      'messages': [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': userContent},
      ],
    })));

    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode != 200) {
      throw Exception('LM Studio HTTP ${res.statusCode}');
    }
    final data = jsonDecode(body) as Map<String, dynamic>;
    final choices = (data['choices'] as List<dynamic>?) ?? const [];
    if (choices.isNotEmpty) {
      orbState = OrbState.answering;
      targetMsg.content =
          choices.first['message']?['content']?.toString() ?? '';
      notifyListeners();
    }
  }

  // Enkraten tihi klic lokalnega LLM-ja za dejansko Learn sintezo pravil
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
          'num_ctx': 4096,
          if (customNumGpuLayers > 0) 'num_gpu': customNumGpuLayers,
        },
      })));
      final res = await req.close().timeout(const Duration(seconds: 45));
      if (res.statusCode == 200) {
        final decoded =
            jsonDecode(await res.transform(utf8.decoder).join());
        return decoded['response']?.toString();
      }
    } catch (_) {
    } finally {
      client.close();
    }
    return null;
  }

  // Sproži dejansko učenje nad trenutno izbrano mapo in pogovorom
  Future<int> triggerLearnPass({String? customFolder, bool silent = false}) async {
    final prevOrb = orbState;
    if (!silent && !isGenerating) {
      orbState = OrbState.thinking;
      notifyListeners();
    }

    final count = await memoryService.runIncrementalLearnPass(
      workspacePath: customFolder ?? currentBrowserDirectory,
      recentTurns: _sessionHistory,
      llmExtractor: _runOneShotLearnSynthesis,
    );

    if (!silent && !isGenerating) {
      orbState = prevOrb;
    }
    notifyListeners();
    return count;
  }

  //**************
  // Metode za vgrajeni VS Code kirurški urejevalnik kode *
  //**************
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
            description: 'Zamenjaj print() z debugPrint() za produkcijsko kodo',
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
        : currentBrowserDirectory;
    try {
      await Process.start('code', [path], runInShell: true);
    } catch (_) {}
  }

  //**************
  // GitHub in spletne povezave *
  //**************
  Future<void> connectGithubWithToken(String token) async {
    githubToken = token.trim();
    if (githubToken.isEmpty) {
      isGithubConnected = false;
      githubUsername = '';
      await saveRouterConfig();
      notifyListeners();
      return;
    }

    final client = HttpClient();
    try {
      final req =
          await client.getUrl(Uri.https('api.github.com', '/user'));
      req.headers.set('Authorization', 'Bearer $githubToken');
      req.headers.set('User-Agent', 'Ultron-Neural-Core');
      final res = await req.close();
      if (res.statusCode == 200) {
        final data = jsonDecode(await res.transform(utf8.decoder).join());
        githubUsername = data['login']?.toString() ?? 'GitHub User';
        isGithubConnected = true;
        await saveRouterConfig();
        await fetchGithubRepos();
      }
    } catch (_) {
    } finally {
      client.close();
      notifyListeners();
    }
  }

  Future<void> startGithubDeviceFlow() async {
    await openWebUrl('https://github.com/settings/tokens');
  }

  Future<void> fetchGithubRepos() async {
    if (githubToken.isEmpty) return;
    isFetchingRepos = true;
    notifyListeners();

    final client = HttpClient();
    try {
      final req = await client.getUrl(
        Uri.https('api.github.com', '/user/repos', {
          'sort': 'updated',
          'per_page': '25',
        }),
      );
      req.headers.set('Authorization', 'Bearer $githubToken');
      req.headers.set('User-Agent', 'Ultron-Neural-Core');
      final res = await req.close();

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

  Future<bool> cloneRepoToDesktop(String cloneUrl) async {
    try {
      final res = await Process.run(
        'git',
        ['clone', cloneUrl],
        workingDirectory: currentBrowserDirectory,
        runInShell: true,
      );
      notifyListeners();
      return res.exitCode == 0;
    } catch (_) {
      return false;
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
    final idx = path.lastIndexOf(Platform.pathSeparator);
    return idx == -1 ? path : path.substring(idx + 1);
  }

  String _extension(String path) {
    final dot = path.lastIndexOf('.');
    final sep = path.lastIndexOf(Platform.pathSeparator);
    if (dot == -1 || dot < sep) return '';
    return path.substring(dot).toLowerCase();
  }
}