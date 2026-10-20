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
// ULTRON MAIN HUD DASHBOARD (PHASES 1 TO 7 UNIFIED)                   *
// - RepaintBoundary + 250ms smooth state interpolation for the Orb    *
// - Sharp header controls, Plugins & Connections windows              *
// - Honest "TRACKED LOCALLY" / "NOT CONNECTED" Usage HUD              *
// - ">" Command-line input bar with blinking caret & EXECUTE button   *
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
  bool _showConnectionsModal = false;
  bool _showPluginsModal = false;
  bool _showChatDrawer = false;

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
        _stateTransitionT = (_stateTransitionT + dt / 0.25).clamp(0.0, 1.0);
        final eased = Curves.easeOutCubic.transform(_stateTransitionT);
        _currentParams = OrbVisualParams.lerp(
          _fromParams,
          OrbVisualParams.forState(_lastTargetState),
          eased,
        );
      }

      _shellAngleY += dt * rotationSpeed * _currentParams.shellSpinMultiplier;
      _ringAngleY +=
          dt * (rotationSpeed * 1.45) * _currentParams.ringDriftMultiplier;
      _beamDriftPhase += dt * 0.8;
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
              final isNarrow = constraints.maxWidth < 900;
              final editorWidth =
                  isNarrow ? constraints.maxWidth - 24 : 520.0;

              return Column(
                children: [
                  _buildSharpHeader(hud, brain),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: AnimatedPadding(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOutCubic,
                            padding: EdgeInsets.only(
                              right: (!isNarrow && brain.isVsCodeWindowOpen)
                                  ? editorWidth + 16
                                  : 0,
                            ),
                            child: _buildCenterOrbAndPromptStage(hud, brain),
                          ),
                        ),
                        Positioned(
                          left: 14,
                          bottom: 14,
                          child: _buildSharpUsagePanel(hud, brain),
                        ),
                        Positioned(
                          left: 14,
                          top: 14,
                          child: FuturisticHoverFileStack(
                            brain: brain,
                            isDarkMode: widget.isDarkMode,
                          ),
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 180),
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
                        if (_showConnectionsModal)
                          Center(
                            child: ConnectionsHudWindow(
                              brain: brain,
                              onClose: () => setState(
                                () => _showConnectionsModal = false,
                              ),
                            ),
                          ),
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

  Widget _buildSharpHeader(UltronHudTheme hud, UltronBrainRouter brain) {
    final isEscalated = brain.activeModelDisplay != brain.defaultTriageModel;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: hud.bgPanel,
        border: Border(bottom: BorderSide(color: hud.borderLine)),
      ),
      child: Wrap(
        spacing: 10,
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
                color: brain.orbState == OrbState.error
                    ? hud.accentErrorRed
                    : hud.primaryPeriwinkle,
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
              const SizedBox(width: 14),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: ShapeDecoration(
                  color: hud.bgInput,
                  shape: hud.chamferShape(
                    borderColor: isEscalated
                        ? hud.accentWarningAmber
                        : hud.primaryPeriwinkle,
                  ),
                ),
                child: Text(
                  'TRIAGE: 3.5 FLASH-LITE [LOW]  ->  ACTIVE: ${brain.activeModelDisplay.toUpperCase()} [${brain.activeThinkingLevel.hudTag}]',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: isEscalated
                        ? hud.accentWarningAmber
                        : hud.primaryPeriwinkle,
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              HudActionButton(
                label: 'CHAT LOG (${brain.chatHistory.length})',
                icon: Icons.subtitles_outlined,
                onTap: () => setState(() => _showChatDrawer = !_showChatDrawer),
              ),
              const SizedBox(width: 8),
              HudActionButton(
                label:
                    'PLUGINS (${brain.pluginService.installedPlugins.where((p) => p.isEnabled).length})',
                icon: Icons.extension_sharp,
                onTap: () => setState(() {
                  _showConnectionsModal = false;
                  _showPluginsModal = !_showPluginsModal;
                }),
              ),
              const SizedBox(width: 8),
              HudActionButton(
                label: brain.isVsCodeWindowOpen
                    ? 'CLOSE VS CODE BRIDGE'
                    : 'OPEN VS CODE BRIDGE',
                icon: Icons.code_sharp,
                onTap: brain.toggleVsCodeWindow,
              ),
              const SizedBox(width: 8),
              HudActionButton(
                label: 'WEB LINKS & SETTINGS',
                icon: Icons.public_sharp,
                isPrimaryAccent: true,
                accentColor: hud.accentErrorRed,
                onTap: () => setState(() {
                  _showPluginsModal = false;
                  _showConnectionsModal = !_showConnectionsModal;
                }),
              ),
              const SizedBox(width: 6),
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

  Widget _buildCenterOrbAndPromptStage(
    UltronHudTheme hud,
    UltronBrainRouter brain,
  ) {
    final isError = brain.lastErrorBanner != null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(74, 14, 20, 0),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: ShapeDecoration(
              color: hud.bgPanel,
              shape: hud.chamferShape(
                borderColor:
                    isError ? hud.accentErrorRed : hud.primaryPeriwinkle,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isError ? Icons.warning_amber_sharp : Icons.terminal_sharp,
                  size: 14,
                  color: isError ? hud.accentErrorRed : hud.primaryPeriwinkle,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    brain.statusBanner.toUpperCase(),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: isError ? hud.accentErrorRed : hud.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
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
              if (_showChatDrawer && brain.chatHistory.isNotEmpty)
                Positioned(
                  bottom: 12,
                  width: 560,
                  height: 210,
                  child: HudBracketPanel(
                    child: ListView.builder(
                      itemCount: brain.chatHistory.length,
                      itemBuilder: (context, i) {
                        final turn =
                            brain.chatHistory[brain.chatHistory.length - 1 - i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '[${turn.sender} // ${turn.modelUsed}]:\n${turn.text}',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: hud.textPrimary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(285, 0, 16, 14),
          child: HudBracketPanel(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                      fontSize: 12,
                      color: hud.textPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'ENTER COMMAND, /learn, /learn status, OR /done...',
                      hintStyle: TextStyle(
                        fontSize: 11,
                        letterSpacing: 0.7,
                        color: hud.textMuted,
                      ),
                      isDense: true,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                HudActionButton(
                  label: 'EXECUTE',
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

  Widget _buildSharpUsagePanel(UltronHudTheme hud, UltronBrainRouter brain) {
    final mem = brain.memoryService;
    final connected = brain.isAnyGeminiConnected;

    return SizedBox(
      width: 260,
      child: HudBracketPanel(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'LIVE GEMINI USAGE',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: hud.primaryPeriwinkle,
                  ),
                ),
                const Spacer(),
                Text(
                  connected ? 'TRACKED LOCALLY' : 'NOT CONNECTED',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: connected
                        ? hud.accentSuccessGreen
                        : hud.accentWarningAmber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!connected) ...[
              Text(
                'Connect Gemini Web Bridge or API key to track real requests & tokens.',
                style: TextStyle(fontSize: 10, color: hud.textMuted),
              ),
              const SizedBox(height: 8),
              HudActionButton(
                label: 'CONNECT GEMINI',
                onTap: () => setState(() => _showConnectionsModal = true),
              ),
            ] else ...[
              _buildHardBlockBar(
                hud: hud,
                label: 'DAILY REQ',
                valueText:
                    '${mem.dailyRequests}/${mem.dailyRequestLimit} (${mem.dailyTokens} TOK)',
                ratio: mem.dailyRatio,
                color: hud.primaryPeriwinkle,
              ),
              const SizedBox(height: 8),
              _buildHardBlockBar(
                hud: hud,
                label: 'WEEKLY REQ',
                valueText:
                    '${mem.weeklyRequests}/${mem.weeklyRequestLimit} (${mem.weeklyTokens} TOK)',
                ratio: mem.weeklyRatio,
                color: hud.secondaryVioletBloom,
              ),
              const SizedBox(height: 6),
              Text(
                'LAST REQ: ~${mem.lastRequestTokens} TOK • PERSISTED ON DISK',
                style: TextStyle(fontSize: 9, color: hud.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHardBlockBar({
    required UltronHudTheme hud,
    required String label,
    required String valueText,
    required double ratio,
    required Color color,
  }) {
    const segs = 14;
    final lit = (ratio * segs).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 9.5, color: hud.textMuted),
            ),
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
        const SizedBox(height: 4),
        Row(
          children: List.generate(segs, (i) {
            return Expanded(
              child: Container(
                height: 5,
                margin: const EdgeInsets.only(right: 2),
                color: i < lit ? color : hud.bgInput,
              ),
            );
          }),
        ),
      ],
    );
  }
}