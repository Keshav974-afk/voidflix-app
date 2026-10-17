import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.scaleFactor = 1.08,
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
    if (_isFocused != _node.hasFocus) {
      setState(() => _isFocused = _node.hasFocus);
      widget.onFocusChange?.call(_node.hasFocus);
      if (_node.hasFocus) {
        // Subtle haptic tick for TV remote navigation
        HapticFeedback.selectionClick();
      }
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.space ||
          key == LogicalKeyboardKey.gameButtonA ||
          key == LogicalKeyboardKey.numpadEnter) {
        widget.onPressed?.call();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
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
                          color: widget.glowColor.withValues(alpha: 0.55),
                          blurRadius: 18,
                          spreadRadius: 2.5,
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
                        width: 2.5,
                      )
                    : Border.all(color: Colors.transparent, width: 2.5),
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
