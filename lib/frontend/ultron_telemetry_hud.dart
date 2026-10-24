import 'dart:ui';
import 'package:flutter/material.dart';
import '../backend/ultron_telemetry_service.dart';
import 'ultron_hud_theme.dart';

//**************
// Gladko animirana vrstica v zgornjem HUD-u za živi prikaz porabe ULTRON + LLM *
// V lastnem RepaintBoundary sloju za ničelno obremenitev glavnega okna *
//**************
class UltronLiveTelemetryPill extends StatefulWidget {
  final UltronProcessTelemetryService telemetry;
  final bool isExpanded;
  final VoidCallback onTap;

  const UltronLiveTelemetryPill({
    super.key,
    required this.telemetry,
    required this.isExpanded,
    required this.onTap,
  });

  @override
  State<UltronLiveTelemetryPill> createState() =>
      _UltronLiveTelemetryPillState();
}

class _UltronLiveTelemetryPillState extends State<UltronLiveTelemetryPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _smoothCtrl;
  UltronResourceSnapshot _fromSnap = const UltronResourceSnapshot();
  UltronResourceSnapshot _toSnap = const UltronResourceSnapshot();
  bool _hovered = false;

  @override
  void initState() {
    super.initState();
    _fromSnap = widget.telemetry.latest;
    _toSnap = widget.telemetry.latest;
    _smoothCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    widget.telemetry.addListener(_onNewTelemetry);
  }

  @override
  void dispose() {
    widget.telemetry.removeListener(_onNewTelemetry);
    _smoothCtrl.dispose();
    super.dispose();
  }

  void _onNewTelemetry() {
    if (!mounted) return;
    final t = Curves.easeOutCubic.transform(_smoothCtrl.value);
    _fromSnap = _lerpSnapshot(_fromSnap, _toSnap, t);
    _toSnap = widget.telemetry.latest;
    _smoothCtrl.forward(from: 0.0);
  }

  UltronResourceSnapshot _lerpSnapshot(
    UltronResourceSnapshot a,
    UltronResourceSnapshot b,
    double t,
  ) {
    return UltronResourceSnapshot(
      appCpuPercent: lerpDouble(a.appCpuPercent, b.appCpuPercent, t) ?? 0.0,
      llmCpuPercent: lerpDouble(a.llmCpuPercent, b.llmCpuPercent, t) ?? 0.0,
      appGpuPercent: lerpDouble(a.appGpuPercent, b.appGpuPercent, t) ?? 0.0,
      llmGpuPercent: lerpDouble(a.llmGpuPercent, b.llmGpuPercent, t) ?? 0.0,
      appRamBytes: lerpDouble(a.appRamBytes, b.appRamBytes, t)?.round() ?? 0,
      llmRamBytes: lerpDouble(a.llmRamBytes, b.llmRamBytes, t)?.round() ?? 0,
      appVramBytes: lerpDouble(a.appVramBytes, b.appVramBytes, t)?.round() ?? 0,
      llmVramBytes: lerpDouble(a.llmVramBytes, b.llmVramBytes, t)?.round() ?? 0,
      activeRunnerModel: b.activeRunnerModel,
      isModelLoadedInMemory: b.isModelLoadedInMemory,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedBuilder(
            animation: _smoothCtrl,
            builder: (context, _) {
              final curved = Curves.easeOutCubic.transform(_smoothCtrl.value);
              final cur = _lerpSnapshot(_fromSnap, _toSnap, curved);

              return AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: widget.isExpanded || _hovered
                      ? hud.bgInput.alphaPct(0.95)
                      : hud.bgPanel.alphaPct(0.84),
                  borderRadius: BorderRadius.circular(hud.cutRadius * 0.8),
                  border: Border.all(
                    color: widget.isExpanded || _hovered
                        ? hud.primaryPeriwinkle.alphaPct(0.65)
                        : hud.borderLine.alphaPct(0.85),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MiniMetricItem(
                      label: 'CPU',
                      valueText: '${cur.totalCpuPercent.toStringAsFixed(1)}%',
                      fillRatio: (cur.totalCpuPercent / 100.0).clamp(0.0, 1.0),
                      barColor: hud.primaryPeriwinkle,
                      hud: hud,
                    ),
                    _divider(hud),
                    _MiniMetricItem(
                      label: 'GPU',
                      valueText: '${cur.totalGpuPercent.toStringAsFixed(0)}%',
                      fillRatio: (cur.totalGpuPercent / 100.0).clamp(0.0, 1.0),
                      barColor: hud.accentSuccessGreen,
                      hud: hud,
                    ),
                    _divider(hud),
                    _MiniMetricItem(
                      label: 'RAM',
                      valueText:
                          UltronResourceSnapshot.formatBytes(cur.totalRamBytes),
                      fillRatio: (cur.totalRamBytes / (8.0 * 1024 * 1024 * 1024))
                          .clamp(0.0, 1.0),
                      barColor: hud.secondaryVioletBloom,
                      hud: hud,
                    ),
                    _divider(hud),
                    _MiniMetricItem(
                      label: 'VRAM',
                      valueText: UltronResourceSnapshot.formatBytes(
                          cur.totalVramBytes),
                      fillRatio:
                          (cur.totalVramBytes / (10.0 * 1024 * 1024 * 1024))
                              .clamp(0.0, 1.0),
                      barColor: cur.totalVramBytes > 8.2 * 1024 * 1024 * 1024
                          ? hud.accentWarningAmber
                          : hud.primaryPeriwinkle,
                      hud: hud,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _divider(UltronHudTheme hud) {
    return Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 7),
      color: hud.borderLine.alphaPct(0.75),
    );
  }
}

class _MiniMetricItem extends StatelessWidget {
  final String label;
  final String valueText;
  final double fillRatio;
  final Color barColor;
  final UltronHudTheme hud;

  const _MiniMetricItem({
    required this.label,
    required this.valueText,
    required this.fillRatio,
    required this.barColor,
    required this.hud,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 9.2,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
                color: hud.textMuted,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              valueText,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: hud.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2.5),
        Container(
          width: 46,
          height: 2.6,
          decoration: BoxDecoration(
            color: hud.bgDeep.alphaPct(0.85),
            borderRadius: BorderRadius.circular(2),
          ),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: fillRatio.clamp(0.04, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: barColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

//**************
// Razširjeno okno s podrobno razčlenitvijo porabe (ločeno ULTRON aplikacija vs. Lokalni LLM) *
// Vključuje živ graf obremenitve in gumb za 1-klik sprostitev LLM-ja iz VRAM-a *
//**************
class UltronTelemetryDetailPopover extends StatelessWidget {
  final UltronProcessTelemetryService telemetry;
  final String activeModelFallback;
  final VoidCallback onClose;
  final ValueChanged<String>? onToast;

  const UltronTelemetryDetailPopover({
    super.key,
    required this.telemetry,
    required this.activeModelFallback,
    required this.onClose,
    this.onToast,
  });

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;

    return ListenableBuilder(
      listenable: telemetry,
      builder: (context, _) {
        final snap = telemetry.latest;

        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          builder: (context, val, child) => Opacity(
            opacity: val,
            child: Transform.translate(
              offset: Offset(0, (1.0 - val) * -8.0),
              child: child,
            ),
          ),
          child: SizedBox(
            width: 345,
            child: HudBracketPanel(
              padding: const EdgeInsets.all(14),
              fillColor: hud.bgPanel.alphaPct(0.97),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.speed_rounded,
                          size: 16, color: hud.primaryPeriwinkle),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'Poraba virov (Samo ULTRON + LLM)',
                          style: TextStyle(
                            fontSize: 12.2,
                            fontWeight: FontWeight.w700,
                            color: hud.textPrimary,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: onClose,
                        child: Icon(Icons.close_rounded,
                            size: 16, color: hud.textMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Živi sparkline graf CPU + GPU obremenitve
                  Container(
                    height: 56,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: hud.bgDeep.alphaPct(0.82),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: hud.borderLine.alphaPct(0.75)),
                    ),
                    child: CustomPaint(
                      painter: _DualSparklinePainter(
                        cpuSeries: telemetry.cpuHistory,
                        gpuSeries: telemetry.gpuHistory,
                        cpuColor: hud.primaryPeriwinkle,
                        gpuColor: hud.accentSuccessGreen,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _legendDot(hud.primaryPeriwinkle,
                          'Skupaj CPU: ${snap.totalCpuPercent.toStringAsFixed(1)}%', hud),
                      const Spacer(),
                      _legendDot(hud.accentSuccessGreen,
                          'Skupaj GPU: ${snap.totalGpuPercent.toStringAsFixed(1)}%', hud),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Divider(height: 1, color: hud.borderLine.alphaPct(0.75)),
                  const SizedBox(height: 10),

                  // 1. ULTRON Aplikacija
                  Text(
                    '1. ULTRON Aplikacija (vmesnik)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: hud.primaryPeriwinkle,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _buildProcessRow(
                    hud: hud,
                    cpu: '${snap.appCpuPercent.toStringAsFixed(1)}%',
                    gpu: '${snap.appGpuPercent.toStringAsFixed(1)}%',
                    ram: UltronResourceSnapshot.formatBytes(snap.appRamBytes),
                    vram: UltronResourceSnapshot.formatBytes(snap.appVramBytes),
                  ),

                  const SizedBox(height: 10),

                  // 2. Lokalni LLM model
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '2. Lokalni LLM (${snap.activeRunnerModel.isNotEmpty ? snap.activeRunnerModel : "V pripravljenosti"})',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: hud.accentSuccessGreen,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  _buildProcessRow(
                    hud: hud,
                    cpu: '${snap.llmCpuPercent.toStringAsFixed(1)}%',
                    gpu: '${snap.llmGpuPercent.toStringAsFixed(1)}%',
                    ram: UltronResourceSnapshot.formatBytes(snap.llmRamBytes),
                    vram: UltronResourceSnapshot.formatBytes(snap.llmVramBytes),
                  ),

                  if (snap.isModelLoadedInMemory) ...[
                    const SizedBox(height: 12),
                    HudActionButton(
                      label: telemetry.isUnloadingVram
                          ? 'Sproščam pomnilnik...'
                          : 'Sprosti LLM iz VRAM / RAM zdaj',
                      icon: Icons.cleaning_services_rounded,
                      compact: true,
                      isPrimaryAccent: true,
                      accentColor: hud.accentWarningAmber,
                      onTap: telemetry.isUnloadingVram
                          ? null
                          : () async {
                              final ok = await telemetry
                                  .unloadActiveModelFromMemory(
                                      activeModelFallback);
                              onToast?.call(
                                ok
                                    ? 'LLM sproščen iz VRAM-a in RAM-a'
                                    : 'Model je že sproščen',
                              );
                            },
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _legendDot(Color c, String text, UltronHudTheme hud) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: 10.5,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: hud.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildProcessRow({
    required UltronHudTheme hud,
    required String cpu,
    required String gpu,
    required String ram,
    required String vram,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: hud.bgInput.alphaPct(0.55),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: hud.borderLine.alphaPct(0.7)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _kv('CPU', cpu, hud),
          _kv('GPU', gpu, hud),
          _kv('RAM', ram, hud),
          _kv('VRAM', vram, hud),
        ],
      ),
    );
  }

  Widget _kv(String k, String v, UltronHudTheme hud) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k, style: TextStyle(fontSize: 9.5, color: hud.textMuted)),
        const SizedBox(height: 1),
        Text(
          v,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
            color: hud.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _DualSparklinePainter extends CustomPainter {
  final List<double> cpuSeries;
  final List<double> gpuSeries;
  final Color cpuColor;
  final Color gpuColor;

  const _DualSparklinePainter({
    required this.cpuSeries,
    required this.gpuSeries,
    required this.cpuColor,
    required this.gpuColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawLine(canvas, size, gpuSeries, gpuColor, fillAlpha: 0.12);
    _drawLine(canvas, size, cpuSeries, cpuColor, fillAlpha: 0.16);
  }

  void _drawLine(
    Canvas canvas,
    Size size,
    List<double> values,
    Color color, {
    required double fillAlpha,
  }) {
    if (values.length < 2) return;
    final path = Path();
    final fillPath = Path();
    final double stepX = size.width / (values.length - 1);

    for (int i = 0; i < values.length; i++) {
      final double x = i * stepX;
      final double norm = (values[i] / 100.0).clamp(0.0, 1.0);
      final double y = size.height - (norm * (size.height - 4)) - 2;
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = color.alphaPct(fillAlpha),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _DualSparklinePainter oldDelegate) => true;
}