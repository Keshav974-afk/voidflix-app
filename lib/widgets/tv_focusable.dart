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
      TvModeService().isTvMode ||
      TvModeService().isHardwareTv ||
      TvModeService().hasDpadDetected;

  bool get _shouldShowVisualFocus =>
      _isFocused &&
      (_isTvActive ||
          FocusManager.instance.highlightMode == FocusHighlightMode.traditional);

  bool get _effectiveAutofocus =>
      widget.autofocus &&
      (_isTvActive ||
          FocusManager.instance.highlightMode == FocusHighlightMode.traditional);

  @override
  void initState() {
    super.initState();
    _node = widget.focusNode ?? FocusNode();
    _node.addListener(_handleFocusChange);
    TvModeService().addListener(_onTvServiceChange);
  }

  void _onTvServiceChange() {
    if (mounted) setState(() {});
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
    TvModeService().removeListener(_onTvServiceChange);
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
        if (_isTvActive ||
            FocusManager.instance.highlightMode ==
                FocusHighlightMode.traditional) {
          HapticFeedback.selectionClick();
        }
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
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowUp ||
          key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowRight) {
        TvModeService().markDpadUsed();
      }
      if (key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.space ||
          key == LogicalKeyboardKey.gameButtonA ||
          key == LogicalKeyboardKey.gameButtonSelect ||
          key == LogicalKeyboardKey.numpadEnter ||
          key.keyId == 0x00100000017 || // KEYCODE_DPAD_CENTER
          key.keyId == 23) {
        TvModeService().markDpadUsed();
        widget.onPressed?.call();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(8);
    final showHighlight = _shouldShowVisualFocus;

    return Focus(
      focusNode: _node,
      autofocus: _effectiveAutofocus,
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Padding(
          padding: widget.padding,
          child: AnimatedScale(
            scale: showHighlight ? widget.scaleFactor : 1.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: radius,
                boxShadow: showHighlight && widget.showGlow
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
                border: showHighlight
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
