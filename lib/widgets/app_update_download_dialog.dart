import 'package:flutter/material.dart';
import '../core/services/app_update_service.dart';

/// Interactive In-App Update Download Dialog / Sheet
class AppUpdateDownloadDialog extends StatefulWidget {
  final String downloadUrl;
  final String targetVersion;
  final VoidCallback? onComplete;

  const AppUpdateDownloadDialog({
    super.key,
    required this.downloadUrl,
    required this.targetVersion,
    this.onComplete,
  });

  static Future<void> show(
    BuildContext context, {
    required String downloadUrl,
    required String targetVersion,
    VoidCallback? onComplete,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AppUpdateDownloadDialog(
          downloadUrl: downloadUrl,
          targetVersion: targetVersion,
          onComplete: onComplete,
        ),
      ),
    );
  }

  @override
  State<AppUpdateDownloadDialog> createState() => _AppUpdateDownloadDialogState();
}

class _AppUpdateDownloadDialogState extends State<AppUpdateDownloadDialog> {
  double _progress = 0.0;
  int _receivedBytes = 0;
  int _totalBytes = 0;
  UpdateDownloadStatus _status = UpdateDownloadStatus.idle;
  String _statusMessage = 'Preparing download…';

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  Future<void> _startDownload() async {
    setState(() {
      _progress = 0.0;
      _status = UpdateDownloadStatus.downloading;
      _statusMessage = 'Connecting to Voidflix servers…';
    });

    final success = await AppUpdateService.downloadAndInstall(
      downloadUrl: widget.downloadUrl,
      targetVersion: widget.targetVersion,
      onProgress: (progress, received, total) {
        if (mounted) {
          setState(() {
            _progress = progress;
            _receivedBytes = received;
            _totalBytes = total;
          });
        }
      },
      onStatusChanged: (status, msg) {
        if (mounted) {
          setState(() {
            _status = status;
            if (msg != null) _statusMessage = msg;
          });
          if (status == UpdateDownloadStatus.completed && widget.onComplete != null) {
            widget.onComplete!();
          }
        }
      },
    );

    if (!success && mounted && _status != UpdateDownloadStatus.cancelled) {
      setState(() {
        _status = UpdateDownloadStatus.error;
      });
    }
  }

  void _handleCancel() {
    AppUpdateService.cancelDownload();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final percentText = (_progress * 100).toInt();
    final downloadedStr = AppUpdateService.formatBytes(_receivedBytes);
    final totalStr = _totalBytes > 0 ? AppUpdateService.formatBytes(_totalBytes) : 'Unknown';

    final isDone = _status == UpdateDownloadStatus.completed || _status == UpdateDownloadStatus.installing;
    final isError = _status == UpdateDownloadStatus.error;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: const Color(0xFF16161D),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0x33E50914), width: 1.5),
          boxShadow: const [
            BoxShadow(
              color: Colors.black87,
              blurRadius: 30,
              spreadRadius: 10,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header Icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone
                    ? const Color(0x2646D369)
                    : isError
                        ? const Color(0x26FF5252)
                        : const Color(0x26E50914),
                border: Border.all(
                  color: isDone
                      ? const Color(0xFF46D369)
                      : isError
                          ? const Color(0xFFFF5252)
                          : const Color(0xFFE50914),
                  width: 2,
                ),
              ),
              child: Icon(
                isDone
                    ? Icons.check_circle_outline_rounded
                    : isError
                        ? Icons.error_outline_rounded
                        : Icons.downloading_rounded,
                size: 38,
                color: isDone
                    ? const Color(0xFF46D369)
                    : isError
                        ? const Color(0xFFFF5252)
                        : const Color(0xFFE50914),
              ),
            ),
            const SizedBox(height: 18),

            // Title
            Text(
              isDone
                  ? 'Installing Update…'
                  : isError
                      ? 'Download Failed'
                      : 'Downloading Voidflix v${widget.targetVersion}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),

            // Subtitle status message
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isError ? const Color(0xFFFF5252) : const Color(0xFFAAAAAA),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            // Progress Bar
            if (!isError) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 10,
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    backgroundColor: const Color(0xFF2B2B36),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isDone ? const Color(0xFF46D369) : const Color(0xFFE50914),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Progress metrics
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '$percentText%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '$downloadedStr / $totalStr',
                    style: const TextStyle(
                      color: Color(0xFF888899),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                if (!isDone)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _handleCancel,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                if (!isDone && isError) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _startDownload,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE50914),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
                if (isDone)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        // Re-trigger install prompt if needed
                        _startDownload();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE50914),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Re-open Installer', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
