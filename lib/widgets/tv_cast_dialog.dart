import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/services/voidcast_service.dart';
import 'tv_focusable.dart';

class TvCastDialog extends StatefulWidget {
  const TvCastDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const TvCastDialog(),
    );
  }

  @override
  State<TvCastDialog> createState() => _TvCastDialogState();
}

class _TvCastDialogState extends State<TvCastDialog> {
  String? _tvCode;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initTvHosting();
  }

  Future<void> _initTvHosting() async {
    final cast = VoidCastService();
    final code = await cast.startHosting(deviceName: 'Voidflix Living Room TV');
    if (mounted) {
      setState(() {
        _tvCode = code;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<VoidCastService>(
      builder: (context, cast, _) {
        final isConnected = cast.isConnected;
        final code = _tvCode ?? cast.roomCode ?? '------';
        final formattedCode = code.length == 6
            ? '${code.substring(0, 3)} - ${code.substring(3)}'
            : code;

        return Dialog(
          backgroundColor: const Color(0xFF12121C),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Colors.white12),
          ),
          child: Container(
            width: 520,
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon & Title
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF00B4D8).withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.cast_connected_rounded, color: Color(0xFF00B4D8), size: 28),
                    ),
                    const SizedBox(width: 14),
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Link Phone to TV',
                          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'VoidCast Wireless Remote & Beam',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // TV Code Box
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A28),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isConnected ? Colors.greenAccent.withValues(alpha: 0.6) : const Color(0xFF00B4D8).withValues(alpha: 0.4),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: (isConnected ? Colors.greenAccent : const Color(0xFF00B4D8)).withValues(alpha: 0.12),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'TV PAIRING CODE',
                        style: TextStyle(
                          color: Color(0xFF00B4D8),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_loading)
                        const SizedBox(
                          height: 48,
                          child: Center(
                            child: CircularProgressIndicator(color: Color(0xFF00B4D8), strokeWidth: 2),
                          ),
                        )
                      else
                        Text(
                          formattedCode,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 6,
                            fontFamily: 'monospace',
                          ),
                        ),
                      const SizedBox(height: 8),
                      // Status Indicator
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: BoxDecoration(
                              color: isConnected ? Colors.greenAccent : Colors.amberAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Text(
                            isConnected
                                ? 'Connected to Phone!'
                                : 'Waiting for connection from phone...',
                            style: TextStyle(
                              color: isConnected ? Colors.greenAccent : Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Steps Instructions
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Column(
                    children: [
                      _StepRow(number: '1', text: 'Open Voidflix app on your mobile phone or browser'),
                      SizedBox(height: 8),
                      _StepRow(number: '2', text: 'Tap the Cast icon at the top of the screen'),
                      SizedBox(height: 8),
                      _StepRow(number: '3', text: 'Enter this 6-digit code to play movies and use phone remote'),
                    ],
                  ),
                ),
                const SizedBox(height: 22),

                // Close Button
                TvFocusable(
                  autofocus: true,
                  scaleFactor: 1.05,
                  glowColor: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Container(
                    width: double.infinity,
                    height: 44,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'Done',
                      style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StepRow extends StatelessWidget {
  final String number;
  final String text;

  const _StepRow({required this.number, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFF00B4D8),
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3),
          ),
        ),
      ],
    );
  }
}
