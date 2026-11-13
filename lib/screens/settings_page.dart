import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/constants/app_constants.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/main.dart';
import 'package:vybe/screens/local_sync_page.dart';
import 'package:vybe/screens/search_page.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/data_manager.dart';
import 'package:vybe/services/listening_stats_service.dart';
import 'package:vybe/services/local_sync_service.dart';
import 'package:vybe/services/playlist_download_service.dart';
import 'package:vybe/services/playlists_manager.dart';
import 'package:vybe/services/router_service.dart';
import 'package:vybe/services/settings_manager.dart';
import 'package:vybe/services/update_manager.dart';
import 'package:vybe/theme/app_themes.dart';
import 'package:vybe/utilities/flutter_toast.dart';
import 'package:vybe/utilities/platform_utils.dart';
import 'package:vybe/widgets/cloud_sync_settings_section.dart';
import 'package:vybe/widgets/confirmation_dialog.dart';
import 'package:vybe/widgets/custom_bar.dart';
import 'package:vybe/widgets/mini_player_bottom_space.dart';
import 'package:vybe/widgets/section_header.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final activatedColor = Theme.of(context).colorScheme.secondaryContainer;
    final inactivatedColor = Theme.of(context).colorScheme.surfaceContainerHigh;

    final content = Column(
      children: <Widget>[
        _buildPreferencesSection(
          context,
          primaryColor,
          activatedColor,
          inactivatedColor,
        ),
        if (!offlineMode.value) _buildOnlineFeaturesSection(context),
        const CloudSyncSettingsSection(),
        const LocalSyncSettingsSection(),
        const SizedBox(height: 20),
        const MiniPlayerBottomSpace(),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.l10n!.settings,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: 'Figtree'),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: IconButton(
              tooltip: 'Developers & support',
              onPressed: () => context.push(NavigationManager.developersPath),
              icon: Icon(
                FluentIcons.people_team_24_regular,
                color: primaryColor,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: commonSingleChildScrollViewPadding,
        child: content,
      ),
    );
  }

  Widget _buildPreferencesSection(
    BuildContext context,
    Color primaryColor,
    Color activatedColor,
    Color inactivatedColor,
  ) {
    return Column(
      children: [
        SectionHeader(
          title: context.l10n!.preferences,
          icon: FluentIcons.options_24_filled,
        ),
        if (isAndroidPlatform)
          CustomBar(
            context.l10n!.equalizer,
            FluentIcons.data_histogram_24_regular,
            borderRadius: commonCustomBarRadiusFirst,
            onTap: () => context.push('/settings/equalizer'),
          ),
        ValueListenableBuilder<bool>(
          valueListenable: useProxy,
          builder: (_, value, __) {
            return CustomBar(
              context.l10n!.useProxy,
              FluentIcons.shield_24_regular,
              description: context.l10n!.useProxyDescription,
              trailing: Switch(
                value: value,
                onChanged: (value) {
                  useProxy.value = value;
                  addOrUpdateData<bool>('settings', 'useProxy', value);
                  showToast(context, context.l10n!.settingChangedMsg);
                },
              ),
            );
          },
        ),
        ValueListenableBuilder<bool>(
          valueListenable: wrappedEnabled,
          builder: (_, value, __) {
            return CustomBar(
              context.l10n!.listeningStats,
              FluentIcons.clock_24_regular,
              description: context.l10n!.listeningStatsDescription,
              trailing: Switch(
                value: value,
                onChanged: (value) => _toggleWrapped(context, value),
              ),
            );
          },
        ),
        if (!isFdroidBuild && isMobilePlatform)
          ValueListenableBuilder<bool?>(
            valueListenable: shouldWeCheckUpdates,
            builder: (_, value, __) {
              return CustomBar(
                context.l10n!.automaticUpdateChecks,
                FluentIcons.arrow_sync_24_regular,
                description: context.l10n!.automaticUpdateChecksDescription,
                trailing: Switch(
                  value: value ?? false,
                  onChanged: (value) =>
                      _toggleAutomaticUpdateChecks(context, value),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildOnlineFeaturesSection(BuildContext context) {
    return Column(
      children: [
        ValueListenableBuilder<bool>(
          valueListenable: playNextSongAutomatically,
          builder: (_, value, __) {
            return CustomBar(
              context.l10n!.automaticSongPicker,
              FluentIcons.music_note_2_play_20_regular,
              description: context.l10n!.automaticSongPickerDescription,
              borderRadius: commonCustomBarRadiusFirst,
              trailing: Switch(
                value: value,
                onChanged: (value) {
                  _toggleAutoPlayNext(context, value);
                  showToast(context, context.l10n!.settingChangedMsg);
                },
              ),
            );
          },
        ),
        ValueListenableBuilder<bool>(
          valueListenable: externalRecommendations,
          builder: (_, value, __) {
            return CustomBar(
              context.l10n!.externalRecommendations,
              FluentIcons.channel_share_24_regular,
              description: context.l10n!.externalRecommendationsDescription,
              trailing: Switch(
                value: value,
                onChanged: (value) =>
                    _toggleExternalRecommendations(context, value),
              ),
            );
          },
        ),

        _buildToolsSection(context),
      ],
    );
  }

  Widget _buildToolsSection(BuildContext context) {
    return Column(
      children: [
        SectionHeader(
          title: context.l10n!.tools,
          icon: FluentIcons.toolbox_24_filled,
        ),
        CustomBar(
          context.l10n!.clearCache,
          FluentIcons.broom_24_regular,
          borderRadius: commonCustomBarRadiusFirst,
          onTap: () async {
            final cleared = await clearCache();
            showToast(
              context,
              cleared ? '${context.l10n!.cacheMsg}!' : context.l10n!.error,
            );
          },
        ),
        CustomBar(
          context.l10n!.clearSearchHistory,
          FluentIcons.history_24_regular,
          onTap: () => _showConfirmationDialog(
            context: context,
            confirmationMessage: context.l10n!.clearSearchHistoryQuestion,
            onSubmit: () {
              searchHistoryNotifier.value = [];
              addOrUpdateData('user', 'searchHistory', <dynamic>[]);
              showToast(context, '${context.l10n!.searchHistoryMsg}!');
            },
          ),
        ),
        CustomBar(
          context.l10n!.clearRecentlyPlayed,
          FluentIcons.receipt_play_24_regular,
          onTap: () => _showConfirmationDialog(
            context: context,
            confirmationMessage: context.l10n!.clearRecentlyPlayedQuestion,
            onSubmit: () {
              userRecentlyPlayed.value = [];
              addOrUpdateData('user', 'recentlyPlayedSongs', <dynamic>[]);
              showToast(context, '${context.l10n!.recentlyPlayedMsg}!');
            },
          ),
        ),
        CustomBar(
          context.l10n!.clearListeningStats,
          FluentIcons.clock_24_regular,
          onTap: () => _showConfirmationDialog(
            context: context,
            confirmationMessage: context.l10n!.clearListeningStatsQuestion,
            submitMessage: context.l10n!.delete,
            isDangerous: true,
            onSubmit: () async {
              audioHandler.resetListeningStatsSession(flushStats: false);
              await listeningStatsService.clearStats();
              audioHandler.startListeningStatsSessionIfNeeded();
              if (context.mounted) {
                showToast(context, '${context.l10n!.listeningStatsCleared}!');
              }
            },
          ),
        ),
        CustomBar(
          context.l10n!.deleteDownloads,
          FluentIcons.delete_24_regular,
          onTap: () => _showConfirmationDialog(
            context: context,
            confirmationMessage: context.l10n!.deleteDownloadsQuestion,
            submitMessage: context.l10n!.delete,
            isDangerous: true,
            onSubmit: () async {
              try {
                await offlinePlaylistService.deleteAllDownloads();
                if (context.mounted) {
                  showToast(context, context.l10n!.downloadsDeleted);
                }
              } catch (e) {
                if (context.mounted) {
                  showToast(context, context.l10n!.error);
                }
              }
            },
          ),
        ),
        CustomBar(
          context.l10n!.importSpotifyPlaylist,
          FluentIcons.arrow_upload_24_regular,
          onTap: () => context.push('/settings/import-spotify-playlist'),
        ),
        CustomBar(
          context.l10n!.backupUserData,
          FluentIcons.cloud_sync_24_regular,
          onTap: () => _backupUserData(context),
        ),
        CustomBar(
          context.l10n!.restoreUserData,
          FluentIcons.cloud_add_24_regular,
          onTap: () async {
            var storageChanged = false;
            try {
              await LocalSyncService.instance.pauseForStorageRestore();
              if (!context.mounted) return;
              final result = await restoreData(
                context,
                onStorageChanged: (changed) => storageChanged = changed,
              );
              if (result.success) {
                reloadSettingsFromStorage();
                reloadSongLibraryStateFromStorage();
                reloadPlaylistLibraryStateFromStorage();
                reloadSearchHistoryFromStorage();
                listeningStatsService.reload();
                await audioHandler.setShuffleMode(
                  shuffleNotifier.value
                      ? AudioServiceShuffleMode.all
                      : AudioServiceShuffleMode.none,
                );
                await audioHandler.setRepeatMode(repeatNotifier.value);
                themeMode = getThemeMode(themeModeSetting);
                brightness = getBrightnessFromThemeMode(themeMode);
                if (context.mounted) {
                  await Vybe.updateAppState(
                    context,
                    newThemeMode: themeMode,
                    newLocale: languageSetting,
                    newAccentColor: primaryColorSetting,
                    useSystemColor: useSystemColor.value,
                  );
                  NavigationManager.refreshRouter();
                }
              }
              if (context.mounted) {
                showToast(
                  context,
                  result.message,
                  icon: result.success
                      ? null
                      : FluentIcons.error_circle_24_regular,
                );
              }
            } catch (e, str) {
              logger.log('Error restoring data', error: e, stackTrace: str);
              if (context.mounted) {
                showToast(
                  context,
                  context.l10n!.error,
                  icon: FluentIcons.error_circle_24_regular,
                );
              }
            } finally {
              await LocalSyncService.instance.resumeAfterStorageRestore(
                storageChanged: storageChanged,
              );
            }
          },
        ),
        if (!isFdroidBuild && isMobilePlatform)
          CustomBar(
            context.l10n!.downloadAppUpdate,
            FluentIcons.arrow_download_24_regular,
            borderRadius: commonCustomBarRadiusLast,
            onTap: checkAppUpdates,
          ),
      ],
    );
  }

  Future<void> _toggleWrapped(BuildContext context, bool value) async {
    if (!value) {
      audioHandler.resetListeningStatsSession(
        countCurrentTick: true,
        flushStats: false,
      );
      await listeningStatsService.flush();
    }

    await addOrUpdateData<bool>('settings', 'wrappedEnabled', value);
    wrappedEnabled.value = value;
    listeningStatsService.reload();
    if (value) {
      audioHandler.startListeningStatsSessionIfNeeded();
    }
    if (context.mounted) {
      showToast(context, context.l10n!.settingChangedMsg);
    }
  }

  void _toggleAutoPlayNext(BuildContext context, bool value) {
    addOrUpdateData<bool>('settings', 'playNextSongAutomatically', value);
    playNextSongAutomatically.value = value;
    showToast(context, context.l10n!.settingChangedMsg);
  }

  void _toggleAutomaticUpdateChecks(BuildContext context, bool value) {
    addOrUpdateData<bool>('settings', 'shouldWeCheckUpdates', value);
    shouldWeCheckUpdates.value = value;
    showToast(context, context.l10n!.settingChangedMsg);
  }

  void _toggleExternalRecommendations(BuildContext context, bool value) {
    addOrUpdateData<bool>('settings', 'externalRecommendations', value);
    externalRecommendations.value = value;
    showToast(context, context.l10n!.settingChangedMsg);
  }

  void _showConfirmationDialog({
    required BuildContext context,
    required String confirmationMessage,
    required VoidCallback onSubmit,
    String? submitMessage,
    bool isDangerous = false,
  }) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return ConfirmationDialog(
          submitMessage: submitMessage ?? context.l10n!.clear,
          confirmationMessage: confirmationMessage,
          isDangerous: isDangerous,
          onCancel: () => Navigator.of(context).pop(),
          onSubmit: () {
            Navigator.of(context).pop();
            onSubmit();
          },
        );
      },
    );
  }

  Future<void> _backupUserData(BuildContext context) async {
    try {
      final result = await backupData(context);
      if (context.mounted) {
        showToast(
          context,
          result.message,
          icon: result.success ? null : FluentIcons.error_circle_24_regular,
        );
      }
    } catch (e, stackTrace) {
      logger.log('Error backing up data', error: e, stackTrace: stackTrace);
      if (context.mounted) {
        showToast(
          context,
          context.l10n!.error,
          icon: FluentIcons.error_circle_24_regular,
        );
      }
    }
  }
}
