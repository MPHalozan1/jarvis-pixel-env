import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../backend/project_workspace_service.dart';
import '../backend/ultron_brain_router.dart';
import 'ultron_bubble_painter.dart';
import 'ultron_hud_theme.dart';

//**************
// Dodelana kartica sporočila uporabnika in ULTRON odgovora *
// Vključuje inženirsko glavo (model, hitrost tok/s, trajanje), *
// odpiranje kode v urejevalniku, shranjevanje izpiska in 1-klik učenje *
//**************
class UltronChatMessageCard extends StatefulWidget {
  final ChatMessageItem message;
  final UltronBrainRouter brain;
  final VoidCallback? onHeightGrew;
  final ValueChanged<String>? onToast;

  const UltronChatMessageCard({
    super.key,
    required this.message,
    required this.brain,
    this.onHeightGrew,
    this.onToast,
  });

  @override
  State<UltronChatMessageCard> createState() => _UltronChatMessageCardState();
}

class _UltronChatMessageCardState extends State<UltronChatMessageCard>
    with SingleTickerProviderStateMixin {
  Ticker? _typeTicker;
  Duration _lastTick = Duration.zero;

  double _visibleCharsExact = 0.0;
  int _visibleChars = 0;
  bool _typingFinished = false;
  bool _hovered = false;
  bool _copiedWholeMsg = false;
  int _scrollNotifyCounter = 0;

  bool get _isUser => widget.message.role == 'user';

  @override
  void initState() {
    super.initState();
    if (_isUser || !widget.message.isStreaming) {
      _visibleChars = widget.message.content.length;
      _visibleCharsExact = _visibleChars.toDouble();
      _typingFinished = true;
    } else {
      _attachStreamingListeners();
      _evaluateTickerState();
    }
  }

  @override
  void didUpdateWidget(covariant UltronChatMessageCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id) {
      _detachStreamingListeners(oldWidget.message);
      if (_isUser || !widget.message.isStreaming) {
        _stopTicker();
        _visibleChars = widget.message.content.length;
        _visibleCharsExact = _visibleChars.toDouble();
        _typingFinished = true;
      } else {
        _visibleChars = 0;
        _visibleCharsExact = 0.0;
        _typingFinished = false;
        _attachStreamingListeners();
        _evaluateTickerState();
      }
    }
  }

  void _attachStreamingListeners() {
    widget.message.liveTargetText.addListener(_onStreamSignal);
    widget.message.networkDone.addListener(_onStreamSignal);
    widget.message.bufferedCharsCount.addListener(_onBufferCountSignal);
  }

  void _detachStreamingListeners(ChatMessageItem msg) {
    msg.liveTargetText.removeListener(_onStreamSignal);
    msg.networkDone.removeListener(_onStreamSignal);
    msg.bufferedCharsCount.removeListener(_onBufferCountSignal);
  }

  @override
  void dispose() {
    _detachStreamingListeners(widget.message);
    _typeTicker?.dispose();
    super.dispose();
  }

  void _onBufferCountSignal() {
    if (!mounted) return;
    if (widget.brain.typingMode != UltronTypingMode.adaptiveSmooth &&
        !widget.message.networkDone.value) {
      setState(() {});
    }
  }

  void _onStreamSignal() {
    if (!mounted) return;
    final target = widget.message.liveTargetText.value;
    if (target.length < _visibleChars) {
      _visibleChars = target.length;
      _visibleCharsExact = target.length.toDouble();
    }
    _evaluateTickerState();
    setState(() {});
  }

  void _evaluateTickerState() {
    if (_isUser || _typingFinished) {
      _stopTicker();
      return;
    }

    final mode = widget.brain.typingMode;
    final netDone = widget.message.networkDone.value;
    final targetLen = widget.message.liveTargetText.value.length;

    if (mode == UltronTypingMode.instant) {
      if (netDone) {
        _visibleChars = targetLen;
        _visibleCharsExact = targetLen.toDouble();
        _typingFinished = true;
        _stopTicker();
        widget.onHeightGrew?.call();
      }
      return;
    }

    if (mode == UltronTypingMode.waitFullThenType && !netDone) {
      _stopTicker();
      return;
    }

    if (_visibleChars < targetLen || !netDone) {
      _startTickerIfNeeded();
    } else if (netDone && _visibleChars >= targetLen) {
      _typingFinished = true;
      _stopTicker();
    }
  }

  void _startTickerIfNeeded() {
    if (_typeTicker != null && _typeTicker!.isActive) return;
    _lastTick = Duration.zero;
    _typeTicker ??= createTicker(_onTick);
    _typeTicker!.start();
  }

  void _stopTicker() {
    if (_typeTicker != null && _typeTicker!.isActive) {
      _typeTicker!.stop();
    }
    _lastTick = Duration.zero;
  }

  void _onTick(Duration elapsed) {
    final double dt = _lastTick == Duration.zero
        ? 0.016
        : ((elapsed - _lastTick).inMicroseconds / 1000000.0)
            .clamp(0.001, 0.05);
    _lastTick = elapsed;

    final String target = widget.message.liveTargetText.value;
    final int targetLen = target.length;
    final bool netDone = widget.message.networkDone.value;

    if (_visibleChars < targetLen) {
      final int backlog = targetLen - _visibleChars;
      final double speedMult = widget.brain.typingSpeedMultiplier;

      final double baseRate =
          widget.brain.typingMode == UltronTypingMode.waitFullThenType
              ? 340.0 * speedMult
              : 185.0 * speedMult;
      final double catchupBoost = backlog * (12.0 * speedMult);
      final double charsPerSec =
          (baseRate + catchupBoost).clamp(65.0, 3200.0);

      _visibleCharsExact = (_visibleCharsExact + dt * charsPerSec)
          .clamp(0.0, targetLen.toDouble());
      final int nextCount = _visibleCharsExact.floor();

      if (nextCount != _visibleChars) {
        _visibleChars = nextCount;
        _scrollNotifyCounter++;
        if (_scrollNotifyCounter % 4 == 0) {
          widget.onHeightGrew?.call();
        }
        if (mounted) setState(() {});
      }
    } else if (netDone) {
      _typingFinished = true;
      _stopTicker();
      widget.onHeightGrew?.call();
      if (mounted) setState(() {});
    }
  }

  void _skipTypingNow() {
    final targetLen = widget.message.liveTargetText.value.length;
    setState(() {
      _visibleChars = targetLen;
      _visibleCharsExact = targetLen.toDouble();
      if (widget.message.networkDone.value) {
        _typingFinished = true;
        _stopTicker();
      }
    });
    widget.onHeightGrew?.call();
  }

  Future<void> _copyWholeMessage(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    setState(() => _copiedWholeMsg = true);
    widget.onToast?.call('Sporočilo kopirano v odložišče');
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _copiedWholeMsg = false);
  }

  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  void _showEditUserMessageDialog() {
    final ctrl = TextEditingController(text: widget.message.content);
    showDialog(
      context: context,
      builder: (ctx) {
        final hud =
            Theme.of(ctx).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
        return AlertDialog(
          backgroundColor: hud.bgPanel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(hud.cutRadius),
            side: BorderSide(color: hud.borderLine),
          ),
          title: Text(
            'Uredi poziv & ponovno pošlji',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: hud.textPrimary,
            ),
          ),
          content: SizedBox(
            width: 520,
            child: TextField(
              controller: ctrl,
              autofocus: true,
              minLines: 2,
              maxLines: 8,
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
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Prekliči', style: TextStyle(color: hud.textMuted)),
            ),
            TextButton(
              onPressed: () {
                widget.brain
                    .editAndResubmitUserMessage(widget.message.id, ctrl.text);
                Navigator.pop(ctx);
              },
              child: Text(
                'Pošlji ponovno',
                style: TextStyle(
                  color: hud.primaryPeriwinkle,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showSaveOutputDialog(String fullText) {
    final defaultName =
        'ultron_izpisek_${DateTime.now().millisecondsSinceEpoch % 10000}.md';
    final ctrl = TextEditingController(text: defaultName);

    showDialog(
      context: context,
      builder: (ctx) {
        final hud =
            Theme.of(ctx).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
        return AlertDialog(
          backgroundColor: hud.bgPanel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(hud.cutRadius),
            side: BorderSide(color: hud.borderLine),
          ),
          title: Text(
            'Shrani ULTRON izpisek v datoteko',
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
                widget.brain.hasActiveProject
                    ? 'Shrani v aktivni projekt (${widget.brain.activeProjectName}):'
                    : 'Shrani v trenutno mapo (${widget.brain.currentBrowserFolderName}):',
                style: TextStyle(fontSize: 12, color: hud.textMuted),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                autofocus: true,
                style: TextStyle(fontSize: 12.5, color: hud.textPrimary),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: hud.bgInput,
                  hintText: 'npr. docs/arhitektura.md',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: hud.borderLine),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Prekliči', style: TextStyle(color: hud.textMuted)),
            ),
            TextButton(
              onPressed: () async {
                final saved = await widget.brain.saveAssistantOutputToFile(
                  content: fullText,
                  relativeOrFullPath: ctrl.text,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                widget.onToast?.call(
                  saved != null
                      ? 'Shranjeno: $saved'
                      : 'Shranjevanje ni uspelo',
                );
              },
              child: Text(
                'Shrani',
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
  }

  void _showLearnFromMessageDialog(String fullText) {
    final ctrl = TextEditingController(
      text: _isUser ? 'Uporabniško navodilo' : 'Arhitekturni vzorec',
    );
    bool isGlobal = !widget.brain.hasActiveProject;

    showDialog(
      context: context,
      builder: (ctx) {
        final hud =
            Theme.of(ctx).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              backgroundColor: hud.bgPanel,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(hud.cutRadius),
                side: BorderSide(color: hud.borderLine),
              ),
              title: Text(
                'Shrani v Learn Vault',
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
                    'ULTRON bo iz tega sporočila izluščil trajno pravilo.',
                    style: TextStyle(fontSize: 12, color: hud.textMuted),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ctrl,
                    style: TextStyle(fontSize: 12.5, color: hud.textPrimary),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: hud.bgInput,
                      hintText: 'Kratek naslov pravila...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: hud.borderLine),
                      ),
                    ),
                  ),
                  if (widget.brain.hasActiveProject) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Switch(
                          value: isGlobal,
                          activeTrackColor: hud.accentSuccessGreen,
                          activeThumbColor: Colors.white,
                          onChanged: (v) =>
                              setStateDialog(() => isGlobal = v),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isGlobal
                                ? 'Globalno pravilo (vsi klepeti)'
                                : 'Samo za projekt ${widget.brain.activeProjectName}',
                            style: TextStyle(
                                fontSize: 12, color: hud.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ],
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
                    await widget.brain.learnFromMessageContent(
                      title: ctrl.text,
                      contentOrRule: fullText,
                      isGlobal: isGlobal,
                      extractViaLlm: true,
                    );
                    widget.onToast?.call('Pravilo dodano v Learn Vault');
                  },
                  child: Text(
                    'Nauči se',
                    style: TextStyle(
                      color: hud.primaryPeriwinkle,
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

    final String fullTarget = _isUser
        ? widget.message.content
        : (widget.message.liveTargetText.value.isNotEmpty
            ? widget.message.liveTargetText.value
            : widget.message.content);

    final bool netDone = _isUser || widget.message.networkDone.value;
    final bool isWaitingForFullBuffer = !_isUser &&
        !netDone &&
        (widget.brain.typingMode == UltronTypingMode.waitFullThenType ||
            widget.brain.typingMode == UltronTypingMode.instant);

    final String renderedText = (_isUser || _typingFinished)
        ? fullTarget
        : fullTarget.substring(0, _visibleChars.clamp(0, fullTarget.length));

    final bool activelyTypingOut =
        !_isUser && !_typingFinished && !isWaitingForFullBuffer;

    return RepaintBoundary(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
        builder: (context, anim, child) {
          return Opacity(
            opacity: anim,
            child: Transform.translate(
              offset: Offset(0, (1.0 - anim) * 6.0),
              child: child,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Align(
            alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _isUser ? 660 : 840),
              child: MouseRegion(
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _isUser
                        ? hud.primaryPeriwinkle.alphaPct(0.14)
                        : hud.bgPanel.alphaPct(_hovered ? 0.92 : 0.84),
                    borderRadius: BorderRadius.circular(hud.cutRadius + 2),
                    border: Border.all(
                      color: _isUser
                          ? hud.primaryPeriwinkle
                              .alphaPct(_hovered ? 0.58 : 0.34)
                          : (activelyTypingOut || isWaitingForFullBuffer
                              ? hud.primaryPeriwinkle.alphaPct(0.50)
                              : hud.borderLine
                                  .alphaPct(_hovered ? 0.95 : 0.72)),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.alphaPct(_hovered ? 0.22 : 0.12),
                        blurRadius: _hovered ? 18 : 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isUser) ...[
                        _buildUserHeader(hud, fullTarget),
                        const SizedBox(height: 6),
                      ] else ...[
                        _buildAssistantHeader(
                          hud: hud,
                          fullTarget: fullTarget,
                          activelyTypingOut: activelyTypingOut,
                          netDone: netDone,
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (widget.message.attachedFileNames.isNotEmpty) ...[
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children:
                              widget.message.attachedFileNames.map((fName) {
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: hud.bgInput.alphaPct(0.88),
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: hud.primaryPeriwinkle.alphaPct(0.35),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.attach_file_rounded,
                                      size: 11.5,
                                      color: hud.primaryPeriwinkle),
                                  const SizedBox(width: 4),
                                  Text(
                                    fName,
                                    style: TextStyle(
                                        fontSize: 10.8,
                                        color: hud.textPrimary),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (!_isUser &&
                          widget.message.workspaceActions.isNotEmpty) ...[
                        _buildWorkspaceBadges(hud),
                        const SizedBox(height: 9),
                      ],
                      if (isWaitingForFullBuffer)
                        _buildBufferingSynthesisState(hud)
                      else if (renderedText.isEmpty && !netDone)
                        _buildThinkingPulseRow(hud)
                      else
                        _buildStructuredContent(
                          hud: hud,
                          text: renderedText,
                          isActivelyTyping: activelyTypingOut,
                        ),
                      if (!_isUser &&
                          widget.message.pendingWriteProposals.isNotEmpty &&
                          _typingFinished) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: widget.message.pendingWriteProposals
                              .map((prop) {
                            return HudActionButton(
                              compact: true,
                              isPrimaryAccent: true,
                              accentColor: hud.accentSuccessGreen,
                              icon: prop.isDirectory
                                  ? Icons.create_new_folder_outlined
                                  : Icons.save_alt_rounded,
                              label: prop.isDirectory
                                  ? 'Ustvari mapo ${prop.path}'
                                  : 'Zapiši ${prop.path} v projekt',
                              onTap: () async {
                                await widget.brain.applyProposalDirective(
                                  widget.message,
                                  prop,
                                );
                                widget.onToast
                                    ?.call('Zapisano v projekt: ${prop.path}');
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserHeader(UltronHudTheme hud, String fullTarget) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.person_outline_rounded,
            size: 13.5, color: hud.primaryPeriwinkle),
        const SizedBox(width: 5),
        Text(
          'TI · ${_formatTime(widget.message.timestamp)}',
          style: TextStyle(
            fontSize: 10.2,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
            color: hud.textMuted,
          ),
        ),
        const Spacer(),
        AnimatedOpacity(
          duration: const Duration(milliseconds: 140),
          opacity: _hovered || _copiedWholeMsg ? 1.0 : 0.0,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _headerActionChip(
                hud: hud,
                icon: Icons.edit_outlined,
                label: 'Uredi',
                onTap: _showEditUserMessageDialog,
              ),
              const SizedBox(width: 4),
              _headerActionChip(
                hud: hud,
                icon: _copiedWholeMsg
                    ? Icons.check_rounded
                    : Icons.copy_rounded,
                label: _copiedWholeMsg ? 'Kopirano' : 'Kopiraj',
                color: _copiedWholeMsg ? hud.accentSuccessGreen : null,
                onTap: () => _copyWholeMessage(fullTarget),
              ),
              const SizedBox(width: 4),
              _headerActionChip(
                hud: hud,
                icon: Icons.psychology_alt,
                label: 'Nauči se',
                color: hud.primaryPeriwinkle,
                onTap: () => _showLearnFromMessageDialog(fullTarget),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAssistantHeader({
    required UltronHudTheme hud,
    required String fullTarget,
    required bool activelyTypingOut,
    required bool netDone,
  }) {
    final bool miniOrbActive = !netDone || activelyTypingOut;
    final OrbState miniState =
        !netDone ? OrbState.thinking : OrbState.answering;

    final statsParts = <String>[
      widget.message.modelName,
      if (widget.message.tokensPerSec > 0)
        '${widget.message.tokensPerSec.toStringAsFixed(1)} tok/s',
      if (widget.message.generationDurationMs > 0)
        '${(widget.message.generationDurationMs / 1000.0).toStringAsFixed(1)}s',
    ];

    return Row(
      children: [
        UltronMiniChatOrb(
          isAnimating: miniOrbActive,
          activeState: miniState,
          size: 24.0,
        ),
        const SizedBox(width: 8),
        Text(
          'ULTRON',
          style: TextStyle(
            fontSize: 10.8,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
            color: hud.primaryPeriwinkle,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '· ${statsParts.join(" · ")}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              color: hud.textMuted.alphaPct(0.85),
            ),
          ),
        ),
        if (activelyTypingOut && fullTarget.length - _visibleChars > 25)
          _headerActionChip(
            hud: hud,
            icon: Icons.fast_forward_rounded,
            label: 'Prikaži vse',
            color: hud.primaryPeriwinkle,
            onTap: _skipTypingNow,
          ),
        if (_typingFinished && fullTarget.isNotEmpty)
          AnimatedOpacity(
            duration: const Duration(milliseconds: 140),
            opacity: _hovered || _copiedWholeMsg ? 1.0 : 0.0,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _headerActionChip(
                  hud: hud,
                  icon: _copiedWholeMsg
                      ? Icons.check_rounded
                      : Icons.copy_rounded,
                  label: _copiedWholeMsg ? 'Kopirano' : 'Kopiraj',
                  color: _copiedWholeMsg ? hud.accentSuccessGreen : null,
                  onTap: () => _copyWholeMessage(fullTarget),
                ),
                const SizedBox(width: 4),
                _headerActionChip(
                  hud: hud,
                  icon: Icons.save_alt_rounded,
                  label: 'Shrani',
                  onTap: () => _showSaveOutputDialog(fullTarget),
                ),
                const SizedBox(width: 4),
                _headerActionChip(
                  hud: hud,
                  icon: Icons.psychology_alt,
                  label: 'Nauči se',
                  color: hud.accentSuccessGreen,
                  onTap: () => _showLearnFromMessageDialog(fullTarget),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _headerActionChip({
    required UltronHudTheme hud,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    final c = color ?? hud.textMuted;
    return InkWell(
      borderRadius: BorderRadius.circular(5),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
        decoration: BoxDecoration(
          color: hud.bgInput.alphaPct(0.75),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: hud.borderLine.alphaPct(0.75)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11.5, color: c),
            const SizedBox(width: 3.5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: c,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBufferingSynthesisState(UltronHudTheme hud) {
    final chars = widget.message.bufferedCharsCount.value;
    final status = widget.brain.liveAgentStatus.isNotEmpty
        ? widget.brain.liveAgentStatus
        : 'ULTRON pripravlja celoten odgovor pred gladkim izpisom...';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: hud.bgInput.alphaPct(0.65),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: hud.primaryPeriwinkle.alphaPct(0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: hud.textPrimary,
                  ),
                ),
              ),
              if (chars > 0)
                Text(
                  '$chars znakov',
                  style: TextStyle(
                    fontSize: 10.8,
                    fontWeight: FontWeight.w600,
                    color: hud.primaryPeriwinkle,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: hud.bgDeep.alphaPct(0.7),
              color: hud.primaryPeriwinkle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThinkingPulseRow(UltronHudTheme hud) {
    final label = widget.brain.liveAgentStatus.isNotEmpty
        ? widget.brain.liveAgentStatus
        : 'ULTRON razmišlja...';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Text(
        label,
        style: TextStyle(fontSize: 12.2, color: hud.textMuted),
      ),
    );
  }

  Widget _buildWorkspaceBadges(UltronHudTheme hud) {
    final mutations = widget.message.workspaceActions
        .where((a) =>
            a.type == WorkspaceActionType.createFile ||
            a.type == WorkspaceActionType.updateFile ||
            a.type == WorkspaceActionType.createFolder ||
            a.type == WorkspaceActionType.error)
        .toList();
    final readCount = widget.message.workspaceActions
        .where((a) =>
            a.type == WorkspaceActionType.readFile ||
            a.type == WorkspaceActionType.listFolder)
        .length;

    return Wrap(
      spacing: 6,
      runSpacing: 5,
      children: [
        if (readCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: hud.bgInput.alphaPct(0.80),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: hud.borderLine.alphaPct(0.8)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder_open_rounded,
                    size: 11.5, color: hud.primaryPeriwinkle),
                const SizedBox(width: 5),
                Text(
                  'Prebranih $readCount projektnih datotek',
                  style: TextStyle(fontSize: 10.5, color: hud.textMuted),
                ),
              ],
            ),
          ),
        for (final act in mutations)
          InkWell(
            borderRadius: BorderRadius.circular(5),
            onTap: (act.type == WorkspaceActionType.createFile ||
                    act.type == WorkspaceActionType.updateFile)
                ? () => widget.brain.openFileInEditorTab(act.fullPath)
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: act.success
                    ? hud.accentSuccessGreen.alphaPct(0.13)
                    : hud.accentErrorRed.alphaPct(0.13),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: act.success
                      ? hud.accentSuccessGreen.alphaPct(0.48)
                      : hud.accentErrorRed.alphaPct(0.48),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    act.type == WorkspaceActionType.createFolder
                        ? Icons.create_new_folder_outlined
                        : (act.success
                            ? Icons.check_circle_outline
                            : Icons.error_outline),
                    size: 12,
                    color: act.success
                        ? hud.accentSuccessGreen
                        : hud.accentErrorRed,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${act.detail}: ${act.relativePath}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      color: hud.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStructuredContent({
    required UltronHudTheme hud,
    required String text,
    required bool isActivelyTyping,
  }) {
    final blocks = _splitMarkdownCodeBlocks(text);
    final children = <Widget>[];

    for (int i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      final isLastBlock = i == blocks.length - 1;

      if (b.isCode) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _InteractiveCodeBlockCard(
              language: b.language,
              code: b.content,
              isTyping: isActivelyTyping && isLastBlock,
              onToast: widget.onToast,
              onOpenInEditor: () async {
                final opened = await widget.brain.openCodeSnippetInEditor(
                  code: b.content,
                  language: b.language,
                );
                widget.onToast?.call('Odprto v urejevalniku: $opened');
              },
            ),
          ),
        );
      } else if (b.content.trim().isNotEmpty ||
          (isActivelyTyping && isLastBlock)) {
        final spans = _buildFormattedSpans(
          raw: b.content,
          hud: hud,
          appendCursor: isActivelyTyping && isLastBlock,
        );
        if (isActivelyTyping) {
          children.add(
            RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 13.4,
                  height: 1.55,
                  color: hud.textPrimary,
                ),
                children: spans,
              ),
            ),
          );
        } else {
          children.add(
            SelectableText.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 13.4,
                  height: 1.55,
                  color: hud.textPrimary,
                ),
                children: spans,
              ),
            ),
          );
        }
      }
    }

    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  List<InlineSpan> _buildFormattedSpans({
    required String raw,
    required UltronHudTheme hud,
    required bool appendCursor,
  }) {
    final spans = <InlineSpan>[];
    final tokenRegex =
        RegExp(r'(\*\*[^*]+\*\*|`[^`\n]+`|@[A-Za-z0-9_.\-/\\]+)');
    int lastEnd = 0;

    for (final match in tokenRegex.allMatches(raw)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: raw.substring(lastEnd, match.start)));
      }
      final tok = match.group(0)!;
      if (tok.startsWith('**') && tok.endsWith('**') && tok.length > 4) {
        spans.add(
          TextSpan(
            text: tok.substring(2, tok.length - 2),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: hud.textPrimary,
            ),
          ),
        );
      } else if (tok.startsWith('`') && tok.endsWith('`') && tok.length > 2) {
        spans.add(
          TextSpan(
            text: ' ${tok.substring(1, tok.length - 1)} ',
            style: TextStyle(
              fontFamily: 'Consolas',
              fontSize: 12.2,
              color: hud.primaryPeriwinkle,
              backgroundColor: hud.bgInput.alphaPct(0.9),
            ),
          ),
        );
      } else if (tok.startsWith('@') && tok.length > 1) {
        spans.add(
          TextSpan(
            text: tok,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: hud.accentSuccessGreen,
            ),
          ),
        );
      } else {
        spans.add(TextSpan(text: tok));
      }
      lastEnd = match.end;
    }

    if (lastEnd < raw.length) {
      spans.add(TextSpan(text: raw.substring(lastEnd)));
    }

    if (appendCursor) {
      spans.add(
        TextSpan(
          text: ' ▋',
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: hud.primaryPeriwinkle,
          ),
        ),
      );
    }

    return spans;
  }

  List<_MarkdownBlock> _splitMarkdownCodeBlocks(String input) {
    final result = <_MarkdownBlock>[];
    int cursor = 0;

    while (cursor < input.length) {
      final fenceStart = input.indexOf('```', cursor);
      if (fenceStart == -1) {
        result.add(_MarkdownBlock.prose(input.substring(cursor)));
        break;
      }

      if (fenceStart > cursor) {
        result.add(_MarkdownBlock.prose(input.substring(cursor, fenceStart)));
      }

      final firstLineBreak = input.indexOf('\n', fenceStart + 3);
      if (firstLineBreak == -1) {
        final lang = input.substring(fenceStart + 3).trim();
        result.add(_MarkdownBlock.code(lang, ''));
        break;
      }

      final lang = input.substring(fenceStart + 3, firstLineBreak).trim();
      final fenceEnd = input.indexOf('```', firstLineBreak + 1);
      if (fenceEnd == -1) {
        final partialCode = input.substring(firstLineBreak + 1);
        result.add(_MarkdownBlock.code(lang, partialCode));
        break;
      }

      final fullCode = input.substring(firstLineBreak + 1, fenceEnd);
      result.add(_MarkdownBlock.code(lang, fullCode.trimRight()));
      cursor = fenceEnd + 3;
    }

    return result;
  }
}

class _MarkdownBlock {
  final bool isCode;
  final String language;
  final String content;

  const _MarkdownBlock._({
    required this.isCode,
    required this.language,
    required this.content,
  });

  factory _MarkdownBlock.prose(String text) =>
      _MarkdownBlock._(isCode: false, language: '', content: text);

  factory _MarkdownBlock.code(String lang, String code) =>
      _MarkdownBlock._(isCode: true, language: lang, content: code);
}

class _InteractiveCodeBlockCard extends StatefulWidget {
  final String language;
  final String code;
  final bool isTyping;
  final ValueChanged<String>? onToast;
  final VoidCallback onOpenInEditor;

  const _InteractiveCodeBlockCard({
    required this.language,
    required this.code,
    required this.isTyping,
    this.onToast,
    required this.onOpenInEditor,
  });

  @override
  State<_InteractiveCodeBlockCard> createState() =>
      _InteractiveCodeBlockCardState();
}

class _InteractiveCodeBlockCardState extends State<_InteractiveCodeBlockCard> {
  bool _copied = false;
  bool _hovered = false;

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    widget.onToast?.call('Koda kopirana v odložišče');
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
    final langLabel =
        widget.language.isEmpty ? 'CODE' : widget.language.toUpperCase();

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: hud.bgDeep.alphaPct(0.88),
          borderRadius: BorderRadius.circular(hud.cutRadius * 0.85),
          border: Border.all(
            color: _hovered
                ? hud.primaryPeriwinkle.alphaPct(0.50)
                : hud.borderLine.alphaPct(0.85),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              color: hud.bgInput.alphaPct(0.75),
              child: Row(
                children: [
                  Icon(Icons.terminal_rounded,
                      size: 13, color: hud.primaryPeriwinkle),
                  const SizedBox(width: 6),
                  Text(
                    langLabel,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: hud.textMuted,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: widget.onOpenInEditor,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.code_rounded,
                              size: 12.5, color: hud.primaryPeriwinkle),
                          const SizedBox(width: 4),
                          Text(
                            'V urejevalnik',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: hud.primaryPeriwinkle,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: _copyCode,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _copied ? Icons.check_rounded : Icons.copy_rounded,
                            size: 12,
                            color: _copied
                                ? hud.accentSuccessGreen
                                : hud.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _copied ? 'Kopirano' : 'Kopiraj',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: _copied
                                  ? hud.accentSuccessGreen
                                  : hud.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: widget.isTyping
                  ? Text(
                      '${widget.code} ▋',
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 12.2,
                        height: 1.46,
                        color: hud.textPrimary,
                      ),
                    )
                  : SelectableText(
                      widget.code,
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 12.2,
                        height: 1.46,
                        color: hud.textPrimary,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}