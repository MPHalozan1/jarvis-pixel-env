import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';

//**************
// Trenutni odčitek porabe virov IZKLJUČNO za aplikacijo ULTRON in lokalni LLM *
// Ne vključuje ostalih procesov operacijskega sistema (brskalnika, VS Code itd.) *
//**************
class UltronResourceSnapshot {
  final double appCpuPercent;
  final double llmCpuPercent;
  final double appGpuPercent;
  final double llmGpuPercent;
  final int appRamBytes;
  final int llmRamBytes;
  final int appVramBytes;
  final int llmVramBytes;
  final String activeRunnerModel;
  final bool isModelLoadedInMemory;

  const UltronResourceSnapshot({
    this.appCpuPercent = 0.0,
    this.llmCpuPercent = 0.0,
    this.appGpuPercent = 0.0,
    this.llmGpuPercent = 0.0,
    this.appRamBytes = 0,
    this.llmRamBytes = 0,
    this.appVramBytes = 0,
    this.llmVramBytes = 0,
    this.activeRunnerModel = '',
    this.isModelLoadedInMemory = false,
  });

  double get totalCpuPercent =>
      (appCpuPercent + llmCpuPercent).clamp(0.0, 100.0);

  double get totalGpuPercent =>
      (appGpuPercent + llmGpuPercent).clamp(0.0, 100.0);

  int get totalRamBytes => appRamBytes + llmRamBytes;

  int get totalVramBytes => appVramBytes + llmVramBytes;

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final double mb = bytes / (1024 * 1024);
    if (mb < 1024) {
      return '${mb.round()} MB';
    }
    final double gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }
}

//**************
// Nizko-obremenitveni servis za živo merjenje CPE, GPE, RAM in VRAM porabe *
// Na Windowsih uporablja 4 MB trajni SWbemRefresher tok brez zaganjanja PowerShella, *
// na Linuxu (CachyOS) pa neposredno bere /proc in DRM fdinfo brez zunanjih procesov *
//**************
class UltronProcessTelemetryService extends ChangeNotifier {
  UltronResourceSnapshot latest = const UltronResourceSnapshot();
  final List<double> cpuHistory = List<double>.filled(28, 0.0, growable: true);
  final List<double> gpuHistory = List<double>.filled(28, 0.0, growable: true);

  String _ollamaBaseUrl = 'http://127.0.0.1:11434';
  bool _isStarted = false;
  bool _disposed = false;
  bool isUnloadingVram = false;

  Process? _winProbeProcess;
  Timer? _pollTimer;

  // Vmesne vrednosti iz sistemske sonde
  double _probeAppCpu = 0.0;
  double _probeLlmCpu = 0.0;
  double _probeAppGpu = 0.0;
  double _probeLlmGpu = 0.0;
  int _probeAppRam = 0;
  int _probeLlmRam = 0;
  int _probeAppVram = 0;
  int _probeLlmVram = 0;

  // Vmesne vrednosti iz Ollama /api/ps
  int _ollamaPsVramBytes = 0;
  int _ollamaPsCpuOffloadBytes = 0;
  String _ollamaLoadedModel = '';

  // Sledilniki za Linux /proc delto
  int _prevTotalCpuJiffies = 0;
  int _prevAppJiffies = 0;
  int _prevLlmJiffies = 0;
  final Map<int, int> _prevDrmEngineNs = {};
  DateTime _prevLinuxSampleTime = DateTime.now();

  void updateOllamaUrl(String url) {
    if (url.trim().isNotEmpty) {
      _ollamaBaseUrl = url.trim();
    }
  }

  Future<void> start({required String ollamaBaseUrl}) async {
    if (_isStarted) return;
    _isStarted = true;
    updateOllamaUrl(ollamaBaseUrl);

    if (Platform.isWindows) {
      await _startLightweightWindowsWmiStream();
    }

    await _sampleTick();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 1600),
      (_) => _sampleTick(),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _winProbeProcess?.kill();
    _winProbeProcess = null;
    super.dispose();
  }

  //**************
  // Zažene en sam lahek cscript.exe SWbemRefresher proces (~4 MB RAM) za PID meritve *
  //**************
  Future<void> _startLightweightWindowsWmiStream() async {
    try {
      final dir = Directory(
          '${Directory.current.path}${Platform.pathSeparator}ultron_memory');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final scriptFile = File(
          '${dir.path}${Platform.pathSeparator}ultron_telemetry_probe.js');

      const jsSource = r'''
var args = WScript.Arguments;
var appPid = args.length > 0 ? parseInt(args(0), 10) : -1;
var cores = args.length > 1 ? parseInt(args(1), 10) : 1;
if (cores < 1) cores = 1;
var wmi = GetObject("winmgmts:\\\\.\\root\\cimv2");
var refresher = new ActiveXObject("WbemScripting.SWbemRefresher");
var procEnum = null;
var gpuEngEnum = null;
var gpuMemEnum = null;
try { procEnum = refresher.AddEnum(wmi, "Win32_PerfFormattedData_PerfProc_Process").ObjectSet; } catch (e) {}
try { gpuEngEnum = refresher.AddEnum(wmi, "Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine").ObjectSet; } catch (e) {}
try { gpuMemEnum = refresher.AddEnum(wmi, "Win32_PerfFormattedData_GPUPerformanceCounters_GPUProcessMemory").ObjectSet; } catch (e) {}
refresher.Refresh();
WScript.Sleep(450);
while (true) {
  try {
    refresher.Refresh();
    var appCpu = 0, llmCpu = 0, appRam = 0, llmRam = 0;
    var appGpu = 0, llmGpu = 0, appVram = 0, llmVram = 0;
    var llmPids = {};
    if (procEnum != null) {
      var eProc = new Enumerator(procEnum);
      for (; !eProc.atEnd(); eProc.moveNext()) {
        var p = eProc.item();
        var id = Number(p.IDProcess);
        if (id <= 0) continue;
        var nm = String(p.Name || "").toLowerCase();
        var isApp = (id === appPid);
        var isLlm = !isApp && (nm.indexOf("ollama") === 0 || nm.indexOf("llama") === 0 || nm.indexOf("lm studio") === 0 || nm.indexOf("lmstudio") === 0);
        if (isApp) {
          appCpu += Number(p.PercentProcessorTime || 0);
          appRam += Number(p.WorkingSetPrivate || p.WorkingSet || 0);
        } else if (isLlm) {
          llmPids[id] = true;
          llmCpu += Number(p.PercentProcessorTime || 0);
          llmRam += Number(p.WorkingSetPrivate || p.WorkingSet || 0);
        }
      }
    }
    if (gpuEngEnum != null) {
      var eEng = new Enumerator(gpuEngEnum);
      for (; !eEng.atEnd(); eEng.moveNext()) {
        var g = eEng.item();
        var gName = String(g.Name || "");
        if (gName.indexOf("pid_") !== 0) continue;
        var us = gName.indexOf("_", 4);
        if (us === -1) continue;
        var gPid = parseInt(gName.substring(4, us), 10);
        var util = Number(g.UtilizationPercentage || 0);
        if (util <= 0) continue;
        if (gPid === appPid) appGpu += util;
        else if (llmPids[gPid]) llmGpu += util;
      }
    }
    if (gpuMemEnum != null) {
      var eMem = new Enumerator(gpuMemEnum);
      for (; !eMem.atEnd(); eMem.moveNext()) {
        var m = eMem.item();
        var mName = String(m.Name || "");
        if (mName.indexOf("pid_") !== 0) continue;
        var mus = mName.indexOf("_", 4);
        if (mus === -1) continue;
        var mPid = parseInt(mName.substring(4, mus), 10);
        var ded = Number(m.DedicatedUsage || 0);
        if (ded <= 0) continue;
        if (mPid === appPid) appVram += ded;
        else if (llmPids[mPid]) llmVram += ded;
      }
    }
    appCpu = Math.min(100, appCpu / cores);
    llmCpu = Math.min(100, llmCpu / cores);
    appGpu = Math.min(100, appGpu);
    llmGpu = Math.min(100, llmGpu);
    WScript.StdOut.WriteLine('{"appCpu":' + appCpu.toFixed(2) + ',"llmCpu":' + llmCpu.toFixed(2) + ',"appGpu":' + appGpu.toFixed(2) + ',"llmGpu":' + llmGpu.toFixed(2) + ',"appRam":' + Math.round(appRam) + ',"llmRam":' + Math.round(llmRam) + ',"appVram":' + Math.round(appVram) + ',"llmVram":' + Math.round(llmVram) + '}');
  } catch (err) {}
  WScript.Sleep(1400);
}
''';

      await scriptFile.writeAsString(jsSource);

      final proc = await Process.start(
        'cscript',
        [
          '//NoLogo',
          scriptFile.path,
          '$pid',
          '${Platform.numberOfProcessors}',
        ],
        runInShell: false,
      );
      _winProbeProcess = proc;

      proc.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        if (_disposed || line.trim().isEmpty || !line.startsWith('{')) return;
        try {
          final map = jsonDecode(line) as Map<String, dynamic>;
          _probeAppCpu = (map['appCpu'] as num?)?.toDouble() ?? 0.0;
          _probeLlmCpu = (map['llmCpu'] as num?)?.toDouble() ?? 0.0;
          _probeAppGpu = (map['appGpu'] as num?)?.toDouble() ?? 0.0;
          _probeLlmGpu = (map['llmGpu'] as num?)?.toDouble() ?? 0.0;
          _probeAppRam = (map['appRam'] as num?)?.toInt() ?? 0;
          _probeLlmRam = (map['llmRam'] as num?)?.toInt() ?? 0;
          _probeAppVram = (map['appVram'] as num?)?.toInt() ?? 0;
          _probeLlmVram = (map['llmVram'] as num?)?.toInt() ?? 0;
        } catch (_) {}
      });
    } catch (_) {}
  }

  //**************
  // Neposredno branje Linux /proc in DRM fdinfo (nič zunanjih procesov na CachyOS) *
  //**************
  Future<void> _sampleLinuxProc() async {
    try {
      final statHeader = await File('/proc/stat').readAsLines();
      if (statHeader.isEmpty) return;
      final cpuCols = statHeader.first
          .trim()
          .split(RegExp(r'\s+'))
          .skip(1)
          .map((s) => int.tryParse(s) ?? 0)
          .toList();
      final int totalJiffies = cpuCols.fold<int>(0, (a, b) => a + b);

      final appStat = await _readLinuxPidJiffiesAndRss(pid);
      int llmJiffiesSum = 0;
      int llmRssSum = 0;
      final llmPids = <int>[];

      await for (final entity
          in Directory('/proc').list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = entity.path.split('/').last;
        final procId = int.tryParse(name);
        if (procId == null || procId == pid) continue;

        try {
          final comm =
              (await File('${entity.path}/comm').readAsString()).trim().toLowerCase();
          if (comm.startsWith('ollama') ||
              comm.startsWith('llama') ||
              comm.contains('lmstudio') ||
              comm.contains('lm-studio')) {
            llmPids.add(procId);
            final st = await _readLinuxPidJiffiesAndRss(procId);
            llmJiffiesSum += st.$1;
            llmRssSum += st.$2;
          }
        } catch (_) {}
      }

      final int deltaTotal = totalJiffies - _prevTotalCpuJiffies;
      if (_prevTotalCpuJiffies > 0 && deltaTotal > 0) {
        final int deltaApp = math.max(0, appStat.$1 - _prevAppJiffies);
        final int deltaLlm = math.max(0, llmJiffiesSum - _prevLlmJiffies);
        _probeAppCpu = ((deltaApp / deltaTotal) * 100.0).clamp(0.0, 100.0);
        _probeLlmCpu = ((deltaLlm / deltaTotal) * 100.0).clamp(0.0, 100.0);
      }

      _prevTotalCpuJiffies = totalJiffies;
      _prevAppJiffies = appStat.$1;
      _prevLlmJiffies = llmJiffiesSum;
      _probeAppRam = appStat.$2;
      _probeLlmRam = llmRssSum;

      // Branje DRM GPU fdinfo (Intel Arc xe/i915 & AMD amdgpu)
      final now = DateTime.now();
      final elapsedNs =
          now.difference(_prevLinuxSampleTime).inMicroseconds * 1000;
      _prevLinuxSampleTime = now;

      if (elapsedNs > 0) {
        final appDrm = await _readLinuxDrmFdInfo(pid);
        final prevAppNs = _prevDrmEngineNs[pid] ?? appDrm.$1;
        _prevDrmEngineNs[pid] = appDrm.$1;
        _probeAppGpu =
            (((appDrm.$1 - prevAppNs).clamp(0, elapsedNs) / elapsedNs) * 100.0)
                .clamp(0.0, 100.0);
        _probeAppVram = appDrm.$2;

        double totalLlmGpu = 0.0;
        int totalLlmDrmVram = 0;
        for (final lPid in llmPids) {
          final lDrm = await _readLinuxDrmFdInfo(lPid);
          final prevNs = _prevDrmEngineNs[lPid] ?? lDrm.$1;
          _prevDrmEngineNs[lPid] = lDrm.$1;
          totalLlmGpu +=
              ((lDrm.$1 - prevNs).clamp(0, elapsedNs) / elapsedNs) * 100.0;
          totalLlmDrmVram += lDrm.$2;
        }
        _probeLlmGpu = totalLlmGpu.clamp(0.0, 100.0);
        _probeLlmVram = totalLlmDrmVram;
      }
    } catch (_) {}
  }

  Future<(int, int)> _readLinuxPidJiffiesAndRss(int targetPid) async {
    try {
      final rawStat = await File('/proc/$targetPid/stat').readAsString();
      final closeParen = rawStat.lastIndexOf(')');
      if (closeParen == -1) return (0, 0);
      final fields =
          rawStat.substring(closeParen + 2).trim().split(RegExp(r'\s+'));
      final int utime = int.tryParse(fields[11]) ?? 0;
      final int stime = int.tryParse(fields[12]) ?? 0;
      final int rssPages = int.tryParse(fields[21]) ?? 0;
      return (utime + stime, rssPages * 4096);
    } catch (_) {
      return (0, 0);
    }
  }

  Future<(int, int)> _readLinuxDrmFdInfo(int targetPid) async {
    int maxEngineNs = 0;
    int maxVramBytes = 0;
    try {
      final fdInfoDir = Directory('/proc/$targetPid/fdinfo');
      if (!await fdInfoDir.exists()) return (0, 0);
      int checked = 0;
      await for (final f in fdInfoDir.list(followLinks: false)) {
        if (f is! File || checked++ > 28) break;
        try {
          final content = await f.readAsString();
          if (!content.contains('drm-')) continue;
          int fileEngSum = 0;
          for (final line in content.split('\n')) {
            if (line.startsWith('drm-engine-')) {
              final m = RegExp(r':\s*(\d+)\s*ns').firstMatch(line);
              if (m != null) fileEngSum += int.tryParse(m.group(1)!) ?? 0;
            } else if (line.startsWith('drm-memory-vram:') ||
                line.startsWith('drm-resident-vram0:')) {
              final m = RegExp(r':\s*(\d+)\s*([KkMmGg]i?[Bb])?').firstMatch(line);
              if (m != null) {
                final val = int.tryParse(m.group(1)!) ?? 0;
                final unit = (m.group(2) ?? 'kib').toLowerCase();
                final mult = unit.startsWith('m')
                    ? 1024 * 1024
                    : (unit.startsWith('g') ? 1024 * 1024 * 1024 : 1024);
                maxVramBytes = math.max(maxVramBytes, val * mult);
              }
            }
          }
          maxEngineNs = math.max(maxEngineNs, fileEngSum);
        } catch (_) {}
      }
    } catch (_) {}
    return (maxEngineNs, maxVramBytes);
  }

  //**************
  // Preveri Ollama /api/ps za natančno zasedenost VRAM-a in RAM-a naloženega LLM-ja *
  //**************
  Future<void> _queryOllamaRunningPs() async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(milliseconds: 900);
    try {
      final cleanBase = _ollamaBaseUrl.endsWith('/')
          ? _ollamaBaseUrl.substring(0, _ollamaBaseUrl.length - 1)
          : _ollamaBaseUrl;
      final req = await client.getUrl(Uri.parse('$cleanBase/api/ps'));
      final res =
          await req.close().timeout(const Duration(milliseconds: 1100));
      if (res.statusCode == 200) {
        final body = await res.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final models = (data['models'] as List<dynamic>?) ?? const [];

        int vramSum = 0;
        int cpuWeightSum = 0;
        String activeName = '';

        for (final item in models) {
          if (item is! Map<String, dynamic>) continue;
          final int sz = (item['size'] as num?)?.toInt() ?? 0;
          final int vram = (item['size_vram'] as num?)?.toInt() ?? 0;
          vramSum += vram;
          if (sz > vram) {
            cpuWeightSum += (sz - vram);
          }
          activeName = item['name']?.toString() ?? activeName;
        }

        _ollamaPsVramBytes = vramSum;
        _ollamaPsCpuOffloadBytes = cpuWeightSum;
        _ollamaLoadedModel = activeName;
      }
    } catch (_) {
      _ollamaPsVramBytes = 0;
      _ollamaPsCpuOffloadBytes = 0;
      _ollamaLoadedModel = '';
    } finally {
      client.close();
    }
  }

  Future<void> _sampleTick() async {
    if (_disposed) return;

    if (Platform.isLinux) {
      await _sampleLinuxProc();
    }
    await _queryOllamaRunningPs();

    final int dartRss = ProcessInfo.currentRss;
    final int effectiveAppRam = _probeAppRam > 0 ? _probeAppRam : dartRss;
    final int effectiveLlmRam = _probeLlmRam > 0
        ? _probeLlmRam
        : _ollamaPsCpuOffloadBytes;
    final int effectiveLlmVram =
        math.max(_ollamaPsVramBytes, _probeLlmVram);

    latest = UltronResourceSnapshot(
      appCpuPercent: _probeAppCpu,
      llmCpuPercent: _probeLlmCpu,
      appGpuPercent: _probeAppGpu,
      llmGpuPercent: _probeLlmGpu,
      appRamBytes: effectiveAppRam,
      llmRamBytes: effectiveLlmRam,
      appVramBytes: _probeAppVram,
      llmVramBytes: effectiveLlmVram,
      activeRunnerModel: _ollamaLoadedModel,
      isModelLoadedInMemory:
          _ollamaLoadedModel.isNotEmpty || effectiveLlmVram > 64 * 1024 * 1024,
    );

    if (cpuHistory.length >= 28) cpuHistory.removeAt(0);
    if (gpuHistory.length >= 28) gpuHistory.removeAt(0);
    cpuHistory.add(latest.totalCpuPercent);
    gpuHistory.add(latest.totalGpuPercent);

    if (!_disposed) {
      notifyListeners();
    }
  }

  //**************
  // Z enim klikom takoj sprosti naloženi lokalni LLM iz VRAM-a in RAM-a (keep_alive: 0) *
  //**************
  Future<bool> unloadActiveModelFromMemory(String fallbackModelName) async {
    final targetModel = _ollamaLoadedModel.isNotEmpty
        ? _ollamaLoadedModel
        : fallbackModelName;
    if (targetModel.isEmpty || targetModel.startsWith('lmstudio:')) {
      return false;
    }

    isUnloadingVram = true;
    notifyListeners();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 3);
    try {
      final cleanBase = _ollamaBaseUrl.endsWith('/')
          ? _ollamaBaseUrl.substring(0, _ollamaBaseUrl.length - 1)
          : _ollamaBaseUrl;
      final req = await client.postUrl(Uri.parse('$cleanBase/api/generate'));
      req.headers.contentType = ContentType.json;
      req.add(utf8.encode(jsonEncode({
        'model': targetModel,
        'keep_alive': 0,
      })));
      final res = await req.close().timeout(const Duration(seconds: 4));
      await res.drain<void>();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await _sampleTick();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close();
      isUnloadingVram = false;
      if (!_disposed) notifyListeners();
    }
  }
}