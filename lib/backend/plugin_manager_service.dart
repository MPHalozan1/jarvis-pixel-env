import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

//**************
// Deklarativni model vtičnika za razširitev spretnosti Ultrona *
//**************
class UltronPlugin {
  final String id;
  final String name;
  final String description;
  final String repoUrl;
  final String instructions;
  final bool enabled;

  const UltronPlugin({
    required this.id,
    required this.name,
    required this.description,
    required this.repoUrl,
    required this.instructions,
    this.enabled = false,
  });

  UltronPlugin copyWith({bool? enabled, String? instructions}) {
    return UltronPlugin(
      id: id,
      name: name,
      description: description,
      repoUrl: repoUrl,
      instructions: instructions ?? this.instructions,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'repoUrl': repoUrl,
        'instructions': instructions,
        'enabled': enabled,
      };

  factory UltronPlugin.fromJson(Map<String, dynamic> json) {
    return UltronPlugin(
      id: json['id']?.toString() ?? 'plugin',
      name: json['name']?.toString() ?? 'Plugin',
      description: json['description']?.toString() ?? '',
      repoUrl: json['repoUrl']?.toString() ?? '',
      instructions: json['instructions']?.toString() ?? '',
      enabled: json['enabled'] == true,
    );
  }
}

//**************
// Upravitelj vtičnikov z lokalnim shranjevanjem in iskanjem po GitHubu *
//**************
class PluginManagerService extends ChangeNotifier {
  late File _pluginsFile;
  final List<UltronPlugin> installedPlugins = [];
  final List<UltronPlugin> browseResults = [];

  bool isSearchingGithub = false;
  int globalPluginTokenBudget = 1200;
  String statusMessage = 'Vtičniki pripravljeni';

  Future<void> initialize() async {
    try {
      final dir = Directory(
          '${Directory.current.path}${Platform.pathSeparator}ultron_memory');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      _pluginsFile =
          File('${dir.path}${Platform.pathSeparator}installed_plugins.json');

      if (await _pluginsFile.exists()) {
        final decoded = jsonDecode(await _pluginsFile.readAsString());
        if (decoded is List) {
          installedPlugins
            ..clear()
            ..addAll(decoded
                .whereType<Map<String, dynamic>>()
                .map(UltronPlugin.fromJson));
        }
      }

      if (installedPlugins.isEmpty) {
        installedPlugins.addAll(const [
          UltronPlugin(
            id: 'clean-code-guard',
            name: 'Clean Code Guard',
            description:
                'Preverja robne primere, tipe, velike/male začetnice in čitljivost kode.',
            repoUrl: 'local://builtin/clean-code-guard',
            instructions:
                'Vedno preveri velike in male začetnice identifikatorjev, null-safety ter vrni popolno, delujočo kodo brez izpuščenih delov.',
            enabled: true,
          ),
          UltronPlugin(
            id: 'study-assistant',
            name: 'Study & Exercise Solver',
            description:
                'strukturirano rešuje šolske in laboratorijske vaje iz priloženih dokumentov.',
            repoUrl: 'local://builtin/study-assistant',
            instructions:
                'Ko uporabnik priloži dokument z vajami, naloge rešuj korak za korakom, jasno razloži logiko in dodaj čisto kodo.',
            enabled: true,
          ),
        ]);
        await _save();
      }
      notifyListeners();
    } catch (e) {
      statusMessage = 'Napaka pri nalaganju vtičnikov: $e';
    }
  }

  Future<void> _save() async {
    try {
      await _pluginsFile.writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert(installedPlugins.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> approveAndTogglePlugin(String id, bool enabled) async {
    final idx = installedPlugins.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    installedPlugins[idx] = installedPlugins[idx].copyWith(enabled: enabled);
    statusMessage = enabled
        ? 'Vtičnik ${installedPlugins[idx].name} vklopljen'
        : 'Vtičnik ${installedPlugins[idx].name} izklopljen';
    await _save();
    notifyListeners();
  }

  Future<void> uninstallPlugin(String id) async {
    installedPlugins.removeWhere((p) => p.id == id);
    statusMessage = 'Vtičnik odstranjen';
    await _save();
    notifyListeners();
  }

  Future<void> searchGithubPlugins(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return;

    isSearchingGithub = true;
    statusMessage = 'Iščem na GitHubu...';
    notifyListeners();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.https('api.github.com', '/search/repositories', {
        'q': '$trimmed topic:ai-agent OR $trimmed prompt',
        'per_page': '8',
      });
      final req = await client.getUrl(uri);
      req.headers.set('User-Agent', 'Ultron-Neural-Core');
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();

      if (res.statusCode == 200) {
        final data = jsonDecode(body) as Map<String, dynamic>;
        final items = (data['items'] as List<dynamic>?) ?? const [];
        browseResults
          ..clear()
          ..addAll(items.whereType<Map<String, dynamic>>().map((repo) {
            final fullName = repo['full_name']?.toString() ?? 'repo';
            final desc = repo['description']?.toString() ?? 'Brez opisa';
            return UltronPlugin(
              id: fullName.replaceAll('/', '_').toLowerCase(),
              name: fullName,
              description: desc,
              repoUrl: repo['html_url']?.toString() ?? '',
              instructions: 'Uporabi znanje modula $fullName: $desc',
            );
          }));
        statusMessage = 'Najdenih ${browseResults.length} rezultatov';
      } else {
        statusMessage = 'GitHub status: ${res.statusCode}';
      }
    } catch (e) {
      statusMessage = 'Iskanje ni uspelo (preveri povezavo)';
    } finally {
      client.close();
      isSearchingGithub = false;
      notifyListeners();
    }
  }

  Future<void> installPluginFromGithubUrl(String urlOrName) async {
    final cleaned = urlOrName.trim();
    if (cleaned.isEmpty) return;

    final existingFromBrowse = browseResults.where((p) =>
        p.repoUrl.toLowerCase() == cleaned.toLowerCase() ||
        p.name.toLowerCase() == cleaned.toLowerCase());

    if (existingFromBrowse.isNotEmpty) {
      final found = existingFromBrowse.first.copyWith(enabled: true);
      installedPlugins.removeWhere((p) => p.id == found.id);
      installedPlugins.insert(0, found);
      statusMessage = 'Nameščen ${found.name}';
      await _save();
      notifyListeners();
      return;
    }

    final shortName = cleaned.split('/').where((s) => s.isNotEmpty).last;
    final plugin = UltronPlugin(
      id: 'custom_${shortName.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch % 1000}',
      name: shortName,
      description: 'Uvožen modul iz $cleaned',
      repoUrl: cleaned,
      instructions:
          'Sledi pravilom in vzorcem iz repozitorija $shortName ($cleaned).',
      enabled: true,
    );
    installedPlugins.insert(0, plugin);
    statusMessage = 'Nameščen $shortName';
    await _save();
    notifyListeners();
  }

  String buildLazyLoadedPluginContext() {
    final active = installedPlugins.where((p) => p.enabled).toList();
    if (active.isEmpty) return '';

    final buf = StringBuffer()..writeln('AKTIVNI VTIČNIKI:');
    int approxChars = 0;
    final maxChars = globalPluginTokenBudget * 4;

    for (final p in active) {
      final line = '- [${p.name}]: ${p.instructions}\n';
      if (approxChars + line.length > maxChars) break;
      buf.write(line);
      approxChars += line.length;
    }
    return buf.toString();
  }
}