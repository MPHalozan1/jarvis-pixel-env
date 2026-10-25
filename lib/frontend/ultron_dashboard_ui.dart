import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../backend/memory_learning_usage_service.dart';
import '../backend/ultron_brain_router.dart';
import 'connections_hud_window.dart';
import 'plugins_hud_window.dart';
import 'sleek_file_manager.dart';
import 'ultron_bubble_painter.dart';
import 'ultron_chat_history_sidebar.dart';
import 'ultron_chat_renderer.dart';
import 'ultron_hud_theme.dart';
import 'ultron_telemetry_hud.dart';
import 'vscode_live_window.dart';

//**************
// Glavna nadzorna plošča ULTRON: *
// - Čist začetni zaslon s 3D kroglo in hitrimi akcijskimi karticami *
// - Središčni pogovorni oder brez prečnih črt čez zaslon *
// - Lebdeči Command Composer z vlečenjem višine (Drag-to-Resize), Zen načinom, *
//   @omenjanjem datotek, /ukazi ter stalno vidnim statusom projekta in Gita *
//**************
class UltronDashboardScreen extends StatefulWidget {
  final UltronBrainRouter brain;
  final bool isDarkMode;
  final VoidCallback onToggleTheme;

  const UltronDashboardScreen({
    super.key,
    required this.brain,
    required this.isDarkMode,
    required this.onToggleTheme,
  });

  @override
  State<UltronDashboardScreen> createState() => _UltronDashboardScreenState();
}

class _UltronDashboardScreenState extends State<UltronDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _orbTicker;
  Duration _lastTick = Duration.zero;

  final ValueNotifier<int> _orbFrameTick = ValueNotifier<int>(0);
  double _shellAngleY = 0.0;
  double _ringAngleY = 0.0;
  double _beamDriftPhase = 0.0;
  double _pulseClock = 0.0;
  double _keystrokeRipple = 0.0;
  OrbVisualParams _currentVisualParams =
      OrbVisualParams.forState(OrbState.standby);

  final TextEditingController _promptCtrl = TextEditingController();
  final ScrollController _chatScrollCtrl = ScrollController();
  final FocusNode _promptFocusNode = FocusNode();

  bool _promptFocused = false;
  bool _userScrolledUp = false;
  bool _isZenModeInput = false;
  bool _ctrlEnterToSend = false;
  double? _customComposerHeight;
  final Stopwatch _scrollThrottle = Stopwatch()..start();

  bool _showMentionMenu = false;
  String _mentionQuery = '';
  bool _showCommandMenu = false;
  String _commandQuery = '';

  static const List<Map<String, String>> _slashCommands = [
    {
      'cmd': '/fix ',
      'label': '/fix',
      'desc': 'Poišči in popravi napake v kodi ali aktivni datoteki',
    },
    {
      'cmd': '/refactor ',
      'label': '/refactor',
      'desc': 'Preuredi in optimiziraj izbrano kodo brez spremembe logike',
    },
    {
      'cmd': '/explain ',
      'label': '/explain',
      'desc': 'Jedrnato razloži delovanje kode ali arhitekture',
    },
    {
      'cmd': '/newfile ',
      'label': '/newfile',
      'desc': 'Ustvari novo datoteko neposredno v priklopljenem projektu',
    },
    {
      'cmd': '/learn',
      'label': '/learn',
      'desc': 'Zaženi učenje vzorcev iz trenutnega projekta in klepeta',
    },
    {
      'cmd': '/pull',
      'label': '/pull',
      'desc': 'Izvedi git pull v trenutni projektni mapi',
    },
    {
      'cmd': '/commit ',
      'label': '/commit',
      'desc': 'Izvedi git add & commit z izbranim sporočilom',
    },
    {
      'cmd': '/push',
      'label': '/push',
      'desc': 'Potisni lokalne commite na GitHub (git push)',
    },
    {
      'cmd': '/done',
      'label': '/done',
      'desc': 'Shrani trenutno sejo v zgodovino in začni nov klepet',
    },
  ];

  bool _showConnectionsModal = false;
  int _connectionsInitialTab = 0;
  bool _showPluginsModal = false;
  bool _showStudioCustomizer = false;
  bool _showTelemetryDetail = false;
  String? _toastMessage;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    widget.brain.addListener(_onBrainUpdated);
    _promptFocusNode.addListener(() {
      if (mounted) {
        setState(() => _promptFocused = _promptFocusNode.hasFocus);
        widget.brain.setInputFocus(_promptFocusNode.hasFocus);
      }
    });
    _chatScrollCtrl.addListener(_onScrollPositionChanged);
    _promptCtrl.addListener(_onPromptTextChanged);

    _orbTicker = createTicker((elapsed) {
      final double dt = _lastTick == Duration.zero
          ? 0.016
          : ((elapsed - _lastTick).inMicroseconds / 1000000.0)
              .clamp(0.001, 0.05);
      _lastTick = elapsed;

      final targetParams = OrbVisualParams.forState(widget.brain.orbState);
      _currentVisualParams = OrbVisualParams.lerp(
        _currentVisualParams,
        targetParams,
        (dt * 5.5).clamp(0.0, 1.0),
      );

      _shellAngleY += dt *
          OrbVisualParams.rotationSpeed *
          _currentVisualParams.shellSpinMultiplier;
      _ringAngleY -= dt * 0.36 * _currentVisualParams.ringDriftMultiplier;
      _beamDriftPhase += dt * 1.1;
      _pulseClock += dt;

      if (_keystrokeRipple > 0.001) {
        _keystrokeRipple = (_keystrokeRipple - dt * 2.6).clamp(0.0, 1.0);
      } else {
        _keystrokeRipple = 0.0;
      }

      _orbFrameTick.value++;
    });

    _syncBackgroundOrbTicker();
  }

  void _onPromptTextChanged() {
    widget.brain.notifyUserTyping();
    final text = _promptCtrl.text;
    final selection = _promptCtrl.selection;
    if (selection.baseOffset < 0 || selection.baseOffset > text.length) {
      if (mounted) setState(() {});
      return;
    }

    final textBeforeCursor = text.substring(0, selection.baseOffset);

    final mentionMatch =
        RegExp(r'(?:^|\s)@([a-zA-Z0-9_\-./\\]*)$').firstMatch(textBeforeCursor);
    if (mentionMatch != null && widget.brain.hasActiveProject) {
      setState(() {
        _showMentionMenu = true;
        _showCommandMenu = false;
        _mentionQuery = mentionMatch.group(1) ?? '';
      });
      return;
    }

    final commandMatch =
        RegExp(r'(?:^|\s)/([a-zA-Z]*)$').firstMatch(textBeforeCursor);
    if (commandMatch != null) {
      setState(() {
        _showCommandMenu = true;
        _showMentionMenu = false;
        _commandQuery = commandMatch.group(1) ?? '';
      });
      return;
    }

    setState(() {
      _showMentionMenu = false;
      _showCommandMenu = false;
    });
  }

  void _insertMentionOrCommand(String replacement, {String? filePathToAttach}) {
    final text = _promptCtrl.text;
    final selection = _promptCtrl.selection;
    final cursor = (selection.baseOffset >= 0 &&
            selection.baseOffset <= text.length)
        ? selection.baseOffset
        : text.length;
    final before = text.substring(0, cursor);
    final after = text.substring(cursor);

    final triggerIdx = before.lastIndexOf(RegExp(r'[@/]'));
    if (triggerIdx != -1) {
      final suffix = replacement.endsWith(' ') ? '' : ' ';
      final inserted = '$replacement$suffix';
      final newText = '${text.substring(0, triggerIdx)}$inserted$after';
      _promptCtrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: triggerIdx + inserted.length),
      );
    } else {
      final newText = '$text$replacement ';
      _promptCtrl.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: newText.length),
      );
    }

    setState(() {
      _showMentionMenu = false;
      _showCommandMenu = false;
    });
    _promptFocusNode.requestFocus();

    if (filePathToAttach != null) {
      widget.brain.attachFileFromPath(filePathToAttach);
      _showToast(
        'Pripeta datoteka: ${filePathToAttach.split(Platform.pathSeparator).last}',
      );
    }
  }

  KeyEventResult _handleComposerKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.escape &&
        (_showMentionMenu || _showCommandMenu || _isZenModeInput)) {
      setState(() {
        _showMentionMenu = false;
        _showCommandMenu = false;
        _isZenModeInput = false;
      });
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final isCtrl = HardwareKeyboard.instance.isControlPressed ||
          HardwareKeyboard.instance.isMetaPressed;
      final isShift = HardwareKeyboard.instance.isShiftPressed;

      if (_ctrlEnterToSend || _isZenModeInput) {
        if (isCtrl) {
          _submitPrompt();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      } else {
        if (!isShift) {
          _submitPrompt();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      }
    }

    return KeyEventResult.ignored;
  }

  void _syncBackgroundOrbTicker() {
    final bool shouldRunBigOrb = widget.brain.messages.isEmpty &&
        !_showConnectionsModal &&
        !_showPluginsModal;

    if (shouldRunBigOrb) {
      if (!_orbTicker.isActive) {
        _lastTick = Duration.zero;
        _orbTicker.start();
      }
    } else {
      if (_orbTicker.isActive) {
        _orbTicker.stop();
        _lastTick = Duration.zero;
      }
    }
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _promptCtrl.removeListener(_onPromptTextChanged);
    widget.brain.removeListener(_onBrainUpdated);
    _chatScrollCtrl.removeListener(_onScrollPositionChanged);
    _orbTicker.dispose();
    _orbFrameTick.dispose();
    _promptCtrl.dispose();
    _chatScrollCtrl.dispose();
    _promptFocusNode.dispose();
    super.dispose();
  }

  void _onScrollPositionChanged() {
    if (!_chatScrollCtrl.hasClients) return;
    final pos = _chatScrollCtrl.position;
    final nearBottom = (pos.maxScrollExtent - pos.pixels) <= 130.0;
    if (_userScrolledUp == nearBottom && mounted) {
      setState(() => _userScrolledUp = !nearBottom);
    }
  }

  void _onBrainUpdated() {
    if (!mounted) return;
    _syncBackgroundOrbTicker();
    setState(() {});
    _smoothFollowBottom();
  }

  void _smoothFollowBottom({bool force = false}) {
    if (!_chatScrollCtrl.hasClients) return;
    if (!force && _userScrolledUp) return;
    if (!force && _scrollThrottle.elapsedMilliseconds < 65) return;
    _scrollThrottle.reset();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScrollCtrl.hasClients) return;
      final target = _chatScrollCtrl.position.maxScrollExtent;
      if ((target - _chatScrollCtrl.offset).abs() < 2.0) return;
      _chatScrollCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toastMessage = message);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  Future<void> _pickAnyFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (result == null) return;

      int count = 0;
      for (final f in result.files) {
        if (f.path != null) {
          final ok = await widget.brain.attachFileFromPath(f.path!);
          if (ok) count++;
        }
      }
      if (count > 0) {
        _showToast('Pripeta $count datoteka/e');
      }
    } catch (_) {
      _showToast('Uporabi pripenjanje prek levega PC File Managerja');
    }
  }

  Future<void> _pickAndConnectProjectFolder() async {
    try {
      final dirPath = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Izberi projektno mapo za ULTRON',
        initialDirectory: widget.brain.hasActiveProject
            ? widget.brain.activeProjectPath
            : widget.brain.currentBrowserDirectory,
      );
      if (dirPath == null || dirPath.trim().isEmpty) return;

      await widget.brain.setActiveProjectFolder(dirPath);
      _showToast(
        'Priklopljen projekt: ${widget.brain.activeProjectName} (${widget.brain.workspaceService.indexedFiles.length} datotek)',
      );
    } catch (_) {
      await widget.brain
          .setActiveProjectFolder(widget.brain.currentBrowserDirectory);
      _showToast('Priklopljena trenutna mapa: ${widget.brain.activeProjectName}');
    }
  }

  void _openModalTab(int tabIdx) {
    setState(() {
      _connectionsInitialTab = tabIdx;
      _showConnectionsModal = true;
      _showPluginsModal = false;
      _showStudioCustomizer = false;
      _showTelemetryDetail = false;
    });
    _syncBackgroundOrbTicker();
  }

  void _submitPrompt([String? quickOverride]) {
    final text = quickOverride ?? _promptCtrl.text;
    if (text.trim().isEmpty && widget.brain.pendingAttachments.isEmpty) return;
    if (quickOverride == null) {
      _promptCtrl.clear();
    }
    _userScrolledUp = false;
    _keystrokeRipple = 1.0;
    setState(() {
      _isZenModeInput = false;
      _showMentionMenu = false;
      _showCommandMenu = false;
    });
    widget.brain.executeUltronPrompt(text);
    _syncBackgroundOrbTicker();
    _smoothFollowBottom(force: true);
  }

  void _showProjectMetaDialog(UltronProjectMeta meta) {
    showDialog(
      context: context,
      builder: (context) => _ProjectMetaDialog(
        meta: meta,
        brain: widget.brain,
      ),
    );
  }

  void _showQuickGitCommitDialog() {
    final ctrl =
        TextEditingController(text: 'feat: posodobitev prek ULTRON');
    bool pushAfter = true;

    showDialog(
      context: context,
      builder: (ctx) {
        final hud =
            Theme.of(ctx).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: hud.bgPanel,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(hud.cutRadius),
                side: BorderSide(color: hud.borderLine),
              ),
              title: Text(
                'Git Commit · veja "${widget.brain.localGitBranch}"',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: hud.textPrimary,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mapa: ${widget.brain.effectiveGitDirectory}\nSpremenjenih datotek: ${widget.brain.localGitChangedCount}',
                    style: TextStyle(fontSize: 11.5, color: hud.textMuted),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    style: TextStyle(fontSize: 13, color: hud.textPrimary),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: hud.bgInput,
                      hintText: 'Vpiši commit sporočilo...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: hud.borderLine),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Switch(
                        value: pushAfter,
                        activeTrackColor: hud.accentSuccessGreen,
                        activeThumbColor: Colors.white,
                        onChanged: (v) =>
                            setDialogState(() => pushAfter = v),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Takoj izvedi tudi Git Push',
                        style:
                            TextStyle(fontSize: 12, color: hud.textPrimary),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child:
                      Text('Prekliči', style: TextStyle(color: hud.textMuted)),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final ok = await widget.brain.commitCurrentGitWorkspace(
                      ctrl.text,
                      pushAfter: pushAfter,
                    );
                    _showToast(
                      ok
                          ? (pushAfter
                              ? 'Git Commit & Push uspešen'
                              : 'Git Commit uspešen')
                          : 'Git ukaz opozorilo: preveri spremembe',
                    );
                  },
                  child: Text(
                    pushAfter ? 'Commit & Push' : 'Commit',
                    style: TextStyle(
                      color: hud.accentSuccessGreen,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
    final bool showBigCenterOrb = widget.brain.messages.isEmpty;
    final screenH = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: hud.bgDeep,
      body: Stack(
        children: [
          // 1. Subtilni radialni sij ozadja
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.28),
                    radius: 1.05,
                    colors: [
                      hud.primaryPeriwinkle
                          .alphaPct(widget.isDarkMode ? 0.055 : 0.035),
                      hud.bgDeep.alphaPct(0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 2. Sredinska 3D krogla na začetnem zaslonu
          if (showBigCenterOrb)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 340),
                    curve: Curves.easeOutCubic,
                    offset: Offset(
                      widget.brain.isVsCodeWindowOpen ? -0.12 : 0.0,
                      -0.14,
                    ),
                    child: RepaintBoundary(
                      child: SizedBox(
                        width: 380,
                        height: 380,
                        child: ValueListenableBuilder<int>(
                          valueListenable: _orbFrameTick,
                          builder: (context, _, __) {
                            return CustomPaint(
                              painter: UltronWireframeOrbPainter(
                                shellAngleY: _shellAngleY,
                                ringAngleY: _ringAngleY,
                                beamDriftPhase: _beamDriftPhase,
                                pulseClock: _pulseClock,
                                subtleKeystrokeRipple: _keystrokeRipple,
                                params: _currentVisualParams,
                                isDarkMode: widget.isDarkMode,
                                customPrimaryColor: hud.primaryPeriwinkle,
                                customSecondaryColor: hud.secondaryVioletBloom,
                                glowMultiplier: hud.orbGlowMultiplier,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // 3. Glavna delovna postavitev (Top Bar + Središčni oder + Lebdeči Composer)
          Column(
            children: [
              _buildMinimalTopBar(hud),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Stack(
                        children: [
                          Column(
                            children: [
                              Expanded(
                                child: _buildCenterConversationStage(hud),
                              ),
                              _buildFloatingCommandComposer(hud, screenH),
                            ],
                          ),
                          if (_userScrolledUp &&
                              widget.brain.messages.isNotEmpty)
                            Positioned(
                              bottom: 150,
                              right: 28,
                              child: HudActionButton(
                                label: 'Na dno',
                                icon: Icons.keyboard_arrow_down_rounded,
                                compact: true,
                                isPrimaryAccent: true,
                                onTap: () {
                                  setState(() => _userScrolledUp = false);
                                  _smoothFollowBottom(force: true);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, anim) {
                        return SizeTransition(
                          axis: Axis.horizontal,
                          sizeFactor: anim,
                          child: FadeTransition(opacity: anim, child: child),
                        );
                      },
                      child: widget.brain.isVsCodeWindowOpen
                          ? VsCodeLiveSurgicalWindow(
                              key: const ValueKey('vscode_open'),
                              brain: widget.brain,
                              isDarkMode: widget.isDarkMode,
                            )
                          : const SizedBox.shrink(
                              key: ValueKey('vscode_closed')),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // 4. Kompaktna lebdeča predala zgoraj levo (PC Datoteke + Zgodovina)
          // Brez prisilnega raztezanja do dna zaslona!
          Positioned(
            top: 58,
            left: 14,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: screenH - 74),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FuturisticHoverFileStack(
                      brain: widget.brain,
                      isDarkMode: widget.isDarkMode,
                      onStatusToast: _showToast,
                    ),
                    const SizedBox(height: 8),
                    UltronChatHistorySidebar(
                      brain: widget.brain,
                      onToast: _showToast,
                      maxExpandedHeight: (screenH - 135).clamp(260.0, 440.0),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 5. Podrobno okno žive telemetrije
          if (_showTelemetryDetail)
            Positioned(
              top: 56,
              left: 368,
              child: UltronTelemetryDetailPopover(
                telemetry: widget.brain.telemetryService,
                activeModelFallback: widget.brain.activeLocalModel,
                onClose: () => setState(() => _showTelemetryDetail = false),
                onToast: _showToast,
              ),
            ),

          // 6. Studio za prilagoditev videza
          if (_showStudioCustomizer)
            Positioned(
              top: 56,
              right: 16,
              child: _buildStudioCustomizerPopover(hud),
            ),

          // 7. Obvestilo (Toast)
          if (_toastMessage != null)
            Positioned(
              top: 62,
              right: _showStudioCustomizer ? 356 : 20,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 180),
                builder: (context, val, child) => Opacity(
                  opacity: val,
                  child: Transform.translate(
                    offset: Offset(0, (1 - val) * -8),
                    child: child,
                  ),
                ),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: hud.bgPanel.alphaPct(0.96),
                    borderRadius: BorderRadius.circular(hud.cutRadius * 0.8),
                    border:
                        Border.all(color: hud.primaryPeriwinkle.alphaPct(0.6)),
                  ),
                  child: Text(
                    _toastMessage!,
                    style: TextStyle(fontSize: 12, color: hud.textPrimary),
                  ),
                ),
              ),
            ),

          // 8. Modalna okna (Modeli / Learn Vault / GitHub in Vtičniki)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _showConnectionsModal
                ? Container(
                    key: ValueKey('conn_modal_$_connectionsInitialTab'),
                    color: Colors.black.alphaPct(0.52),
                    padding: const EdgeInsets.all(24),
                    child: ConnectionsHudWindow(
                      brain: widget.brain,
                      initialTab: _connectionsInitialTab,
                      onToast: _showToast,
                      onClose: () {
                        setState(() => _showConnectionsModal = false);
                        _syncBackgroundOrbTicker();
                      },
                    ),
                  )
                : _showPluginsModal
                    ? Container(
                        key: const ValueKey('plug_modal'),
                        color: Colors.black.alphaPct(0.52),
                        padding: const EdgeInsets.all(24),
                        child: PluginsHudWindow(
                          brain: widget.brain,
                          onClose: () {
                            setState(() => _showPluginsModal = false);
                            _syncBackgroundOrbTicker();
                          },
                        ),
                      )
                    : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  //**************
  // Zgornja HUD vrstica z modelom, živo telemetrijo, projektom in Git kontrolami *
  //**************
  Widget _buildMinimalTopBar(UltronHudTheme hud) {
    final mem = widget.brain.memoryService;
    final models = widget.brain.discoveredModels;

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: hud.bgDeep.alphaPct(0.90),
        border: Border(
          bottom: BorderSide(color: hud.borderLine.alphaPct(0.65), width: 1.0),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GestureDetector(
                        onTap: () {
                          widget.brain.startNewChatSession();
                          _syncBackgroundOrbTicker();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 5),
                          decoration: BoxDecoration(
                            color: hud.primaryPeriwinkle.alphaPct(0.11),
                            borderRadius:
                                BorderRadius.circular(hud.cutRadius * 0.75),
                            border: Border.all(
                              color: hud.primaryPeriwinkle.alphaPct(0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: widget.brain.isOllamaOnline
                                      ? hud.accentSuccessGreen
                                      : hud.accentWarningAmber,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'ULTRON',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2.0,
                                  color: hud.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        height: 32,
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        decoration: BoxDecoration(
                          color: hud.bgPanel.alphaPct(0.88),
                          borderRadius:
                              BorderRadius.circular(hud.cutRadius * 0.8),
                          border:
                              Border.all(color: hud.borderLine.alphaPct(0.85)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: models.any((m) =>
                                    m.name == widget.brain.activeLocalModel)
                                ? widget.brain.activeLocalModel
                                : null,
                            hint: Text(
                              widget.brain.activeLocalModel,
                              style: TextStyle(
                                  fontSize: 12, color: hud.textPrimary),
                            ),
                            icon: Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(Icons.expand_more_rounded,
                                  size: 16, color: hud.textMuted),
                            ),
                            dropdownColor: hud.bgPanel,
                            borderRadius: BorderRadius.circular(hud.cutRadius),
                            style:
                                TextStyle(fontSize: 12, color: hud.textPrimary),
                            items: models.map((m) {
                              return DropdownMenuItem<String>(
                                value: m.name,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.memory_rounded,
                                      size: 13,
                                      color: m.isLiveInServer
                                          ? hud.primaryPeriwinkle
                                          : hud.textMuted,
                                    ),
                                    const SizedBox(width: 7),
                                    Text(m.name),
                                    if (m.sizeLabel.isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Text(
                                        m.sizeLabel,
                                        style: TextStyle(
                                            fontSize: 10.5,
                                            color: hud.textMuted),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (selected) {
                              if (selected != null) {
                                widget.brain.selectLocalOllamaModel(selected);
                                _showToast('Aktiven model: $selected');
                              }
                            },
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Ponovno skeniraj lokalne LLM modele',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.refresh_rounded,
                          size: 16,
                          color: widget.brain.isScanningModels
                              ? hud.primaryPeriwinkle
                              : hud.textMuted,
                        ),
                        onPressed: widget.brain.isScanningModels
                            ? null
                            : () async {
                                await widget.brain.scanAllLocalLlms();
                                _showToast(
                                  'Najdenih ${widget.brain.discoveredModels.length} lokalnih modelov',
                                );
                              },
                      ),
                      const SizedBox(width: 4),
                      UltronLiveTelemetryPill(
                        telemetry: widget.brain.telemetryService,
                        isExpanded: _showTelemetryDetail,
                        onTap: () => setState(() {
                          _showTelemetryDetail = !_showTelemetryDetail;
                          _showStudioCustomizer = false;
                        }),
                      ),
                      if (mem.liveTokensPerSecond > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${mem.liveTokensPerSecond.toStringAsFixed(1)} tok/s',
                          style:
                              TextStyle(fontSize: 10.8, color: hud.textMuted),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(width: 12),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      HudActionButton(
                        label: 'Nov klepet',
                        icon: Icons.add_circle_outline_rounded,
                        compact: true,
                        onTap: () {
                          widget.brain.startNewChatSession();
                          _syncBackgroundOrbTicker();
                          _showToast('Začet nov klepet');
                        },
                      ),
                      const SizedBox(width: 6),
                      _buildWorkspaceAndProjectPill(hud, mem),
                      const SizedBox(width: 6),
                      ListenableBuilder(
                        listenable: mem,
                        builder: (context, _) {
                          return HudActionButton(
                            label: mem.isLearningNow ? 'Učim se...' : 'Learn',
                            icon: Icons.psychology_alt,
                            compact: true,
                            isPrimaryAccent: mem.isLearningNow,
                            accentColor: hud.accentSuccessGreen,
                            badgeText: '${mem.learnedEntries.length}',
                            onTap: () => _openModalTab(1),
                          );
                        },
                      ),
                      const SizedBox(width: 6),
                      HudActionButton(
                        label: 'Modeli',
                        icon: Icons.hub_outlined,
                        compact: true,
                        onTap: () => _openModalTab(0),
                      ),
                      const SizedBox(width: 6),
                      HudActionButton(
                        label: widget.brain.isGithubConnected
                            ? '@${widget.brain.githubUsername}'
                            : 'GitHub',
                        icon: widget.brain.isGithubConnected
                            ? Icons.verified_user_outlined
                            : Icons.account_circle_outlined,
                        compact: true,
                        isPrimaryAccent: widget.brain.isGithubConnected,
                        accentColor: widget.brain.isGithubConnected
                            ? hud.accentSuccessGreen
                            : hud.primaryPeriwinkle,
                        onTap: () => _openModalTab(2),
                      ),
                      const SizedBox(width: 6),
                      HudActionButton(
                        label: 'Vtičniki',
                        icon: Icons.extension_outlined,
                        compact: true,
                        onTap: () {
                          setState(() {
                            _showPluginsModal = true;
                            _showConnectionsModal = false;
                            _showStudioCustomizer = false;
                            _showTelemetryDetail = false;
                          });
                          _syncBackgroundOrbTicker();
                        },
                      ),
                      const SizedBox(width: 6),
                      HudActionButton(
                        label: 'Koda',
                        icon: Icons.code_rounded,
                        compact: true,
                        isPrimaryAccent: widget.brain.isVsCodeWindowOpen,
                        onTap: widget.brain.toggleVsCodeWindow,
                      ),
                      const SizedBox(width: 6),
                      HudActionButton(
                        label: 'Prilagodi',
                        icon: Icons.tune_rounded,
                        compact: true,
                        isPrimaryAccent: _showStudioCustomizer,
                        onTap: () => setState(() {
                          _showStudioCustomizer = !_showStudioCustomizer;
                          _showTelemetryDetail = false;
                        }),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        tooltip:
                            widget.isDarkMode ? 'Svetli način' : 'Temni način',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          widget.isDarkMode
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          size: 17,
                          color: hud.textMuted,
                        ),
                        onPressed: widget.onToggleTheme,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Stalno vidna značka projektne mape (jasno pokaže, ali je LLM v projektu ali ne)
  Widget _buildWorkspaceAndProjectPill(
    UltronHudTheme hud,
    MemoryLearningUsageService mem,
  ) {
    if (!widget.brain.hasActiveProject) {
      return HudActionButton(
        label: 'Priklopi projekt',
        icon: Icons.create_new_folder_outlined,
        compact: true,
        onTap: _pickAndConnectProjectFolder,
      );
    }

    final meta = mem.getProjectMeta(widget.brain.activeProjectPath);
    final isDone = meta?.isCompleted ?? false;
    final projLabel = meta?.projectName ?? widget.brain.activeProjectName;
    final statusSuffix = meta != null
        ? (meta.hasDeadline
            ? ' · ${meta.deadlineSummaryLabel}'
            : ' · ${meta.statusLabel}')
        : '';

    return HudActionButton(
      label: '$projLabel$statusSuffix',
      icon: isDone
          ? Icons.check_circle_rounded
          : Icons.folder_special_rounded,
      compact: true,
      isPrimaryAccent: true,
      accentColor:
          isDone ? hud.accentSuccessGreen : hud.accentWarningAmber,
      onTap: () {
        if (meta != null) {
          _showProjectMetaDialog(meta);
        } else {
          _pickAndConnectProjectFolder();
        }
      },
    );
  }

  //**************
  // Začetni zaslon (ko je klepet prazen) + Osrednji pogovorni stolpec *
  //**************
  Widget _buildCenterConversationStage(UltronHudTheme hud) {
    if (widget.brain.messages.isEmpty) {
      final hasProj = widget.brain.hasActiveProject;
      final fileCount = widget.brain.workspaceService.indexedFiles.length;

      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(48, 220, 48, 12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ULTRON NEURAL STUDIO',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3.2,
                    color: hud.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  hasProj
                      ? 'Priklopljen projekt: ${widget.brain.activeProjectName} ($fileCount datotek)${widget.brain.localGitBranch.isNotEmpty ? " · git:${widget.brain.localGitBranch}" : ""}'
                      : 'Lokalni pogon: ${widget.brain.activeLocalModel} · Hitri način (brez priklopljene projektne mape)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.2,
                    color: hasProj ? hud.accentSuccessGreen : hud.textMuted,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    HudActionButton(
                      label: hasProj
                          ? 'Zamenjaj projektno mapo'
                          : 'Priklopi projektno mapo',
                      icon: Icons.folder_special_outlined,
                      isPrimaryAccent: !hasProj,
                      accentColor: hud.accentSuccessGreen,
                      onTap: _pickAndConnectProjectFolder,
                    ),
                    HudActionButton(
                      label: 'Analiziraj arhitekturo',
                      icon: Icons.architecture_rounded,
                      onTap: () => _submitPrompt(
                        hasProj
                            ? 'Preglej strukturo priklopljenega projekta in povzemi arhitekturo ter ključne module.'
                            : 'Kaj vse zmoreš pri analizi in pisanju kode v mojih projektih?',
                      ),
                    ),
                    HudActionButton(
                      label: 'Nauči se iz kode (/learn)',
                      icon: Icons.psychology_alt,
                      onTap: () => _submitPrompt('/learn'),
                    ),
                    HudActionButton(
                      label: 'GitHub & Repozitoriji',
                      icon: Icons.hub_outlined,
                      onTap: () => _openModalTab(2),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920),
        child: ListView.builder(
          controller: _chatScrollCtrl,
          padding: const EdgeInsets.fromLTRB(56, 20, 28, 12),
          itemCount: widget.brain.messages.length,
          itemBuilder: (context, idx) {
            final m = widget.brain.messages[idx];
            return UltronChatMessageCard(
              key: ValueKey(m.id),
              message: m,
              brain: widget.brain,
              onHeightGrew: _smoothFollowBottom,
              onToast: _showToast,
            );
          },
        ),
      ),
    );
  }

  //**************
  // Lebdeči "Command Composer" brez prečne črte čez celoten zaslon! *
  // Vključuje Drag-to-Resize, Zen način, @datoteke, /ukaze in projektno/Git vrstico *
  //**************
  Widget _buildFloatingCommandComposer(UltronHudTheme hud, double screenH) {
    final hasAttachments = widget.brain.pendingAttachments.isNotEmpty;
    final text = _promptCtrl.text;
    final lineCount = text.isEmpty ? 1 : '\n'.allMatches(text).length + 1;
    final approxTokens = (text.length / 4).ceil();

    final double? targetBoxHeight = _isZenModeInput
        ? (screenH * 0.44).clamp(240.0, 520.0)
        : _customComposerHeight;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(56, 2, 28, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Plavajoči meni za @datoteke in /ukaze
              if (_showMentionMenu || _showCommandMenu)
                _buildSmartAutocompleteMenu(hud),

              // Živi status med generiranjem
              if (widget.brain.isGenerating ||
                  widget.brain.liveAgentStatus.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6, left: 4, right: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: hud.primaryPeriwinkle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.brain.liveAgentStatus,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: hud.primaryPeriwinkle,
                          ),
                        ),
                      ),
                      if (widget.brain.isGenerating)
                        HudActionButton(
                          label: 'Prekini',
                          icon: Icons.stop_rounded,
                          compact: true,
                          accentColor: hud.accentErrorRed,
                          onTap: widget.brain.stopGeneration,
                        ),
                    ],
                  ),
                ),

              // Glavna lebdeča kartica ukaznega polja
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                decoration: BoxDecoration(
                  color: hud.bgPanel.alphaPct(_promptFocused ? 0.96 : 0.90),
                  borderRadius: BorderRadius.circular(hud.cutRadius + 3),
                  border: Border.all(
                    color: _promptFocused
                        ? hud.primaryPeriwinkle.alphaPct(0.72)
                        : hud.borderLine.alphaPct(0.85),
                    width: _promptFocused ? 1.3 : 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.alphaPct(0.28),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                    if (_promptFocused)
                      BoxShadow(
                        color: hud.primaryPeriwinkle.alphaPct(0.10),
                        blurRadius: 16,
                      ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1. Zgornja ročica za vlečenje višine (Drag-to-Resize) + Kontekstna/Git vrstica
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (details) {
                        setState(() {
                          _isZenModeInput = false;
                          final base = _customComposerHeight ?? 76.0;
                          _customComposerHeight = (base - details.delta.dy)
                              .clamp(56.0, screenH * 0.50);
                        });
                      },
                      onDoubleTap: () =>
                          setState(() => _customComposerHeight = null),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                        child: Column(
                          children: [
                            MouseRegion(
                              cursor: SystemMouseCursors.resizeUpDown,
                              child: Center(
                                child: Container(
                                  width: 34,
                                  height: 3.5,
                                  decoration: BoxDecoration(
                                    color: hud.borderLine.alphaPct(0.95),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            _buildComposerStatusAndGitStrip(
                              hud: hud,
                              lineCount: lineCount,
                              approxTokens: approxTokens,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 2. Pripete datoteke ali mape (če obstajajo)
                    if (hasAttachments)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children:
                                widget.brain.pendingAttachments.map((a) {
                              return Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: hud.bgInput.alphaPct(0.85),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color:
                                        hud.primaryPeriwinkle.alphaPct(0.40),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      a.isFolder
                                          ? Icons.folder_rounded
                                          : Icons.insert_drive_file_rounded,
                                      size: 12.5,
                                      color: hud.primaryPeriwinkle,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      a.name,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: hud.textPrimary),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      a.humanSize,
                                      style: TextStyle(
                                          fontSize: 9.5,
                                          color: hud.textMuted),
                                    ),
                                    const SizedBox(width: 5),
                                    InkWell(
                                      onTap: () => widget.brain
                                          .removeAttachment(a.path),
                                      child: Icon(Icons.close_rounded,
                                          size: 13, color: hud.textMuted),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),

                    // 3. Večvrstično vnosno polje
                    SizedBox(
                      height: targetBoxHeight,
                      child: Focus(
                        onKeyEvent: _handleComposerKeyEvent,
                        child: TextField(
                          controller: _promptCtrl,
                          focusNode: _promptFocusNode,
                          minLines: targetBoxHeight != null ? null : 1,
                          maxLines: targetBoxHeight != null ? null : 7,
                          expands: targetBoxHeight != null,
                          style: TextStyle(
                            fontSize: 13.6,
                            height: 1.48,
                            color: hud.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: widget.brain.hasActiveProject
                                ? 'Vprašaj ULTRON o projektu ${widget.brain.activeProjectName}, omeni @datoteko ali vtipkaj /ukaz...'
                                : 'Vprašaj ULTRON karkoli, pripni dokument ali vtipkaj / za hitre ukaze...',
                            hintStyle: TextStyle(
                                fontSize: 12.6, color: hud.textMuted),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 10),
                          ),
                        ),
                      ),
                    ),

                    // 4. Spodnja akcijska vrstica znotraj lebdeče kartice
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 2, 10, 8),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Pripni datoteko s PC-ja',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.attach_file_rounded,
                                size: 17, color: hud.primaryPeriwinkle),
                            onPressed: _pickAnyFiles,
                          ),
                          if (widget.brain.hasActiveProject)
                            IconButton(
                              tooltip: 'Omeni projektno datoteko (@)',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.alternate_email_rounded,
                                  size: 16.5, color: hud.textMuted),
                              onPressed: () {
                                final cur = _promptCtrl.text;
                                final next = cur.isEmpty || cur.endsWith(' ')
                                    ? '$cur@'
                                    : '$cur @';
                                _promptCtrl.value = TextEditingValue(
                                  text: next,
                                  selection: TextSelection.collapsed(
                                      offset: next.length),
                                );
                                _promptFocusNode.requestFocus();
                              },
                            ),
                          IconButton(
                            tooltip: 'Hitri ukazi (/)',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(Icons.terminal_rounded,
                                size: 16.5, color: hud.textMuted),
                            onPressed: () {
                              final cur = _promptCtrl.text;
                              final next = cur.isEmpty || cur.endsWith(' ')
                                  ? '$cur/'
                                  : '$cur /';
                              _promptCtrl.value = TextEditingValue(
                                text: next,
                                selection: TextSelection.collapsed(
                                    offset: next.length),
                              );
                              _promptFocusNode.requestFocus();
                            },
                          ),
                          IconButton(
                            tooltip: _isZenModeInput
                                ? 'Zapri razširjeni Zen način'
                                : 'Razširi vnosno polje (Zen način)',
                            visualDensity: VisualDensity.compact,
                            icon: Icon(
                              _isZenModeInput
                                  ? Icons.close_fullscreen_rounded
                                  : Icons.open_in_full_rounded,
                              size: 16,
                              color: _isZenModeInput
                                  ? hud.primaryPeriwinkle
                                  : hud.textMuted,
                            ),
                            onPressed: () => setState(
                                () => _isZenModeInput = !_isZenModeInput),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            borderRadius: BorderRadius.circular(5),
                            onTap: () => setState(
                                () => _ctrlEnterToSend = !_ctrlEnterToSend),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              child: Text(
                                _ctrlEnterToSend || _isZenModeInput
                                    ? 'Ctrl+Enter pošlje'
                                    : 'Enter pošlje',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: hud.textMuted.alphaPct(0.85),
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (text.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: Text(
                                '$lineCount vrst. · ~$approxTokens tok',
                                style: TextStyle(
                                    fontSize: 10.5, color: hud.textMuted),
                              ),
                            ),
                          HudActionButton(
                            label:
                                widget.brain.isGenerating ? 'Stop' : 'Pošlji',
                            icon: widget.brain.isGenerating
                                ? Icons.stop_rounded
                                : Icons.arrow_upward_rounded,
                            isPrimaryAccent: true,
                            accentColor: widget.brain.isGenerating
                                ? hud.accentErrorRed
                                : hud.primaryPeriwinkle,
                            onTap: widget.brain.isGenerating
                                ? widget.brain.stopGeneration
                                : _submitPrompt,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Kompaktna statusna vrstica v glavi Composerja (Aktivna mapa + Git Pull/Commit/Push)
  Widget _buildComposerStatusAndGitStrip({
    required UltronHudTheme hud,
    required int lineCount,
    required int approxTokens,
  }) {
    final b = widget.brain;
    final hasProj = b.hasActiveProject;
    final hasGit = b.localGitBranch.isNotEmpty;

    return Row(
      children: [
        // Status projektne mape
        InkWell(
          borderRadius: BorderRadius.circular(5),
          onTap: _pickAndConnectProjectFolder,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            decoration: BoxDecoration(
              color: hasProj
                  ? hud.accentSuccessGreen.alphaPct(0.13)
                  : hud.bgInput.alphaPct(0.65),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: hasProj
                    ? hud.accentSuccessGreen.alphaPct(0.45)
                    : hud.borderLine.alphaPct(0.75),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  hasProj
                      ? Icons.folder_special_rounded
                      : Icons.folder_off_outlined,
                  size: 12,
                  color:
                      hasProj ? hud.accentSuccessGreen : hud.textMuted,
                ),
                const SizedBox(width: 5),
                Text(
                  hasProj
                      ? 'Projekt: ${b.activeProjectName} (${b.workspaceService.indexedFiles.length} dat.)'
                      : 'Brez projekta (klikni za priklop)',
                  style: TextStyle(
                    fontSize: 10.3,
                    fontWeight: FontWeight.w600,
                    color: hasProj ? hud.textPrimary : hud.textMuted,
                  ),
                ),
                if (hasProj) ...[
                  const SizedBox(width: 5),
                  GestureDetector(
                    onTap: () {
                      b.clearActiveProject();
                      _showToast('Projekt odklopljen');
                    },
                    child: Icon(Icons.close_rounded,
                        size: 12, color: hud.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Živ Git status in hitri ukazi (če je trenutna mapa ali projekt Git repo)
        if (hasGit) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            decoration: BoxDecoration(
              color: hud.bgInput.alphaPct(0.65),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: hud.borderLine.alphaPct(0.75)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.call_split_rounded,
                    size: 12, color: hud.primaryPeriwinkle),
                const SizedBox(width: 4),
                Text(
                  '${b.localGitBranch}${b.localGitChangedCount > 0 ? " (${b.localGitChangedCount}*)" : ""}',
                  style: TextStyle(
                    fontSize: 10.3,
                    fontWeight: FontWeight.w600,
                    color: b.localGitChangedCount > 0
                        ? hud.accentWarningAmber
                        : hud.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                _tinyGitBtn(
                  label: 'Pull',
                  hud: hud,
                  onTap: b.isSyncingLocalGit
                      ? null
                      : () async {
                          final ok = await b.pullCurrentGitWorkspace();
                          _showToast(
                              ok ? 'Git Pull uspešen' : 'Git Pull opozorilo');
                        },
                ),
                const SizedBox(width: 4),
                _tinyGitBtn(
                  label: 'Commit',
                  hud: hud,
                  onTap: b.isSyncingLocalGit
                      ? null
                      : _showQuickGitCommitDialog,
                ),
                const SizedBox(width: 4),
                _tinyGitBtn(
                  label: 'Push',
                  hud: hud,
                  onTap: b.isSyncingLocalGit
                      ? null
                      : () async {
                          final ok = await b.pushCurrentGitWorkspace();
                          _showToast(
                              ok ? 'Git Push uspešen' : 'Git Push ni uspel');
                        },
                ),
              ],
            ),
          ),
        ],

        const Spacer(),
      ],
    );
  }

  Widget _tinyGitBtn({
    required String label,
    required UltronHudTheme hud,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 9.8,
            fontWeight: FontWeight.w700,
            color: onTap != null ? hud.primaryPeriwinkle : hud.textMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildSmartAutocompleteMenu(UltronHudTheme hud) {
    Widget? menuBody;

    if (_showMentionMenu) {
      final q = _mentionQuery.toLowerCase();
      final files = widget.brain.workspaceService.indexedFiles
          .where((f) =>
              f.relativePath.toLowerCase().contains(q) ||
              f.name.toLowerCase().contains(q))
          .take(6)
          .toList();

      if (files.isEmpty) return const SizedBox.shrink();

      menuBody = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: files.map((f) {
          return InkWell(
            onTap: () => _insertMentionOrCommand(
              '@${f.relativePath}',
              filePathToAttach: f.fullPath,
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.insert_drive_file_outlined,
                      size: 14.5, color: hud.primaryPeriwinkle),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      f.relativePath,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 12.2, color: hud.textPrimary),
                    ),
                  ),
                  Text(
                    f.humanSize,
                    style: TextStyle(fontSize: 10.5, color: hud.textMuted),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      );
    } else if (_showCommandMenu) {
      final q = _commandQuery.toLowerCase();
      final cmds = _slashCommands
          .where((c) => c['label']!.toLowerCase().contains(q))
          .toList();

      if (cmds.isEmpty) return const SizedBox.shrink();

      menuBody = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: cmds.map((c) {
          return InkWell(
            onTap: () => _insertMentionOrCommand(c['cmd']!.trimRight()),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7.5),
              child: Row(
                children: [
                  Icon(Icons.terminal_rounded,
                      size: 14.5, color: hud.accentSuccessGreen),
                  const SizedBox(width: 8),
                  Text(
                    c['label']!,
                    style: TextStyle(
                      fontSize: 12.2,
                      fontWeight: FontWeight.w700,
                      color: hud.accentSuccessGreen,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      c['desc']!,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 11.2, color: hud.textMuted),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      );
    }

    if (menuBody == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: hud.bgPanel.alphaPct(0.98),
        borderRadius: BorderRadius.circular(hud.cutRadius),
        border: Border.all(color: hud.primaryPeriwinkle.alphaPct(0.50)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.alphaPct(0.28),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: menuBody,
    );
  }

  Widget _buildStudioCustomizerPopover(UltronHudTheme hud) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      builder: (context, val, child) => Opacity(
        opacity: val,
        child: Transform.translate(
          offset: Offset(0, (1.0 - val) * -10.0),
          child: child,
        ),
      ),
      child: SizedBox(
        width: 330,
        child: HudBracketPanel(
          padding: const EdgeInsets.all(14),
          fillColor: hud.bgPanel.alphaPct(0.97),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.palette_outlined,
                      size: 15, color: hud.primaryPeriwinkle),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      'ULTRON Studio & Izpis klepeta',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: hud.textPrimary,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _showStudioCustomizer = false),
                    child: Icon(Icons.close_rounded,
                        size: 16, color: hud.textMuted),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Text(
                'Način izpisovanja odgovorov:',
                style: TextStyle(fontSize: 11, color: hud.textMuted),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: HudActionButton(
                      label: 'Smooth Live',
                      compact: true,
                      isPrimaryAccent: widget.brain.typingMode ==
                          UltronTypingMode.adaptiveSmooth,
                      onTap: () => widget.brain
                          .setTypingMode(UltronTypingMode.adaptiveSmooth),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: HudActionButton(
                      label: 'Wait & Type',
                      compact: true,
                      isPrimaryAccent: widget.brain.typingMode ==
                          UltronTypingMode.waitFullThenType,
                      onTap: () => widget.brain
                          .setTypingMode(UltronTypingMode.waitFullThenType),
                    ),
                  ),
                  const SizedBox(width: 5),
                  HudActionButton(
                    label: 'Instant',
                    compact: true,
                    isPrimaryAccent:
                        widget.brain.typingMode == UltronTypingMode.instant,
                    onTap: () =>
                        widget.brain.setTypingMode(UltronTypingMode.instant),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Hitrost tipkanja',
                      style: TextStyle(fontSize: 11, color: hud.textMuted)),
                  Text(
                    '${widget.brain.typingSpeedMultiplier.toStringAsFixed(1)}x',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: hud.textPrimary,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(trackHeight: 2.5),
                child: Slider(
                  value: widget.brain.typingSpeedMultiplier,
                  min: 0.5,
                  max: 3.0,
                  divisions: 25,
                  onChanged: (v) =>
                      widget.brain.updateAppearanceSettings(typingSpeed: v),
                ),
              ),
              Divider(height: 10, color: hud.borderLine.alphaPct(0.75)),
              const SizedBox(height: 4),
              Text(
                'Barvno jedro ULTRON:',
                style: TextStyle(fontSize: 11, color: hud.textMuted),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(
                  UltronAccentPreset.presets.length,
                  (idx) {
                    final preset = UltronAccentPreset.presets[idx];
                    final selected = widget.brain.accentPresetIndex == idx;
                    final swatchColor = widget.isDarkMode
                        ? preset.darkPrimary
                        : preset.lightPrimary;

                    return Tooltip(
                      message: preset.name,
                      child: GestureDetector(
                        onTap: () => widget.brain
                            .updateAppearanceSettings(accentIndex: idx),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: selected
                                ? swatchColor.alphaPct(0.20)
                                : hud.bgInput.alphaPct(0.65),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: selected
                                  ? swatchColor
                                  : hud.borderLine.alphaPct(0.8),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: swatchColor,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                preset.name.split(' ').last,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: hud.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Zaobljenost robov',
                      style: TextStyle(fontSize: 11, color: hud.textMuted)),
                  Text(
                    '${widget.brain.customCutRadius.toStringAsFixed(1)} px',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: hud.textPrimary,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(trackHeight: 2.5),
                child: Slider(
                  value: widget.brain.customCutRadius,
                  min: 4.0,
                  max: 16.0,
                  divisions: 12,
                  onChanged: (v) =>
                      widget.brain.updateAppearanceSettings(cutRadius: v),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectMetaDialog extends StatefulWidget {
  final UltronProjectMeta meta;
  final UltronBrainRouter brain;

  const _ProjectMetaDialog({required this.meta, required this.brain});

  @override
  State<_ProjectMetaDialog> createState() => _ProjectMetaDialogState();
}

class _ProjectMetaDialogState extends State<_ProjectMetaDialog> {
  late final TextEditingController _nameCtrl;
  late bool _isCompleted;
  DateTime? _deadline;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.meta.projectName);
    _isCompleted = widget.meta.isCompleted;
    _deadline = widget.meta.deadlineDate;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;

    return AlertDialog(
      backgroundColor: hud.bgPanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(hud.cutRadius),
        side: BorderSide(color: hud.primaryPeriwinkle.alphaPct(0.5)),
      ),
      title: Text(
        'Projektni Sledilnik',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: hud.textPrimary,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ime projekta:',
                style: TextStyle(fontSize: 12, color: hud.textMuted)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameCtrl,
              style: TextStyle(fontSize: 13, color: hud.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: hud.bgInput,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: hud.borderLine),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Status projekta:',
                    style: TextStyle(fontSize: 12, color: hud.textMuted)),
                Switch(
                  value: _isCompleted,
                  activeTrackColor: hud.accentSuccessGreen,
                  activeThumbColor: Colors.white,
                  onChanged: (val) => setState(() => _isCompleted = val),
                ),
              ],
            ),
            Text(
              _isCompleted ? 'Zaključeno' : 'V delu',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _isCompleted
                    ? hud.accentSuccessGreen
                    : hud.accentWarningAmber,
              ),
            ),
            const SizedBox(height: 16),
            Text('Rok oddaje (Deadline):',
                style: TextStyle(fontSize: 12, color: hud.textMuted)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _deadline == null
                        ? 'Brez roka'
                        : '${_deadline!.day}. ${_deadline!.month}. ${_deadline!.year}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _deadline == null
                          ? hud.textMuted
                          : hud.primaryPeriwinkle,
                    ),
                  ),
                ),
                HudActionButton(
                  label: _deadline == null ? 'Nastavi' : 'Spremeni',
                  compact: true,
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _deadline ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (d != null) {
                      setState(() => _deadline = d);
                    }
                  },
                ),
                if (_deadline != null) ...[
                  const SizedBox(width: 6),
                  HudActionButton(
                    label: 'Počisti',
                    compact: true,
                    accentColor: hud.accentErrorRed,
                    onTap: () => setState(() => _deadline = null),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.brain.clearActiveProject();
            Navigator.pop(context);
          },
          child: Text('Odklopi projekt',
              style: TextStyle(color: hud.accentErrorRed)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Prekliči', style: TextStyle(color: hud.textMuted)),
        ),
        TextButton(
          onPressed: () {
            widget.brain.memoryService.updateProjectMeta(
              projectPath: widget.meta.projectPath,
              projectName: _nameCtrl.text,
              isCompleted: _isCompleted,
              deadlineIso: _deadline?.toIso8601String() ?? '',
            );
            Navigator.pop(context);
          },
          child: Text(
            'Shrani',
            style: TextStyle(
              color: hud.primaryPeriwinkle,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}