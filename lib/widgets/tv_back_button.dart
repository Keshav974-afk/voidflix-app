import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants/theme_constants.dart';
import '../core/services/tv_mode_service.dart';
import 'tv_focusable.dart';

/// TV and Leanback-optimized Back Button.
///
/// Features:
/// 1. D-Pad navigable with [TvFocusable] (scale animation + glowing border).
/// 2. Clear visual cues on 10-foot TV displays: "[ ← Back ]" pill with elevated contrast.
/// 3. Responds to hardware back triggers: Remote Select, Enter, Space, Gamepad A.
/// 4. Global key shortcut support: Escape, Backspace, Remote Back key.
class TvBackButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String? label;
  final bool? showLabel;
  final bool autofocus;
  final Color? color;
  final Color? focusGlowColor;
  final bool showBackground;
  final EdgeInsetsGeometry? padding;
  final FocusNode? focusNode;

  const TvBackButton({
    super.key,
    this.onPressed,
    this.label,
    this.showLabel,
    this.autofocus = false,
    this.color,
    this.focusGlowColor,
    this.showBackground = false,
    this.padding,
    this.focusNode,
  });

  void _handleBack(BuildContext context) {
    if (onPressed != null) {
      onPressed!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTv = TvModeService().isTvMode;
    final displayLabel = label ?? 'Back';
    final shouldShowLabel = showLabel ?? isTv;
    final textColor = color ?? Colors.white;
    final glow = focusGlowColor ?? AppTheme.primaryRed;

    final childWidget = Container(
      padding: padding ??
          (shouldShowLabel
              ? const EdgeInsets.symmetric(horizontal: 14, vertical: 7)
              : const EdgeInsets.all(8)),
      decoration: BoxDecoration(
        color: showBackground
            ? Colors.black.withValues(alpha: 0.75)
            : (isTv ? const Color(0xFF1E1E28) : Colors.black.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isTv ? Colors.white24 : Colors.white12,
          width: 1.0,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.arrow_back_rounded,
            color: textColor,
            size: isTv ? 20 : 18,
          ),
          if (shouldShowLabel) ...[
            const SizedBox(width: 6),
            Text(
              displayLabel,
              style: TextStyle(
                color: textColor,
                fontSize: isTv ? 14 : 13,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ],
      ),
    );

    return Semantics(
      label: 'Back',
      button: true,
      child: TvFocusable(
        focusNode: focusNode,
        autofocus: autofocus,
        scaleFactor: 1.08,
        glowColor: glow,
        borderRadius: BorderRadius.circular(24),
        onPressed: () => _handleBack(context),
        child: childWidget,
      ),
    );
  }
}

/// A wrapper widget that listens for global TV remote back / desktop keyboard back keys
/// ([LogicalKeyboardKey.escape], [LogicalKeyboardKey.backspace], [LogicalKeyboardKey.goBack])
/// and automatically invokes [Navigator.maybePop] on the active route.
class TvScreenWrapper extends StatelessWidget {
  final Widget child;
  final VoidCallback? onBack;
  final bool enableBackShortcut;

  const TvScreenWrapper({
    super.key,
    required this.child,
    this.onBack,
    this.enableBackShortcut = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!enableBackShortcut) return child;

    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.escape ||
              key == LogicalKeyboardKey.backspace ||
              key == LogicalKeyboardKey.goBack ||
              key == LogicalKeyboardKey.browserBack) {
            if (onBack != null) {
              onBack!();
              return KeyEventResult.handled;
            } else if (Navigator.of(context).canPop()) {
              Navigator.of(context).maybePop();
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}
