import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../backend/ultron_brain_router.dart';
import 'connections_hud_window.dart';
import 'plugins_hud_window.dart';
import 'sleek_file_manager.dart';
import 'ultron_bubble_painter.dart';
import 'ultron_chat_renderer.dart';
import 'ultron_hud_theme.dart';
import 'ultron_telemetry_hud.dart';
import 'vscode_live_window.dart';

//**************
// Glavna nadzorna plošča ULTRON: *
// - Živi merilnik CPU, GPU, RAM in VRAM porabe (izključno ULTRON + Lokalni LLM) *
// - Samodejna hibernacija velike 3D krogle med pogovorom (preseli se v oblaček klepeta) *
// - 1-klik dostop do GitHub prijavnega okna, prilagoditvenega Studia in 100% projektnega branja *
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
  final Stopwatch _scrollThrottle = Stopwatch()..start();

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
      }
    });
    _chatScrollCtrl.addListener(_onScrollPositionChanged);

    // Velika krogla teče SAMO na začetnem praznem zaslonu; med klepetom miruje (0% GPU)
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

  Future<void> _pickProjectDirectory() async {
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
        'Aktivni projekt: ${widget.brain.activeProjectName} (${widget.brain.workspaceService.indexedFiles.length} datotek)',
      );
    } catch (_) {
      _showToast(
          'Za izbiro projekta klikni zeleno ikono tarče v levem PC File Managerju');
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
    widget.brain.executeUltronPrompt(text);
    _syncBackgroundOrbTicker();
    _smoothFollowBottom(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
    final bool showBigCenterOrb = widget.brain.messages.isEmpty;

    return Scaffold(
      backgroundColor: hud.bgDeep,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.25),
                    radius: 1.05,
                    colors: [
                      hud.primaryPeriwinkle
                          .alphaPct(widget.isDarkMode ? 0.05 : 0.035),
                      hud.bgDeep.alphaPct(0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 1. Sredinska 3D krogla: aktivna SAMO na domačem zaslonu, med klepetom ugasnjena
          if (showBigCenterOrb)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 340),
                    curve: Curves.easeOutCubic,
                    offset: Offset(
                      widget.brain.isVsCodeWindowOpen ? -0.14 : 0.0,
                      -0.06,
                    ),
                    child: RepaintBoundary(
                      child: SizedBox(
                        width: 410,
                        height: 410,
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

          // 2. Glavna delovna postavitev
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
                                  child: _buildCenterConversationStage(hud)),
                              _buildBottomPromptDeck(hud),
                            ],
                          ),
                          if (_userScrolledUp &&
                              widget.brain.messages.isNotEmpty)
                            Positioned(
                              bottom: 122,
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

          // 3. Plavajoči PC File Manager zgoraj levo
          Positioned(
            top: 58,
            left: 14,
            child: FuturisticHoverFileStack(
              brain: widget.brain,
              isDarkMode: widget.isDarkMode,
              onStatusToast: _showToast,
            ),
          ),

          // 4. Razširjeno okno žive telemetrije (Samo ULTRON + Lokalni LLM)
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

          // 5. Plavajoči Studio za prilagajanje ULTRON videza in načina izpisa
          if (_showStudioCustomizer)
            Positioned(
              top: 56,
              right: 16,
              child: _buildStudioCustomizerPopover(hud),
            ),

          // 6. Minimalistično obvestilo (Toast)
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

          // 7. Modalna okna (Modeli/Vault/GitHub in Vtičniki)
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

  Widget _buildMinimalTopBar(UltronHudTheme hud) {
    final mem = widget.brain.memoryService;
    final models = widget.brain.discoveredModels;

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: hud.bgDeep.alphaPct(0.90),
        border: Border(
          bottom: BorderSide(color: hud.borderLine.alphaPct(0.70), width: 1.0),
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
                      // Identiteta ULTRON
                      Container(
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
                      const SizedBox(width: 10),

                      // Izbirnik lokalnih LLM modelov
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
                        tooltip:
                            'Ponovno skeniraj računalnik za lokalne LLM modele',
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
                                    'Najdenih ${widget.brain.discoveredModels.length} lokalnih modelov');
                              },
                      ),
                      const SizedBox(width: 4),

                      // Živa CPU / GPU / RAM / VRAM telemetrija (samo ULTRON + LLM)
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
                      Tooltip(
                        message:
                            'Način izpisa klepeta (Smooth Live / Wait & Type / Instant)',
                        child: HudActionButton(
                          label: widget.brain.typingModeLabel,
                          icon: widget.brain.typingMode ==
                                  UltronTypingMode.waitFullThenType
                              ? Icons.hourglass_top_rounded
                              : (widget.brain.typingMode ==
                                      UltronTypingMode.instant
                                  ? Icons.flash_on_rounded
                                  : Icons.bolt_rounded),
                          compact: true,
                          isPrimaryAccent: widget.brain.typingMode ==
                              UltronTypingMode.waitFullThenType,
                          onTap: () {
                            widget.brain.cycleTypingMode();
                            _showToast(
                                'Način izpisa: ${widget.brain.typingModeLabel}');
                          },
                        ),
                      ),
                      const SizedBox(width: 6),

                      ListenableBuilder(
                        listenable: mem,
                        builder: (context, _) {
                          return HudActionButton(
                            label: mem.isLearningNow ? 'Learning...' : 'Learn',
                            icon: Icons.psychology_alt,
                            compact: true,
                            isPrimaryAccent: mem.isLearningNow,
                            accentColor: hud.accentSuccessGreen,
                            badgeText: '${mem.learnedEntries.length}',
                            onTap: mem.isLearningNow
                                ? null
                                : () async {
                                    _showToast('ULTRON analizira vzorce...');
                                    final count =
                                        await widget.brain.triggerLearnPass();
                                    _showToast(
                                      count > 0
                                          ? 'ULTRON se je naučil $count novih vzorcev'
                                          : 'Baza znanja posodobljena (${mem.learnedEntries.length} pravil)',
                                    );
                                  },
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

                      // Neposreden 1-klik gumb za novo GitHub prijavno okno
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

                      if (widget.brain.messages.isNotEmpty)
                        IconButton(
                          tooltip: 'Počisti trenutni pogovor',
                          visualDensity: VisualDensity.compact,
                          icon: Icon(Icons.delete_outline_rounded,
                              size: 17, color: hud.textMuted),
                          onPressed: () {
                            widget.brain.clearConversation();
                            _syncBackgroundOrbTicker();
                          },
                        ),

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
                        color: hud.textPrimary),
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
                  Text('${widget.brain.customCutRadius.round()} px',
                      style: TextStyle(fontSize: 11, color: hud.textPrimary)),
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
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Sij 3D nevronske krogle',
                      style: TextStyle(fontSize: 11, color: hud.textMuted)),
                  Text(
                    '${(widget.brain.orbGlowMultiplier * 100).round()}%',
                    style: TextStyle(fontSize: 11, color: hud.textPrimary),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(trackHeight: 2.5),
                child: Slider(
                  value: widget.brain.orbGlowMultiplier,
                  min: 0.4,
                  max: 1.8,
                  divisions: 14,
                  onChanged: (v) =>
                      widget.brain.updateAppearanceSettings(orbGlow: v),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCenterConversationStage(UltronHudTheme hud) {
    if (widget.brain.messages.isEmpty) {
      final hasProj = widget.brain.hasActiveProject;
      final fileCount = widget.brain.workspaceService.indexedFiles.length;

      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 235, left: 24, right: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IgnorePointer(
                child: Column(
                  children: [
                    Text(
                      'ULTRON · ${widget.brain.activeLocalModel}',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: hud.textPrimary.alphaPct(0.90),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      hasProj
                          ? 'Projekt "${widget.brain.activeProjectName}" aktiven ($fileCount datotek pripravljenih)'
                          : 'Hitri način pripravljen (brez odprte projektne mape · minimalna poraba RAM/VRAM)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: hud.textMuted.alphaPct(0.75),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  HudActionButton(
                    label: hasProj
                        ? 'Zamenjaj projektno mapo'
                        : 'Odpri projektno mapo',
                    icon: Icons.folder_open_rounded,
                    compact: true,
                    isPrimaryAccent: !hasProj,
                    accentColor: hud.accentSuccessGreen,
                    onTap: _pickProjectDirectory,
                  ),
                  HudActionButton(
                    label: widget.brain.isGithubConnected
                        ? 'Odpri GitHub repozitorije'
                        : 'Prijava v GitHub',
                    icon: Icons.account_circle_outlined,
                    compact: true,
                    onTap: () => _openModalTab(2),
                  ),
                  if (hasProj) ...[
                    HudActionButton(
                      label: 'Analiziraj projekt',
                      icon: Icons.layers_outlined,
                      compact: true,
                      onTap: () => _submitPrompt(
                        'Preglej strukturo in ključne datoteke aktivnega projekta "${widget.brain.activeProjectName}" ter podaj kratek inženirski povzetek.',
                      ),
                    ),
                    HudActionButton(
                      label: 'Poišči izboljšave',
                      icon: Icons.auto_fix_high_rounded,
                      compact: true,
                      onTap: () => _submitPrompt(
                        'Preglej izvorno kodo aktivnega projekta in izpostavi morebitne napake ali predloge za optimizacijo.',
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: ListView.builder(
          controller: _chatScrollCtrl,
          padding: const EdgeInsets.fromLTRB(30, 56, 30, 18),
          itemCount: widget.brain.messages.length,
          itemBuilder: (context, index) {
            final msg = widget.brain.messages[index];
            return UltronChatMessageCard(
              key: ValueKey(msg.id),
              message: msg,
              brain: widget.brain,
              onHeightGrew: _smoothFollowBottom,
              onToast: _showToast,
            );
          },
        ),
      ),
    );
  }

  Widget _buildBottomPromptDeck(UltronHudTheme hud) {
    final attachments = widget.brain.pendingAttachments;
    final ws = widget.brain.workspaceService;
    final hasProj = widget.brain.hasActiveProject;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color: hasProj
                            ? hud.accentSuccessGreen.alphaPct(0.13)
                            : hud.bgPanel.alphaPct(0.75),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: hasProj
                              ? hud.accentSuccessGreen.alphaPct(0.50)
                              : hud.borderLine.alphaPct(0.8),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasProj
                                ? Icons.folder_special_rounded
                                : Icons.bolt_rounded,
                            size: 13.5,
                            color: hasProj
                                ? hud.accentSuccessGreen
                                : hud.primaryPeriwinkle,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            hasProj
                                ? 'Projekt: ${widget.brain.activeProjectName} (${ws.indexedFiles.length} datotek)'
                                : 'Brez projekta (Hitri klepet · varčen RAM)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: hasProj ? hud.textPrimary : hud.textMuted,
                            ),
                          ),
                          if (hasProj) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message:
                                  'Odklopi projektno mapo in preklopi v lahki način',
                              child: GestureDetector(
                                onTap: () {
                                  widget.brain.clearActiveProject();
                                  _showToast(
                                      'Projekt odklopljen (Hitri način)');
                                },
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 13.5,
                                  color: hud.textMuted,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Tooltip(
                      message:
                          'Izberi in poveži projektno mapo za 100% LLM branje in pisanje',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: _pickProjectDirectory,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: hud.bgPanel.alphaPct(0.78),
                            borderRadius: BorderRadius.circular(6),
                            border:
                                Border.all(color: hud.borderLine.alphaPct(0.8)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.drive_folder_upload_rounded,
                                  size: 13, color: hud.primaryPeriwinkle),
                              const SizedBox(width: 4),
                              Text(
                                hasProj ? 'Zamenjaj mapo' : 'Odpri projekt',
                                style: TextStyle(
                                    fontSize: 10.8, color: hud.textMuted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (hasProj) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: widget.brain.autoApplyProjectWrites
                            ? 'Samodejno ustvarjanje datotek/map je VKLOPLJENO'
                            : 'Varni način: vsak zapis potrdiš z 1 klikom',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () => widget.brain.toggleAutoApplyProjectWrites(
                            !widget.brain.autoApplyProjectWrites,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: widget.brain.autoApplyProjectWrites
                                  ? hud.primaryPeriwinkle.alphaPct(0.14)
                                  : hud.bgPanel.alphaPct(0.75),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: widget.brain.autoApplyProjectWrites
                                    ? hud.primaryPeriwinkle.alphaPct(0.45)
                                    : hud.borderLine.alphaPct(0.8),
                              ),
                            ),
                            child: Text(
                              widget.brain.autoApplyProjectWrites
                                  ? 'Auto-Write: ON'
                                  : 'Auto-Write: Potrdi',
                              style: TextStyle(
                                fontSize: 10.8,
                                color: widget.brain.autoApplyProjectWrites
                                    ? hud.primaryPeriwinkle
                                    : hud.textMuted,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const Spacer(),
                    if (widget.brain.liveAgentStatus.isNotEmpty)
                      Flexible(
                        child: Text(
                          widget.brain.liveAgentStatus,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: hud.primaryPeriwinkle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: attachments.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: attachments.map((att) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 5),
                              decoration: BoxDecoration(
                                color: hud.bgPanel.alphaPct(0.92),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: hud.primaryPeriwinkle.alphaPct(0.50),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    att.isFolder
                                        ? Icons.folder_copy_outlined
                                        : Icons.insert_drive_file_outlined,
                                    size: 13,
                                    color: hud.primaryPeriwinkle,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    '${att.name} (${att.kindLabel} · ${att.humanSize})',
                                    style: TextStyle(
                                      fontSize: 11.2,
                                      color: hud.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  GestureDetector(
                                    onTap: () =>
                                        widget.brain.removeAttachment(att.path),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 14,
                                      color: hud.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: hud.bgPanel.alphaPct(0.92),
                  borderRadius: BorderRadius.circular(hud.cutRadius + 1),
                  border: Border.all(
                    color: _promptFocused
                        ? hud.primaryPeriwinkle.alphaPct(0.68)
                        : hud.borderLine.alphaPct(0.90),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Tooltip(
                      message:
                          'Pripni datoteke vseh vrst (.docx, .pdf, koda, slike, .zip...)',
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.add_rounded,
                          size: 20,
                          color: hud.primaryPeriwinkle,
                        ),
                        onPressed: _pickAnyFiles,
                      ),
                    ),
                    Tooltip(
                      message:
                          'Odpri projektno mapo za celotno branje in pisanje',
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          Icons.folder_open_rounded,
                          size: 18,
                          color: hasProj
                              ? hud.accentSuccessGreen
                              : hud.textMuted,
                        ),
                        onPressed: _pickProjectDirectory,
                      ),
                    ),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 140),
                        child: TextField(
                          controller: _promptCtrl,
                          focusNode: _promptFocusNode,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _submitPrompt(),
                          onChanged: (_) {
                            if (widget.brain.messages.isEmpty) {
                              _keystrokeRipple =
                                  (_keystrokeRipple + 0.35).clamp(0.0, 1.0);
                              widget.brain.notifyUserTyping();
                            }
                          },
                          style: TextStyle(
                            fontSize: 13.2,
                            color: hud.textPrimary,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 9),
                            hintText: hasProj
                                ? 'Ukaži ULTRON-u (${widget.brain.activeLocalModel}) nad projektom "${widget.brain.activeProjectName}"...'
                                : 'Piši ULTRON-u (${widget.brain.activeLocalModel}) ali odpri projektno mapo...',
                            hintStyle: TextStyle(
                              fontSize: 12.6,
                              color: hud.textMuted.alphaPct(0.75),
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: widget.brain.isGenerating ? 'Ustavi' : 'Pošlji',
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        widget.brain.isGenerating
                            ? Icons.stop_rounded
                            : Icons.send_rounded,
                        size: 19,
                        color: widget.brain.isGenerating
                            ? hud.accentErrorRed
                            : hud.primaryPeriwinkle,
                      ),
                      onPressed: widget.brain.isGenerating
                          ? widget.brain.stopGeneration
                          : () => _submitPrompt(),
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
}