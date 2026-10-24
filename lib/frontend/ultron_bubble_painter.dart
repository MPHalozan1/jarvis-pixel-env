import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'ultron_hud_theme.dart';

// Stanja osrednje in mini nevronske krogle ULTRON
enum OrbState {
  standby,
  listening,
  thinking,
  answering,
  error,
}

//**************
// Posamezna 3D vezalna nit na površini holografske sfere *
//**************
class CircuitStrand {
  final int layer;
  final List<List<double>> points;
  final double phaseOffset;

  const CircuitStrand({
    required this.layer,
    required this.points,
    required this.phaseOffset,
  });
}

//**************
// Sinaptični delec za prostorski globinski učinek okoli jedra *
//**************
class SynapticParticle {
  final double theta;
  final double phi;
  final double radiusFactor;
  final double speedFactor;
  final double size;

  const SynapticParticle({
    required this.theta,
    required this.phi,
    required this.radiusFactor,
    required this.speedFactor,
    required this.size,
  });
}

//**************
// Predpomnilnik 3D geometrije krogle z ločenim ultra-lahkim naborom za Mini Chat kroglo *
//**************
class OrbGeometryCache {
  static final OrbGeometryCache instance = OrbGeometryCache._internal();

  late final List<CircuitStrand> strands;
  late final List<CircuitStrand> miniStrands;
  late final List<SynapticParticle> synapticParticles;
  late final List<SynapticParticle> miniParticles;

  OrbGeometryCache._internal() {
    final rng = math.Random(42);
    final generatedStrands = <CircuitStrand>[];

    for (int layer = 0; layer < 2; layer++) {
      final double rScale = layer == 0 ? 1.0 : 0.72;
      final int count = layer == 0 ? 28 : 18;

      for (int i = 0; i < count; i++) {
        final double baseLat = (rng.nextDouble() - 0.5) * math.pi * 0.92;
        final double baseLon = rng.nextDouble() * math.pi * 2;
        final int segments = 14 + rng.nextInt(10);
        final pts = <List<double>>[];

        double curLat = baseLat;
        double curLon = baseLon;
        for (int s = 0; s < segments; s++) {
          final double x = rScale * math.cos(curLat) * math.cos(curLon);
          final double y = rScale * math.sin(curLat);
          final double z = rScale * math.cos(curLat) * math.sin(curLon);
          pts.add([x, y, z]);

          curLon += 0.11 + (s.isEven ? 0.04 : -0.02);
          curLat += (s % 3 == 0 ? 0.05 : -0.025);
          curLat = curLat.clamp(-1.42, 1.42);
        }

        generatedStrands.add(
          CircuitStrand(
            layer: layer,
            points: pts,
            phaseOffset: rng.nextDouble() * math.pi * 2,
          ),
        );
      }
    }
    strands = List.unmodifiable(generatedStrands);
    // Mini nabor (samo 10 niti) za izjemno varčen izris v oblačku klepeta
    miniStrands = List.unmodifiable(generatedStrands.take(10).toList());

    final generatedParticles = <SynapticParticle>[];
    for (int i = 0; i < 44; i++) {
      generatedParticles.add(
        SynapticParticle(
          theta: rng.nextDouble() * math.pi * 2,
          phi: math.acos(2 * rng.nextDouble() - 1),
          radiusFactor: 0.52 + rng.nextDouble() * 0.66,
          speedFactor: 0.55 + rng.nextDouble() * 1.15,
          size: 1.1 + rng.nextDouble() * 1.9,
        ),
      );
    }
    synapticParticles = List.unmodifiable(generatedParticles);
    miniParticles = List.unmodifiable(generatedParticles.take(8).toList());
  }
}

//**************
// Vizualni parametri krogle z gladko interpolacijo med stanji *
//**************
class OrbVisualParams {
  static const int strandCount = 46;
  static const double glowIntensity = 1.0;
  static const double rotationSpeed = 0.45;

  final double shellSpinMultiplier;
  final double ringDriftMultiplier;
  final double glowScale;
  final double coreBrightness;
  final double beamBrightness;
  final double outwardPulseStrength;
  final double errorTintMix;

  const OrbVisualParams({
    required this.shellSpinMultiplier,
    required this.ringDriftMultiplier,
    required this.glowScale,
    required this.coreBrightness,
    required this.beamBrightness,
    required this.outwardPulseStrength,
    required this.errorTintMix,
  });

  static OrbVisualParams forState(OrbState state) {
    switch (state) {
      case OrbState.standby:
        return const OrbVisualParams(
          shellSpinMultiplier: 1.0,
          ringDriftMultiplier: 1.0,
          glowScale: 1.0,
          coreBrightness: 0.55,
          beamBrightness: 0.35,
          outwardPulseStrength: 0.04,
          errorTintMix: 0.0,
        );
      case OrbState.listening:
        return const OrbVisualParams(
          shellSpinMultiplier: 1.45,
          ringDriftMultiplier: 1.35,
          glowScale: 1.12,
          coreBrightness: 0.76,
          beamBrightness: 0.55,
          outwardPulseStrength: 0.08,
          errorTintMix: 0.0,
        );
      case OrbState.thinking:
        return const OrbVisualParams(
          shellSpinMultiplier: 2.35,
          ringDriftMultiplier: 2.1,
          glowScale: 1.24,
          coreBrightness: 0.92,
          beamBrightness: 0.85,
          outwardPulseStrength: 0.14,
          errorTintMix: 0.0,
        );
      case OrbState.answering:
        return const OrbVisualParams(
          shellSpinMultiplier: 1.75,
          ringDriftMultiplier: 1.65,
          glowScale: 1.18,
          coreBrightness: 0.86,
          beamBrightness: 0.72,
          outwardPulseStrength: 0.11,
          errorTintMix: 0.0,
        );
      case OrbState.error:
        return const OrbVisualParams(
          shellSpinMultiplier: 0.65,
          ringDriftMultiplier: 0.75,
          glowScale: 1.08,
          coreBrightness: 0.80,
          beamBrightness: 0.60,
          outwardPulseStrength: 0.09,
          errorTintMix: 1.0,
        );
    }
  }

  static OrbVisualParams lerp(OrbVisualParams a, OrbVisualParams b, double t) {
    return OrbVisualParams(
      shellSpinMultiplier:
          lerpDouble(a.shellSpinMultiplier, b.shellSpinMultiplier, t)!,
      ringDriftMultiplier:
          lerpDouble(a.ringDriftMultiplier, b.ringDriftMultiplier, t)!,
      glowScale: lerpDouble(a.glowScale, b.glowScale, t)!,
      coreBrightness: lerpDouble(a.coreBrightness, b.coreBrightness, t)!,
      beamBrightness: lerpDouble(a.beamBrightness, b.beamBrightness, t)!,
      outwardPulseStrength:
          lerpDouble(a.outwardPulseStrength, b.outwardPulseStrength, t)!,
      errorTintMix: lerpDouble(a.errorTintMix, b.errorTintMix, t)!,
    );
  }
}

//**************
// Varčna mini 3D krogla znotraj oblačka klepeta LLM-ja *
// Animira se SAMO med razmišljanjem ali izpisovanjem in se samodejno ustavi ob zaključku *
//**************
class UltronMiniChatOrb extends StatefulWidget {
  final bool isAnimating;
  final OrbState activeState;
  final double size;

  const UltronMiniChatOrb({
    super.key,
    required this.isAnimating,
    required this.activeState,
    this.size = 26.0,
  });

  @override
  State<UltronMiniChatOrb> createState() => _UltronMiniChatOrbState();
}

class _UltronMiniChatOrbState extends State<UltronMiniChatOrb>
    with SingleTickerProviderStateMixin {
  Ticker? _miniTicker;
  Duration _lastElapsed = Duration.zero;
  double _angleY = 0.4;
  double _ringY = 0.0;
  double _pulse = 0.0;

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant UltronMiniChatOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isAnimating != widget.isAnimating) {
      _syncTicker();
    }
  }

  void _syncTicker() {
    if (widget.isAnimating) {
      if (_miniTicker != null && _miniTicker!.isActive) return;
      _lastElapsed = Duration.zero;
      _miniTicker ??= createTicker((elapsed) {
        final double dt = _lastElapsed == Duration.zero
            ? 0.016
            : ((elapsed - _lastElapsed).inMicroseconds / 1000000.0)
                .clamp(0.001, 0.05);
        _lastElapsed = elapsed;
        setState(() {
          _angleY += dt * 1.15;
          _ringY -= dt * 0.85;
          _pulse += dt;
        });
      });
      _miniTicker!.start();
    } else {
      _miniTicker?.stop();
      _lastElapsed = Duration.zero;
    }
  }

  @override
  void dispose() {
    _miniTicker?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = widget.isAnimating ? widget.activeState : OrbState.standby;

    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: UltronWireframeOrbPainter(
            shellAngleY: _angleY,
            ringAngleY: _ringY,
            beamDriftPhase: _pulse,
            pulseClock: _pulse,
            subtleKeystrokeRipple: 0.0,
            params: OrbVisualParams.forState(state),
            isDarkMode: isDark,
            customPrimaryColor: hud.primaryPeriwinkle,
            customSecondaryColor: hud.secondaryVioletBloom,
            glowMultiplier: hud.orbGlowMultiplier,
            miniMode: true,
          ),
        ),
      ),
    );
  }
}

//**************
// Glavni in Mini 3D holografski izrisovalnik ULTRON nevronske krogle *
//**************
class UltronWireframeOrbPainter extends CustomPainter {
  final double shellAngleY;
  final double ringAngleY;
  final double beamDriftPhase;
  final double pulseClock;
  final double subtleKeystrokeRipple;
  final OrbVisualParams params;
  final bool isDarkMode;
  final Color? customPrimaryColor;
  final Color? customSecondaryColor;
  final double glowMultiplier;
  final bool miniMode;

  const UltronWireframeOrbPainter({
    required this.shellAngleY,
    required this.ringAngleY,
    required this.beamDriftPhase,
    required this.pulseClock,
    required this.subtleKeystrokeRipple,
    required this.params,
    this.isDarkMode = true,
    this.customPrimaryColor,
    this.customSecondaryColor,
    this.glowMultiplier = 1.0,
    this.miniMode = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width * 0.5, size.height * 0.5);
    final double baseRadius =
        math.min(size.width, size.height) * (miniMode ? 0.39 : 0.34);
    final double breath =
        1.0 + math.sin(pulseClock * 2.1) * params.outwardPulseStrength * 0.45;
    final double rippleScale = 1.0 + subtleKeystrokeRipple * 0.065;
    final double orbRadius = baseRadius * breath * rippleScale;

    final Color basePrimary = customPrimaryColor ??
        (isDarkMode ? const Color(0xFF8EA8FF) : const Color(0xFF3B5BDB));
    final Color baseSecondary = customSecondaryColor ??
        (isDarkMode ? const Color(0xFF7B68EE) : const Color(0xFF6741D9));
    const Color errorRed = Color(0xFFFF5C77);

    final Color primaryTone =
        Color.lerp(basePrimary, errorRed, params.errorTintMix)!;
    final Color secondaryTone = Color.lerp(
        baseSecondary, const Color(0xFFFF8787), params.errorTintMix)!;

    final double effectiveGlow = glowMultiplier.clamp(0.4, 1.8);

    // 1. Atmosferski sij
    final double glowR =
        orbRadius * (miniMode ? 1.25 : 1.55) * params.glowScale;
    final Paint auraPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          primaryTone.alphaPct(
              ((isDarkMode ? 0.24 : 0.16) * params.coreBrightness * effectiveGlow)
                  .clamp(0.0, 0.9)),
          secondaryTone.alphaPct(
              ((isDarkMode ? 0.10 : 0.06) * params.coreBrightness * effectiveGlow)
                  .clamp(0.0, 0.7)),
          primaryTone.alphaPct(0.0),
        ],
        stops: const [0.0, 0.48, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: glowR));
    canvas.drawCircle(center, glowR, auraPaint);

    // 2. Diagonalni energijski žarek (preskočimo v mini načinu za čistost)
    if (!miniMode) {
      final double beamAngle = -0.58 + math.sin(beamDriftPhase * 0.7) * 0.08;
      final Offset beamOffset = Offset(
        math.cos(beamAngle) * orbRadius * 1.32,
        math.sin(beamAngle) * orbRadius * 1.32,
      );
      final Paint beamPaint = Paint()
        ..strokeWidth = 2.0 + subtleKeystrokeRipple * 1.6
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: [
            primaryTone.alphaPct(0.0),
            secondaryTone.alphaPct(0.45 * params.beamBrightness),
            Colors.white.alphaPct(
                (isDarkMode ? 0.72 : 0.45) * params.beamBrightness),
            secondaryTone.alphaPct(0.45 * params.beamBrightness),
            primaryTone.alphaPct(0.0),
          ],
          stops: const [0.0, 0.30, 0.50, 0.70, 1.0],
        ).createShader(
          Rect.fromPoints(center - beamOffset, center + beamOffset),
        );
      canvas.drawLine(center - beamOffset, center + beamOffset, beamPaint);
    }

    // 3. 3D mreža nevronskih niti (polna ali varčna mini mreža)
    final cache = OrbGeometryCache.instance;
    final activeStrands = miniMode ? cache.miniStrands : cache.strands;
    final double cosY = math.cos(shellAngleY);
    final double sinY = math.sin(shellAngleY);
    const double tiltX = 0.28;
    final double cosX = math.cos(tiltX);
    final double sinX = math.sin(tiltX);

    final Paint strandPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Path strandPath = Path();

    for (final strand in activeStrands) {
      strandPath.reset();
      double avgZ = 0.0;
      final double layerSpin = strand.layer == 0 ? 1.0 : -1.35;
      final double localCosY =
          strand.layer == 0 ? cosY : math.cos(shellAngleY * layerSpin);
      final double localSinY =
          strand.layer == 0 ? sinY : math.sin(shellAngleY * layerSpin);

      for (int i = 0; i < strand.points.length; i++) {
        final pt = strand.points[i];
        final double x1 = pt[0] * localCosY - pt[2] * localSinY;
        final double z1 = pt[0] * localSinY + pt[2] * localCosY;
        final double y2 = pt[1] * cosX - z1 * sinX;
        final double z2 = pt[1] * sinX + z1 * cosX;

        avgZ += z2;
        final double perspective = 2.6 / (2.6 - z2 * 0.55);
        final double sx = center.dx + x1 * orbRadius * perspective;
        final double sy = center.dy + y2 * orbRadius * perspective;

        if (i == 0) {
          strandPath.moveTo(sx, sy);
        } else {
          strandPath.lineTo(sx, sy);
        }
      }

      avgZ /= strand.points.length;
      final double depthFactor = ((avgZ + 1.0) * 0.5).clamp(0.12, 1.0);
      final double shimmer =
          0.72 + 0.28 * math.sin(pulseClock * 2.8 + strand.phaseOffset);

      final Color lineColor = strand.layer == 0 ? primaryTone : secondaryTone;
      final double opacity =
          (depthFactor * shimmer * (isDarkMode ? 0.68 : 0.56) * effectiveGlow)
              .clamp(0.10, 0.95);

      strandPaint
        ..color = lineColor.alphaPct(opacity)
        ..strokeWidth = miniMode
            ? 1.0
            : (strand.layer == 0 ? 1.25 : 0.95) * (0.75 + depthFactor * 0.45);

      canvas.drawPath(strandPath, strandPaint);
    }

    // 4. Orbitalni obroč
    final Path ringPath = Path();
    final int ringSteps = miniMode ? 24 : 64;
    const double ringTilt = 0.52;
    final double cosRT = math.cos(ringTilt);
    final double sinRT = math.sin(ringTilt);
    final double ringR = orbRadius * 1.18;

    for (int i = 0; i <= ringSteps; i++) {
      final double t = (i / ringSteps) * math.pi * 2 + ringAngleY;
      final double rx = math.cos(t) * ringR;
      final double rz = math.sin(t) * ringR;
      final double ry = rz * sinRT;
      final double depthZ = rz * cosRT / ringR;
      final double persp = 2.8 / (2.8 - depthZ * 0.45);

      final double px = center.dx + rx * persp;
      final double py = center.dy + ry * persp;
      if (i == 0) {
        ringPath.moveTo(px, py);
      } else {
        ringPath.lineTo(px, py);
      }
    }

    canvas.drawPath(
      ringPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = miniMode ? 0.85 : 1.15
        ..color = primaryTone.alphaPct(isDarkMode ? 0.45 : 0.36),
    );

    // 5. Sinaptični delci
    final activeParticles =
        miniMode ? cache.miniParticles : cache.synapticParticles;
    final Paint particlePaint = Paint()..style = PaintingStyle.fill;
    for (final p in activeParticles) {
      final double angle = p.theta + shellAngleY * p.speedFactor;
      final double sinPhi = math.sin(p.phi);
      final double px3 = p.radiusFactor * sinPhi * math.cos(angle);
      final double py3 = p.radiusFactor * math.cos(p.phi);
      final double pz3 = p.radiusFactor * sinPhi * math.sin(angle);

      final double depth = ((pz3 + 1.2) / 2.4).clamp(0.15, 1.0);
      particlePaint.color = primaryTone.alphaPct(
        (depth * 0.65 * params.coreBrightness).clamp(0.10, 0.95),
      );
      canvas.drawCircle(
        Offset(center.dx + px3 * orbRadius, center.dy + py3 * orbRadius),
        (miniMode ? 0.8 : p.size) * (0.7 + depth * 0.5),
        particlePaint,
      );
    }

    // 6. Svetlo jedro
    final double coreR = orbRadius * (miniMode ? 0.36 : 0.28);
    final Paint corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.alphaPct(
              (isDarkMode ? 0.88 : 0.72) * params.coreBrightness),
          primaryTone.alphaPct(0.45 * params.coreBrightness),
          primaryTone.alphaPct(0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: coreR));
    canvas.drawCircle(center, coreR, corePaint);
  }

  @override
  bool shouldRepaint(covariant UltronWireframeOrbPainter oldDelegate) {
    return oldDelegate.shellAngleY != shellAngleY ||
        oldDelegate.ringAngleY != ringAngleY ||
        oldDelegate.pulseClock != pulseClock ||
        oldDelegate.subtleKeystrokeRipple != subtleKeystrokeRipple ||
        oldDelegate.isDarkMode != isDarkMode ||
        oldDelegate.miniMode != miniMode ||
        oldDelegate.customPrimaryColor != customPrimaryColor ||
        oldDelegate.glowMultiplier != glowMultiplier ||
        oldDelegate.params.coreBrightness != params.coreBrightness;
  }
}