import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:audio_service/audio_service.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/localization/app_localizations.dart';
import 'package:vybe/screens/listen_together_page.dart';
import 'package:vybe/screens/local_sync_page.dart';
import 'package:vybe/screens/startup_splash.dart';
import 'package:vybe/services/audio_service.dart';
import 'package:vybe/services/cloud_sync_service.dart';
import 'package:vybe/services/collaborative_playlist_service.dart';
import 'package:vybe/services/data_manager.dart';
import 'package:vybe/services/followed_artists_service.dart';
import 'package:vybe/services/home_feed_service.dart';
import 'package:vybe/services/io_service.dart';
import 'package:vybe/services/listen_together_service.dart';
import 'package:vybe/services/listening_stats_service.dart';
import 'package:vybe/services/local_sync_service.dart';
import 'package:vybe/services/logger_service.dart';
import 'package:vybe/services/offline_backup_service.dart';
import 'package:vybe/services/playlist_sharing.dart';
import 'package:vybe/services/playlists_manager.dart';
import 'package:vybe/services/router_service.dart';
import 'package:vybe/services/settings_manager.dart';
import 'package:vybe/services/update_manager.dart';
import 'package:vybe/theme/app_themes.dart';
import 'package:vybe/utilities/flutter_toast.dart';
import 'package:vybe/utilities/language_utils.dart';
import 'package:vybe/utilities/platform_utils.dart';
import 'package:vybe/utilities/playlist_utils.dart';
import 'package:vybe/utilities/sharing_intent.dart';

late VybeAudioHandler audioHandler;
StreamSubscription<String?>? sharingIntentSubscription;
StreamSubscription<Uri?>? appLinksSubscription;

final logger = Logger();
final appLinks = AppLinks();

bool isFdroidBuild = false;
bool isUpdateChecked = false;

class Vybe extends StatefulWidget {
  const Vybe({super.key});

  static Future<void> updateAppState(
    BuildContext context, {
    ThemeMode? newThemeMode,
    Locale? newLocale,
    Color? newAccentColor,
    bool? useSystemColor,
  }) async {
    context.findAncestorStateOfType<_VybeState>()!.changeSettings(
      newThemeMode: newThemeMode,
      newLocale: newLocale,
      newAccentColor: newAccentColor,
      systemColorStatus: useSystemColor,
    );
  }

  @override
  _VybeState createState() => _VybeState();
}

class _VybeState extends State<Vybe> with WidgetsBindingObserver {
  void changeSettings({
    ThemeMode? newThemeMode,
    Locale? newLocale,
    Color? newAccentColor,
    bool? systemColorStatus,
  }) {
    setState(() {
      if (newThemeMode != null) {
        themeMode = newThemeMode;
        brightness = getBrightnessFromThemeMode(newThemeMode);
      }
      if (newLocale != null) {
        languageSetting = newLocale;
      }
      if (newAccentColor != null) {
        if (systemColorStatus != null &&
            useSystemColor.value != systemColorStatus) {
          useSystemColor.value = systemColorStatus;
          addOrUpdateData<bool>(
            'settings',
            'useSystemColor',
            systemColorStatus,
          );
        }
        primaryColorSetting = newAccentColor;
      }
    });
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    if (isMobilePlatform) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    final platformDispatcher = PlatformDispatcher.instance;

    // This callback is called every time the brightness changes.
    platformDispatcher.onPlatformBrightnessChanged = () {
      if (themeMode == ThemeMode.system) {
        setState(() {
          brightness = platformDispatcher.platformBrightness;
        });
      }
    };

    offlineMode.addListener(_onOfflineModeChanged);
    LocalSyncService.instance.incomingPairingRequest.addListener(
      showIncomingPairingDialog,
    );

    if (isMobilePlatform) {
      sharingIntentSubscription = ReceiveSharingIntent.getTextStream().listen(
        (String? value) async {
          await consumeYoutubeSharedTextIntent(
            value,
            audioHandler: audioHandler,
            onError: (error, stackTrace) {
              logger.log(
                'Error while playing shared song:',
                error: error,
                stackTrace: stackTrace,
              );
            },
          );
        },
        onError: (err) {
          logger.log('getTextStream error:', error: err);
        },
      );
    }

    try {
      LicenseRegistry.addLicense(() async* {
        final license = await rootBundle.loadString(
          'assets/licenses/paytone.txt',
        );
        yield LicenseEntryWithLineBreaks(['paytoneOne'], license);
      });
    } catch (e, stackTrace) {
      logger.log(
        'License Registration Error',
        error: e,
        stackTrace: stackTrace,
      );
    }

    if (!isFdroidBuild && isMobilePlatform) {
      if (shouldWeCheckUpdates.value != false) {
        // Enable update checks automatically in background for new users without showing prompt
        if (shouldWeCheckUpdates.value == null) {
          shouldWeCheckUpdates.value = true;
          addOrUpdateData<bool>('settings', 'shouldWeCheckUpdates', true);
        }

        if (!isUpdateChecked && kReleaseMode) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (!offlineMode.value) {
              checkAppUpdates();
            }
            isUpdateChecked = true;
          });
        }
      } else {
        SchedulerBinding.instance.addPostFrameCallback((_) async {
          if (!offlineMode.value) {
            await fetchAnnouncementOnly();
          }
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(LocalSyncService.instance.syncOnResume());
      if (kReleaseMode && !offlineMode.value && !isFdroidBuild) {
        unawaited(fetchAnnouncementOnly());
      }
    }
    super.didChangeAppLifecycleState(state);
    // Persist listening stats when the app leaves the foreground. This is the
    // reliable moment to snapshot and flush: unlike widget dispose, these
    // callbacks are delivered before the OS suspends or terminates the process.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      listeningStatsService.recordListeningSessionProgress(
        wasPlaying: audioHandler.audioPlayer.playing,
      );
      unawaited(listeningStatsService.flush());
      unawaited(OfflineBackupService.instance.flushBackup());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    offlineMode.removeListener(_onOfflineModeChanged);
    PlatformDispatcher.instance.onPlatformBrightnessChanged = null;

    LocalSyncService.instance.incomingPairingRequest.removeListener(
      showIncomingPairingDialog,
    );
    unawaited(LocalSyncService.instance.dispose());
    Hive.close();
    unawaited(sharingIntentSubscription?.cancel());
    unawaited(appLinksSubscription?.cancel());
    super.dispose();
  }

  void _onOfflineModeChanged() {
    // Force rebuild when offline mode changes
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (lightColorScheme, darkColorScheme) {
        final colorScheme = getAppColorScheme(
          lightColorScheme,
          darkColorScheme,
        );

        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarContrastEnforced: true,
            statusBarBrightness: brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
            statusBarIconBrightness: brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
            systemNavigationBarIconBrightness: brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
          ),
          child: MaterialApp.router(
            themeMode: ThemeMode.dark,
            darkTheme: getAppTheme(colorScheme),
            theme: getAppTheme(colorScheme),
            localizationsDelegates: [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: appSupportedLocales,
            locale: languageSetting,
            routerConfig: NavigationManager.router,
          ),
        );
      },
    );
  }
}

/// Set once the animated opening with its sound has played.
const _openingPlayedKey = 'openingPlayed';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The opening plays only on the very first launch. Reading the flag here
  // takes a few milliseconds, behind Android's own launch screen.
  var firstLaunch = true;
  try {
    await Hive.initFlutter();
    final settings = await Hive.openBox('settings');
    firstLaunch = settings.get(_openingPlayedKey) != true;
  } catch (e, stackTrace) {
    logger.log('Could not read first launch', error: e, stackTrace: stackTrace);
  }
  runApp(_VybeStartup(firstLaunch: firstLaunch));
}

class _VybeStartup extends StatefulWidget {
  const _VybeStartup({required this.firstLaunch});

  final bool firstLaunch;

  @override
  State<_VybeStartup> createState() => _VybeStartupState();
}

class _VybeStartupState extends State<_VybeStartup> {
  late final Future<void> _ready;

  @override
  void initState() {
    super.initState();
    _ready = _initialize();
  }

  Future<void> _initialize() async {
    // Let Flutter present the splash before starting platform services.
    final binding = WidgetsBinding.instance;
    await binding.endOfFrame;
    final reduceMotion =
        PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;
    try {
      await Future.wait<void>([
        initialisation().then((_) => _preloadHome()),
        // Only the first launch waits for the full animated opening.
        if (widget.firstLaunch && !reduceMotion)
          binding.waitUntilFirstFrameRasterized.then(
            (_) => Future<void>.delayed(const Duration(milliseconds: 1900)),
          ),
      ], eagerError: true);
      if (widget.firstLaunch) {
        await Hive.box('settings').put(_openingPlayedKey, true);
      }
    } catch (error, stackTrace) {
      logger.log('Vybe could not start', error: error, stackTrace: stackTrace);
      rethrow;
    }
  }

  /// Starts loading Home while the splash is still up, so it opens ready. Home
  /// asks for the same feed and reuses this request. A slow network never
  /// holds the app back for long: Home keeps loading once it opens.
  Future<void> _preloadHome() async {
    if (offlineMode.value) return;
    try {
      await HomeFeedService.instance
          .load(PlatformDispatcher.instance.locale.countryCode ?? 'IN')
          .timeout(Duration(seconds: widget.firstLaunch ? 6 : 3));
    } catch (e) {
      logger.log('Home was not ready before opening', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        final ready =
            snapshot.connectionState == ConnectionState.done &&
            !snapshot.hasError;
        final reducedMotion =
            PlatformDispatcher.instance.accessibilityFeatures.disableAnimations;

        Widget content;
        if (!ready) {
          content = MaterialApp(
            key: const ValueKey('opening'),
            debugShowCheckedModeBanner: false,
            theme: ThemeData.dark(),
            home: StartupSplash(
              failed: snapshot.hasError,
              quiet: !widget.firstLaunch,
            ),
          );
        } else {
          content = const Vybe(key: ValueKey('ready'));
        }

        return AnimatedSwitcher(
          duration: reducedMotion
              ? Duration.zero
              : const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: content,
        );
      },
    );
  }
}

Future<void> initialisation() async {
  try {
    await Hive.initFlutter();

    await Future.wait([
      Hive.openBox('settings'),
      Hive.openBox('user'),
      Hive.openBox('userNoBackup'),
      Hive.openBox('cache'),
    ]);

    // Nothing else removes cache entries nobody asks for again.
    unawaited(cleanupOldCacheEntries());

    try {
      await LocalSyncService.instance.initialise();
    } catch (e, stackTrace) {
      logger.log(
        'Local sync could not start',
        error: e,
        stackTrace: stackTrace,
      );
    }

    try {
      await CloudSyncService.instance.initialise();
    } catch (e, stackTrace) {
      logger.log(
        'Cloud sync could not start',
        error: e,
        stackTrace: stackTrace,
      );
    }

    try {
      await FollowedArtistsService.instance.initialise();
    } catch (e, stackTrace) {
      logger.log(
        'Followed artists service could not start',
        error: e,
        stackTrace: stackTrace,
      );
    }

    try {
      CollaborativePlaylistService.instance.initialise();
    } catch (e, stackTrace) {
      logger.log(
        'Collaborative playlist service could not start',
        error: e,
        stackTrace: stackTrace,
      );
    }

    if (isMobilePlatform) {
      audioHandler = await AudioService.init(
        builder: VybeAudioHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.vybe.music',
          androidNotificationChannelName: 'Vybe',
          androidNotificationIcon: 'drawable/ic_launcher_foreground',
          androidShowNotificationBadge: true,
          androidResumeOnClick: false,
          androidStopForegroundOnPause: false,
          // Handed to Android Auto on the browsable root. Without the search
          // flag the car never offers a search box, and without the content
          // style keys it falls back to an undifferentiated list of everything.
          androidBrowsableRootExtras: {
            AndroidContentStyle.supportedKey: true,
            AndroidContentStyle.browsableHintKey:
                AndroidContentStyle.gridItemHintValue,
            AndroidContentStyle.playableHintKey:
                AndroidContentStyle.listItemHintValue,
            'android.media.browse.SEARCH_SUPPORTED': true,
          },
        ),
      );
    }

    if (isMobilePlatform) audioHandler.restoreLastPlayed();

    // Init router
    NavigationManager.instance;

    try {
      // Listen to incoming links while app is running
      appLinksSubscription = appLinks.uriLinkStream.listen(
        handleIncomingLink,
        onError: (err) {
          logger.log('URI link error:', error: err);
        },
      );
    } on PlatformException {
      logger.log('Failed to get initial uri');
    }

    if (isFdroidBuild && !offlineMode.value) {
      await fetchAnnouncementOnly();
    }
  } catch (e, stackTrace) {
    logger.log('Initialization Error', error: e, stackTrace: stackTrace);
  }

  applicationDirPath = (await getApplicationDocumentsDirectory()).path;
  await FilePaths.ensureDirectoriesExist();
  OfflineBackupService.instance.initialise();
  await OfflineBackupService.instance.initialiseAndRestoreIfNeeded();
}

void handleIncomingLink(Uri? uri) async {
  if (uri != null &&
      uri.scheme == 'vybe' &&
      uri.host == 'collab' &&
      uri.pathSegments.isNotEmpty) {
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        final context = NavigationManager().context;
        final code = uri.pathSegments.first;
        final joinResult = await CollaborativePlaylistService.instance
            .joinCollaborativePlaylist(code);
        if (!context.mounted) return;
        showToast(context, joinResult.message);
        final playlist = joinResult.playlist;
        if (joinResult.success && playlist != null) {
          final playlistId = (playlist['ytid'] ?? playlist['id'])?.toString();
          if (playlistId != null) {
            unawaited(
              NavigationManager.router.push(
                NavigationManager.playlistPath(playlistId),
              ),
            );
          }
        }
        return;
      } on StateError {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } catch (e, stackTrace) {
        logger.log(
          'Failed to open Collaborative playlist link',
          error: e,
          stackTrace: stackTrace,
        );
        return;
      }
    }
    return;
  }

  final jamCode = uri == null ? null : ListenTogetherService.codeFromLink(uri);
  if (jamCode != null) {
    // On a cold start the link arrives before the UI exists: wait for it.
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        await openListenTogetherPage(
          NavigationManager().context,
          initialCode: jamCode,
        );
        return;
      } on StateError {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      } catch (e, stackTrace) {
        logger.log(
          'Failed to open Listen Together link',
          error: e,
          stackTrace: stackTrace,
        );
        return;
      }
    }
    return;
  }

  if (uri == null || uri.scheme != 'vybe' || uri.host != 'playlist') return;

  if (uri.pathSegments.length < 2 || uri.pathSegments[0] != 'custom') return;

  try {
    final encodedPlaylist = uri.pathSegments[1];
    final playlist = await PlaylistSharingService.decodeAndExpandPlaylist(
      encodedPlaylist,
    );

    if (playlist == null) {
      _showPlaylistError();
      return;
    }

    // Ensure the incoming playlist has a unique id so it can be removed later
    if (playlist['ytid'] == null || playlist['ytid'].toString().isEmpty) {
      playlist['ytid'] = PlaylistUtils.generateCustomPlaylistId();
    }

    // Check for duplicate by title and song ytids
    final incomingYtids = (playlist['list'] as List<dynamic>)
        .map((s) => s['ytid'].toString())
        .toList();

    final isDuplicate = PlaylistUtils.playlistExists(
      playlist,
      incomingYtids,
      userCustomPlaylists.value,
    );

    if (isDuplicate) {
      showToast(
        NavigationManager().context,
        NavigationManager().context.l10n!.playlistAlreadyExists,
      );
    } else {
      userCustomPlaylists.value = [...userCustomPlaylists.value, playlist];
      unawaited(
        addOrUpdateData<List>(
          'user',
          'customPlaylists',
          userCustomPlaylists.value,
        ),
      );
      showToast(
        NavigationManager().context,
        '${NavigationManager().context.l10n!.addedSuccess}!',
      );
    }
  } catch (e) {
    _showPlaylistError();
  }
}

void _showPlaylistError() {
  showToast(
    NavigationManager().context,
    NavigationManager().context.l10n!.failedToLoadPlaylist,
  );
}
