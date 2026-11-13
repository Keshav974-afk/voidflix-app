import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/constants/theme_constants.dart';
import '../models/media_item.dart';
import 'media_card.dart';

class MediaRow extends StatefulWidget {
  final String title;
  final List<MediaItem> items;
  final String? forceType;
  final VoidCallback? onSeeAll;

  const MediaRow({
    super.key,
    required this.title,
    required this.items,
    this.forceType,
    this.onSeeAll,
  });

  @override
  State<MediaRow> createState() => _MediaRowState();
}

class _MediaRowState extends State<MediaRow> {
  final ScrollController _scrollController = ScrollController();
  bool _isHovered = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scroll(int direction) {
    if (!_scrollController.hasClients) return;
    final viewportWidth = _scrollController.position.viewportDimension;
    final scrollDelta = (viewportWidth * 0.75) * direction;
    final target = (_scrollController.offset + scrollDelta)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = !kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS || screenWidth >= 850);

    final cardWidth = isDesktop ? 245.0 : 130.0;
    final cardHeight = isDesktop ? 145.0 : 195.0;
    final rowHeight = isDesktop ? 152.0 : 195.0;

    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.title,
                    style: TextStyle(
                      fontSize: isDesktop ? 20 : 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  if (widget.onSeeAll != null)
                    GestureDetector(
                      onTap: widget.onSeeAll,
                      child: const Text(
                        'See All',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryRed,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: rowHeight,
              child: Stack(
                children: [
                  ListView.builder(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    itemCount: widget.items.length,
                    itemBuilder: (context, index) {
                      return MediaCard(
                        item: widget.items[index],
                        forceType: widget.forceType,
                        width: cardWidth,
                        height: cardHeight,
                        isLandscape: isDesktop,
                      );
                    },
                  ),

                  // Desktop Hover Left Scroll Arrow
                  if (isDesktop && _isHovered)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: () => _scroll(-1),
                        child: Container(
                          width: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: [
                                Colors.black.withValues(alpha: 0.85),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: const Center(
                            child: Icon(Icons.chevron_left_rounded, color: Colors.white, size: 36),
                          ),
                        ),
                      ),
                    ),

                  // Desktop Hover Right Scroll Arrow
                  if (isDesktop && _isHovered)
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: GestureDetector(
                        onTap: () => _scroll(1),
                        child: Container(
                          width: 48,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerRight,
                              end: Alignment.centerLeft,
                              colors: [
                                Colors.black.withValues(alpha: 0.85),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: const Center(
                            child: Icon(Icons.chevron_right_rounded, color: Colors.white, size: 36),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
