import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/services/tv_mode_service.dart';

class TvFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final ValueChanged<bool>? onFocusChange;
  final FocusNode? focusNode;
  final bool autofocus;
  final double scaleFactor;
  final BorderRadius? borderRadius;
  final Color glowColor;
  final bool showGlow;
  final EdgeInsetsGeometry padding;

  const TvFocusable({
    super.key,
    required this.child,
    this.onPressed,
    this.onFocusChange,
    this.focusNode,
    this.autofocus = false,
    this.scaleFactor = 1.06,
    this.borderRadius,
    this.glowColor = Colors.white,
    this.showGlow = true,
    this.padding = EdgeInsets.zero,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  late FocusNode _node;
  bool _isFocused = false;

  bool get _isTvActive =>
      TvModeService().isTvMode || TvModeService().isHardwareTv;

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode();
    _node.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant TvFocusable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focusNode != oldWidget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChange);
      _node = widget.focusNode ?? FocusNode();
      _node.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    if (widget.focusNode == null) {
      _node.dispose();
    } else {
      _node.removeListener(_handleFocusChange);
    }
    super.dispose();
  }

  void _handleFocusChange() {
    if (!_isTvActive) {
      if (_isFocused) {
        setState(() => _isFocused = false);
      }
      return;
    }
    if (_isFocused != _node.hasFocus) {
      setState(() => _isFocused = _node.hasFocus);
      widget.onFocusChange?.call(_node.hasFocus);
      if (_node.hasFocus) {
        HapticFeedback.selectionClick();
        if (mounted) {
          Scrollable.ensureVisible(
            context,
            alignment: 0.5,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
          );
        }
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!_isTvActive) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.space ||
          key == LogicalKeyboardKey.gameButtonA ||
          key == LogicalKeyboardKey.gameButtonSelect ||
          key == LogicalKeyboardKey.numpadEnter ||
          key.keyId == 0x00100000017 || // KEYCODE_DPAD_CENTER
          key.keyId == 23) {
        widget.onPressed?.call();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // On mobile/touch devices when TV mode is not enabled, do NOT attach D-pad
    // autofocus, white borders, or focus glow outlines.
    if (!_isTvActive) {
      if (widget.onPressed == null) {
        return Padding(
          padding: widget.padding,
          child: widget.child,
        );
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Padding(
          padding: widget.padding,
          child: widget.child,
        ),
      );
    }

    final radius = widget.borderRadius ?? BorderRadius.circular(8);

    return Focus(
      focusNode: _node,
      autofocus: widget.autofocus,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Padding(
          padding: widget.padding,
          child: AnimatedScale(
            scale: _isFocused ? widget.scaleFactor : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: _isFocused && widget.showGlow
                    ? [
                        BoxShadow(
                          color: widget.glowColor.withValues(alpha: 0.45),
                          blurRadius: 16,
                          spreadRadius: 1.5,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.8),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ]
                    : null,
                border: _isFocused
                    ? Border.all(
                        color: widget.glowColor,
                        width: 2.0,
                      )
                    : Border.all(color: Colors.transparent, width: 2.0),
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
