import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../backend/ultron_brain_router.dart';
import 'connections_hud_window.dart';
import 'plugins_hud_window.dart';
import 'sleek_file_manager.dart';
import 'ultron_bubble_painter.dart';
import 'ultron_hud_theme.dart';
import 'vscode_live_window.dart';

//**********************************************************************
// ULTRON MAIN CYBER-BLUE HUD DASHBOARD                                *
// - Orb shrinks smoothly to top-center when chatting                  *
// - Ultron writes responses in the center as pure floating text       *
//   (no borders, no backgrounds) with a snappy streaming cursor       *
// - Bottom-left displays 100% live tok/s, CPU %, GPU %, VRAM & RAM    *
//**********************************************************************

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
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  double _shellAngleY = 0.0;
  double _ringAngleY = 0.0;
  double _beamDriftPhase = 0.0;
  double _pulseClock = 0.0;

  OrbState _lastTargetState = OrbState.standby;
  OrbVisualParams _fromParams = OrbVisualParams.forState(OrbState.standby);
  OrbVisualParams _currentParams = OrbVisualParams.forState(OrbState.standby);
  double _stateTransitionT = 1.0;

  final TextEditingController _promptController = TextEditingController();
  final FocusNode _promptFocusNode = FocusNode();
  final ScrollController _centerTextScrollController = ScrollController();

  bool _showConnectionsModal = false;
  bool _showPluginsModal = false;
  bool _showHistoryModal = false;

  @override
  void initState() {
    super.initState();
    _promptFocusNode.addListener(() {
      widget.brain.setInputFocus(_promptFocusNode.hasFocus);
    });

    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
      _lastElapsed = elapsed;
      if (dt <= 0 || dt > 0.5) return;

      final targetState = widget.brain.orbState;
      if (targetState != _lastTargetState) {
        _fromParams = _currentParams;
        _lastTargetState = targetState;
        _stateTransitionT = 0.0;
      }
      if (_stateTransitionT < 1.0) {
        _stateTransitionT = (_stateTransitionT + dt / 0.22).clamp(0.0, 1.0);
        final eased = Curves.easeOutCubic.transform(_stateTransitionT);
        _currentParams = OrbVisualParams.lerp(
          _fromParams,
          OrbVisualParams.forState(_lastTargetState),
          eased,
        );
      }

      _shellAngleY += dt * rotationSpeed * _currentParams.shellSpinMultiplier;
      _ringAngleY +=
          dt * (rotationSpeed * 1.35) * _currentParams.ringDriftMultiplier;
      _beamDriftPhase += dt * 0.75;
      _pulseClock += dt;
      widget.brain.decayKeystrokeRipple(dt);
      setState(() {});
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _promptController.dispose();
    _promptFocusNode.dispose();
    _centerTextScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;

    return ListenableBuilder(
      listenable: widget.brain,
      builder: (context, _) {
        final brain = widget.brain;

        return Scaffold(
          backgroundColor: hud.bgDeep,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 1050;
              final editorWidth =
                  isNarrow ? constraints.maxWidth - 28 : 540.0;

              return Column(
                children: [
                  _buildModernBlueHeader(hud, brain),
                  Expanded(
                    child: Stack(
                      children: [
                        // 1. CENTER STAGE: SHRINKING TOP-CENTER ORB + BORDERLESS FLOATING TEXT
                        Positioned.fill(
                          child: AnimatedPadding(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            padding: EdgeInsets.only(
                              right: (!isNarrow && brain.isVsCodeWindowOpen)
                                  ? editorWidth + 16
                                  : 0,
                            ),
                            child: _buildCenterOrbAndBorderlessTextStage(
                              hud,
                              brain,
                            ),
                          ),
                        ),

                        // 2. BOTTOM-LEFT: LIVE HARDWARE & RESPONSE SPEED TELEMETRY
                        Positioned(
                          left: 14,
                          bottom: 14,
                          child: _buildLiveHardwareTelemetryPanel(hud, brain),
                        ),

                        // 3. TOP-LEFT: HOVER-STACK FILE MANAGER
                        Positioned(
                          left: 14,
                          top: 14,
                          child: FuturisticHoverFileStack(
                            brain: brain,
                            isDarkMode: widget.isDarkMode,
                          ),
                        ),

                        // 4. RIGHT: LIVE VS CODE WINDOW (OPENS AUTOMATICALLY WHEN ULTRON CODES)
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          top: 14,
                          bottom: 14,
                          right: brain.isVsCodeWindowOpen
                              ? 14
                              : -(editorWidth + 40),
                          width: editorWidth,
                          child: VsCodeLiveSurgicalWindow(
                            brain: brain,
                            isDarkMode: widget.isDarkMode,
                          ),
                        ),

                        // 5. MINIMAL CHAT HISTORY ARCHIVE OVERLAY
                        if (_showHistoryModal)
                          Center(
                            child: _buildChatHistoryModal(hud, brain),
                          ),

                        // 6. CONNECTIONS & GIT MODAL
                        if (_showConnectionsModal)
                          Center(
                            child: ConnectionsHudWindow(
                              brain: brain,
                              onClose: () => setState(
                                () => _showConnectionsModal = false,
                              ),
                            ),
                          ),

                        // 7. DECLARATIVE PLUGINS MODAL
                        if (_showPluginsModal)
                          Center(
                            child: PluginsHudWindow(
                              brain: brain,
                              onClose: () => setState(
                                () => _showPluginsModal = false,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  //********************************************************************
  // TOP HEADER BAR                                                    *
  //********************************************************************
  Widget _buildModernBlueHeader(UltronHudTheme hud, UltronBrainRouter brain) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: hud.bgPanel,
        border: Border(bottom: BorderSide(color: hud.borderLine)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: brain.isOllamaOnline
                      ? hud.primaryPeriwinkle
                      : hud.accentErrorRed,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'ULTRON // NEURAL CONSCIOUSNESS',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.4,
                  color: hud.textPrimary,
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: ShapeDecoration(
                  color: hud.bgInput,
                  shape: hud.chamferShape(
                    borderColor: brain.isOllamaOnline
                        ? hud.primaryPeriwinkle.withValues(alpha: 0.65)
                        : hud.accentWarningAmber,
                  ),
                ),
                child: Text(
                  'ENGINE: ${brain.activeLocalModel.toUpperCase()}  •  ${brain.memoryService.liveTokensPerSecond.toStringAsFixed(1)} TOK/S',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: hud.primaryPeriwinkle,
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (brain.isOrbCompactTop)
                HudActionButton(
                  label: 'CENTER ORB',
                  icon: Icons.filter_tilt_shift,
                  onTap: brain.resetCenterStageToStandbyOrb,
                ),
              const SizedBox(width: 6),
              HudActionButton(
                label: 'HISTORY (${brain.memoryService.savedChatArchives.length})',
                icon: Icons.history_sharp,
                onTap: () {
                  brain.memoryService.refreshSavedChatArchives();
                  setState(() {
                    _showConnectionsModal = false;
                    _showPluginsModal = false;
                    _showHistoryModal = !_showHistoryModal;
                  });
                },
              ),
              const SizedBox(width: 6),
              HudActionButton(
                label: 'LEARN CODE',
                icon: Icons.psychology_sharp,
                accentColor: hud.accentSuccessGreen,
                onTap: brain.learnFromProjectsAndChats,
              ),
              const SizedBox(width: 6),
              HudActionButton(
                label: 'GIT PULL',
                icon: Icons.download_sharp,
                onTap: brain.gitPull,
              ),
              const SizedBox(width: 6),
              HudActionButton(
                label: 'GIT PUSH',
                icon: Icons.cloud_upload_sharp,
                onTap: () => brain.gitCommitAndPush(
                  commitMessage: 'feat: update via Ultron Qwen 14B',
                  pushAfter: true,
                ),
              ),
              const SizedBox(width: 6),
              HudActionButton(
                label:
                    'PLUGINS (${brain.pluginService.installedPlugins.where((p) => p.isEnabled).length})',
                icon: Icons.extension_sharp,
                onTap: () => setState(() {
                  _showConnectionsModal = false;
                  _showHistoryModal = false;
                  _showPluginsModal = !_showPluginsModal;
                }),
              ),
              const SizedBox(width: 6),
              HudActionButton(
                label: brain.isVsCodeWindowOpen ? 'HIDE VS CODE' : 'VS CODE STUDIO',
                icon: Icons.code_sharp,
                isPrimaryAccent: brain.isVsCodeWindowOpen,
                onTap: brain.toggleVsCodeWindow,
              ),
              const SizedBox(width: 6),
              HudActionButton(
                label: 'GITHUB & OLLAMA',
                icon: Icons.hub_sharp,
                onTap: () => setState(() {
                  _showPluginsModal = false;
                  _showHistoryModal = false;
                  _showConnectionsModal = !_showConnectionsModal;
                }),
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: widget.onToggleTheme,
                icon: Icon(
                  widget.isDarkMode
                      ? Icons.dark_mode_sharp
                      : Icons.light_mode_sharp,
                  size: 16,
                  color: hud.primaryPeriwinkle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  //********************************************************************
  // CENTER STAGE: SHRINKING TOP-CENTER ORB + BORDERLESS FLOATING TEXT *
  //********************************************************************
  Widget _buildCenterOrbAndBorderlessTextStage(
    UltronHudTheme hud,
    UltronBrainRouter brain,
  ) {
    final compact = brain.isOrbCompactTop;
    final hasText =
        brain.currentCenterResponseText.isNotEmpty || brain.isStreamingResponse;
    final showCursor =
        brain.isStreamingResponse && ((_pulseClock * 6).floor().isEven);

    return Column(
      children: [
        const SizedBox(height: 12),

        // 1. SMOOTH ANIMATED ORB (SHRINKS & MOVES TO TOP-CENTER WHEN CHATTING)
        AnimatedContainer(
          duration: const Duration(milliseconds: 340),
          curve: Curves.easeOutQuart,
          width: compact ? 148 : 370,
          height: compact ? 148 : 370,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: UltronWireframeOrbPainter(
                shellAngleY: _shellAngleY,
                ringAngleY: _ringAngleY,
                beamDriftPhase: _beamDriftPhase,
                pulseClock: _pulseClock,
                subtleKeystrokeRipple: brain.subtleKeystrokePulse,
                params: _currentParams,
              ),
            ),
          ),
        ),

        // Subtle floating status line directly under the orb (No box, no border!)
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 8),
          child: Text(
            brain.statusBanner.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
              color: brain.lastErrorBanner != null
                  ? hud.accentErrorRed
                  : hud.primaryPeriwinkle.withValues(alpha: 0.75),
            ),
          ),
        ),

        // 2. BORDERLESS, BACKGROUNDLESS FLOATING RESPONSE TEXT IN THE MIDDLE
        Expanded(
          child: hasText
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 740),
                    child: SingleChildScrollView(
                      controller: _centerTextScrollController,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                      child: TweenAnimationBuilder<double>(
                        key: ValueKey<int>(
                          brain.currentCenterResponseText.length ~/ 18,
                        ),
                        tween: Tween<double>(begin: 0.88, end: 1.0),
                        duration: const Duration(milliseconds: 90),
                        curve: Curves.easeOutCubic,
                        builder: (context, opacity, child) {
                          return Opacity(opacity: opacity, child: child);
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (brain.currentPromptLabel.isNotEmpty) ...[
                              Text(
                                '> ${brain.currentPromptLabel}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.8,
                                  color: hud.textMuted,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            SelectableText.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: brain.currentCenterResponseText,
                                    style: TextStyle(
                                      fontSize: 15,
                                      height: 1.62,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.25,
                                      color: hud.textPrimary,
                                      shadows: [
                                        Shadow(
                                          color: hud.secondaryVioletBloom
                                              .withValues(alpha: 0.35),
                                          blurRadius: 12,
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (showCursor)
                                    TextSpan(
                                      text: ' ▋',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w900,
                                        color: hud.primaryPeriwinkle,
                                      ),
                                    ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),

        // 3. BOTTOM COMMAND INPUT BAR
        Padding(
          padding: const EdgeInsets.fromLTRB(295, 0, 16, 14),
          child: HudBracketPanel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            borderColor: _promptFocusNode.hasFocus
                ? hud.primaryPeriwinkle
                : hud.borderLine,
            child: Row(
              children: [
                Text(
                  '>_',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: hud.primaryPeriwinkle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _promptController,
                    focusNode: _promptFocusNode,
                    cursorColor: hud.primaryPeriwinkle,
                    cursorWidth: 6,
                    onChanged: brain.onUserKeystroke,
                    onSubmitted: (v) {
                      brain.executeUltronPrompt(v);
                      _promptController.clear();
                    },
                    style: TextStyle(
                      fontSize: 12.5,
                      color: hud.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'ASK ULTRON OR WRITE CODE TO VS CODE (/learn, /pull, /commit, /push, /done)...',
                      hintStyle: TextStyle(
                        fontSize: 10.5,
                        letterSpacing: 0.6,
                        color: hud.textMuted,
                      ),
                      isDense: true,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                HudActionButton(
                  label: brain.isStreamingResponse ? 'STREAMING...' : 'EXECUTE',
                  icon: Icons.bolt_sharp,
                  isPrimaryAccent: true,
                  accentColor: hud.primaryPeriwinkle,
                  onTap: () {
                    brain.executeUltronPrompt(_promptController.text);
                    _promptController.clear();
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  //********************************************************************
  // BOTTOM-LEFT: LIVE SPEED (TOK/S), CPU %, GPU %, VRAM & SYSTEM RAM  *
  //********************************************************************
  Widget _buildLiveHardwareTelemetryPanel(
    UltronHudTheme hud,
    UltronBrainRouter brain,
  ) {
    final mem = brain.memoryService;
    final online = brain.isOllamaOnline;

    return SizedBox(
      width: 272,
      child: HudBracketPanel(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.speed_sharp,
                  size: 13,
                  color: hud.primaryPeriwinkle,
                ),
                const SizedBox(width: 6),
                Text(
                  'LIVE SYSTEM & AI TELEMETRY',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.9,
                    color: hud.primaryPeriwinkle,
                  ),
                ),
                const Spacer(),
                Text(
                  online ? 'LIVE' : 'OFFLINE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: online
                        ? hud.accentSuccessGreen
                        : hud.accentWarningAmber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),

            // 1. RESPONSE SPEED (TOK/S)
            _buildTelemetryBar(
              hud: hud,
              label: 'SPEED',
              valueText: '${mem.liveTokensPerSecond.toStringAsFixed(1)} tok/s',
              ratio: (mem.liveTokensPerSecond / 45.0).clamp(0.04, 1.0),
              color: hud.primaryPeriwinkle,
            ),
            const SizedBox(height: 7),

            // 2. CPU & GPU POWER / LOAD
            _buildTelemetryBar(
              hud: hud,
              label: 'CPU / GPU',
              valueText:
                  'CPU ${mem.liveCpuPercent.toStringAsFixed(0)}%  •  GPU ${mem.liveGpuPercent.toStringAsFixed(0)}%',
              ratio: ((mem.liveCpuPercent + mem.liveGpuPercent) / 200.0)
                  .clamp(0.05, 1.0),
              color: hud.secondaryVioletBloom,
            ),
            const SizedBox(height: 7),

            // 3. GPU VRAM (ARC B570 10GB)
            _buildTelemetryBar(
              hud: hud,
              label: 'GPU VRAM',
              valueText:
                  '${mem.liveGpuVramUsedGb.toStringAsFixed(1)} / ${mem.liveGpuVramTotalGb.toStringAsFixed(1)} GiB',
              ratio: mem.gpuVramRatio,
              color: hud.accentSuccessGreen,
            ),
            const SizedBox(height: 7),

            // 4. SYSTEM RAM (31.2 GiB)
            _buildTelemetryBar(
              hud: hud,
              label: 'SYS RAM',
              valueText:
                  '${mem.liveSysRamUsedGb.toStringAsFixed(1)} / ${mem.liveSysRamTotalGb.toStringAsFixed(1)} GiB',
              ratio: mem.sysRamRatio,
              color: hud.primaryPeriwinkle,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTelemetryBar({
    required UltronHudTheme hud,
    required String label,
    required String valueText,
    required double ratio,
    required Color color,
  }) {
    const segs = 16;
    final lit = (ratio * segs).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 9, color: hud.textMuted)),
            Text(
              valueText,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.bold,
                color: hud.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: List.generate(segs, (i) {
            return Expanded(
              child: Container(
                height: 4,
                margin: const EdgeInsets.only(right: 2),
                color: i < lit ? color : hud.bgInput,
              ),
            );
          }),
        ),
      ],
    );
  }

  //********************************************************************
  // MINIMAL ARCHIVED CHAT HISTORY OVERLAY                             *
  //********************************************************************
  Widget _buildChatHistoryModal(UltronHudTheme hud, UltronBrainRouter brain) {
    final archives = brain.memoryService.savedChatArchives;
    return SizedBox(
      width: 560,
      height: 420,
      child: HudBracketPanel(
        padding: const EdgeInsets.all(16),
        borderColor: hud.primaryPeriwinkle,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history_sharp, size: 16, color: hud.primaryPeriwinkle),
                const SizedBox(width: 8),
                Text(
                  'SAVED SESSIONS & CONVERSATION HISTORY',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: hud.textPrimary,
                  ),
                ),
                const Spacer(),
                HudActionButton(
                  label: 'NEW SESSION',
                  icon: Icons.add,
                  onTap: () {
                    brain.startNewChatSession();
                    setState(() => _showHistoryModal = false);
                  },
                ),
                const SizedBox(width: 6),
                HudActionButton(
                  label: 'CLOSE',
                  accentColor: hud.accentErrorRed,
                  onTap: () => setState(() => _showHistoryModal = false),
                ),
              ],
            ),
            Divider(height: 18, color: hud.borderLine),
            Expanded(
              child: archives.isEmpty
                  ? Center(
                      child: Text(
                        'No archived sessions yet. Type /done to save a session.',
                        style: TextStyle(fontSize: 11, color: hud.textMuted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: archives.length,
                      itemBuilder: (context, i) {
                        final arch = archives[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: hud.bgInput,
                            border: Border.all(color: hud.borderLine),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      arch.fileName,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: hud.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      '${arch.modifiedDate} • ${arch.lineCount} lines',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        color: hud.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              HudActionButton(
                                label: 'LOAD',
                                onTap: () {
                                  brain.loadSavedChatArchiveIntoView(arch);
                                  setState(() => _showHistoryModal = false);
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}