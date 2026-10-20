import 'dart:math';
import 'package:flutter/material.dart';

//**********************************************************************
// PHASE 1 // IMAGE 1 PROCEDURAL 3D PCB/CIRCUIT WIREFRAME ORB          *
// - Thin 1px pale periwinkle (#A9A8FF) lines + #4B3FFF violet bloom   *
// - Jagged 45°/90° axis-snapped PCB traces with terminal hooks        *
// - 3 Nested Shells (Outer polar cage, Mid arcs, Inner hex honeycomb) *
// - Tilted Equatorial Band + Corner-to-Corner Diagonal Axis Beam      *
// - Five States: STANDBY, LISTENING, THINKING, ANSWERING, ERROR       *
//**********************************************************************

const int strandCount = 175;
const double glowIntensity = 0.68;
const double rotationSpeed = 0.24;

enum OrbState {
  standby,   // 1. Calm slow rotation, dim glow, lazy strand crawl
  listening, // 2. Input focused/typing: shells nearly hold, ring breathes gently
  thinking,  // 3. Request in flight: core mesh pulses, diagonal beam intensifies
  answering, // 4. Streaming: bright pulses travel outward along strands
  error,     // 5. Brief ~1s shift toward red/magenta (#FF2A6D), then STANDBY
}

enum ShellLayer {
  outerCage,
  midArcs,
  innerHexCore,
  equatorialRing,
  diagonalBeam,
}

class Vec3 {
  final double x;
  final double y;
  final double z;
  const Vec3(this.x, this.y, this.z);
}

class CircuitStrand {
  final ShellLayer layer;
  final List<Vec3> points;
  final double phaseOffset;

  const CircuitStrand({
    required this.layer,
    required this.points,
    required this.phaseOffset,
  });
}

// Generates the 3D jagged PCB strands once at startup with a fixed seed
class OrbGeometryCache {
  static final OrbGeometryCache instance = OrbGeometryCache._internal();
  late final List<CircuitStrand> strands;

  OrbGeometryCache._internal() {
    final rng = Random(42);
    final List<CircuitStrand> built = [];

    final outerCount = (strandCount * 0.34).round();
    final midCount = (strandCount * 0.20).round();
    final hexCount = (strandCount * 0.22).round();
    final eqCount = (strandCount * 0.14).round();
    final beamCount = strandCount - outerCount - midCount - hexCount - eqCount;

    // 1. OUTER SHELL: Fragmented polar bands & jagged PCB traces with 45°/90° kinks
    for (int i = 0; i < outerCount; i++) {
      final poleSign = i.isEven ? 1.0 : -1.0;
      double lat = poleSign * (0.25 + rng.nextDouble() * 1.15);
      double lon = rng.nextDouble() * 2 * pi;
      final r = 0.96 + rng.nextDouble() * 0.05;
      final steps = 9 + rng.nextInt(12);
      final List<Vec3> pts = [];

      for (int s = 0; s < steps; s++) {
        pts.add(_sphericalToCartesian(r, lat, lon));
        final mode = s % 3;
        if (mode == 0) {
          lon += (rng.nextBool() ? 1 : -1) * (0.09 + rng.nextDouble() * 0.08);
        } else if (mode == 1) {
          lat += (rng.nextBool() ? 1 : -1) * 0.06;
          lon += 0.06;
        } else {
          lat += (s == steps - 2 ? 0.045 : -0.03);
        }
      }
      built.add(CircuitStrand(
        layer: ShellLayer.outerCage,
        points: pts,
        phaseOffset: rng.nextDouble(),
      ));
    }

    // 2. MID SHELL: Thinner concentric stepped arcs
    for (int i = 0; i < midCount; i++) {
      double lat = (rng.nextDouble() - 0.5) * 2.2;
      double lon = rng.nextDouble() * 2 * pi;
      const r = 0.68;
      final steps = 8 + rng.nextInt(9);
      final List<Vec3> pts = [];

      for (int s = 0; s < steps; s++) {
        pts.add(_sphericalToCartesian(r, lat, lon));
        lon += 0.11;
        if (s % 4 == 2) {
          lat += (rng.nextBool() ? 0.05 : -0.05);
        }
      }
      built.add(CircuitStrand(
        layer: ShellLayer.midArcs,
        points: pts,
        phaseOffset: rng.nextDouble(),
      ));
    }

    // 3. INNER CORE: Dense honeycomb / hexagonal interlocking cells
    for (int i = 0; i < hexCount; i++) {
      final centerLat = (rng.nextDouble() - 0.5) * 2.6;
      final centerLon = rng.nextDouble() * 2 * pi;
      final r = 0.36 + rng.nextDouble() * 0.08;
      const cellRadius = 0.09;
      final List<Vec3> pts = [];

      for (int h = 0; h <= 6; h++) {
        final angle = (h / 6.0) * 2 * pi;
        final dLat = sin(angle) * cellRadius;
        final dLon = cos(angle) * cellRadius;
        pts.add(_sphericalToCartesian(r, centerLat + dLat, centerLon + dLon));
      }
      built.add(CircuitStrand(
        layer: ShellLayer.innerHexCore,
        points: pts,
        phaseOffset: rng.nextDouble(),
      ));
    }

    // 4. TILTED EQUATORIAL RING: Tightly packed parallel combed strands
    const tiltAngle = -0.22;
    for (int i = 0; i < eqCount; i++) {
      final bandOffset = (rng.nextDouble() - 0.5) * 0.11;
      final r = 1.03 + rng.nextDouble() * 0.10;
      double lon = rng.nextDouble() * 2 * pi;
      final steps = 16 + rng.nextInt(12);
      final List<Vec3> pts = [];

      for (int s = 0; s < steps; s++) {
        final raw = _sphericalToCartesian(r, bandOffset, lon);
        final yTilted = raw.y * cos(tiltAngle) - raw.x * sin(tiltAngle);
        final xTilted = raw.y * sin(tiltAngle) + raw.x * cos(tiltAngle);
        pts.add(Vec3(xTilted, yTilted, raw.z));
        lon += 0.11;
        if (s == steps - 2) {
          lon += 0.03;
        }
      }
      built.add(CircuitStrand(
        layer: ShellLayer.equatorialRing,
        points: pts,
        phaseOffset: rng.nextDouble(),
      ));
    }

    // 5. STRAIGHT DIAGONAL AXIS BEAM: Corner-to-corner parallel lines
    const beamAngle = 0.96;
    final dirX = sin(beamAngle);
    final dirY = cos(beamAngle);
    final perpX = -dirY;
    final perpY = dirX;

    for (int i = 0; i < beamCount; i++) {
      final spread = (rng.nextDouble() - 0.5) * 0.075;
      final zSpread = (rng.nextDouble() - 0.5) * 0.06;
      final List<Vec3> pts = [];
      const segs = 12;

      for (int s = 0; s <= segs; s++) {
        final t = -1.06 + (s / segs) * 2.12;
        final kink = (s == 2 || s == segs - 2) ? 0.014 : 0.0;
        final px = dirX * t + perpX * (spread + kink);
        final py = dirY * t + perpY * (spread + kink);
        pts.add(Vec3(px, py, zSpread));
      }
      built.add(CircuitStrand(
        layer: ShellLayer.diagonalBeam,
        points: pts,
        phaseOffset: rng.nextDouble(),
      ));
    }

    strands = built;
  }

  static Vec3 _sphericalToCartesian(double r, double lat, double lon) {
    final clat = cos(lat);
    return Vec3(
      r * clat * sin(lon),
      r * sin(lat),
      r * clat * cos(lon),
    );
  }
}

class OrbVisualParams {
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
          glowScale: 0.75,
          coreBrightness: 0.80,
          beamBrightness: 0.88,
          outwardPulseStrength: 0.0,
          errorTintMix: 0.0,
        );
      case OrbState.listening:
        return const OrbVisualParams(
          shellSpinMultiplier: 0.14,
          ringDriftMultiplier: 0.35,
          glowScale: 0.95,
          coreBrightness: 0.94,
          beamBrightness: 0.95,
          outwardPulseStrength: 0.08,
          errorTintMix: 0.0,
        );
      case OrbState.thinking:
        return const OrbVisualParams(
          shellSpinMultiplier: 1.65,
          ringDriftMultiplier: 1.85,
          glowScale: 1.15,
          coreBrightness: 1.25,
          beamBrightness: 1.35,
          outwardPulseStrength: 0.35,
          errorTintMix: 0.0,
        );
      case OrbState.answering:
        return const OrbVisualParams(
          shellSpinMultiplier: 1.25,
          ringDriftMultiplier: 1.45,
          glowScale: 1.20,
          coreBrightness: 1.30,
          beamBrightness: 1.25,
          outwardPulseStrength: 1.0,
          errorTintMix: 0.0,
        );
      case OrbState.error:
        return const OrbVisualParams(
          shellSpinMultiplier: 0.45,
          ringDriftMultiplier: 0.50,
          glowScale: 1.25,
          coreBrightness: 1.15,
          beamBrightness: 1.20,
          outwardPulseStrength: 0.25,
          errorTintMix: 1.0,
        );
    }
  }

  static OrbVisualParams lerp(
    OrbVisualParams a,
    OrbVisualParams b,
    double t,
  ) {
    final c = t.clamp(0.0, 1.0);
    return OrbVisualParams(
      shellSpinMultiplier: a.shellSpinMultiplier +
          (b.shellSpinMultiplier - a.shellSpinMultiplier) * c,
      ringDriftMultiplier: a.ringDriftMultiplier +
          (b.ringDriftMultiplier - a.ringDriftMultiplier) * c,
      glowScale: a.glowScale + (b.glowScale - a.glowScale) * c,
      coreBrightness:
          a.coreBrightness + (b.coreBrightness - a.coreBrightness) * c,
      beamBrightness:
          a.beamBrightness + (b.beamBrightness - a.beamBrightness) * c,
      outwardPulseStrength: a.outwardPulseStrength +
          (b.outwardPulseStrength - a.outwardPulseStrength) * c,
      errorTintMix: a.errorTintMix + (b.errorTintMix - a.errorTintMix) * c,
    );
  }
}

class UltronWireframeOrbPainter extends CustomPainter {
  final double shellAngleY;
  final double ringAngleY;
  final double beamDriftPhase;
  final double pulseClock;
  final double subtleKeystrokeRipple;
  final OrbVisualParams params;

  static final Path _backPath = Path();
  static final Path _frontOuterMidPath = Path();
  static final Path _coreAndRingPath = Path();
  static final Path _beamAndPulsePath = Path();

  UltronWireframeOrbPainter({
    required this.shellAngleY,
    required this.ringAngleY,
    required this.beamDriftPhase,
    required this.pulseClock,
    required this.subtleKeystrokeRipple,
    required this.params,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _backPath.reset();
    _frontOuterMidPath.reset();
    _coreAndRingPath.reset();
    _beamAndPulsePath.reset();

    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) * 0.40;

    final crispColor = Color.lerp(
      const Color(0xFFA9A8FF),
      const Color(0xFFFF2A6D),
      params.errorTintMix,
    )!;
    final bloomColor = Color.lerp(
      const Color(0xFF4B3FFF),
      const Color(0xFFD90452),
      params.errorTintMix,
    )!;
    final coreHighlight = Color.lerp(
      const Color(0xFFDCD8FF),
      const Color(0xFFFF85A9),
      params.errorTintMix,
    )!;

    const tiltX = 0.22;
    final cosX = cos(tiltX);
    final sinX = sin(tiltX);

    final strands = OrbGeometryCache.instance.strands;
    final waveFront = (pulseClock * 1.4) % 1.0;

    for (int i = 0; i < strands.length; i++) {
      final strand = strands[i];
      final pts = strand.points;
      if (pts.length < 2) continue;

      double rotY = shellAngleY;
      if (strand.layer == ShellLayer.equatorialRing) {
        rotY = ringAngleY;
      } else if (strand.layer == ShellLayer.diagonalBeam) {
        rotY = sin(beamDriftPhase) * 0.08;
      } else if (strand.layer == ShellLayer.midArcs) {
        rotY = -shellAngleY * 0.65;
      }

      final cosY = cos(rotY);
      final sinY = sin(rotY);

      final crawlShift = (pulseClock * 0.35 + strand.phaseOffset) % 1.0;
      final isAnsweringPulse = params.outwardPulseStrength > 0.15 &&
          ((strand.phaseOffset - waveFront).abs() < 0.16);

      double zSum = 0.0;
      Offset? prevScreen;

      for (int p = 0; p < pts.length; p++) {
        final v = pts[p];

        final x1 = v.x * cosY - v.z * sinY;
        final z1 = v.x * sinY + v.z * cosY;
        final y2 = v.y * cosX - z1 * sinX;
        final z2 = v.y * sinX + z1 * cosX;

        zSum += z2;

        final persp = 1.0 / (2.35 - z2 * 0.55);
        final sx = center.dx + x1 * radius * 2.15 * persp;
        final sy = center.dy + y2 * radius * 2.15 * persp;
        final currentScreen = Offset(sx, sy);

        if (prevScreen != null) {
          final skipSegment = strand.layer == ShellLayer.outerCage &&
              ((p / pts.length - crawlShift).abs() < 0.09);

          if (!skipSegment) {
            final avgZ = zSum / (p + 1);
            if (strand.layer == ShellLayer.diagonalBeam || isAnsweringPulse) {
              _beamAndPulsePath.moveTo(prevScreen.dx, prevScreen.dy);
              _beamAndPulsePath.lineTo(currentScreen.dx, currentScreen.dy);
            } else if (avgZ < -0.08) {
              _backPath.moveTo(prevScreen.dx, prevScreen.dy);
              _backPath.lineTo(currentScreen.dx, currentScreen.dy);
            } else if (strand.layer == ShellLayer.innerHexCore ||
                strand.layer == ShellLayer.equatorialRing) {
              _coreAndRingPath.moveTo(prevScreen.dx, prevScreen.dy);
              _coreAndRingPath.lineTo(currentScreen.dx, currentScreen.dy);
            } else {
              _frontOuterMidPath.moveTo(prevScreen.dx, prevScreen.dy);
              _frontOuterMidPath.lineTo(currentScreen.dx, currentScreen.dy);
            }
          }
        }
        prevScreen = currentScreen;
      }
    }

    final effGlow = (glowIntensity * params.glowScale).clamp(0.15, 1.0);
    final bloomPaint = Paint()
      ..color = bloomColor.withValues(alpha: 0.42 * effGlow)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4.5);

    canvas.drawPath(_frontOuterMidPath, bloomPaint);
    canvas.drawPath(
      _coreAndRingPath,
      bloomPaint..color = bloomColor.withValues(alpha: 0.58 * effGlow),
    );
    canvas.drawPath(
      _beamAndPulsePath,
      bloomPaint
        ..color = crispColor.withValues(alpha: 0.72 * effGlow)
        ..strokeWidth = 4.0,
    );

    canvas.drawPath(
      _backPath,
      Paint()
        ..color = crispColor.withValues(alpha: 0.24)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.75,
    );

    canvas.drawPath(
      _frontOuterMidPath,
      Paint()
        ..color = crispColor.withValues(alpha: 0.78)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    canvas.drawPath(
      _coreAndRingPath,
      Paint()
        ..color = crispColor.withValues(
            alpha: (0.86 * params.coreBrightness).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.05,
    );

    canvas.drawPath(
      _beamAndPulsePath,
      Paint()
        ..color = coreHighlight.withValues(
            alpha: (0.94 * params.beamBrightness).clamp(0.0, 1.0))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.25,
    );

    if (subtleKeystrokeRipple > 0.01) {
      final rippleR = radius * (0.38 + (1.0 - subtleKeystrokeRipple) * 0.22);
      canvas.drawCircle(
        center,
        rippleR,
        Paint()
          ..color = crispColor.withValues(alpha: subtleKeystrokeRipple * 0.28)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9,
      );
    }
  }

  @override
  bool shouldRepaint(covariant UltronWireframeOrbPainter oldDelegate) => true;
}