import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'ultron_hud_theme.dart';

// Stanja osrednje nevronske krogle
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
// Predpomnilnik 3D geometrije krogle za ničelno obremenitev pomnilnika med izrisom *
// Zagotavlja tekoče delovanje pri 60 Hz in 240 Hz *
//**************
class OrbGeometryCache {
  static final OrbGeometryCache instance = OrbGeometryCache._internal();

  late final List<CircuitStrand> strands;
  late final List<SynapticParticle> synapticParticles;

  OrbGeometryCache._internal() {
    final rng = math.Random(42);
    final generatedStrands = <CircuitStrand>[];

    // Ustvarimo dve gnezdeni lupini nevronskih niti
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

    // Ustvarimo sinaptične delce
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
// Glavni 3D holografski izrisovalnik Ultron nevronske krogle *
// Optimiziran za minimalno porabo CPE in GPE brez izgube vizualnih učinkov *
//**************
class UltronWireframeOrbPainter extends CustomPainter {
  final double shellAngleY;
  final double ringAngleY;
  final double beamDriftPhase;
  final double pulseClock;
  final double subtleKeystrokeRipple;
  final OrbVisualParams params;
  final bool isDarkMode;

  const UltronWireframeOrbPainter({
    required this.shellAngleY,
    required this.ringAngleY,
    required this.beamDriftPhase,
    required this.pulseClock,
    required this.subtleKeystrokeRipple,
    required this.params,
    this.isDarkMode = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width * 0.5, size.height * 0.5);
    final double baseRadius = math.min(size.width, size.height) * 0.34;
    final double breath =
        1.0 + math.sin(pulseClock * 2.1) * params.outwardPulseStrength * 0.45;
    final double rippleScale = 1.0 + subtleKeystrokeRipple * 0.065;
    final double orbRadius = baseRadius * breath * rippleScale;

    final Color baseBlue = isDarkMode
        ? const Color(0xFF8EA8FF)
        : const Color(0xFF3B5BDB);
    final Color baseViolet = isDarkMode
        ? const Color(0xFF7B68EE)
        : const Color(0xFF6741D9);
    final Color errorRed = const Color(0xFFFF5C77);

    final Color primaryTone =
        Color.lerp(baseBlue, errorRed, params.errorTintMix)!;
    final Color secondaryTone =
        Color.lerp(baseViolet, const Color(0xFFFF8787), params.errorTintMix)!;

    // 1. Mehak atmosferski sij v ozadju jedra
    final double glowR = orbRadius * 1.55 * params.glowScale;
    final Paint auraPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          primaryTone.alphaPct(
              (isDarkMode ? 0.24 : 0.16) * params.coreBrightness),
          secondaryTone.alphaPct(
              (isDarkMode ? 0.10 : 0.06) * params.coreBrightness),
          primaryTone.alphaPct(0.0),
        ],
        stops: const [0.0, 0.48, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: glowR));
    canvas.drawCircle(center, glowR, auraPaint);

    // 2. Diagonalni energijski žarek skozi jedro
    final double beamAngle =
        -0.58 + math.sin(beamDriftPhase * 0.7) * 0.08;
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

    // 3. 3D gnezdena mreža nevronskih niti
    final cache = OrbGeometryCache.instance;
    final double cosY = math.cos(shellAngleY);
    final double sinY = math.sin(shellAngleY);
    const double tiltX = 0.28;
    final double cosX = math.cos(tiltX);
    final double sinX = math.sin(tiltX);

    final Paint strandPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final Path strandPath = Path();

    for (final strand in cache.strands) {
      strandPath.reset();
      double avgZ = 0.0;
      final double layerSpin = strand.layer == 0 ? 1.0 : -1.35;
      final double localCosY =
          strand.layer == 0 ? cosY : math.cos(shellAngleY * layerSpin);
      final double localSinY =
          strand.layer == 0 ? sinY : math.sin(shellAngleY * layerSpin);

      for (int i = 0; i < strand.points.length; i++) {
        final pt = strand.points[i];
        final double x0 = pt[0];
        final double y0 = pt[1];
        final double z0 = pt[2];

        // Rotacija okoli osi Y in nagib okoli osi X
        final double x1 = x0 * localCosY - z0 * localSinY;
        final double z1 = x0 * localSinY + z0 * localCosY;
        final double y2 = y0 * cosX - z1 * sinX;
        final double z2 = y0 * sinX + z1 * cosX;

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
      final double shimmer = 0.72 +
          0.28 * math.sin(pulseClock * 2.8 + strand.phaseOffset);

      final Color lineColor = strand.layer == 0 ? primaryTone : secondaryTone;
      final double opacity =
          (depthFactor * shimmer * (isDarkMode ? 0.62 : 0.52) +
                  subtleKeystrokeRipple * 0.18)
              .clamp(0.06, 0.92);

      strandPaint
        ..color = lineColor.alphaPct(opacity)
        ..strokeWidth = (strand.layer == 0 ? 1.25 : 0.95) *
            (0.75 + depthFactor * 0.45);

      canvas.drawPath(strandPath, strandPaint);
    }

    // 4. Nagnjen ekvatorialni orbitalni obroč
    final Path ringPath = Path();
    const int ringSteps = 64;
    const double ringTilt = 0.52;
    final double cosRT = math.cos(ringTilt);
    final double sinRT = math.sin(ringTilt);
    final double ringR = orbRadius * (1.22 + subtleKeystrokeRipple * 0.04);

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

    final Paint ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.15
      ..color = primaryTone.alphaPct(isDarkMode ? 0.42 : 0.35);
    canvas.drawPath(ringPath, ringPaint);

    // 5. Sinaptični delci
    final Paint particlePaint = Paint()..style = PaintingStyle.fill;
    for (final p in cache.synapticParticles) {
      final double angle = p.theta + shellAngleY * p.speedFactor;
      final double sinPhi = math.sin(p.phi);
      final double px3 = p.radiusFactor * sinPhi * math.cos(angle);
      final double py3 = p.radiusFactor * math.cos(p.phi);
      final double pz3 = p.radiusFactor * sinPhi * math.sin(angle);

      final double depth = ((pz3 + 1.2) / 2.4).clamp(0.15, 1.0);
      final double sx = center.dx + px3 * orbRadius;
      final double sy = center.dy + py3 * orbRadius;

      particlePaint.color = primaryTone.alphaPct(
        (depth * 0.65 * params.coreBrightness + subtleKeystrokeRipple * 0.2)
            .clamp(0.08, 0.95),
      );
      canvas.drawCircle(
        Offset(sx, sy),
        p.size * (0.7 + depth * 0.5),
        particlePaint,
      );
    }

    // 6. Svetlo jedro in odzivni val ob tipkanju
    final Paint corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.alphaPct(
              (isDarkMode ? 0.85 : 0.70) * params.coreBrightness),
          primaryTone.alphaPct(0.42 * params.coreBrightness),
          primaryTone.alphaPct(0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: orbRadius * 0.28));
    canvas.drawCircle(center, orbRadius * 0.28, corePaint);

    if (subtleKeystrokeRipple > 0.01) {
      final Paint ripplePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color =
            primaryTone.alphaPct((subtleKeystrokeRipple * 0.55).clamp(0.0, 0.8));
      canvas.drawCircle(
        center,
        orbRadius * (0.85 + (1.0 - subtleKeystrokeRipple) * 0.38),
        ripplePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant UltronWireframeOrbPainter oldDelegate) {
    return oldDelegate.shellAngleY != shellAngleY ||
        oldDelegate.ringAngleY != ringAngleY ||
        oldDelegate.beamDriftPhase != beamDriftPhase ||
        oldDelegate.pulseClock != pulseClock ||
        oldDelegate.subtleKeystrokeRipple != subtleKeystrokeRipple ||
        oldDelegate.isDarkMode != isDarkMode ||
        oldDelegate.params.coreBrightness != params.coreBrightness ||
        oldDelegate.params.errorTintMix != params.errorTintMix;
  }
}