import 'package:flutter/material.dart';

import '../control_centre/automation_centre.dart';
import '../control_centre/backup_export_screen.dart';
import '../security/biometric_security.dart';
import 'sound_settings.dart';

class SettingsHubScreen extends StatelessWidget {
  const SettingsHubScreen({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(child: ListTile(
          leading: const Icon(Icons.fingerprint_rounded),
          title: const Text('Fingerprint & device security'),
          subtitle: const Text('Manage biometric sign-in and device protection.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, const SecuritySettingsScreen()),
        )),
        Card(child: ListTile(
          leading: const Icon(Icons.volume_up_rounded),
          title: const Text('Sounds & vibration'),
          subtitle: const Text('Control app sounds and feedback.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, const SoundSettingsScreen()),
        )),
        Card(child: ListTile(
          leading: const Icon(Icons.auto_awesome_rounded),
          title: const Text('Automation centre'),
          subtitle: const Text('Manage reminders and automated routines.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, const AutomationCentreScreen()),
        )),
        Card(child: ListTile(
          leading: const Icon(Icons.backup_outlined),
          title: const Text('Backup & export'),
          subtitle: const Text('Export and protect your SkyNest records.'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _open(context, const BackupExportScreen()),
        )),
      ],
    ),
  );
}
