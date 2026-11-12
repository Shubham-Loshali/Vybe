import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/services/cloud_sync_service.dart';
import 'package:vybe/utilities/flutter_toast.dart';
import 'package:vybe/widgets/auth_dialog.dart';
import 'package:vybe/widgets/custom_bar.dart';
import 'package:vybe/widgets/section_header.dart';

class CloudSyncSettingsSection extends StatefulWidget {
  const CloudSyncSettingsSection({super.key});

  @override
  State<CloudSyncSettingsSection> createState() =>
      _CloudSyncSettingsSectionState();
}

class _CloudSyncSettingsSectionState extends State<CloudSyncSettingsSection> {
  void _openAuthPage(BuildContext context) {
    AuthDialog.show(context).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _showSetupDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(FluentIcons.cloud_error_24_regular),
            SizedBox(width: 8),
            Text('Firebase Setup Required'),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            'To connect your free Firebase backend:\n\n'
            '1. Go to console.firebase.google.com and create a project.\n'
            '2. Add an Android app with package name:\n'
            '   com.vybe.music\n'
            '3. Download google-services.json and place it into:\n'
            '   android/app/google-services.json\n'
            '4. In Firebase Console, enable Authentication (Google & Email) and Cloud Firestore.\n\n'
            'Once placed, your app will automatically connect and sync for free!',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(DateTime? dateTime) {
    if (dateTime == null) return 'Never';
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    if (difference.inSeconds < 60) return 'Just now';
    if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
    if (difference.inHours < 24) return '${difference.inHours}h ago';
    return DateFormat.yMMMd().add_jm().format(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SectionHeader(
          title: 'Cloud Backup & Account',
          icon: FluentIcons.cloud_sync_24_filled,
        ),
        if (!CloudSyncService.instance.isFirebaseConfigured)
          CustomBar(
            'Firebase Setup Pending',
            FluentIcons.cloud_error_24_regular,
            description: 'Tap to see instructions to enable free cloud sync',
            onTap: () => _showSetupDialog(context),
          )
        else
          ValueListenableBuilder(
            valueListenable: CloudSyncService.instance.currentUser,
            builder: (context, user, _) {
              if (user == null) {
                return CustomBar(
                  'Sign In & Never Lose Playlists',
                  FluentIcons.person_arrow_right_24_regular,
                  description:
                      'Sign in with Google or Email to safely back up your data',
                  onTap: () => _openAuthPage(context),
                );
              }

              return Column(
                children: [
                  CustomBar(
                    user.displayName ?? user.email ?? 'Connected',
                    FluentIcons.person_available_24_filled,
                    description: 'Email: ${user.email ?? "Google User"}',
                  ),
                  ValueListenableBuilder(
                    valueListenable: CloudSyncService.instance.lastSyncedAt,
                    builder: (context, lastSynced, _) {
                      return ValueListenableBuilder(
                        valueListenable: CloudSyncService.instance.syncState,
                        builder: (context, state, _) {
                          final isSyncing = state == CloudSyncState.syncing;
                          return CustomBar(
                            isSyncing ? 'Syncing with cloud...' : 'Sync Now',
                            FluentIcons.arrow_sync_24_regular,
                            description:
                                'Last synced: ${_formatTimestamp(lastSynced)}',
                            trailing: isSyncing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : null,
                            onTap: isSyncing
                                ? null
                                : () async {
                                    showToast(context, 'Syncing with cloud...');
                                    final success = await CloudSyncService
                                        .instance
                                        .syncToCloud();
                                    if (context.mounted) {
                                      showToast(
                                        context,
                                        success
                                            ? 'Synced successfully!'
                                            : 'Sync failed. Check connection.',
                                      );
                                    }
                                  },
                          );
                        },
                      );
                    },
                  ),
                  CustomBar(
                    'Sign Out',
                    FluentIcons.sign_out_24_regular,
                    iconColor: Theme.of(context).colorScheme.error,
                    textColor: Theme.of(context).colorScheme.error,
                    onTap: () async {
                      await CloudSyncService.instance.signOut();
                      if (context.mounted) {
                        showToast(context, 'Signed out of cloud');
                      }
                    },
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}
