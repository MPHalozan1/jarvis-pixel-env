import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../backend/ultron_brain_router.dart';
import 'connections_hud_window.dart';
import 'plugins_hud_window.dart';
import 'sleek_file_manager.dart';
import 'ultron_bubble_painter.dart';
import 'ultron_hud_theme.dart';
import 'vscode_live_window.dart';

//**************
// Glavna nadzorna plošča Ultron Neural Core: *
// Minimalističen HUD z delta-time (60-240Hz) 3D kroglo, hitrim izbirnikom LLM-jev, *
// pošiljanjem vseh vrst datotek, celotnim PC File Managerjem in aktivnim Learn sistemom *
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

  bool _showConnectionsModal = false;
  int _connectionsInitialTab = 0;
  bool _showPluginsModal = false;
  String? _toastMessage;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    widget.brain.addListener(_onBrainUpdated);

    // Fizikalno neodvisen Ticker (enaka hitrost pri 60 Hz in 240 Hz)
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

      _shellAngleY +=
          dt * OrbVisualParams.rotationSpeed * _currentVisualParams.shellSpinMultiplier;
      _ringAngleY -= dt * 0.36 * _currentVisualParams.ringDriftMultiplier;
      _beamDriftPhase += dt * 1.1;
      _pulseClock += dt;

      if (_keystrokeRipple > 0.001) {
        _keystrokeRipple = (_keystrokeRipple - dt * 2.6).clamp(0.0, 1.0);
      } else {
        _keystrokeRipple = 0.0;
      }

      _orbFrameTick.value++;
    })
      ..start();
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    widget.brain.removeListener(_onBrainUpdated);
    _orbTicker.dispose();
    _orbFrameTick.dispose();
    _promptCtrl.dispose();
    _chatScrollCtrl.dispose();
    super.dispose();
  }

  void _onBrainUpdated() {
    if (!mounted) return;
    setState(() {});
    if (widget.brain.isGenerating && _chatScrollCtrl.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chatScrollCtrl.hasClients) {
          _chatScrollCtrl.jumpTo(_chatScrollCtrl.position.maxScrollExtent);
        }
      });
    }
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toastMessage = message);
    _toastTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toastMessage = null);
    });
  }

  // Odpre sistemsko okno za izbiro poljubnih datotek vseh vrst
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
    } catch (e) {
      _showToast('Uporabi pripenjanje prek levega PC File Managerja');
    }
  }

  void _submitPrompt() {
    final text = _promptCtrl.text;
    if (text.trim().isEmpty && widget.brain.pendingAttachments.isEmpty) return;
    _promptCtrl.clear();
    _keystrokeRipple = 1.0;
    widget.brain.executeUltronPrompt(text);
  }

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;

    return Scaffold(
      backgroundColor: hud.bgDeep,
      body: Stack(
        children: [
          // 1. Sredinska animirana 3D krogla v lastnem RepaintBoundary sloju
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutCubic,
                  offset: Offset(
                    widget.brain.isVsCodeWindowOpen ? -0.14 : 0.0,
                    widget.brain.messages.isEmpty ? -0.04 : -0.16,
                  ),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 320),
                    opacity: widget.brain.messages.isEmpty ? 1.0 : 0.34,
                    child: RepaintBoundary(
                      child: SizedBox(
                        width: 430,
                        height: 430,
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
          ),

          // 2. Glavna delovna postavitev (Zgornja vrstica + Sredinski klepet + Desni urejevalnik)
          Column(
            children: [
              _buildMinimalTopBar(hud),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(child: _buildCenterConversationStage(hud)),
                          _buildBottomPromptDeck(hud),
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

          // 4. Minimalistično obvestilo (Toast)
          if (_toastMessage != null)
            Positioned(
              top: 62,
              right: 20,
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
                    color: hud.bgPanel.alphaPct(0.95),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(
                        color: hud.primaryPeriwinkle.alphaPct(0.6)),
                  ),
                  child: Text(
                    _toastMessage!,
                    style: TextStyle(fontSize: 12, color: hud.textPrimary),
                  ),
                ),
              ),
            ),

          // 5. Modalna okna (Modeli/Learn/Povezave in Vtičniki)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _showConnectionsModal
                ? Container(
                    key: const ValueKey('conn_modal'),
                    color: Colors.black.alphaPct(0.48),
                    padding: const EdgeInsets.all(24),
                    child: ConnectionsHudWindow(
                      brain: widget.brain,
                      initialTab: _connectionsInitialTab,
                      onClose: () =>
                          setState(() => _showConnectionsModal = false),
                    ),
                  )
                : _showPluginsModal
                    ? Container(
                        key: const ValueKey('plug_modal'),
                        color: Colors.black.alphaPct(0.48),
                        padding: const EdgeInsets.all(24),
                        child: PluginsHudWindow(
                          brain: widget.brain,
                          onClose: () =>
                              setState(() => _showPluginsModal = false),
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
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: hud.bgDeep.alphaPct(0.84),
        border: Border(
          bottom: BorderSide(color: hud.borderLine.alphaPct(0.65), width: 1.0),
        ),
      ),
      child: Row(
        children: [
          // Identiteta in status povezave
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
          const SizedBox(width: 9),
          Text(
            'ULTRON',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
              color: hud.textPrimary,
            ),
          ),
          const SizedBox(width: 14),

          // Hitri spustni izbirnik med vsemi zaznanimi lokalnimi LLM modeli
          Container(
            height: 31,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: hud.bgPanel.alphaPct(0.85),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: hud.borderLine.alphaPct(0.85)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: models.any(
                        (m) => m.name == widget.brain.activeLocalModel)
                    ? widget.brain.activeLocalModel
                    : null,
                hint: Text(
                  widget.brain.activeLocalModel,
                  style: TextStyle(fontSize: 12, color: hud.textPrimary),
                ),
                icon: Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Icon(Icons.expand_more_rounded,
                      size: 16, color: hud.textMuted),
                ),
                dropdownColor: hud.bgPanel,
                borderRadius: BorderRadius.circular(8),
                style: TextStyle(fontSize: 12, color: hud.textPrimary),
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
                            style:
                                TextStyle(fontSize: 10.5, color: hud.textMuted),
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
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Ponovno skeniraj računalnik za lokalne LLM modele',
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

          if (mem.liveTokensPerSecond > 0) ...[
            const SizedBox(width: 8),
            Text(
              '${mem.liveTokensPerSecond.toStringAsFixed(1)} tok/s',
              style: TextStyle(fontSize: 11, color: hud.textMuted),
            ),
          ],

          const Spacer(),

          // Dejansko delujoč gumb Learn + odpiranje trezorja znanja
          ListenableBuilder(
            listenable: mem,
            builder: (context, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HudActionButton(
                    label: mem.isLearningNow ? 'Learning...' : 'Learn',
                    icon: Icons.psychology_alt,
                    compact: true,
                    isPrimaryAccent: mem.isLearningNow,
                    accentColor: hud.accentSuccessGreen,
                    badgeText: '${mem.learnedEntries.length}',
                    onTap: mem.isLearningNow
                        ? null
                        : () async {
                            _showToast(
                                'Analiziram kodo in pogovor z modelom ${widget.brain.activeLocalModel}...');
                            final count =
                                await widget.brain.triggerLearnPass();
                            _showToast(
                              count > 0
                                  ? 'Ultron se je naučil $count novih vzorcev'
                                  : 'Baza znanja je posodobljena (${mem.learnedEntries.length} pravil)',
                            );
                          },
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 8),

          HudActionButton(
            label: 'Modeli & Vault',
            icon: Icons.hub_outlined,
            compact: true,
            onTap: () => setState(() {
              _connectionsInitialTab = 0;
              _showConnectionsModal = true;
              _showPluginsModal = false;
            }),
          ),
          const SizedBox(width: 8),

          HudActionButton(
            label: 'Vtičniki',
            icon: Icons.extension_outlined,
            compact: true,
            onTap: () => setState(() {
              _showPluginsModal = true;
              _showConnectionsModal = false;
            }),
          ),
          const SizedBox(width: 8),

          HudActionButton(
            label: 'Koda',
            icon: Icons.code,
            compact: true,
            isPrimaryAccent: widget.brain.isVsCodeWindowOpen,
            onTap: widget.brain.toggleVsCodeWindow,
          ),
          const SizedBox(width: 6),

          if (widget.brain.messages.isNotEmpty)
            IconButton(
              tooltip: 'Počisti trenutni pogovor',
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.delete_outline_rounded,
                  size: 17, color: hud.textMuted),
              onPressed: widget.brain.clearConversation,
            ),

          IconButton(
            tooltip: widget.isDarkMode ? 'Svetli način' : 'Temni način',
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
    );
  }

  Widget _buildCenterConversationStage(UltronHudTheme hud) {
    if (widget.brain.messages.isEmpty) {
      return Center(
        child: IgnorePointer(
          child: Padding(
            padding: const EdgeInsets.only(top: 250),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.brain.activeLocalModel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.6,
                    color: hud.textMuted.alphaPct(0.85),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Pripni poljubno datoteko (.docx, .pdf, kodo, sliko) ali vpiši ukaz',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: hud.textMuted.alphaPct(0.60),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 790),
        child: ListView.builder(
          controller: _chatScrollCtrl,
          padding: const EdgeInsets.fromLTRB(32, 62, 32, 18),
          itemCount: widget.brain.messages.length,
          itemBuilder: (context, index) {
            final msg = widget.brain.messages[index];
            final isUser = msg.role == 'user';

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Align(
                alignment:
                    isUser ? Alignment.centerRight : Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 15, vertical: 11),
                    decoration: BoxDecoration(
                      color: isUser
                          ? hud.primaryPeriwinkle.alphaPct(0.14)
                          : hud.bgPanel.alphaPct(0.76),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: isUser
                            ? hud.primaryPeriwinkle.alphaPct(0.38)
                            : hud.borderLine.alphaPct(0.70),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (msg.attachedFileNames.isNotEmpty) ...[
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: msg.attachedFileNames.map((fName) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: hud.bgInput.alphaPct(0.85),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.attach_file,
                                        size: 11,
                                        color: hud.primaryPeriwinkle),
                                    const SizedBox(width: 4),
                                    Text(
                                      fName,
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          color: hud.textMuted),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 6),
                        ],
                        SelectableText(
                          msg.content.isEmpty && msg.isStreaming
                              ? '...'
                              : msg.content,
                          style: TextStyle(
                            fontSize: 13.2,
                            height: 1.52,
                            color: hud.textPrimary,
                          ),
                        ),
                        if (!isUser) ...[
                          const SizedBox(height: 5),
                          Text(
                            msg.modelName,
                            style: TextStyle(
                              fontSize: 10,
                              color: hud.textMuted.alphaPct(0.68),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBottomPromptDeck(UltronHudTheme hud) {
    final attachments = widget.brain.pendingAttachments;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 790),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Animirana vrstica pripetih datotek nad vnosnim poljem
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
                                  color:
                                      hud.primaryPeriwinkle.alphaPct(0.50),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.insert_drive_file_outlined,
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
                                    onTap: () => widget.brain
                                        .removeAttachment(att.path),
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

              // Minimalistična ukazna vrstica
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: hud.bgPanel.alphaPct(0.90),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: hud.borderLine.alphaPct(0.90),
                    width: 1.0,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.alphaPct(0.18),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
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
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 140),
                        child: TextField(
                          controller: _promptCtrl,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _submitPrompt(),
                          onChanged: (_) {
                            _keystrokeRipple =
                                (_keystrokeRipple + 0.35).clamp(0.0, 1.0);
                            widget.brain.notifyUserTyping();
                          },
                          style: TextStyle(
                            fontSize: 13.2,
                            color: hud.textPrimary,
                          ),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 9),
                            hintText:
                                'Vprašaj ${widget.brain.activeLocalModel} ali priloži vaje / kodo...',
                            hintStyle: TextStyle(
                              fontSize: 12.8,
                              color: hud.textMuted.alphaPct(0.75),
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip:
                          widget.brain.isGenerating ? 'Ustavi' : 'Pošlji',
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
                          : _submitPrompt,
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