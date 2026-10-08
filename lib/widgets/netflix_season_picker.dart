import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/media_detail.dart';

/// Full-screen Netflix-style Season Picker overlay with blurred backdrop,
/// centered large typography, and circular white bottom close button.
/// Matches flowflix-web/src/components/DetailModal.tsx lines 582-625.
class NetflixSeasonPicker {
  static Future<int?> show({
    required BuildContext context,
    required List<TvSeason> seasons,
    required int selectedSeason,
  }) {
    final validSeasons = seasons.where((s) => s.seasonNumber > 0).toList();
    if (validSeasons.isEmpty) return Future.value(null);

    return showGeneralDialog<int>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.85),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, anim1, anim2) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Material(
            color: Colors.transparent,
            child: SafeArea(
              child: Stack(
                children: [
                  // Dismiss on tapping empty area
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(ctx).pop(),
                      child: const SizedBox.expand(),
                    ),
                  ),

                  // Centered Vertical Season List (Matching Netflix Web & Mobile)
                  Center(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: validSeasons.map((se) {
                          final n = se.seasonNumber;
                          final isSel = n == selectedSeason;
                          final label = se.name.toLowerCase().startsWith('season')
                              ? se.name
                              : 'Season $n';

                          return GestureDetector(
                            onTap: () => Navigator.of(ctx).pop(n),
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              child: Text(
                                label,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: isSel ? 26 : 21,
                                  fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                                  color: isSel ? Colors.white : Colors.white60,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  // Floating Circular Close Button at Bottom (Matching Web/Netflix App)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 28,
                    child: Center(
                      child: GestureDetector(
                        onTap: () => Navigator.of(ctx).pop(),
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black45,
                                blurRadius: 10,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.black,
                            size: 28,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          child: child,
        );
      },
    );
  }
}
