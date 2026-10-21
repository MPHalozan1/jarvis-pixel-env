import 'package:flutter/material.dart';

//**********************************************************************
// MODERN CYBER-BLUE DARK HUD THEME                                    *
// Deep sapphire/midnight navy surfaces (#040814) with crisp ice-blue  *
// (#38BDF8) and electric azure (#0284C7) accents.                     *
//**********************************************************************

@immutable
class UltronHudTheme extends ThemeExtension<UltronHudTheme> {
  final Color bgDeep;
  final Color bgPanel;
  final Color bgInput;
  final Color primaryPeriwinkle; // Kept field name for compatibility (now Ice Blue)
  final Color secondaryVioletBloom; // Now Deep Sapphire Blue Bloom
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
    this.cutRadius = 4.0,
  });

  static const UltronHudTheme dark = UltronHudTheme(
    bgDeep: Color(0xFF040814),
    bgPanel: Color(0xFF081124),
    bgInput: Color(0xFF060D1C),
    primaryPeriwinkle: Color(0xFF38BDF8),
    secondaryVioletBloom: Color(0xFF0284C7),
    accentErrorRed: Color(0xFFF43F5E),
    accentSuccessGreen: Color(0xFF10B981),
    accentWarningAmber: Color(0xFFF59E0B),
    textPrimary: Color(0xFFE2F1FF),
    textMuted: Color(0xFF6482A6),
    borderLine: Color(0xFF152C4F),
    cutRadius: 4.0,
  );

  static const UltronHudTheme light = UltronHudTheme(
    bgDeep: Color(0xFFF0F6FC),
    bgPanel: Color(0xFFFFFFFF),
    bgInput: Color(0xFFF8FAFC),
    primaryPeriwinkle: Color(0xFF0284C7),
    secondaryVioletBloom: Color(0xFF2563EB),
    accentErrorRed: Color(0xFFE11D48),
    accentSuccessGreen: Color(0xFF059669),
    accentWarningAmber: Color(0xFFD97706),
    textPrimary: Color(0xFF0F172A),
    textMuted: Color(0xFF475569),
    borderLine: Color(0xFFCBD5E1),
    cutRadius: 4.0,
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
    return RoundedRectangleBorder(
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

class HudBracketPanel extends StatefulWidget {
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
  State<HudBracketPanel> createState() => _HudBracketPanelState();
}

class _HudBracketPanelState extends State<HudBracketPanel> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
    final baseCol = widget.borderColor ?? hud.borderLine;
    final activeBorder = _hovered
        ? Color.lerp(baseCol, hud.primaryPeriwinkle, 0.55)!
        : baseCol;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: CustomPaint(
        foregroundPainter: _CornerBracketPainter(
          bracketColor: hud.primaryPeriwinkle,
          bracketLength: _hovered ? 9.0 : 6.0,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: widget.padding,
          decoration: ShapeDecoration(
            color: widget.fillColor ?? hud.bgPanel.withValues(alpha: 0.94),
            shape: hud.chamferShape(borderColor: activeBorder, width: 1.0),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

class _CornerBracketPainter extends CustomPainter {
  final Color bracketColor;
  final double bracketLength;

  const _CornerBracketPainter({
    required this.bracketColor,
    this.bracketLength = 6.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = bracketColor.withValues(alpha: 0.80)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final len = bracketLength;
    canvas.drawLine(Offset.zero, Offset(len, 0), paint);
    canvas.drawLine(Offset.zero, Offset(0, len), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width - len, 0), paint);
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, len), paint);
    canvas.drawLine(Offset(0, size.height), Offset(len, size.height), paint);
    canvas.drawLine(
        Offset(0, size.height), Offset(0, size.height - len), paint);
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width - len, size.height), paint);
    canvas.drawLine(Offset(size.width, size.height),
        Offset(size.width, size.height - len), paint);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketPainter oldDelegate) =>
      oldDelegate.bracketColor != bracketColor ||
      oldDelegate.bracketLength != bracketLength;
}

class HudActionButton extends StatefulWidget {
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
  State<HudActionButton> createState() => _HudActionButtonState();
}

class _HudActionButtonState extends State<HudActionButton> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final hud =
        Theme.of(context).extension<UltronHudTheme>() ?? UltronHudTheme.dark;
    final col = widget.accentColor ??
        (widget.isPrimaryAccent ? hud.secondaryVioletBloom : hud.primaryPeriwinkle);

    final scale = _pressed ? 0.97 : (_hovered ? 1.02 : 1.0);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: ShapeDecoration(
              color: _hovered
                  ? col.withValues(alpha: 0.25)
                  : (widget.isPrimaryAccent
                      ? col.withValues(alpha: 0.18)
                      : hud.bgInput),
              shape: hud.chamferShape(
                borderColor: _hovered ? Colors.white : col.withValues(alpha: 0.85),
                width: 1.0,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    size: 13,
                    color: _hovered ? Colors.white : col,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  widget.label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                    color:
                        (widget.isPrimaryAccent || _hovered) ? Colors.white : col,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}