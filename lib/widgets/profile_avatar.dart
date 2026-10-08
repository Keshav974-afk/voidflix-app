import 'package:flutter/material.dart';
import '../providers/profile_provider.dart';

class ProfileAvatarTile extends StatelessWidget {
  final String name;
  final List<Color> gradientColors;
  final double size;
  final bool isKids;
  final bool showEditBadge;
  final bool isLocked;

  const ProfileAvatarTile({
    super.key,
    required this.name,
    required this.gradientColors,
    this.size = 80,
    this.isKids = false,
    this.showEditBadge = false,
    this.isLocked = false,
  });

  factory ProfileAvatarTile.fromProfile({
    Key? key,
    required UserProfile profile,
    double size = 80,
    bool showEditBadge = false,
  }) {
    final colors = ProfileProvider.avatarGradients[
      profile.colorIndex % ProfileProvider.avatarGradients.length
    ];
    return ProfileAvatarTile(
      key: key,
      name: profile.name,
      gradientColors: colors,
      size: size,
      isKids: profile.isKids,
      showEditBadge: showEditBadge,
      isLocked: profile.pin != null && profile.pin!.isNotEmpty,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradientColors,
        ),
        borderRadius: BorderRadius.circular(size * 0.14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Netflix Classic Smiley Custom Painter
          CustomPaint(
            size: Size(size * 0.65, size * 0.65),
            painter: _VoidflixSmileyPainter(),
          ),

          // Lock badge at top-right if PIN locked
          if (isLocked)
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.lock_rounded,
                  size: size * 0.16,
                  color: Colors.white,
                ),
              ),
            ),

          // Kids badge at bottom
          if (isKids)
            Positioned(
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Text(
                  'KIDS',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),

          // Edit pencil badge when managing profiles
          if (showEditBadge)
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(size * 0.14),
              ),
              child: Center(
                child: Icon(
                  Icons.edit_rounded,
                  color: Colors.white,
                  size: size * 0.35,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VoidflixSmileyPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final smilePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.10
      ..strokeCap = StrokeCap.round;

    // Left eye circle
    final eyeRadius = size.width * 0.085;
    canvas.drawCircle(
      Offset(size.width * 0.30, size.height * 0.36),
      eyeRadius,
      whitePaint,
    );

    // Right eye circle
    canvas.drawCircle(
      Offset(size.width * 0.70, size.height * 0.36),
      eyeRadius,
      whitePaint,
    );

    // Smile curved arc
    final path = Path();
    path.moveTo(size.width * 0.22, size.height * 0.58);
    path.quadraticBezierTo(
      size.width * 0.50,
      size.height * 0.88,
      size.width * 0.78,
      size.height * 0.58,
    );

    canvas.drawPath(path, smilePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
