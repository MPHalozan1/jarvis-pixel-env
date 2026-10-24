import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../backend/project_workspace_service.dart';
import '../backend/ultron_brain_router.dart';
import 'ultron_bubble_painter.dart';
import 'ultron_hud_theme.dart';

//**************
// Izolirana kartica sporočila v klepetu z vgrajeno varčno Mini 3D kroglo (UltronMiniChatOrb) *
// Mini krogla se animira SAMO med razmišljanjem/tipkanjem in se ob koncu popolnoma ustavi *
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
              ? 120.0 * speedMult
              : 65.0 * speedMult;
      final double catchupBoost = backlog * (6.0 * speedMult);
      final double charsPerSec =
          (baseRate + catchupBoost).clamp(38.0, 1650.0);

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
    widget.onToast?.call('Odgovor kopiran v odložišče');
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _copiedWholeMsg = false);
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
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        builder: (context, anim, child) {
          return Opacity(
            opacity: anim,
            child: Transform.translate(
              offset: Offset(0, (1.0 - anim) * 7.0),
              child: child,
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Align(
            alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: _isUser ? 620 : 720),
              child: MouseRegion(
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  curve: Curves.easeOutCubic,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _isUser
                        ? hud.primaryPeriwinkle.alphaPct(0.15)
                        : hud.bgPanel.alphaPct(_hovered ? 0.90 : 0.82),
                    borderRadius: BorderRadius.circular(hud.cutRadius + 1),
                    border: Border.all(
                      color: _isUser
                          ? hud.primaryPeriwinkle
                              .alphaPct(_hovered ? 0.58 : 0.38)
                          : (activelyTypingOut || isWaitingForFullBuffer
                              ? hud.primaryPeriwinkle.alphaPct(0.52)
                              : hud.borderLine
                                  .alphaPct(_hovered ? 0.95 : 0.72)),
                      width: 1.0,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.alphaPct(_hovered ? 0.20 : 0.11),
                        blurRadius: _hovered ? 16 : 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_isUser) ...[
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
                                    color:
                                        hud.primaryPeriwinkle.alphaPct(0.35)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.attach_file_rounded,
                                      size: 11.5, color: hud.primaryPeriwinkle),
                                  const SizedBox(width: 4),
                                  Text(
                                    fName,
                                    style: TextStyle(
                                        fontSize: 10.8, color: hud.textPrimary),
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
                          children:
                              widget.message.pendingWriteProposals.map((prop) {
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

  //**************
  // Glava sporočila asistenta z vgrajeno mini 3D kroglo UltronMiniChatOrb *
  //**************
  Widget _buildAssistantHeader({
    required UltronHudTheme hud,
    required String fullTarget,
    required bool activelyTypingOut,
    required bool netDone,
  }) {
    final bool miniOrbActive = !netDone || activelyTypingOut;
    final OrbState miniState =
        !netDone ? OrbState.thinking : OrbState.answering;

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
        Text(
          '· ${widget.message.modelName}',
          style: TextStyle(
            fontSize: 10.5,
            color: hud.textMuted.alphaPct(0.80),
          ),
        ),
        const Spacer(),
        if (activelyTypingOut && fullTarget.length - _visibleChars > 25)
          InkWell(
            borderRadius: BorderRadius.circular(5),
            onTap: _skipTypingNow,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: hud.primaryPeriwinkle.alphaPct(0.16),
                borderRadius: BorderRadius.circular(5),
                border:
                    Border.all(color: hud.primaryPeriwinkle.alphaPct(0.45)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fast_forward_rounded,
                      size: 12, color: hud.primaryPeriwinkle),
                  const SizedBox(width: 4),
                  Text(
                    'Prikaži vse',
                    style: TextStyle(
                      fontSize: 10.2,
                      fontWeight: FontWeight.w600,
                      color: hud.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_typingFinished && fullTarget.isNotEmpty)
          AnimatedOpacity(
            duration: const Duration(milliseconds: 140),
            opacity: _hovered || _copiedWholeMsg ? 1.0 : 0.0,
            child: InkWell(
              borderRadius: BorderRadius.circular(5),
              onTap: () => _copyWholeMessage(fullTarget),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _copiedWholeMsg
                          ? Icons.check_rounded
                          : Icons.copy_rounded,
                      size: 12.5,
                      color: _copiedWholeMsg
                          ? hud.accentSuccessGreen
                          : hud.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _copiedWholeMsg ? 'Kopirano' : 'Kopiraj',
                      style: TextStyle(
                        fontSize: 10.2,
                        color: _copiedWholeMsg
                            ? hud.accentSuccessGreen
                            : hud.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
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
                  fontSize: 13.3,
                  height: 1.54,
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
                  fontSize: 13.3,
                  height: 1.54,
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
    final tokenRegex = RegExp(r'(\*\*[^*]+\*\*|`[^`\n]+`)');
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

  const _InteractiveCodeBlockCard({
    required this.language,
    required this.code,
    required this.isTyping,
    this.onToast,
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
                            _copied ? 'Kopirano' : 'Kopiraj kodo',
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