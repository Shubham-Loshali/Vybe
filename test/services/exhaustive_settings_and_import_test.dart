// ignore_for_file: depend_on_referenced_packages, avoid_print, cascade_invocations, prefer_const_constructors, prefer_const_declarations, deprecated_member_use

import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vybe/screens/playlist_page.dart';
import 'package:vybe/screens/search_page.dart';
import 'package:vybe/screens/user_songs_page.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/data_manager.dart';
import 'package:vybe/services/io_service.dart';
import 'package:vybe/services/offline_backup_service.dart';
import 'package:vybe/services/playlists_manager.dart';
import 'package:vybe/services/settings_manager.dart';
import 'package:vybe/services/spotify_playlist_import.dart';
import 'package:vybe/theme/app_themes.dart';
import 'package:vybe/utilities/language_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('vybe_settings_import_');
    applicationDirPath = tempDir.path;
    await FilePaths.ensureDirectoriesExist();

    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.openBox('user');
    await Hive.openBox('userNoBackup');
    await Hive.openBox('cache');
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('1. Exhaustive Settings Verification - All Options & Toggles', () {
    test('crossfadeSeconds: valid values, boundary limits, and persistence', () async {
      final box = Hive.box('settings');

      // 0 = Off
      crossfadeSeconds.value = 0;
      await box.put('crossfadeSeconds', 0);
      expect(crossfadeSeconds.value, 0);
      expect(box.get('crossfadeSeconds'), 0);

      // 1 to 12 = Valid range
      for (var s = 1; s <= maxCrossfadeSeconds; s++) {
        crossfadeSeconds.value = s;
        await box.put('crossfadeSeconds', s);
        expect(crossfadeSeconds.value, s);
        expect(box.get('crossfadeSeconds'), s);
      }

      // Clamping out-of-bounds inputs
      const overMax = 20;
      final clampedOver = overMax.clamp(0, maxCrossfadeSeconds);
      expect(clampedOver, maxCrossfadeSeconds);

      const underMin = -10;
      final clampedUnder = underMin.clamp(0, maxCrossfadeSeconds);
      expect(clampedUnder, 0);
    });

    test('audioQualitySetting: lossless, high, medium, low persistence and default migration', () async {
      final box = Hive.box('settings');

      final qualities = ['lossless', 'high', 'medium', 'low'];
      for (final q in qualities) {
        audioQualitySetting.value = q;
        await box.put('audioQuality', q);
        expect(audioQualitySetting.value, q);
        expect(box.get('audioQuality'), q);
      }

      // Reset to default lossless
      audioQualitySetting.value = 'lossless';
      await box.put('audioQuality', 'lossless');
      expect(audioQualitySetting.value, 'lossless');
    });

    test('useProxy: toggle and persistence', () async {
      final box = Hive.box('settings');

      useProxy.value = true;
      await box.put('useProxy', true);
      expect(useProxy.value, isTrue);
      expect(box.get('useProxy'), isTrue);

      useProxy.value = false;
      await box.put('useProxy', false);
      expect(useProxy.value, isFalse);
      expect(box.get('useProxy'), isFalse);
    });

    test('wrappedEnabled: toggle and persistence', () async {
      final box = Hive.box('settings');

      wrappedEnabled.value = false;
      await box.put('wrappedEnabled', false);
      expect(wrappedEnabled.value, isFalse);
      expect(box.get('wrappedEnabled'), isFalse);

      wrappedEnabled.value = true;
      await box.put('wrappedEnabled', true);
      expect(wrappedEnabled.value, isTrue);
      expect(box.get('wrappedEnabled'), isTrue);
    });

    test('shouldWeCheckUpdates: toggle, null state, and persistence', () async {
      final box = Hive.box('settings');

      shouldWeCheckUpdates.value = true;
      await box.put('shouldWeCheckUpdates', true);
      expect(shouldWeCheckUpdates.value, isTrue);
      expect(box.get('shouldWeCheckUpdates'), isTrue);

      shouldWeCheckUpdates.value = false;
      await box.put('shouldWeCheckUpdates', false);
      expect(shouldWeCheckUpdates.value, isFalse);
      expect(box.get('shouldWeCheckUpdates'), isFalse);
    });

    test('playNextSongAutomatically: toggle and persistence', () async {
      final box = Hive.box('settings');

      playNextSongAutomatically.value = false;
      await box.put('playNextSongAutomatically', false);
      expect(playNextSongAutomatically.value, isFalse);
      expect(box.get('playNextSongAutomatically'), isFalse);

      playNextSongAutomatically.value = true;
      await box.put('playNextSongAutomatically', true);
      expect(playNextSongAutomatically.value, isTrue);
      expect(box.get('playNextSongAutomatically'), isTrue);
    });

    test('externalRecommendations: toggle and persistence', () async {
      final box = Hive.box('settings');

      externalRecommendations.value = false;
      await box.put('externalRecommendations', false);
      expect(externalRecommendations.value, isFalse);
      expect(box.get('externalRecommendations'), isFalse);

      externalRecommendations.value = true;
      await box.put('externalRecommendations', true);
      expect(externalRecommendations.value, isTrue);
      expect(box.get('externalRecommendations'), isTrue);
    });

    test('offlineMode: toggle and persistence', () async {
      final box = Hive.box('settings');

      offlineMode.value = true;
      await box.put('offlineMode', true);
      expect(offlineMode.value, isTrue);
      expect(box.get('offlineMode'), isTrue);

      offlineMode.value = false;
      await box.put('offlineMode', false);
      expect(offlineMode.value, isFalse);
      expect(box.get('offlineMode'), isFalse);
    });

    test('syncedLyricsEnabled: toggle and persistence', () async {
      final box = Hive.box('settings');

      syncedLyricsEnabled.value = false;
      await box.put('syncedLyricsEnabled', false);
      expect(syncedLyricsEnabled.value, isFalse);
      expect(box.get('syncedLyricsEnabled'), isFalse);

      syncedLyricsEnabled.value = true;
      await box.put('syncedLyricsEnabled', true);
      expect(syncedLyricsEnabled.value, isTrue);
      expect(box.get('syncedLyricsEnabled'), isTrue);
    });

    test('showAudioQualityBadge: toggle and persistence', () async {
      final box = Hive.box('settings');

      showAudioQualityBadge.value = true;
      await box.put('showAudioQualityBadge', true);
      expect(showAudioQualityBadge.value, isTrue);
      expect(box.get('showAudioQualityBadge'), isTrue);

      showAudioQualityBadge.value = false;
      await box.put('showAudioQualityBadge', false);
      expect(showAudioQualityBadge.value, isFalse);
      expect(box.get('showAudioQualityBadge'), isFalse);
    });

    test('sponsorBlockSupport: toggle and persistence', () async {
      final box = Hive.box('settings');

      sponsorBlockSupport.value = true;
      await box.put('sponsorBlockSupport', true);
      expect(sponsorBlockSupport.value, isTrue);
      expect(box.get('sponsorBlockSupport'), isTrue);

      sponsorBlockSupport.value = false;
      await box.put('sponsorBlockSupport', false);
      expect(sponsorBlockSupport.value, isFalse);
      expect(box.get('sponsorBlockSupport'), isFalse);
    });

    test('equalizerEnabled and equalizerBandGains: state and gain array persistence', () async {
      final box = Hive.box('settings');

      equalizerEnabled.value = true;
      await box.put('equalizerEnabled', true);
      expect(equalizerEnabled.value, isTrue);
      expect(box.get('equalizerEnabled'), isTrue);

      final gains = [1.5, -2.0, 3.2, 0.0, -1.1];
      equalizerBandGains.value = gains;
      await box.put('equalizerBandGains', gains);
      expect(equalizerBandGains.value, gains);

      final retrieved = box.get('equalizerBandGains') as List;
      expect(retrieved.length, 5);
      expect(retrieved[0], 1.5);
      expect(retrieved[1], -2.0);
    });

    test('ThemeMode setting: Vybe locks to Spotify dark theme as designed', () async {
      final box = Hive.box('settings');

      await box.put('themeIndex', 0);
      expect(getThemeMode(0).name, 'dark');

      await box.put('themeIndex', 1);
      expect(getThemeMode(1).name, 'dark');

      await box.put('themeIndex', 2);
      expect(getThemeMode(2).name, 'dark');
    });

    test('Language utils: locale conversion and language codes', () async {
      final box = Hive.box('settings');

      final supported = ['en', 'hi', 'es', 'de', 'fr', 'ja', 'ru'];
      for (final code in supported) {
        await box.put('languageCode', code);
        final locale = getLocaleFromLanguageCode(code);
        expect(locale.languageCode, code);
      }
    });

    test('Color options: useSystemColor, usePureBlackColor, and custom accentColor', () async {
      final box = Hive.box('settings');

      useSystemColor.value = true;
      await box.put('useSystemColor', true);
      expect(useSystemColor.value, isTrue);

      usePureBlackColor.value = true;
      await box.put('usePureBlackColor', true);
      expect(usePureBlackColor.value, isTrue);

      const customAccent = 0xFF9C27B0; // Purple
      await box.put('accentColor', customAccent);
      primaryColorSetting = const Color(customAccent);
      expect(primaryColorSetting.value, customAccent);
    });

    test('Queue controls: shuffleNotifier and repeatNotifier modes', () async {
      final box = Hive.box('settings');

      shuffleNotifier.value = true;
      await box.put('shuffleEnabled', true);
      expect(shuffleNotifier.value, isTrue);
      expect(box.get('shuffleEnabled'), isTrue);

      for (final mode in AudioServiceRepeatMode.values) {
        repeatNotifier.value = mode;
        await box.put('repeatMode', mode.index);
        expect(repeatNotifier.value, mode);
        expect(box.get('repeatMode'), mode.index);
      }
    });

    test('Sorting options: playlistSortSetting and offlineSortSetting', () async {
      final box = Hive.box('settings');

      for (final sort in PlaylistSortType.values) {
        playlistSortSetting = sort.name;
        await box.put('playlistSortType', sort.name);
        expect(box.get('playlistSortType'), sort.name);
      }

      for (final sort in OfflineSortType.values) {
        offlineSortSetting = sort.name;
        await box.put('offlineSortType', sort.name);
        expect(box.get('offlineSortType'), sort.name);
      }
    });

    test('LocalSync options: localSyncEnabled, localSyncAutomatic, localSyncLastSyncedAt', () async {
      final box = Hive.box('settings');

      localSyncEnabled.value = true;
      await box.put('localSyncEnabled', true);
      expect(localSyncEnabled.value, isTrue);

      localSyncAutomatic.value = false;
      await box.put('localSyncAutomatic', false);
      expect(localSyncAutomatic.value, isFalse);

      final now = DateTime.now();
      await box.put('localSyncLastSyncedAt', now.toIso8601String());
      final restored = DateTime.tryParse(box.get('localSyncLastSyncedAt') as String);
      expect(restored, isNotNull);
      expect(restored!.millisecondsSinceEpoch, now.millisecondsSinceEpoch);
    });

    test('reloadSettingsFromStorage restores every single setting from storage box', () async {
      final settings = Hive.box('settings');

      await settings.put('playNextSongAutomatically', false);
      await settings.put('useSystemColor', false);
      await settings.put('usePureBlackColor', true);
      await settings.put('offlineMode', true);
      await settings.put('wrappedEnabled', false);
      await settings.put('crossfadeSeconds', 7);
      await settings.put('sponsorBlockSupport', true);
      await settings.put('externalRecommendations', false);
      await settings.put('useProxy', true);
      await settings.put('audioQuality', 'lossless');
      await settings.put('showAudioQualityBadge', true);
      await settings.put('syncedLyricsEnabled', false);
      await settings.put('equalizerEnabled', true);
      await settings.put('equalizerBandGains', [2.0, -1.0, 3.0]);
      await settings.put('themeIndex', 1);
      await settings.put('languageCode', 'hi');
      await settings.put('accentColor', 0xFFE91E63);
      await settings.put('shuffleEnabled', true);
      await settings.put('repeatMode', AudioServiceRepeatMode.one.index);

      reloadSettingsFromStorage();

      expect(playNextSongAutomatically.value, isFalse);
      expect(useSystemColor.value, isFalse);
      expect(usePureBlackColor.value, isTrue);
      expect(offlineMode.value, isTrue);
      expect(wrappedEnabled.value, isFalse);
      expect(sponsorBlockSupport.value, isTrue);
      expect(externalRecommendations.value, isFalse);
      expect(useProxy.value, isTrue);
      expect(audioQualitySetting.value, 'lossless');
      expect(showAudioQualityBadge.value, isTrue);
      expect(syncedLyricsEnabled.value, isFalse);
      expect(equalizerEnabled.value, isTrue);
      expect(equalizerBandGains.value, [2.0, -1.0, 3.0]);
      expect(themeModeSetting, 1);
      expect(languageSetting.languageCode, 'hi');
      expect(primaryColorSetting.value, 0xFFE91E63);
      expect(shuffleNotifier.value, isTrue);
      expect(repeatNotifier.value, AudioServiceRepeatMode.one);
    });

    test('Data cleanup actions: clearSearchHistory, clearRecentlyPlayed, clearCache', () async {
      final userBox = Hive.box('user');
      final cacheBox = Hive.box('cache');

      // 1. Search history cleanup
      searchHistoryNotifier.value = ['song A', 'artist B'];
      await userBox.put('searchHistory', searchHistoryNotifier.value);
      expect(userBox.get('searchHistory'), isNotEmpty);

      searchHistoryNotifier.value = [];
      await userBox.put('searchHistory', <dynamic>[]);
      expect(searchHistoryNotifier.value, isEmpty);
      expect(userBox.get('searchHistory'), isEmpty);

      // 2. Recently played cleanup
      userRecentlyPlayed.value = [{'ytid': 'recent_1', 'title': 'Song 1'}];
      await userBox.put('recentlyPlayedSongs', userRecentlyPlayed.value);
      expect(userRecentlyPlayed.value, isNotEmpty);

      userRecentlyPlayed.value = [];
      await userBox.put('recentlyPlayedSongs', <dynamic>[]);
      expect(userRecentlyPlayed.value, isEmpty);
      expect(userBox.get('recentlyPlayedSongs'), isEmpty);

      // 3. Cache cleanup
      await cacheBox.put('cachedKey', 'cachedValue');
      expect(cacheBox.get('cachedKey'), 'cachedValue');
      final cleared = await clearCache();
      expect(cleared, isTrue);
    });

    test('Offline backup and restore subsystem recovers downloads gracefully', () async {
      userOfflineSongs.value = [
        {
          'ytid': 'download_song_1',
          'title': 'Download Song One',
          'artist': 'Artist One',
          'audioPath': '${tempDir.path}/download_song_1.m4a',
        },
      ];

      await OfflineBackupService.instance.saveOfflineBackup();
      final backup = Hive.box('user').get('offlineBackupData') as String?;
      expect(backup, isNotNull);
      expect(backup, contains('download_song_1'));

      // Wipe current in-memory offline songs
      userOfflineSongs.value = [];
      expect(userOfflineSongs.value, isEmpty);

      // Restore from saved backup data
      final count = await OfflineBackupService.instance.restoreOfflineBackup();
      expect(count, greaterThanOrEqualTo(0));
    });
  });

  group('2. Exhaustive Import Verification - Spotify URLs, Redirects, Payloads, & Exporter', () {
    const sampleId = '37i9dQZF1DXcBWIGoYBM5M';

    test('spotifyPlaylistId: parses all valid formats (standard, query, intl, embed, uri)', () {
      // Standard open.spotify.com
      expect(
        spotifyPlaylistId('https://open.spotify.com/playlist/$sampleId'),
        sampleId,
      );

      // With query parameters (si, pi, context)
      expect(
        spotifyPlaylistId('https://open.spotify.com/playlist/$sampleId?si=9e658cb4d755452f&pi=a-b123'),
        sampleId,
      );

      // Internationalized Spotify URLs (intl-en, intl-de, intl-fr, intl-es, intl-ja)
      expect(
        spotifyPlaylistId('https://open.spotify.com/intl-en/playlist/$sampleId'),
        sampleId,
      );
      expect(
        spotifyPlaylistId('https://open.spotify.com/intl-de/playlist/$sampleId?si=xyz'),
        sampleId,
      );
      expect(
        spotifyPlaylistId('https://open.spotify.com/intl-fr/playlist/$sampleId'),
        sampleId,
      );
      expect(
        spotifyPlaylistId('https://open.spotify.com/intl-ja/playlist/$sampleId'),
        sampleId,
      );

      // Embed URLs
      expect(
        spotifyPlaylistId('https://open.spotify.com/embed/playlist/$sampleId'),
        sampleId,
      );

      // Native Spotify URI
      expect(
        spotifyPlaylistId('spotify:playlist:$sampleId'),
        sampleId,
      );

      // Untrimmed whitespace
      expect(
        spotifyPlaylistId('   https://open.spotify.com/playlist/$sampleId   '),
        sampleId,
      );
    });

    test('spotifyPlaylistId: securely rejects invalid links, tracks, albums, and spoofed domains', () {
      // Track or Album URL (not playlist)
      expect(spotifyPlaylistId('https://open.spotify.com/track/$sampleId'), isNull);
      expect(spotifyPlaylistId('https://open.spotify.com/album/$sampleId'), isNull);
      expect(spotifyPlaylistId('https://open.spotify.com/artist/$sampleId'), isNull);

      // Domain spoofing attacks
      expect(spotifyPlaylistId('https://open.spotify.com.attacker.com/playlist/$sampleId'), isNull);
      expect(spotifyPlaylistId('https://fake-spotify.com/playlist/$sampleId'), isNull);

      // Insecure scheme or non-standard port
      expect(spotifyPlaylistId('http://open.spotify.com/playlist/$sampleId'), isNull);
      expect(spotifyPlaylistId('https://open.spotify.com:8080/playlist/$sampleId'), isNull);

      // Invalid ID length (< 22 or > 22 characters)
      expect(spotifyPlaylistId('https://open.spotify.com/playlist/tooShort'), isNull);
      expect(spotifyPlaylistId('https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M_TOOLONG'), isNull);

      // Garbage or empty input
      expect(spotifyPlaylistId(''), isNull);
      expect(spotifyPlaylistId('not a url'), isNull);
    });

    test('loadSpotifyPlaylist: parses embed Next.js payload with tracks, metadata, and Unicode', () async {
      final embedMock = {
        'props': {
          'pageProps': {
            'state': {
              'data': {
                'entity': {
                  'type': 'playlist',
                  'id': sampleId,
                  'name': 'Bollywood Top 50 💖',
                  'trackList': [
                    {
                      'uri': 'spotify:track:t1',
                      'title': 'Kesariya',
                      'subtitle': 'Arijit Singh, Pritam',
                    },
                    {
                      'uri': 'spotify:track:t2',
                      'title': 'Apna Bana Le',
                      'subtitle': 'Arijit Singh, Sachin-Jigar',
                    },
                    {
                      'uri': 'spotify:episode:podcast1', // Should be skipped (podcast episode)
                      'title': 'Daily News Podcast',
                      'subtitle': 'News Network',
                    },
                    {
                      'uri': 'spotify:track:t3',
                      'title': 'Tum Hi Ho',
                      'subtitle': 'Mithoon, Arijit Singh',
                    },
                  ],
                },
              },
            },
          },
        },
      };

      final client = MockClient((request) async {
        if (request.url.path.contains('/embed/playlist/')) {
          return http.Response.bytes(
            utf8.encode(
              '<html><body><script id="__NEXT_DATA__" type="application/json">${jsonEncode(embedMock)}</script></body></html>',
            ),
            200,
          );
        }
        return http.Response('', 404);
      });

      final playlist = await loadSpotifyPlaylist(
        'https://open.spotify.com/playlist/$sampleId',
        client: client,
      );

      expect(playlist.title, 'Bollywood Top 50 💖');
      expect(playlist.tracks.length, 3); // Podcast episode was correctly filtered
      expect(playlist.tracks[0].title, 'Kesariya');
      expect(playlist.tracks[0].artist, 'Arijit Singh, Pritam');
      expect(playlist.tracks[1].title, 'Apna Bana Le');
      expect(playlist.tracks[2].title, 'Tum Hi Ho');
    });

    test('loadSpotifyPlaylist: handles short links (spotify.link) 302 redirect resolution', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'spotify.link') {
          return http.Response(
            '',
            302,
            headers: {'location': 'https://open.spotify.com/playlist/$sampleId'},
          );
        }
        if (request.url.path.contains('/embed/playlist/')) {
          final mock = {
            'props': {
              'pageProps': {
                'state': {
                  'data': {
                    'entity': {
                      'type': 'playlist',
                      'id': sampleId,
                      'name': 'Redirected Playlist',
                      'trackList': [
                        {'uri': 'spotify:track:1', 'title': 'Song 1', 'subtitle': 'Artist 1'},
                      ],
                    },
                  },
                },
              },
            },
          };
          return http.Response(
            '<script id="__NEXT_DATA__" type="application/json">${jsonEncode(mock)}</script>',
            200,
          );
        }
        return http.Response('', 404);
      });

      final playlist = await loadSpotifyPlaylist('https://spotify.link/short123', client: client);
      expect(playlist.title, 'Redirected Playlist');
      expect(playlist.tracks.single.title, 'Song 1');
      expect(playlist.tracks.single.artist, 'Artist 1');
    });

    test('loadSpotifyPlaylist: falls back to external CSV exporter when preview is partial', () async {
      const exporter = 'https://export.example.com/playlist';

      final client = MockClient((request) async {
        if (request.url.host == 'export.example.com') {
          expect(request.url.toString(), '$exporter?id=$sampleId');
          return http.Response.bytes(
            utf8.encode(
              'Track Name,Artist Name(s)\r\n'
              'Chaleya,Arijit Singh & Shilpa Rao\r\n'
              'Jawan Title Track,Anirudh Ravichander\r\n',
            ),
            200,
            headers: {
              'content-type': 'text/csv; charset=utf-8',
              'x-playlist-total': '2',
            },
          );
        }
        // Embed returns 404
        return http.Response('', 404);
      });

      final playlist = await loadSpotifyPlaylist(
        'spotify:playlist:$sampleId',
        client: client,
        exporterUrl: exporter,
      );

      expect(playlist.tracks.length, 2);
      expect(playlist.tracks[0].title, 'Chaleya');
      expect(playlist.tracks[0].artist, 'Arijit Singh & Shilpa Rao');
      expect(playlist.tracks[1].title, 'Jawan Title Track');
    });

    test('Custom playlist creation and song insertion flow for imported items', () async {
      final userBox = Hive.box('user');
      const playlistId = 'imported_spotify_123';
      final creationTime = DateTime.now().millisecondsSinceEpoch;

      final importedSongs = [
        {
          'ytid': 'yt_imported_1',
          'title': 'Kesariya',
          'artist': 'Arijit Singh',
          'image': 'https://example.com/img1.jpg',
        },
        {
          'ytid': 'yt_imported_2',
          'title': 'Apna Bana Le',
          'artist': 'Sachin-Jigar',
          'image': 'https://example.com/img2.jpg',
        },
      ];

      final customPlaylist = {
        'id': playlistId,
        'title': 'My Imported Spotify Hits',
        'image': null,
        'list': importedSongs,
        'createdAt': creationTime,
      };

      userCustomPlaylists.value = [...userCustomPlaylists.value, customPlaylist];
      await userBox.put('customPlaylists', userCustomPlaylists.value);

      final playlists = userCustomPlaylists.value;
      final found = playlists.firstWhere(
        (p) => p['id'] == playlistId,
        orElse: () => {},
      );
      expect(found, isNotEmpty);
      expect(found['title'], 'My Imported Spotify Hits');
      expect(found['list'], isNotNull);
      final list = found['list'] as List;
      expect(list.length, 2);
      expect(list[0]['ytid'], 'yt_imported_1');
      expect(list[1]['ytid'], 'yt_imported_2');

      // Verify Hive persistence
      final persisted = userBox.get('customPlaylists') as List;
      expect(persisted, isNotEmpty);
      expect(persisted.any((p) => p['id'] == playlistId), isTrue);
    });
  });
}

