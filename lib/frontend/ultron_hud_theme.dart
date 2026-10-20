import 'package:flutter/material.dart';

//**********************************************************************
// PHASE 2 // CENTRAL SHARP TECHNICAL SCI-FI HUD THEME                 *
// Single source of truth for colors, 0-3px cut corners, typography,   *
// corner brackets, and scanline overlays.                             *
//**********************************************************************

@immutable
class UltronHudTheme extends ThemeExtension<UltronHudTheme> {
  final Color bgDeep;
  final Color bgPanel;
  final Color bgInput;
  final Color primaryPeriwinkle;
  final Color secondaryVioletBloom;
  final Color accentErrorRed;
  final Color accentSuccessGreen;
  final Color accentWarningAmber;
  final Color textPrimary;
  final Color textMuted;
  final Color borderLine;
  final double cutRadius;

  const UltronHudTheme({
    required this.bgDeep,
    required this.bgPanel,
    required this.bgInput,
    required this.primaryPeriwinkle,
    required this.secondaryVioletBloom,
    required this.accentErrorRed,
    required this.accentSuccessGreen,
    required this.accentWarningAmber,
    required this.textPrimary,
    required this.textMuted,
    required this.borderLine,
    this.cutRadius = 3.0,
  });

  static const UltronHudTheme dark = UltronHudTheme(
    bgDeep: Color(0xFF05050F),
    bgPanel: Color(0xFF0A0A1A),
    bgInput: Color(0xFF070714),
    primaryPeriwinkle: Color(0xFFA9A8FF),
    secondaryVioletBloom: Color(0xFF4B3FFF),
    accentErrorRed: Color(0xFFFF2A6D),
    accentSuccessGreen: Color(0xFF00F59B),
    accentWarningAmber: Color(0xFFFFB800),
    textPrimary: Color(0xFFE6E6FF),
    textMuted: Color(0xFF7A7A9E),
    borderLine: Color(0xFF2D2C5A),
    cutRadius: 3.0,
  );

  static const UltronHudTheme light = UltronHudTheme(
    bgDeep: Color(0xFFECEDF8),
    bgPanel: Color(0xFFF7F7FC),
    bgInput: Color(0xFFFFFFFF),
    primaryPeriwinkle: Color(0xFF3B32B3),
    secondaryVioletBloom: Color(0xFF4B3FFF),
    accentErrorRed: Color(0xFFD91B5C),
    accentSuccessGreen: Color(0xFF008A57),
    accentWarningAmber: Color(0xFFB47800),
    textPrimary: Color(0xFF0D0D26),
    textMuted: Color(0xFF56567A),
    borderLine: Color(0xFFB5B4D9),
    cutRadius: 3.0,
  );

  static ThemeData buildThemeData(bool isDark) {
    final ext = isDark ? dark : light;
    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: ext.bgDeep,
      fontFamily: 'monospace',
      colorScheme: ColorScheme.fromSeed(
        seedColor: ext.primaryPeriwinkle,
        brightness: isDark ? Brightness.dark : Brightness.light,
        surface: ext.bgPanel,
        primary: ext.primaryPeriwinkle,
        secondary: ext.secondaryVioletBloom,
        error: ext.accentErrorRed,
      ),
      extensions: <ThemeExtension<dynamic>>[ext],
    );
  }

  ShapeBorder chamferShape({Color? borderColor, double width = 1.0}) {
    return BeveledRectangleBorder(
      borderRadius: BorderRadius.circular(cutRadius),
      side: BorderSide(color: borderColor ?? borderLine, width: width),
    );
  }

  @override
  UltronHudTheme copyWith({
    Color? bgDeep,
    Color? bgPanel,
    Color? bgInput,
    Color? primaryPeriwinkle,
    Color? secondaryVioletBloom,
    Color? accentErrorRed,
    Color? accentSuccessGreen,
    Color? accentWarningAmber,
    Color? textPrimary,
    Color? textMuted,
    Color? borderLine,
    double? cutRadius,
  }) {
    return UltronHudTheme(
      bgDeep: bgDeep ?? this.bgDeep,
      bgPanel: bgPanel ?? this.bgPanel,
      bgInput: bgInput ?? this.bgInput,
      primaryPeriwinkle: primaryPeriwinkle ?? this.primaryPeriwinkle,
      secondaryVioletBloom: secondaryVioletBloom ?? this.secondaryVioletBloom,
      accentErrorRed: accentErrorRed ?? this.accentErrorRed,
      accentSuccessGreen: accentSuccessGreen ?? this.accentSuccessGreen,
      accentWarningAmber: accentWarningAmber ?? this.accentWarningAmber,
      textPrimary: textPrimary ?? this.textPrimary,
      textMuted: textMuted ?? this.textMuted,
      borderLine: borderLine ?? this.borderLine,
      cutRadius: cutRadius ?? this.cutRadius,
    );
  }

  @override
  UltronHudTheme lerp(ThemeExtension<UltronHudTheme>? other, double t) {
    if (other is! UltronHudTheme) return this;
    return UltronHudTheme(
      bgDeep: Color.lerp(bgDeep, other.bgDeep, t)!,
      bgPanel: Color.lerp(bgPanel, other.bgPanel, t)!,
      bgInput: Color.lerp(bgInput, other.bgInput, t)!,
      primaryPeriwinkle:
          Color.lerp(primaryPeriwinkle, other.primaryPeriwinkle, t)!,
      secondaryVioletBloom:
          Color.lerp(secondaryVioletBloom, other.secondaryVioletBloom, t)!,
      accentErrorRed: Color.lerp(accentErrorRed, other.accentErrorRed, t)!,
      accentSuccessGreen:
          Color.lerp(accentSuccessGreen, other.accentSuccessGreen, t)!,
      accentWarningAmber:
          Color.lerp(accentWarningAmber, other.accentWarningAmber, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      borderLine: Color.lerp(borderLine, other.borderLine, t)!,
      cutRadius: cutRadius,
    );
  }
}

// Reusable sharp HUD panel with corner tick brackets
class HudBracketPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final Color? fillColor;

  const HudBracketPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.borderColor,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
    final bCol = borderColor ?? hud.borderLine;

    return CustomPaint(
      foregroundPainter: _CornerBracketPainter(
        bracketColor: hud.primaryPeriwinkle,
      ),
      child: Container(
        padding: padding,
        decoration: ShapeDecoration(
          color: fillColor ?? hud.bgPanel.withValues(alpha: 0.96),
          shape: hud.chamferShape(borderColor: bCol, width: 1.0),
        ),
        child: child,
      ),
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  final Color bracketColor;
  const _CornerBracketPainter({required this.bracketColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = bracketColor.withValues(alpha: 0.85)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const len = 7.0;
    // Top-left
    canvas.drawLine(Offset.zero, const Offset(len, 0), paint);
    canvas.drawLine(Offset.zero, const Offset(0, len), paint);
    // Top-right
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - len, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, len), paint);
    // Bottom-left
    canvas.drawLine(Offset(0, size.height), Offset(len, size.height), paint);
    canvas.drawLine(
        Offset(0, size.height), Offset(0, size.height - len), paint);
    // Bottom-right
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width - len, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width, size.height - len), paint);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketPainter oldDelegate) =>
      oldDelegate.bracketColor != bracketColor;
}

// Sharp angular button widget
class HudActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? accentColor;
  final bool isPrimaryAccent;

  const HudActionButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.accentColor,
    this.isPrimaryAccent = false,
  });

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
    final col = accentColor ??
        (isPrimaryAccent ? hud.accentErrorRed : hud.primaryPeriwinkle);

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: ShapeDecoration(
          color: isPrimaryAccent ? col.withValues(alpha: 0.22) : hud.bgInput,
          shape: hud.chamferShape(borderColor: col, width: 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: col),
              const SizedBox(width: 6),
            ],
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: isPrimaryAccent ? Colors.white : col,
              ),
            ),
          ],
        ),
      ),
    );
  }
}