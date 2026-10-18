import 'dart:math';
import 'package:flutter/material.dart';
import '../backend/office_orchestrator.dart';

//**********************************************************************
// JARVIS_V2 PIXEL ART ENGINE // ULTRA-DETAILED 16-BIT RENDERER        *
// Renders the 16-bit RPG office, computers, typing hands, and legs    *
// while dynamically reading custom agent names & provider badges.     *
//**********************************************************************

class UltraDetailedPixelOfficePainter extends CustomPainter {
  final List<OfficeAgent> agents;
  final int selectedAgentId;
  final bool isDarkMode;
  final double animTick;
  final bool isDirectorAvailable;

  UltraDetailedPixelOfficePainter({
    required this.agents,
    required this.selectedAgentId,
    required this.isDarkMode,
    required this.animTick,
    required this.isDirectorAvailable,
  });

  void _px(Canvas c, double x, double y, double w, double h, Color color) {
    c.drawRect(
      Rect.fromLTWH(
        x.floorToDouble(),
        y.floorToDouble(),
        w.floorToDouble(),
        h.floorToDouble(),
      ),
      Paint()
        ..color = color
        ..isAntiAlias = false,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final finalRev = agents[6]; // #7 Final Reviewer
    final afkRev = agents[7];   // #8 Offline Reviewer
    final staxCfo = agents[8];  // #9 Token Reporter

    // 1. CENTRAL CORRIDOR WITH FIBER DATA CONDUITS
    const hallwayRect = Rect.fromLTWH(120, 300, 900, 80);
    _drawDetailedHallway(canvas, hallwayRect);

    // 2. TOP EXECUTIVE WING (3 Configurable Reviewer Rooms)
    const finalRoom = Rect.fromLTWH(120, 70, 290, 230);
    _drawDetailedWoodRoom(
      canvas,
      finalRoom,
      finalRev.badgeColor,
      '1. FINAL REVIEW & SSH (${finalRev.name.toUpperCase()})',
    );
    _drawDoorwayMat(canvas, const Offset(275, 300));
    _drawServerRackDetailed(canvas, const Offset(138, 96), finalRev.badgeColor);
    _drawCloudBridgeTerminal(canvas, const Offset(182, 96), finalRev.providerName);
    _drawDetailedBookshelf(canvas, const Offset(335, 94));
    _drawDetailedWorkstation(
      canvas,
      const Offset(275, 175),
      '#7 ${finalRev.name}',
      finalRev.badgeColor,
      isTyping: finalRev.isTypingAtDesk,
    );

    const afkRoom = Rect.fromLTWH(420, 70, 285, 230);
    _drawDetailedWoodRoom(
      canvas,
      afkRoom,
      afkRev.badgeColor,
      '2. OFFLINE / AFK REVIEW (${afkRev.name.toUpperCase()})',
    );
    _drawDoorwayMat(canvas, const Offset(565, 300));
    _drawDetailedBookshelf(canvas, const Offset(438, 94));
    _drawCloudBridgeTerminal(canvas, const Offset(632, 96), afkRev.providerName);
    _drawDetailedWorkstation(
      canvas,
      const Offset(565, 175),
      '#8 ${afkRev.name}',
      afkRev.badgeColor,
      isTyping: afkRev.isTypingAtDesk,
    );

    const tokenRoom = Rect.fromLTWH(715, 70, 305, 230);
    _drawDetailedWoodRoom(
      canvas,
      tokenRoom,
      staxCfo.badgeColor,
      '3. TOKEN & QUOTA AUDITOR (${staxCfo.name.toUpperCase()})',
    );
    _drawDoorwayMat(canvas, const Offset(855, 300));
    _drawWallLedgerChart(canvas, const Offset(735, 92));
    _drawDetailedWorkstation(
      canvas,
      const Offset(855, 175),
      '#9 ${staxCfo.name}',
      staxCfo.badgeColor,
      isTyping: staxCfo.isTypingAtDesk,
    );

    // 3. BOTTOM-LEFT WING: 4 CODING/CRITIC DESKS + OVERFLOW/GIT AGENT
    const codingBay = Rect.fromLTWH(120, 380, 555, 300);
    _drawDetailedWoodRoom(
      canvas,
      codingBay,
      const Color(0xFF3B82F6),
      'DEV & CRITIC BAY (FE + BE + GIT OVERFLOW BOT)',
    );
    _drawDoorwayMat(canvas, const Offset(335, 380));

    _drawDetailedBookshelf(canvas, const Offset(138, 398));
    _drawDetailedWaterCooler(canvas, const Offset(205, 396));
    _drawDetailedPlant(canvas, const Offset(142, 630));
    _drawDetailedPlant(canvas, const Offset(495, 402));

    for (int i = 0; i < 4; i++) {
      final a = agents[i];
      _drawDetailedWorkstation(
        canvas,
        a.homePos,
        '#${a.id} ${a.name}',
        a.badgeColor,
        isTyping: a.isTypingAtDesk,
      );
    }

    // #5 Overflow & Git Agent Station
    final gitBot = agents[4];
    _drawServerRackDetailed(canvas, const Offset(555, 398), gitBot.badgeColor);
    _drawCloudBridgeTerminal(canvas, const Offset(595, 398), gitBot.providerName);
    _drawDetailedWorkstation(
      canvas,
      gitBot.homePos,
      '#5 ${gitBot.name}',
      gitBot.badgeColor,
      isTyping: gitBot.isTypingAtDesk,
    );

    // 4. BOTTOM-RIGHT WING: SHINY VIP DIRECTOR SUITE
    const directorRoom = Rect.fromLTWH(685, 380, 335, 300);
    _drawUltraShinyDirectorSuite(canvas, directorRoom);
    _drawDoorwayMat(canvas, const Offset(805, 380));

    // 5. Y-SORTED FULL-BODY PIXEL CHARACTERS
    final sortedAgents = List<OfficeAgent>.from(agents)
      ..sort((a, b) => a.currentPos.dy.compareTo(b.currentPos.dy));

    for (final agent in sortedAgents) {
      _drawFullBodyPixelCharacter(
        canvas,
        agent,
        isSelected: agent.id == selectedAgentId,
      );
    }

    // 6. NON-OVERLAPPING SPEECH BUBBLES
    _drawNonOverlappingBubbles(canvas);
  }

  void _drawDetailedHallway(Canvas canvas, Rect rect) {
    _px(canvas, rect.left - 6, rect.top - 6, rect.width + 12, rect.height + 12,
        const Color(0xFF161925));
    _px(canvas, rect.left, rect.top, rect.width, rect.height,
        const Color(0xFF23293A));

    for (double y = rect.top; y < rect.bottom; y += 20) {
      for (double x = rect.left; x < rect.right; x += 20) {
        final isAlt =
            (((x - rect.left) ~/ 20) + ((y - rect.top) ~/ 20)) % 2 == 0;
        _px(
          canvas,
          x,
          y,
          19,
          19,
          isAlt ? const Color(0xFF262D40) : const Color(0xFF202636),
        );
      }
    }

    final pulse = (sin(animTick * pi * 2) * 0.3 + 0.7);
    _px(
      canvas,
      275,
      rect.top + 38,
      580,
      4,
      const Color(0xFF38BDF8).withValues(alpha: pulse * 0.6),
    );
  }

  void _drawDetailedWoodRoom(
    Canvas canvas,
    Rect rect,
    Color neonTrim,
    String title,
  ) {
    _px(canvas, rect.left - 8, rect.top - 18, rect.width + 16, rect.height + 26,
        const Color(0xFF121521));
    _px(canvas, rect.left - 4, rect.top - 14, rect.width + 8, 14,
        const Color(0xFF242B3D));
    _px(canvas, rect.left - 4, rect.top - 2, rect.width + 8, 3, neonTrim);

    _px(canvas, rect.left, rect.top, rect.width, rect.height,
        const Color(0xFF8D5B30));
    for (double y = rect.top; y < rect.bottom; y += 12) {
      _px(canvas, rect.left, y, rect.width, 2, const Color(0xFF6B4220));
      for (double x = rect.left + ((y.toInt() % 24 == 0) ? 18 : 0);
          x < rect.right - 20;
          x += 44) {
        _px(canvas, x, y + 2, 2, 10, const Color(0xFF6B4220));
        _px(canvas, x + 4, y + 5, 2, 2, const Color(0xFF4A2C13));
      }
    }

    _px(
      canvas,
      rect.left,
      rect.top,
      rect.width,
      10,
      Colors.black.withValues(alpha: 0.28),
    );

    final tp = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          color: Colors.white.withValues(alpha: 0.9),
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _px(
      canvas,
      rect.left + 8,
      rect.bottom - 18,
      tp.width + 10,
      14,
      const Color(0xFF0F131F).withValues(alpha: 0.82),
    );
    tp.paint(canvas, Offset(rect.left + 13, rect.bottom - 16));
  }

  void _drawUltraShinyDirectorSuite(Canvas canvas, Rect rect) {
    _px(canvas, rect.left - 8, rect.top - 18, rect.width + 16, rect.height + 26,
        const Color(0xFF0B1120));
    _px(canvas, rect.left - 4, rect.top - 14, rect.width + 8, 14,
        const Color(0xFF1E293B));
    _px(canvas, rect.left - 4, rect.top - 2, rect.width + 8, 3,
        const Color(0xFF22D3EE));

    for (double y = rect.top; y < rect.bottom; y += 20) {
      for (double x = rect.left; x < rect.right; x += 20) {
        final isLight =
            (((x - rect.left) ~/ 20) + ((y - rect.top) ~/ 20)) % 2 == 0;
        _px(
          canvas,
          x,
          y,
          20,
          20,
          isLight ? const Color(0xFFF1F5F9) : const Color(0xFFCBD5E1),
        );
        _px(canvas, x, y, 2, 2, const Color(0xFFFACC15));
      }
    }

    canvas.save();
    canvas.clipRect(rect);
    final sweepX = rect.left - 140 + (rect.width + 280) * animTick;
    final shinePath = Path()
      ..moveTo(sweepX, rect.top)
      ..lineTo(sweepX + 60, rect.top)
      ..lineTo(sweepX - 30, rect.bottom)
      ..lineTo(sweepX - 90, rect.bottom)
      ..close();
    canvas.drawPath(
      shinePath,
      Paint()..color = Colors.white.withValues(alpha: 0.65),
    );
    canvas.restore();

    const rugX = 780.0;
    const rugY = 470.0;
    _px(canvas, rugX - 4, rugY - 4, 178, 138, const Color(0xFFFACC15));
    _px(canvas, rugX, rugY, 170, 130, const Color(0xFF7F1D1D));
    _px(canvas, rugX + 6, rugY + 6, 158, 118, const Color(0xFF991B1B));

    _drawEspressoStation(canvas, const Offset(955, 396));
    _drawGoldTrophyPedestal(canvas, const Offset(705, 398));
    _drawDetailedPlant(canvas, const Offset(708, 625));
    _drawDetailedPlant(canvas, const Offset(975, 625));

    _drawDetailedWorkstation(
      canvas,
      const Offset(865, 535),
      isDirectorAvailable ? 'YOU (VIP AVAILABLE)' : 'YOU (AFK MODE)',
      const Color(0xFF22D3EE),
      isVipTripleMonitor: true,
      isTyping: isDirectorAvailable,
    );
  }

  void _drawDoorwayMat(Canvas canvas, Offset center) {
    _px(canvas, center.dx - 28, center.dy - 8, 56, 16, const Color(0xFF334155));
    _px(canvas, center.dx - 24, center.dy - 5, 48, 10, const Color(0xFF38BDF8));
  }

  void _drawDetailedWorkstation(
    Canvas canvas,
    Offset center,
    String label,
    Color accent, {
    bool isVipTripleMonitor = false,
    bool isTyping = true,
  }) {
    final cx = center.dx;
    final cy = center.dy;

    _px(canvas, cx - 12, cy - 4, 24, 3, const Color(0xFF334155));
    _px(canvas, cx - 13, cy - 2, 3, 3, const Color(0xFF0F172A));
    _px(canvas, cx + 10, cy - 2, 3, 3, const Color(0xFF0F172A));
    _px(canvas, cx - 10, cy - 26, 20, 18, const Color(0xFF1E293B));
    _px(
      canvas,
      cx - 8,
      cy - 24,
      16,
      14,
      isVipTripleMonitor ? const Color(0xFFFACC15) : accent.withValues(alpha: 0.7),
    );

    final deskW = isVipTripleMonitor ? 112.0 : 94.0;
    final deskLeft = cx - deskW / 2;
    final deskTop = cy + 6;

    _px(
      canvas,
      deskLeft - 3,
      deskTop + 34,
      deskW + 6,
      8,
      Colors.black.withValues(alpha: 0.35),
    );
    _px(canvas, deskLeft + 4, deskTop + 28, 5, 10, const Color(0xFF1E293B));
    _px(canvas, deskLeft + deskW - 9, deskTop + 28, 5, 10, const Color(0xFF1E293B));
    _px(canvas, cx - 6, deskTop + 28, 2, 8, const Color(0xFF0F172A));
    _px(canvas, cx + 4, deskTop + 28, 2, 9, const Color(0xFF38BDF8));

    _px(
      canvas,
      deskLeft,
      deskTop,
      deskW,
      30,
      isVipTripleMonitor ? const Color(0xFF0F172A) : const Color(0xFF3E2414),
    );
    _px(
      canvas,
      deskLeft + 3,
      deskTop + 3,
      deskW - 6,
      23,
      isVipTripleMonitor ? const Color(0xFF1E293B) : const Color(0xFF5C361E),
    );

    final kbX = cx - 13;
    final kbY = deskTop + 4;
    _px(canvas, kbX - 1, kbY - 1, 26, 9, accent.withValues(alpha: 0.8));
    _px(canvas, kbX, kbY, 24, 7, const Color(0xFF111827));
    for (int kx = 0; kx < 10; kx++) {
      for (int ky = 0; ky < 3; ky++) {
        final keyLit =
            isTyping && ((kx + ky + (animTick * 20).toInt()) % 4 == 0);
        _px(
          canvas,
          kbX + 2 + kx * 2,
          kbY + 1 + ky * 2,
          1.5,
          1.5,
          keyLit ? accent : const Color(0xFF94A3B8),
        );
      }
    }

    _px(canvas, cx + 16, kbY, 12, 9, const Color(0xFF0F172A));
    _px(canvas, cx + 19, kbY + 2, 5, 6, const Color(0xFFE2E8F0));
    _px(canvas, cx + 21, kbY + 2, 1, 2, accent);

    final pcX = deskLeft + 5;
    final pcY = deskTop + 3;
    _px(canvas, pcX, pcY, 14, 20, const Color(0xFF090D16));
    _px(canvas, pcX + 2, pcY + 2, 10, 14, const Color(0xFF1E293B));
    final fanColor = (animTick * 10).toInt() % 2 == 0
        ? accent
        : const Color(0xFFF43F5E);
    _px(canvas, pcX + 4, pcY + 4, 6, 5, fanColor);
    _px(canvas, pcX + 3, pcY + 11, 8, 2, const Color(0xFF22C55E));

    final mugX = deskLeft + deskW - 14;
    final mugY = deskTop + 6;
    _px(canvas, mugX, mugY, 7, 8, Colors.white);
    _px(canvas, mugX + 1, mugY + 1, 5, 3, const Color(0xFF451A03));
    _px(canvas, mugX + 7, mugY + 2, 2, 4, Colors.white);
    final steamOffset = ((animTick * 12) % 6);
    _px(
      canvas,
      mugX + 2,
      mugY - 3 - steamOffset,
      2,
      2,
      Colors.white.withValues(alpha: 0.55),
    );

    final monY = deskTop + 15;
    _drawCodingMonitor(canvas, Offset(cx - 14, monY), accent, isTyping, 0);
    _drawCodingMonitor(canvas, Offset(cx + 12, monY), accent, isTyping, 2);
    if (isVipTripleMonitor) {
      _drawCodingMonitor(
        canvas,
        Offset(cx - 38, monY - 2),
        const Color(0xFFFACC15),
        isTyping,
        4,
      );
    }

    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          color: isVipTripleMonitor ? const Color(0xFF0F172A) : Colors.white,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - tp.width / 2, deskTop + 32));
  }

  void _drawCodingMonitor(
    Canvas canvas,
    Offset pos,
    Color glowColor,
    bool isTyping,
    int seed,
  ) {
    _px(canvas, pos.dx - 3, pos.dy + 10, 6, 3, const Color(0xFF334155));
    _px(canvas, pos.dx - 12, pos.dy, 24, 12, const Color(0xFF090D16));
    _px(canvas, pos.dx - 11, pos.dy + 1, 22, 10, const Color(0xFF0F172A));

    final scroll = isTyping ? (animTick * 16 + seed).toInt() : seed;
    final codeColors = [
      glowColor,
      const Color(0xFF4ADE80),
      const Color(0xFFFACC15),
      const Color(0xFFF472B6),
    ];
    for (int row = 0; row < 4; row++) {
      final lineLen = 6.0 + ((row + scroll) % 3) * 4.0;
      final indent = ((row + scroll) % 2) * 3.0;
      _px(
        canvas,
        pos.dx - 9 + indent,
        pos.dy + 2 + row * 2.2,
        lineLen,
        1.5,
        codeColors[(row + scroll) % codeColors.length],
      );
    }
  }

  void _drawFullBodyPixelCharacter(
    Canvas canvas,
    OfficeAgent agent, {
    required bool isSelected,
  }) {
    final pos = agent.currentPos;
    final walking = agent.isWalking;
    final typing = agent.isTypingAtDesk;

    final walkCycle = walking ? sin(animTick * pi * 12 + agent.id) : 0.0;
    final bodyBob = walking ? (walkCycle.abs() * -3.0) : 0.0;
    final cx = pos.dx;
    final cy = pos.dy + bodyBob;

    if (isSelected) {
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(pos.dx, pos.dy + 14),
          width: 32,
          height: 12,
        ),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }

    canvas.drawOval(
      Rect.fromCenter(center: Offset(pos.dx, pos.dy + 14), width: 24, height: 8),
      Paint()..color = Colors.black.withValues(alpha: 0.4),
    );

    final leftLegOffset = walking ? (walkCycle * 4.0) : 0.0;
    final rightLegOffset = walking ? (-walkCycle * 4.0) : 0.0;

    _px(canvas, cx - 7, cy + 5 + leftLegOffset, 6, 7, agent.pantsColor);
    _px(canvas, cx - 8, cy + 11 + leftLegOffset, 7, 3, const Color(0xFF090D16));
    _px(canvas, cx + 1, cy + 5 + rightLegOffset, 6, 7, agent.pantsColor);
    _px(canvas, cx + 1, cy + 11 + rightLegOffset, 7, 3, const Color(0xFF090D16));

    _px(canvas, cx - 9, cy - 6, 18, 12, agent.shirtColor);
    _px(canvas, cx - 9, cy + 3, 18, 3, Colors.black.withValues(alpha: 0.22));
    _px(canvas, cx - 1, cy - 5, 2, 10, Colors.white.withValues(alpha: 0.25));

    const skin = Color(0xFFFDE68A);
    const skinShadow = Color(0xFFF59E0B);

    _px(canvas, cx - 11, cy - 15, 2, 5, skinShadow);
    _px(canvas, cx + 9, cy - 15, 2, 5, skinShadow);
    _px(canvas, cx - 9, cy - 20, 18, 14, skin);
    _px(canvas, cx - 9, cy - 8, 18, 2, skinShadow);

    final isBlinking = ((animTick * 20 + agent.id) % 9).floor() == 0;
    if (isBlinking) {
      _px(canvas, cx - 6, cy - 13, 4, 1.5, const Color(0xFF0F172A));
      _px(canvas, cx + 2, cy - 13, 4, 1.5, const Color(0xFF0F172A));
    } else {
      _px(canvas, cx - 6, cy - 15, 4, 4, Colors.white);
      _px(canvas, cx + 2, cy - 15, 4, 4, Colors.white);
      final pupilY = typing ? cy - 13 : cy - 14;
      _px(canvas, cx - 5, pupilY, 2.5, 2.5, const Color(0xFF0F172A));
      _px(canvas, cx + 3, pupilY, 2.5, 2.5, const Color(0xFF0F172A));
    }

    _px(canvas, cx - 6, cy - 17, 4, 1.5, agent.hairColor);
    _px(canvas, cx + 2, cy - 17, 4, 1.5, agent.hairColor);

    if (agent.hasGlasses) {
      _px(canvas, cx - 7, cy - 16, 6, 1, const Color(0xFF38BDF8));
      _px(canvas, cx + 1, cy - 16, 6, 1, const Color(0xFF38BDF8));
      _px(canvas, cx - 1, cy - 15, 2, 1, const Color(0xFF38BDF8));
    }

    final mouthOpen = typing && ((animTick * 15 + agent.id).toInt() % 3 == 0);
    _px(
      canvas,
      cx - 2,
      cy - 10,
      4,
      mouthOpen ? 2.5 : 1.5,
      const Color(0xFF78350F),
    );

    _px(canvas, cx - 10, cy - 24, 20, 6, agent.hairColor);
    _px(canvas, cx - 10, cy - 19, 3, 6, agent.hairColor);
    _px(canvas, cx + 7, cy - 19, 3, 6, agent.hairColor);
    _px(
      canvas,
      cx - 6,
      cy - 23,
      10,
      2,
      Colors.white.withValues(alpha: 0.22),
    );

    if (agent.hasHeadphones) {
      _px(canvas, cx - 11, cy - 25, 22, 2, const Color(0xFF334155));
      _px(canvas, cx - 12, cy - 17, 3, 6, agent.badgeColor);
      _px(canvas, cx + 9, cy - 17, 3, 6, agent.badgeColor);
    }

    if (typing) {
      final leftTap = sin(animTick * pi * 28 + agent.id) * 2.5;
      final rightTap = cos(animTick * pi * 28 + agent.id) * 2.5;

      _px(canvas, cx - 11, cy - 4, 4, 8, agent.shirtColor);
      _px(canvas, cx + 7, cy - 4, 4, 8, agent.shirtColor);
      _px(canvas, cx - 8, cy + 5 + leftTap, 4, 4, skin);
      _px(canvas, cx + 4, cy + 5 + rightTap, 4, 4, skin);

      final particleY = cy - 2 - ((animTick * 24 + agent.id * 3) % 14);
      final particleX = cx + sin(animTick * pi * 8 + agent.id) * 10;
      _px(canvas, particleX, particleY, 3, 3, agent.badgeColor);
    } else {
      final armSwing = walking ? (-walkCycle * 3.5) : 0.0;
      _px(canvas, cx - 12, cy - 5 + armSwing, 3, 9, agent.shirtColor);
      _px(canvas, cx - 12, cy + 3 + armSwing, 3, 3, skin);
      _px(canvas, cx + 9, cy - 5 - armSwing, 3, 9, agent.shirtColor);
      _px(canvas, cx + 9, cy + 3 - armSwing, 3, 3, skin);
    }

    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(cx - 14, cy + 4),
        width: 14,
        height: 14,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(badgeRect, Paint()..color = agent.badgeColor);
    final tp = TextPainter(
      text: TextSpan(
        text: '${agent.id}',
        style: const TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(cx - 14 - tp.width / 2, cy + 4 - tp.height / 2));
  }

  void _drawServerRackDetailed(Canvas canvas, Offset topLeft, Color ledColor) {
    _px(canvas, topLeft.dx, topLeft.dy, 34, 48, const Color(0xFF090D16));
    _px(canvas, topLeft.dx + 2, topLeft.dy + 2, 30, 44, const Color(0xFF1E293B));
    for (int i = 0; i < 5; i++) {
      _px(
        canvas,
        topLeft.dx + 4,
        topLeft.dy + 5 + i * 8,
        26,
        5,
        const Color(0xFF0F172A),
      );
      final blink = ((animTick * 16 + i).toInt() % 2 == 0);
      _px(
        canvas,
        topLeft.dx + 6,
        topLeft.dy + 6 + i * 8,
        4,
        3,
        blink ? ledColor : const Color(0xFF22C55E),
      );
    }
  }

  void _drawCloudBridgeTerminal(Canvas canvas, Offset topLeft, String label) {
    _px(canvas, topLeft.dx, topLeft.dy, 58, 36, const Color(0xFF0F172A));
    _px(canvas, topLeft.dx + 2, topLeft.dy + 2, 54, 22, const Color(0xFF0284C7));
    for (int b = 0; b < 8; b++) {
      final bh = 4.0 + ((b + (animTick * 15).toInt()) % 4) * 3.5;
      _px(
        canvas,
        topLeft.dx + 6 + b * 6,
        topLeft.dy + 20 - bh,
        4,
        bh,
        const Color(0xFF38BDF8),
      );
    }
    final tp = TextPainter(
      text: TextSpan(
        text: label.toUpperCase(),
        style: const TextStyle(
          fontSize: 6.5,
          fontWeight: FontWeight.bold,
          color: Colors.white,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(topLeft.dx + 4, topLeft.dy + 25));
  }

  void _drawDetailedBookshelf(Canvas canvas, Offset topLeft) {
    _px(canvas, topLeft.dx, topLeft.dy, 54, 38, const Color(0xFF3E2414));
    _px(canvas, topLeft.dx + 3, topLeft.dy + 3, 48, 14, const Color(0xFF27150B));
    _px(canvas, topLeft.dx + 3, topLeft.dy + 20, 48, 14, const Color(0xFF27150B));
    final colors = [
      const Color(0xFFEF4444),
      const Color(0xFF3B82F6),
      const Color(0xFF22C55E),
      const Color(0xFFFACC15),
      const Color(0xFFA855F7),
    ];
    for (int row = 0; row < 2; row++) {
      for (int b = 0; b < 7; b++) {
        _px(
          canvas,
          topLeft.dx + 5 + b * 6.5,
          topLeft.dy + 5 + row * 17,
          5,
          12,
          colors[(b + row) % colors.length],
        );
      }
    }
  }

  void _drawDetailedWaterCooler(Canvas canvas, Offset topLeft) {
    _px(canvas, topLeft.dx + 3, topLeft.dy, 14, 16, const Color(0xFF0284C7));
    _px(canvas, topLeft.dx + 5, topLeft.dy + 2, 10, 12, const Color(0xFF38BDF8));
    final bubbleY = topLeft.dy + 12 - ((animTick * 14) % 10);
    _px(canvas, topLeft.dx + 8, bubbleY, 3, 3, Colors.white);
    _px(canvas, topLeft.dx, topLeft.dy + 16, 20, 22, const Color(0xFFF8FAFC));
    _px(canvas, topLeft.dx + 5, topLeft.dy + 20, 3, 4, const Color(0xFFEF4444));
    _px(canvas, topLeft.dx + 12, topLeft.dy + 20, 3, 4, const Color(0xFF3B82F6));
  }

  void _drawDetailedPlant(Canvas canvas, Offset center) {
    _px(canvas, center.dx - 7, center.dy + 4, 14, 11, const Color(0xFFB45309));
    _px(canvas, center.dx - 9, center.dy + 2, 18, 4, const Color(0xFFD97706));
    _px(canvas, center.dx - 11, center.dy - 8, 22, 11, const Color(0xFF15803D));
    _px(canvas, center.dx - 8, center.dy - 13, 16, 12, const Color(0xFF22C55E));
    _px(canvas, center.dx - 4, center.dy - 15, 8, 6, const Color(0xFF4ADE80));
  }

  void _drawWallLedgerChart(Canvas canvas, Offset topLeft) {
    _px(canvas, topLeft.dx, topLeft.dy, 195, 36, const Color(0xFF090D16));
    _px(canvas, topLeft.dx + 2, topLeft.dy + 2, 191, 32, const Color(0xFF052E16));
    for (int i = 0; i < 12; i++) {
      final h = 6.0 + ((i * 3 + (animTick * 12).toInt()) % 5) * 4.0;
      _px(
        canvas,
        topLeft.dx + 8 + i * 15,
        topLeft.dy + 30 - h,
        9,
        h,
        i % 3 == 0 ? const Color(0xFFFACC15) : const Color(0xFF4ADE80),
      );
    }
  }

  void _drawEspressoStation(Canvas canvas, Offset topLeft) {
    _px(canvas, topLeft.dx, topLeft.dy, 42, 38, const Color(0xFF0F172A));
    _px(canvas, topLeft.dx + 4, topLeft.dy + 4, 18, 16, const Color(0xFF334155));
    _px(canvas, topLeft.dx + 26, topLeft.dy + 8, 10, 12, const Color(0xFFFACC15));
  }

  void _drawGoldTrophyPedestal(Canvas canvas, Offset topLeft) {
    _px(canvas, topLeft.dx, topLeft.dy + 14, 22, 16, const Color(0xFF1E293B));
    _px(canvas, topLeft.dx + 4, topLeft.dy, 14, 14, const Color(0xFFFACC15));
    _px(canvas, topLeft.dx + 7, topLeft.dy + 3, 8, 6, const Color(0xFFFEF08A));
  }

  void _drawNonOverlappingBubbles(Canvas canvas) {
    final List<Rect> placed = [];

    for (final agent in agents) {
      final tp = TextPainter(
        text: TextSpan(
          text: '[${agent.providerName}] ${agent.name}: ${agent.shortBubble}',
          style: TextStyle(
            fontSize: 8.0,
            fontWeight: FontWeight.bold,
            color: agent.state == AgentState.attention
                ? const Color(0xFFFACC15)
                : Colors.white,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final w = tp.width + 10;
      const h = 15.0;
      double bx = agent.currentPos.dx;
      double by = agent.currentPos.dy - 33;

      Rect candidate = Rect.fromCenter(
        center: Offset(bx, by),
        width: w,
        height: h,
      );

      int guard = 0;
      while (
          placed.any((r) => r.overlaps(candidate.inflate(2))) && guard < 4) {
        by -= 17;
        candidate = Rect.fromCenter(
          center: Offset(bx, by),
          width: w,
          height: h,
        );
        guard++;
      }
      placed.add(candidate);

      final rrect = RRect.fromRectAndRadius(candidate, const Radius.circular(4));
      canvas.drawRRect(
        rrect,
        Paint()..color = const Color(0xFF0B0F1A).withValues(alpha: 0.92),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = agent.badgeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );
      tp.paint(canvas, Offset(bx - tp.width / 2, by - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant UltraDetailedPixelOfficePainter oldDelegate) =>
      true;
}