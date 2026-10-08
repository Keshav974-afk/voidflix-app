import 'package:flutter/material.dart';
import 'settings_screen.dart';

export 'settings_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsScreen(initialSection: SettingsSection.account);
  }
}
