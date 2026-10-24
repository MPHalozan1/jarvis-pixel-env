import 'dart:ui';
import 'package:flutter/material.dart';

//**************
// Pomožna razširitev za varno in hitro računanje prosojnosti barv *
// Deluje brez opozoril na vseh različicah Flutter SDK *
//**************
extension UltronColorAlpha on Color {
  Color alphaPct(double opacity) {
    final int alphaChannel = (opacity.clamp(0.0, 1.0) * 255).round();
    return withAlpha(alphaChannel);
  }
}

//**************
// Barvne prednastavitve za popolno prilagodljivost ULTRON vmesnika *
//**************
class UltronAccentPreset {
  final String name;
  final Color darkPrimary;
  final Color darkSecondary;
  final Color lightPrimary;
  final Color lightSecondary;

  const UltronAccentPreset({
    required this.name,
    required this.darkPrimary,
    required this.darkSecondary,
    required this.lightPrimary,
    required this.lightSecondary,
  });

  static const List<UltronAccentPreset> presets = [
    UltronAccentPreset(
      name: 'Periwinkle Core',
      darkPrimary: Color(0xFF8EA8FF),
      darkSecondary: Color(0xFF7B68EE),
      lightPrimary: Color(0xFF3B5BDB),
      lightSecondary: Color(0xFF6741D9),
    ),
    UltronAccentPreset(
      name: 'Ultron Crimson',
      darkPrimary: Color(0xFFFF5470),
      darkSecondary: Color(0xFFFF8552),
      lightPrimary: Color(0xFFD90429),
      lightSecondary: Color(0xFFE8590C),
    ),
    UltronAccentPreset(
      name: 'Cyber Emerald',
      darkPrimary: Color(0xFF38E8A8),
      darkSecondary: Color(0xFF20C997),
      lightPrimary: Color(0xFF099268),
      lightSecondary: Color(0xFF0CA678),
    ),
    UltronAccentPreset(
      name: 'Quantum Violet',
      darkPrimary: Color(0xFFB78DFF),
      darkSecondary: Color(0xFF845EF7),
      lightPrimary: Color(0xFF6741D9),
      lightSecondary: Color(0xFF7950F2),
    ),
    UltronAccentPreset(
      name: 'Solar Amber',
      darkPrimary: Color(0xFFFFB84D),
      darkSecondary: Color(0xFFFF8748),
      lightPrimary: Color(0xFFD9480F),
      lightSecondary: Color(0xFFF08C00),
    ),
  ];
}

//**************
// Tema vmesnika ULTRON HUD s podporo za temni in svetli način, *
// prilagodljive barvne poudarke, polmer robov in jakost sija *
//**************
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
  final double orbGlowMultiplier;

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
    this.cutRadius = 9.0,
    this.orbGlowMultiplier = 1.0,
  });

  // Temna minimalistična cyber-HUD paleta
  static const UltronHudTheme dark = UltronHudTheme(
    bgDeep: Color(0xFF060911),
    bgPanel: Color(0xFF0D1220),
    bgInput: Color(0xFF131B30),
    primaryPeriwinkle: Color(0xFF8EA8FF),
    secondaryVioletBloom: Color(0xFF7B68EE),
    accentErrorRed: Color(0xFFFF5C77),
    accentSuccessGreen: Color(0xFF3EE0A1),
    accentWarningAmber: Color(0xFFFFBE55),
    textPrimary: Color(0xFFEDF2FF),
    textMuted: Color(0xFF8896BA),
    borderLine: Color(0xFF212C48),
    cutRadius: 9.0,
    orbGlowMultiplier: 1.0,
  );

  // Svetla minimalistična paleta z visokim kontrastom
  static const UltronHudTheme light = UltronHudTheme(
    bgDeep: Color(0xFFF2F5FC),
    bgPanel: Color(0xFFFFFFFF),
    bgInput: Color(0xFFE8EEF9),
    primaryPeriwinkle: Color(0xFF3B5BDB),
    secondaryVioletBloom: Color(0xFF6741D9),
    accentErrorRed: Color(0xFFE03131),
    accentSuccessGreen: Color(0xFF0CA678),
    accentWarningAmber: Color(0xFFF08C00),
    textPrimary: Color(0xFF12192B),
    textMuted: Color(0xFF5A6988),
    borderLine: Color(0xFFD2DDF0),
    cutRadius: 9.0,
    orbGlowMultiplier: 1.0,
  );

  // Ustvari celoten ThemeData objekt z izbranim poudarkom in polmerom robov
  static ThemeData buildThemeData({
    required bool isDark,
    int accentIndex = 0,
    double cutRadius = 9.0,
    double orbGlowMultiplier = 1.0,
  }) {
    final safeIdx =
        accentIndex.clamp(0, UltronAccentPreset.presets.length - 1);
    final preset = UltronAccentPreset.presets[safeIdx];
    final base = isDark ? dark : light;

    final hud = base.copyWith(
      primaryPeriwinkle: isDark ? preset.darkPrimary : preset.lightPrimary,
      secondaryVioletBloom:
          isDark ? preset.darkSecondary : preset.lightSecondary,
      cutRadius: cutRadius,
      orbGlowMultiplier: orbGlowMultiplier,
    );

    final brightness = isDark ? Brightness.dark : Brightness.light;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: hud.bgDeep,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: hud.primaryPeriwinkle,
        onPrimary: isDark ? const Color(0xFF060911) : Colors.white,
        secondary: hud.secondaryVioletBloom,
        onSecondary: Colors.white,
        error: hud.accentErrorRed,
        onError: Colors.white,
        surface: hud.bgPanel,
        onSurface: hud.textPrimary,
      ),
      dividerColor: hud.borderLine,
      splashFactory: InkRipple.splashFactory,
      extensions: <ThemeExtension<dynamic>>[hud],
    );
  }

  ShapeBorder chamferShape({Color? sideColor, double width = 1.0}) {
    return BeveledRectangleBorder(
      borderRadius: BorderRadius.circular(cutRadius * 0.55),
      side: BorderSide(
        color: sideColor ?? borderLine,
        width: width,
      ),
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
    double? orbGlowMultiplier,
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
      orbGlowMultiplier: orbGlowMultiplier ?? this.orbGlowMultiplier,
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
      cutRadius: lerpDouble(cutRadius, other.cutRadius, t) ?? cutRadius,
      orbGlowMultiplier:
          lerpDouble(orbGlowMultiplier, other.orbGlowMultiplier, t) ??
              orbGlowMultiplier,
    );
  }
}

//**************
// Minimalističen HUD panel s kotnimi poudarki in gladko hover mikro-animacijo *
//**************
class HudBracketPanel extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? borderColor;
  final Color? fillColor;
  final bool interactiveHover;

  const HudBracketPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.borderColor,
    this.fillColor,
    this.interactiveHover = false,
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
    final effectiveBorder = widget.borderColor ??
        (_hovered
            ? hud.primaryPeriwinkle.alphaPct(0.60)
            : hud.borderLine.alphaPct(0.85));
    final effectiveFill = widget.fillColor ?? hud.bgPanel.alphaPct(0.90);

    final Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: effectiveFill,
        borderRadius: BorderRadius.circular(hud.cutRadius),
        border: Border.all(color: effectiveBorder, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.alphaPct(_hovered ? 0.24 : 0.16),
            blurRadius: _hovered ? 22 : 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _CornerBracketAccentsPainter(
          color: hud.primaryPeriwinkle.alphaPct(_hovered ? 0.72 : 0.34),
        ),
        child: widget.child,
      ),
    );

    if (!widget.interactiveHover) return content;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: content,
    );
  }
}

class _CornerBracketAccentsPainter extends CustomPainter {
  final Color color;

  const _CornerBracketAccentsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.25
      ..style = PaintingStyle.stroke;

    const double len = 6.5;
    // Zgornji levi kot
    canvas.drawLine(const Offset(0, len), Offset.zero, paint);
    canvas.drawLine(Offset.zero, const Offset(len, 0), paint);
    // Spodnji desni kot
    canvas.drawLine(
        Offset(size.width - len, size.height),
        Offset(size.width, size.height),
        paint);
    canvas.drawLine(
        Offset(size.width, size.height - len),
        Offset(size.width, size.height),
        paint);
  }

  @override
  bool shouldRepaint(covariant _CornerBracketAccentsPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

//**************
// Interaktivni gumb z odzivno animacijo ob prehodu z miško, siju in kliku *
//**************
class HudActionButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? accentColor;
  final bool isPrimaryAccent;
  final bool compact;
  final String? badgeText;

  const HudActionButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.accentColor,
    this.isPrimaryAccent = false,
    this.compact = false,
    this.badgeText,
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
    final accent = widget.accentColor ?? hud.primaryPeriwinkle;
    final enabled = widget.onTap != null;

    final Color bgColor = widget.isPrimaryAccent
        ? accent.alphaPct(_hovered ? 0.25 : 0.15)
        : (_hovered ? hud.bgInput.alphaPct(0.95) : hud.bgPanel.alphaPct(0.68));

    final Color borderColor = widget.isPrimaryAccent || _hovered
        ? accent.alphaPct(_hovered ? 0.85 : 0.48)
        : hud.borderLine.alphaPct(0.85);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.95 : (_hovered ? 1.025 : 1.0),
          duration: const Duration(milliseconds: 125),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 9.5 : 12,
              vertical: widget.compact ? 6 : 7,
            ),
            decoration: BoxDecoration(
              color: enabled ? bgColor : hud.bgPanel.alphaPct(0.35),
              borderRadius: BorderRadius.circular(hud.cutRadius * 0.8),
              border: Border.all(color: borderColor, width: 1.0),
              boxShadow: _hovered && enabled
                  ? [
                      BoxShadow(
                        color: accent.alphaPct(0.14),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(
                    widget.icon,
                    size: widget.compact ? 14 : 15,
                    color: enabled
                        ? (_hovered || widget.isPrimaryAccent
                            ? accent
                            : hud.textMuted)
                        : hud.textMuted.alphaPct(0.45),
                  ),
                  if (widget.label.isNotEmpty) const SizedBox(width: 6),
                ],
                if (widget.label.isNotEmpty)
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: widget.compact ? 11.5 : 12.0,
                      fontWeight: widget.isPrimaryAccent
                          ? FontWeight.w600
                          : FontWeight.w500,
                      letterSpacing: 0.2,
                      color: enabled
                          ? (_hovered || widget.isPrimaryAccent
                              ? hud.textPrimary
                              : hud.textPrimary.alphaPct(0.88))
                          : hud.textMuted.alphaPct(0.45),
                    ),
                  ),
                if (widget.badgeText != null &&
                    widget.badgeText!.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: accent.alphaPct(0.22),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      widget.badgeText!,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}