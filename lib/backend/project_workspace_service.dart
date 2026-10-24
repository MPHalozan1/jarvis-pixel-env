import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

//**************
// Vrste operacij, ki jih lokalni LLM ali uporabnik izvede nad projektno mapo *
//**************
enum WorkspaceActionType {
  readFile,
  listFolder,
  createFolder,
  createFile,
  updateFile,
  error,
}

//**************
// Zapis izvedene operacije v projektni mapi za prikaz interaktivnih značk v klepetu *
//**************
class WorkspaceActionRecord {
  final WorkspaceActionType type;
  final String relativePath;
  final String fullPath;
  final String detail;
  final bool success;

  const WorkspaceActionRecord({
    required this.type,
    required this.relativePath,
    required this.fullPath,
    required this.detail,
    this.success = true,
  });
}

//**************
// Predlog zapisa datoteke ali mape (uporabno za 1-klik potrditev v varnem načinu) *
//**************
class WorkspaceWriteDirective {
  final String path;
  final String content;
  final bool isDirectory;
  final bool isFallbackCodeBlock;

  const WorkspaceWriteDirective({
    required this.path,
    this.content = '',
    this.isDirectory = false,
    this.isFallbackCodeBlock = false,
  });
}

//**************
// Razčlenjene ukaze lokalnega LLM modela za branje in pisanje v projektno mapo *
//**************
class ParsedLlmWorkspaceDirectives {
  final List<String> readRequests;
  final List<String> mkdirRequests;
  final List<WorkspaceWriteDirective> writeRequests;
  final List<WorkspaceWriteDirective> fallbackProposals;
  final String cleanedDisplayContent;

  const ParsedLlmWorkspaceDirectives({
    required this.readRequests,
    required this.mkdirRequests,
    required this.writeRequests,
    required this.fallbackProposals,
    required this.cleanedDisplayContent,
  });
}

//**************
// Metapodatki posamezne datoteke v indeksirani projektni mapi *
//**************
class WorkspaceFileEntry {
  final String fullPath;
  final String relativePath;
  final String name;
  final String extension;
  final int sizeBytes;
  final bool isReadableText;
  final String symbolSummary;

  const WorkspaceFileEntry({
    required this.fullPath,
    required this.relativePath,
    required this.name,
    required this.extension,
    required this.sizeBytes,
    required this.isReadableText,
    this.symbolSummary = '',
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
// Servis za 100% zanesljivo indeksiranje, branje celotnih projektnih map *
// ter ustvarjanje novih map in datotek za vse lokalne LLM modele *
//**************
class ProjectWorkspaceService {
  String activeRootPath = Directory.current.path;
  bool isIndexing = false;
  DateTime? lastIndexedAt;

  final List<WorkspaceFileEntry> indexedFiles = [];
  final List<String> indexedFolders = [];

  static const Set<String> _ignoredDirNames = {
    '.git',
    '.dart_tool',
    'build',
    'node_modules',
    '.idea',
    '.vscode',
    '__pycache__',
    'bin',
    'obj',
    '.gradle',
    'ephemeral',
    '.next',
    'dist',
    'target',
    'Pods',
  };

  static const Set<String> _textCodeExtensions = {
    '.dart',
    '.yaml',
    '.yml',
    '.json',
    '.md',
    '.txt',
    '.cs',
    '.csproj',
    '.sln',
    '.py',
    '.js',
    '.ts',
    '.tsx',
    '.jsx',
    '.html',
    '.css',
    '.scss',
    '.cpp',
    '.cc',
    '.c',
    '.h',
    '.hpp',
    '.go',
    '.rs',
    '.java',
    '.kt',
    '.sql',
    '.sh',
    '.bat',
    '.ps1',
    '.toml',
    '.ini',
    '.xml',
    '.cmake',
    '.gitignore',
  };

  //**************
  // Indeksira celotno projektno mapo in izlušči drevesno strukturo ter simbole kode *
  //**************
  Future<void> indexProjectFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return;

    isIndexing = true;
    activeRootPath = _normalizeRootPath(dir.absolute.path);

    final files = <WorkspaceFileEntry>[];
    final folders = <String>[];

    try {
      await _walkDirectory(
        current: Directory(activeRootPath),
        rootPath: activeRootPath,
        depth: 0,
        maxDepth: 9,
        filesOut: files,
        foldersOut: folders,
      );

      files.sort((a, b) =>
          a.relativePath.toLowerCase().compareTo(b.relativePath.toLowerCase()));
      folders.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      indexedFiles
        ..clear()
        ..addAll(files);
      indexedFolders
        ..clear()
        ..addAll(folders);
      lastIndexedAt = DateTime.now();
    } finally {
      isIndexing = false;
    }
  }

  Future<void> _walkDirectory({
    required Directory current,
    required String rootPath,
    required int depth,
    required int maxDepth,
    required List<WorkspaceFileEntry> filesOut,
    required List<String> foldersOut,
  }) async {
    if (depth > maxDepth || filesOut.length >= 650) return;

    List<FileSystemEntity> children;
    try {
      children = await current.list(followLinks: false).toList();
    } catch (_) {
      return;
    }

    for (final entity in children) {
      if (filesOut.length >= 650) break;
      final name = _basename(entity.path);
      if (name.isEmpty) continue;

      final rel = _toRelativePosix(entity.path, rootPath);

      if (entity is Directory) {
        if (_ignoredDirNames.contains(name)) continue;
        // Izpustimo arhiv klepetov, da ne onesnažuje konteksta kode
        if (rel == 'ultron_memory/chats') continue;

        foldersOut.add(rel);
        await _walkDirectory(
          current: entity,
          rootPath: rootPath,
          depth: depth + 1,
          maxDepth: maxDepth,
          filesOut: filesOut,
          foldersOut: foldersOut,
        );
      } else if (entity is File) {
        if (name == 'pubspec.lock' ||
            name == 'package-lock.json' ||
            name == 'yarn.lock' ||
            name == 'Cargo.lock') {
          // Zabeležimo lock datoteko v drevesu, vendar je ne beremo v predpomnilnik kode
          int sz = 0;
          try {
            sz = (await entity.stat()).size;
          } catch (_) {}
          filesOut.add(
            WorkspaceFileEntry(
              fullPath: entity.path,
              relativePath: rel,
              name: name,
              extension: _ext(name),
              sizeBytes: sz,
              isReadableText: false,
            ),
          );
          continue;
        }

        try {
          final stat = await entity.stat();
          final ext = _ext(name);
          final bool knownText = _textCodeExtensions.contains(ext) ||
              name == 'CMakeLists.txt' ||
              name == 'Dockerfile' ||
              name == 'Makefile';

          bool readable = knownText && stat.size <= 512 * 1024;
          String symbols = '';

          if (!readable && stat.size > 0 && stat.size <= 96 * 1024) {
            final probe = await entity
                .openRead(0, math.min(stat.size, 1024))
                .fold<List<int>>(<int>[], (p, c) => p..addAll(c));
            readable = _looksPrintable(probe);
          }

          if (readable && stat.size > 0 && stat.size <= 180 * 1024) {
            final snippetBytes = await entity
                .openRead(0, math.min(stat.size, 18000))
                .fold<List<int>>(<int>[], (p, c) => p..addAll(c));
            final text = utf8.decode(snippetBytes, allowMalformed: true);
            symbols = _extractTopSymbols(text);
          }

          filesOut.add(
            WorkspaceFileEntry(
              fullPath: entity.path,
              relativePath: rel,
              name: name,
              extension: ext,
              sizeBytes: stat.size,
              isReadableText: readable,
              symbolSummary: symbols,
            ),
          );
        } catch (_) {}
      }
    }
  }

  // Izlušči imena glavnih razredov, gradnikov ali funkcij za takojšen vpogled v vsako datoteko
  String _extractTopSymbols(String source) {
    final found = <String>[];
    final symbolRegex = RegExp(
      r'^\s*(?:abstract\s+|sealed\s+|final\s+)?(?:class|enum|mixin|extension|struct|interface|def|func)\s+([A-Za-z_][A-Za-z0-9_]*)',
      multiLine: true,
    );
    for (final m in symbolRegex.allMatches(source)) {
      final sym = m.group(1);
      if (sym != null && !sym.startsWith('_') && !found.contains(sym)) {
        found.add(sym);
        if (found.length >= 5) break;
      }
    }
    return found.join(', ');
  }

  //**************
  // Zgradi celoten kontekst projektne mape za lokalni LLM: *
  // 1. Popoln seznam vseh map in datotek z velikostmi ter simboli *
  // 2. Samodejno prebrana vsebina relevantnih ali ključnih projektnih datotek *
  //**************
  Future<String> buildWorkspacePromptContext({
    required String userPrompt,
    required int maxCharsBudget,
    Set<String> excludeFullPaths = const {},
    List<WorkspaceActionRecord>? recordedAutoReads,
  }) async {
    if (indexedFiles.isEmpty && indexedFolders.isEmpty) {
      await indexProjectFolder(activeRootPath);
    }

    final out = StringBuffer();
    out.writeln('AKTIVNA PROJEKTNA MAPA: $activeRootPath');
    out.writeln(
        'Statistika projekta: ${indexedFolders.length} map, ${indexedFiles.length} datotek.\n');

    // 1. Celotna struktura projektne mape
    out.writeln('CELOTNA STRUKTURA PROJEKTNE MAPE (vse mape in datoteke):');
    if (indexedFolders.isNotEmpty) {
      for (final folder in indexedFolders.take(120)) {
        out.writeln('  [DIR]  $folder/');
      }
    }
    for (final f in indexedFiles.take(320)) {
      final symInfo =
          f.symbolSummary.isNotEmpty ? '  -> {${f.symbolSummary}}' : '';
      out.writeln('  [FILE] ${f.relativePath} (${f.humanSize})$symInfo');
    }
    if (indexedFiles.length > 320) {
      out.writeln(
          '  ... (+${indexedFiles.length - 320} dodatnih datotek, uporabi <ultron_read path="..." />)');
    }
    out.writeln();

    // 2. Pametno točkovanje in samodejno branje datotek glede na uporabnikovo vprašanje
    final int remainingBudget =
        (maxCharsBudget - out.length).clamp(4000, maxCharsBudget);
    final scored = _scoreFilesForPrompt(userPrompt)
        .where((e) => e.isReadableText && !excludeFullPaths.contains(e.fullPath))
        .toList();

    if (scored.isNotEmpty) {
      out.writeln(
          'SAMODEJNO PREBRANE DATOTEKE IZ PROJEKTNE MAPE (polna izvorna koda):');
      int usedChars = 0;
      int loadedCount = 0;

      for (final entry in scored) {
        if (loadedCount >= 18 || usedChars >= remainingBudget) break;
        try {
          final file = File(entry.fullPath);
          if (!await file.exists()) continue;
          final rawText =
              utf8.decode(await file.readAsBytes(), allowMalformed: true);
          if (rawText.trim().isEmpty) continue;

          final int perFileCap =
              (remainingBudget - usedChars).clamp(1800, 14000);
          final String clipped = rawText.length > perFileCap
              ? '${rawText.substring(0, perFileCap)}\n// ... [Datoteka ${entry.relativePath} skrajšana; za preostanek uporabi <ultron_read path="${entry.relativePath}" />]'
              : rawText;

          final block =
              '--- PROJEKTNA DATOTEKA: ${entry.relativePath} ---\n$clipped\n--- KONEC: ${entry.relativePath} ---\n\n';
          if (usedChars + block.length > remainingBudget && loadedCount > 0) {
            continue;
          }

          out.write(block);
          usedChars += block.length;
          loadedCount++;

          recordedAutoReads?.add(
            WorkspaceActionRecord(
              type: WorkspaceActionType.readFile,
              relativePath: entry.relativePath,
              fullPath: entry.fullPath,
              detail: 'Samodejno prebrano (${entry.humanSize})',
            ),
          );
        } catch (_) {}
      }
    }

    return out.toString();
  }

  List<WorkspaceFileEntry> _scoreFilesForPrompt(String prompt) {
    final lowerPrompt = prompt.toLowerCase();
    final tokens = lowerPrompt
        .split(RegExp(r'[^a-z0-9_čšž.\-/\\]+'))
        .where((t) => t.length >= 3)
        .toSet();

    final bool broadOverviewQuery = lowerPrompt.contains('projekt') ||
        lowerPrompt.contains('project') ||
        lowerPrompt.contains('folder') ||
        lowerPrompt.contains('map') ||
        lowerPrompt.contains('all ') ||
        lowerPrompt.contains('whole') ||
        lowerPrompt.contains('celot') ||
        lowerPrompt.contains('vse ') ||
        lowerPrompt.contains('analiz') ||
        lowerPrompt.contains('analyz') ||
        lowerPrompt.contains('pregled') ||
        lowerPrompt.contains('struktur');

    final scored = <MapEntry<WorkspaceFileEntry, double>>[];

    for (final f in indexedFiles) {
      if (!f.isReadableText) continue;
      double score = 0.0;
      final relLower = f.relativePath.toLowerCase();
      final nameLower = f.name.toLowerCase();
      final stemLower = nameLower.contains('.')
          ? nameLower.substring(0, nameLower.lastIndexOf('.'))
          : nameLower;

      // Neposredna omemba datoteke ali poti v pozivu uporabnika
      if (lowerPrompt.contains(relLower) || lowerPrompt.contains(nameLower)) {
        score += 150.0;
      } else if (stemLower.length >= 4 && lowerPrompt.contains(stemLower)) {
        score += 95.0;
      }

      // Ujemanje posameznih besed s potjo ali simboli v datoteki
      final symLower = f.symbolSummary.toLowerCase();
      for (final tok in tokens) {
        if (relLower.contains(tok)) score += 22.0;
        if (symLower.contains(tok)) score += 26.0;
      }

      // Ključne vstopne in konfiguracijske datoteke projekta
      if (nameLower == 'pubspec.yaml' ||
          nameLower == 'package.json' ||
          nameLower == 'cargo.toml' ||
          nameLower == 'cmakelists.txt' ||
          nameLower.endsWith('.csproj') ||
          nameLower == 'readme.md') {
        score += broadOverviewQuery ? 65.0 : 28.0;
      }

      if (relLower == 'lib/main.dart' ||
          nameLower == 'main.dart' ||
          nameLower == 'main.py' ||
          nameLower == 'program.cs' ||
          nameLower == 'index.ts') {
        score += broadOverviewQuery ? 70.0 : 34.0;
      }

      if (relLower.startsWith('lib/') || relLower.startsWith('src/')) {
        score += broadOverviewQuery ? 48.0 : 18.0;
      }

      // Dajemo rahlo prednost kompaktnim izvornim datotekam za večjo pokritost
      if (f.sizeBytes > 0 && f.sizeBytes < 35000) {
        score += 6.0;
      }

      if (score > 0) {
        scored.add(MapEntry(f, score));
      }
    }

    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.map((e) => e.key).toList();
  }

  //**************
  // Varno razreši relativno ali polno pot znotraj aktivne projektne mape *
  // Prepreči pisanje izven projektnega korena (npr. napačen /lib/... na Linuxu) *
  //**************
  String? resolveSafePath(String rawPath, {required bool mustStayInRoot}) {
    String cleaned = rawPath
        .trim()
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll('`', '');
    if (cleaned.isEmpty) return null;

    final String rootNorm = _normalizeRootPath(activeRootPath);
    final String sep = Platform.pathSeparator;

    // Pretvorimo poševnice v sistemske ločevalnike za primerjavo z rootNorm
    final String osCandidate =
        cleaned.replaceAll('/', sep).replaceAll('\\', sep);

    // Če je pot že polna sistemska pot znotraj projektnega korena
    final bool matchesRoot = Platform.isWindows
        ? osCandidate.toLowerCase().startsWith(rootNorm.toLowerCase())
        : osCandidate.startsWith(rootNorm);

    String combined;
    if (matchesRoot) {
      combined = osCandidate;
    } else if (!mustStayInRoot && File(osCandidate).isAbsolute) {
      combined = osCandidate;
    } else {
      // Odstranimo vodilne ./ ali / (ko LLM zapiše "/lib/foo.dart" za projektni koren)
      String rel = cleaned;
      while (rel.startsWith('./') ||
          rel.startsWith('.\\') ||
          rel.startsWith('/') ||
          rel.startsWith('\\')) {
        rel = rel.substring(1);
      }
      if (rel.isEmpty) return rootNorm;
      combined = '$rootNorm$sep${rel.replaceAll('/', sep).replaceAll('\\', sep)}';
    }

    // Normaliziramo segmente (odpravimo . in ..)
    final normalized = _collapseSegments(combined);

    if (mustStayInRoot) {
      final bool stillInside = Platform.isWindows
          ? (normalized.toLowerCase() == rootNorm.toLowerCase() ||
              normalized
                  .toLowerCase()
                  .startsWith('${rootNorm.toLowerCase()}$sep'))
          : (normalized == rootNorm || normalized.startsWith('$rootNorm$sep'));
      if (!stillInside) return null;
    }

    return normalized;
  }

  //**************
  // Prebere poljubno datoteko ali podmapo v projektu na zahtevo LLM-ja (<ultron_read>) *
  // Vključuje pametno iskanje po imenu datoteke, če model izpusti podmapo *
  //**************
  Future<MapEntry<WorkspaceActionRecord, String>> readProjectTarget(
      String rawTarget) async {
    String? resolved = resolveSafePath(rawTarget, mustStayInRoot: false);
    resolved ??= resolveSafePath(rawTarget, mustStayInRoot: true);

    if (resolved != null) {
      final dir = Directory(resolved);
      if (await dir.exists()) {
        final rel = _toRelativePosix(dir.path, activeRootPath);
        final listing = StringBuffer()
          ..writeln('VSEBINA MAPE "$rel":');
        int count = 0;
        await for (final entity in dir.list(followLinks: false)) {
          count++;
          if (count > 120) break;
          final r = _toRelativePosix(entity.path, activeRootPath);
          listing.writeln(entity is Directory ? '  [DIR]  $r/' : '  [FILE]$r');
        }
        return MapEntry(
          WorkspaceActionRecord(
            type: WorkspaceActionType.listFolder,
            relativePath: rel,
            fullPath: dir.path,
            detail: 'Prebrana mapa ($count elementov)',
          ),
          listing.toString(),
        );
      }

      final file = File(resolved);
      if (await file.exists()) {
        final content =
            utf8.decode(await file.readAsBytes(), allowMalformed: true);
        final rel = _toRelativePosix(file.path, activeRootPath);
        return MapEntry(
          WorkspaceActionRecord(
            type: WorkspaceActionType.readFile,
            relativePath: rel,
            fullPath: file.path,
            detail: 'Prebrana datoteka',
          ),
          '=== CELOTNA DATOTEKA: $rel ===\n${_cap(content, 42000)}\n=== KONEC:$rel ===',
        );
      }
    }

    // Pametni fallback: poiščemo ujemanje po imenu datoteke v indeksu projekta
    final cleanQuery = _basename(rawTarget.replaceAll('/', Platform.pathSeparator))
        .toLowerCase();
    final fuzzyHits = indexedFiles
        .where((f) =>
            f.name.toLowerCase() == cleanQuery ||
            f.relativePath.toLowerCase().endsWith('/$cleanQuery'))
        .toList();

    if (fuzzyHits.isNotEmpty) {
      final hit = fuzzyHits.first;
      final file = File(hit.fullPath);
      if (await file.exists()) {
        final content =
            utf8.decode(await file.readAsBytes(), allowMalformed: true);
        return MapEntry(
          WorkspaceActionRecord(
            type: WorkspaceActionType.readFile,
            relativePath: hit.relativePath,
            fullPath: hit.fullPath,
            detail: 'Prebrana datoteka',
          ),
          '=== CELOTNA DATOTEKA: ${hit.relativePath} ===\n${_cap(content, 42000)}\n=== KONEC:${hit.relativePath} ===',
        );
      }
    }

    return MapEntry(
      WorkspaceActionRecord(
        type: WorkspaceActionType.error,
        relativePath: rawTarget,
        fullPath: rawTarget,
        detail: 'Datoteka ali mapa ne obstaja',
        success: false,
      ),
      'NAPAKA: Datoteka ali mapa "$rawTarget" v projektu "$activeRootPath" ne obstaja. Preveri točno pot v STRUKTURA PROJEKTNE MAPE.',
    );
  }

  //**************
  // Ustvari novo mapo (in morebitne nadrejene mape) v aktivnem projektu *
  //**************
  Future<WorkspaceActionRecord> createFolderInProject(String rawPath) async {
    final safePath = resolveSafePath(rawPath, mustStayInRoot: true);
    if (safePath == null) {
      return WorkspaceActionRecord(
        type: WorkspaceActionType.error,
        relativePath: rawPath,
        fullPath: rawPath,
        detail: 'Neveljavna pot izven projektne mape',
        success: false,
      );
    }

    try {
      final dir = Directory(safePath);
      await dir.create(recursive: true);
      final rel = _toRelativePosix(dir.path, activeRootPath);
      return WorkspaceActionRecord(
        type: WorkspaceActionType.createFolder,
        relativePath: rel,
        fullPath: dir.path,
        detail: 'Ustvarjena mapa',
      );
    } catch (e) {
      return WorkspaceActionRecord(
        type: WorkspaceActionType.error,
        relativePath: rawPath,
        fullPath: safePath,
        detail: 'Napaka pri ustvarjanju mape: $e',
        success: false,
      );
    }
  }

  //**************
  // Ustvari novo datoteko ali posodobi obstoječo datoteko v projektni mapi *
  // Samodejno ustvari manjkajoče podmape *
  //**************
  Future<WorkspaceActionRecord> writeFileInProject(
    String rawPath,
    String rawContent,
  ) async {
    String targetInput = rawPath.trim();

    // Če LLM poda samo ime obstoječe datoteke brez mape, jo posodobimo na pravem mestu
    if (!targetInput.contains('/') && !targetInput.contains('\\')) {
      final matches = indexedFiles
          .where((f) => f.name.toLowerCase() == targetInput.toLowerCase())
          .toList();
      if (matches.length == 1) {
        targetInput = matches.first.relativePath;
      }
    }

    final safePath = resolveSafePath(targetInput, mustStayInRoot: true);
    if (safePath == null) {
      return WorkspaceActionRecord(
        type: WorkspaceActionType.error,
        relativePath: rawPath,
        fullPath: rawPath,
        detail: 'Pot izven projektne mape zavrnjena',
        success: false,
      );
    }

    try {
      final file = File(safePath);
      final existed = await file.exists();
      await file.parent.create(recursive: true);

      final cleanCode = _stripAccidentalOuterCodeFence(rawContent);
      await file.writeAsString(cleanCode);

      final rel = _toRelativePosix(file.path, activeRootPath);
      return WorkspaceActionRecord(
        type: existed
            ? WorkspaceActionType.updateFile
            : WorkspaceActionType.createFile,
        relativePath: rel,
        fullPath: file.path,
        detail: existed ? 'Posodobljena datoteka' : 'Ustvarjena nova datoteka',
      );
    } catch (e) {
      return WorkspaceActionRecord(
        type: WorkspaceActionType.error,
        relativePath: rawPath,
        fullPath: safePath,
        detail: 'Napaka pri zapisu: $e',
        success: false,
      );
    }
  }

  //**************
  // Razčleni odgovor lokalnega LLM modela za <ultron_read>, <ultron_mkdir>, <ultron_write> *
  // ter zazna tudi rezervne kodne bloke z oznako // filepath: pot/datoteka *
  //**************
  ParsedLlmWorkspaceDirectives parseModelOutput(String rawOutput) {
    final reads = <String>[];
    final mkdirs = <String>[];
    final writes = <WorkspaceWriteDirective>[];
    final fallbacks = <WorkspaceWriteDirective>[];

    String display = rawOutput;

    // 1. Branje: <ultron_read path="..." /> ali <ultron_read>...</ultron_read>
    final readAttrRegex = RegExp(
      r'<ultron_read\s+(?:path|file|dir|target)\s*=\s*["\x27]([^"\x27]+)["\x27]\s*/?>',
      caseSensitive: false,
    );
    for (final m in readAttrRegex.allMatches(rawOutput)) {
      final p = m.group(1)?.trim() ?? '';
      if (p.isNotEmpty && !reads.contains(p)) reads.add(p);
    }
    display = display.replaceAll(readAttrRegex, '');

    final readBodyRegex = RegExp(
      r'<ultron_read\s*>([\s\S]*?)</ultron_read>',
      caseSensitive: false,
    );
    for (final m in readBodyRegex.allMatches(display)) {
      final p = m.group(1)?.trim() ?? '';
      if (p.isNotEmpty && !reads.contains(p)) reads.add(p);
    }
    display = display.replaceAll(readBodyRegex, '');

    // 2. Ustvarjanje map: <ultron_mkdir path="..." /> ali <ultron_mkdir>...</ultron_mkdir>
    final mkdirAttrRegex = RegExp(
      r'<ultron_mkdir\s+(?:path|dir|name)\s*=\s*["\x27]([^"\x27]+)["\x27]\s*/?>',
      caseSensitive: false,
    );
    for (final m in mkdirAttrRegex.allMatches(display)) {
      final p = m.group(1)?.trim() ?? '';
      if (p.isNotEmpty && !mkdirs.contains(p)) mkdirs.add(p);
    }
    display = display.replaceAll(mkdirAttrRegex, '');

    final mkdirBodyRegex = RegExp(
      r'<ultron_mkdir\s*>([\s\S]*?)</ultron_mkdir>',
      caseSensitive: false,
    );
    for (final m in mkdirBodyRegex.allMatches(display)) {
      final p = m.group(1)?.trim() ?? '';
      if (p.isNotEmpty && !mkdirs.contains(p)) mkdirs.add(p);
    }
    display = display.replaceAll(mkdirBodyRegex, '');

    // 3. Ustvarjanje / posodabljanje datotek: <ultron_write path="...">...</ultron_write>
    final writeRegex = RegExp(
      r'<ultron_write\s+(?:path|file|name)\s*=\s*["\x27]([^"\x27]+)["\x27]\s*>([\s\S]*?)</ultron_write>',
      caseSensitive: false,
    );
    display = display.replaceAllMapped(writeRegex, (match) {
      final path = match.group(1)?.trim() ?? '';
      final rawBody = match.group(2) ?? '';
      final cleanBody = _stripAccidentalOuterCodeFence(rawBody);
      if (path.isNotEmpty) {
        writes.add(WorkspaceWriteDirective(path: path, content: cleanBody));
      }
      final ext = _ext(path).replaceFirst('.', '');
      return '\n📄 **$path**\n```$ext\n$cleanBody\n```\n';
    });

    // 4. Rezervni razčlenjevalnik, če manjši model zapiše ```lang \n // filepath: pot/datoteka
    if (writes.isEmpty) {
      final fenceRegex = RegExp(r'```([a-zA-Z0-9_+-]*)\r?\n([\s\S]*?)```');
      for (final m in fenceRegex.allMatches(rawOutput)) {
        final code = m.group(2) ?? '';
        final firstLineEnd = code.indexOf('\n');
        final firstLine =
            (firstLineEnd == -1 ? code : code.substring(0, firstLineEnd)).trim();
        final pathMatch = RegExp(
          r'^(?://|#|--|/\*)\s*(?:filepath|file|path)\s*:\s*([A-Za-z0-9_.\-/\\]+)',
          caseSensitive: false,
        ).firstMatch(firstLine);

        if (pathMatch != null) {
          final detectedPath = pathMatch.group(1)?.trim() ?? '';
          final bodyWithoutHeader =
              firstLineEnd == -1 ? '' : code.substring(firstLineEnd + 1);
          if (detectedPath.isNotEmpty && bodyWithoutHeader.trim().isNotEmpty) {
            fallbacks.add(
              WorkspaceWriteDirective(
                path: detectedPath,
                content: bodyWithoutHeader,
                isFallbackCodeBlock: true,
              ),
            );
          }
        }
      }
    }

    return ParsedLlmWorkspaceDirectives(
      readRequests: reads,
      mkdirRequests: mkdirs,
      writeRequests: writes,
      fallbackProposals: fallbacks,
      cleanedDisplayContent: display.trim(),
    );
  }

  // Pripravi lep predogled med samim pretakanjem žetonov (brez surovih XML značk)
  String formatLiveStreamingPreview(String partialStream) {
    return partialStream
        .replaceAll(
          RegExp(
            r'<ultron_read\s+[^>]*>',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'<ultron_mkdir\s+[^>]*>',
            caseSensitive: false,
          ),
          '',
        )
        .replaceAllMapped(
          RegExp(
            r'<ultron_write\s+(?:path|file|name)\s*=\s*["\x27]([^"\x27]+)["\x27]\s*>',
            caseSensitive: false,
          ),
          (m) => '\n📄 **${m.group(1)}**\n```\n',
        )
        .replaceAll('</ultron_write>', '\n```\n');
  }

  //**************
  // Pripravi vsebino poljubne pripete mape za pošiljanje v kontekst klepeta *
  //**************
  Future<String> extractFullFolderPayload(
    String folderPath, {
    int maxChars = 38000,
  }) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return '(Mapa ne obstaja: $folderPath)';

    final root = _normalizeRootPath(dir.absolute.path);
    final tempFiles = <WorkspaceFileEntry>[];
    final tempDirs = <String>[];

    await _walkDirectory(
      current: Directory(root),
      rootPath: root,
      depth: 0,
      maxDepth: 7,
      filesOut: tempFiles,
      foldersOut: tempDirs,
    );

    final buf = StringBuffer()
      ..writeln('PRIPETA CELOTNA MAPA: $root')
      ..writeln('Mape (${tempDirs.length}), Datoteke (${tempFiles.length}):');

    for (final d in tempDirs.take(80)) {
      buf.writeln('  [DIR]  $d/');
    }
    for (final f in tempFiles.take(200)) {
      buf.writeln('  [FILE] ${f.relativePath} (${f.humanSize})');
    }
    buf.writeln();

    int used = buf.length;
    for (final f in tempFiles) {
      if (!f.isReadableText || used >= maxChars) continue;
      try {
        final raw =
            utf8.decode(await File(f.fullPath).readAsBytes(), allowMalformed: true);
        final capLen = (maxChars - used).clamp(1200, 10000);
        final snippet = raw.length > capLen
            ? '${raw.substring(0, capLen)}\n...[skrajšano]...'
            : raw;
        final section = '=== ${f.relativePath} ===\n$snippet\n\n';
        if (used + section.length > maxChars) break;
        buf.write(section);
        used += section.length;
      } catch (_) {}
    }

    return buf.toString();
  }

  String _stripAccidentalOuterCodeFence(String input) {
    String trimmed = input.trim();
    if (trimmed.startsWith('```')) {
      final firstNewline = trimmed.indexOf('\n');
      if (firstNewline != -1 && trimmed.endsWith('```')) {
        trimmed = trimmed.substring(firstNewline + 1, trimmed.length - 3);
      }
    }
    if (input.startsWith('\n') && !trimmed.endsWith('\n')) {
      return '$trimmed\n';
    }
    return trimmed;
  }

  bool _looksPrintable(List<int> bytes) {
    if (bytes.isEmpty) return true;
    int weird = 0;
    for (final b in bytes) {
      if (b == 0) return false;
      if (b < 9 || (b > 13 && b < 32)) weird++;
    }
    return (weird / bytes.length) < 0.08;
  }

  String _normalizeRootPath(String path) {
    if (path.length > 3 && path.endsWith(Platform.pathSeparator)) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }

  String _collapseSegments(String rawOsPath) {
    final sep = Platform.pathSeparator;
    final bool leadingSlash = rawOsPath.startsWith('/');
    final parts = rawOsPath.split(sep);
    final stack = <String>[];

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.isEmpty || part == '.') {
        if (i == 0 && Platform.isWindows && part.contains(':')) {
          stack.add(part);
        }
        continue;
      }
      if (part == '..') {
        if (stack.isNotEmpty && !(Platform.isWindows && stack.length == 1 && stack.first.contains(':'))) {
          stack.removeLast();
        }
      } else {
        stack.add(part);
      }
    }

    final joined = stack.join(sep);
    return leadingSlash ? '/$joined' : joined;
  }

  String _toRelativePosix(String fullPath, String rootPath) {
    final normRoot = _normalizeRootPath(rootPath);
    if (fullPath.length > normRoot.length && fullPath.startsWith(normRoot)) {
      String sub = fullPath.substring(normRoot.length);
      if (sub.startsWith(Platform.pathSeparator)) {
        sub = sub.substring(1);
      }
      return sub.replaceAll('\\', '/');
    }
    return fullPath.replaceAll('\\', '/');
  }

  String _basename(String path) {
    final cleaned = path.endsWith(Platform.pathSeparator) && path.length > 3
        ? path.substring(0, path.length - 1)
        : path;
    final idx = cleaned.lastIndexOf(Platform.pathSeparator);
    return idx == -1 ? cleaned : cleaned.substring(idx + 1);
  }

  String _ext(String path) {
    final dot = path.lastIndexOf('.');
    if (dot == -1) return '';
    return path.substring(dot).toLowerCase();
  }

  String _cap(String s, int maxChars) {
    if (s.length <= maxChars) return s;
    return '${s.substring(0, maxChars)}\n...[Skrajšano na $maxChars znakov]...';
  }
}