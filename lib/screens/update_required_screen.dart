import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../core/services/remote_config_service.dart';
import '../core/services/tv_mode_service.dart';
import '../widgets/app_update_download_dialog.dart';

/// Full-Screen Mandatory App Update Gate
///
/// If the installed app version is older than the required version set in
/// Voidflix Mission Control, this screen completely blocks access to the app
/// and only presents the update action.
class UpdateRequiredScreen extends StatefulWidget {
  const UpdateRequiredScreen({super.key});

  @override
  State<UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<UpdateRequiredScreen> {
  bool _isChecking = false;

  Future<void> _launchUpdateUrl() async {
    final apkUrl = RemoteConfigService.resolvedApkUrl;
    final update = RemoteConfigService.cachedUpdate;
    final targetVersion = update?.version ?? '0.4.2';

    AppUpdateDownloadDialog.show(
      context,
      downloadUrl: apkUrl,
      targetVersion: targetVersion,
    );
  }

  Future<void> _recheckVersion() async {
    setState(() => _isChecking = true);
    await RemoteConfigService.fetchConfig();
    setState(() => _isChecking = false);

    if (!RemoteConfigService.isUpdateAvailable) {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/');
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFFE50914),
            content: Text(
              'Please install the latest APK update to continue streaming.',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final update = RemoteConfigService.cachedUpdate;
    final targetVersion = update?.version ?? 'Latest';
    final currentVersion = RemoteConfigService.currentAppVersion;
    final notes = update?.releaseNotes ?? [];

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          color: const Color(0xFF0A0A0A),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Clean Netflix Alert Icon
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF141414),
                        border: Border.all(color: Colors.white12, width: 1),
                      ),
                      child: const Icon(
                        Icons.system_security_update_rounded,
                        size: 48,
                        color: Color(0xFFE50914),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Priority Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Text(
                        'UPDATE REQUIRED',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Primary Headline
                    const Text(
                      'Please Update Your App',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Subtitle with version details
                    Text(
                      'Your current app version (v$currentVersion) is outdated.\nVersion v$targetVersion is required to continue streaming movies & TV series.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFAAAAAA),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Changelog Card
                    if (notes.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0xFF141414),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0x14FFFFFF)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.stars_rounded, color: Color(0xFFE50914), size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'What\'s New in v$targetVersion',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            ...notes.map((note) => Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '• ',
                                        style: TextStyle(color: Color(0xFFE50914), fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                      Expanded(
                                        child: Text(
                                          note,
                                          style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 12, height: 1.4),
                                        ),
                                      ),
                                    ],
                                  ),
                                )),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                    ],

                    // Prominent Primary Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _launchUpdateUrl,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE50914),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.download_rounded, size: 22),
                            const SizedBox(width: 10),
                            Text(
                              !kIsWeb && Platform.isWindows
                                  ? 'Update Now (Download Windows App)'
                                  : (!kIsWeb && Platform.isAndroid && (TvModeService().isHardwareTv || TvModeService().isTvMode))
                                      ? 'Update Now (Download Android TV APK)'
                                      : 'Update Now (Download Mobile APK)',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Recheck button
                    TextButton(
                      onPressed: _isChecking ? null : _recheckVersion,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF888888),
                      ),
                      child: _isChecking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE50914)),
                            )
                          : const Text(
                              'I\'ve Installed the Update · Refresh',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
