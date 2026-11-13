import 'dart:io';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/screens/home_page.dart';
import 'package:vybe/services/cloud_sync_service.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/playlists_manager.dart';
import 'package:vybe/services/settings_manager.dart';
import 'package:vybe/utilities/player_colors.dart';
import 'package:vybe/widgets/marquee.dart';
import 'package:vybe/widgets/mini_player.dart';
import 'package:vybe/widgets/playlist_cover.dart';
import 'package:vybe/widgets/playlist_cube.dart';
import 'package:vybe/widgets/playlist_page/playlist_header.dart';
import 'package:vybe/widgets/song_bar.dart';
import 'package:vybe/widgets/spotify_download_icon.dart';

import '../support/test_account_user.dart';
import '../support/ui_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final audio = UiTestAudioHandler();
  late Directory directory;
  late List<String> covers;
  setUpAll(() async {
    directory = await openUiLibrary(audio);
    covers = await makeCoverData();
  });
  tearDownAll(() async {
    await audio.close();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'bright covers keep mini-player title and artist above 4.5:1 contrast',
    () {
      for (final source in [
        Colors.yellow,
        Colors.white,
        Colors.cyan,
        Colors.red,
        Colors.black,
      ]) {
        final background = miniPlayerSurface(source).computeLuminance();
        for (final foreground in [Colors.white, const Color(0xFFD9D9D9)]) {
          final text = foreground.computeLuminance();
          expect(
            (math.max(text, background) + 0.05) /
                (math.min(text, background) + 0.05),
            greaterThanOrEqualTo(4.5),
          );
        }
      }
    },
  );

  testWidgets(
    'playlist detail cube derives a collage from the same song artwork as Home',
    (tester) async {
      await tester.runAsync(() => warmArtwork(covers));
      final playlist = {
        'title': 'Spotify download',
        'image': '',
        'list': [
          for (final source in covers) {'highResImage': source},
        ],
      };
      await tester.pumpWidget(uiApp(Center(child: PlaylistCube(playlist))));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('explicit playlist covers override generated collages', (
    tester,
  ) async {
    await tester.runAsync(() => warmArtwork(covers));
    await tester.pumpWidget(
      uiApp(
        PlaylistCover(
          playlist: {
            'image': covers.first,
            'list': [
              for (final source in covers) {'highResImage': source},
            ],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('Liked Songs uses the purple cover at hero size', (tester) async {
    await tester.pumpWidget(uiApp(const PlaylistCube({'isLikedSongs': true})));
    expect(find.byType(LikedSongsCover), findsOneWidget);
    expect(tester.getSize(find.byType(LikedSongsCover)), const Size(220, 220));
  });

  test(
    'collage sources include offline paths, ignore blanks, and deduplicate',
    () {
      final sources = PlaylistCover.songArtwork({
        'list': [
          {
            'artworkPath': '/local/cover.jpg',
            'highResImage': 'https://example.com/a.jpg',
          },
          {'artworkPath': '/local/cover.jpg'},
          {'highResImage': 'null'},
          {'artWorkPath': 'file:///local/second.jpg'},
        ],
      });
      expect(sources.length, 2);
      expect(sources.first, ['/local/cover.jpg', 'https://example.com/a.jpg']);
      expect(sources.last.single, 'file:///local/second.jpg');
    },
  );

  testWidgets(
    'marquee resets to the first word when a long title becomes short',
    (tester) async {
      Widget marquee(String text) => uiApp(
        Center(
          child: SizedBox(
            width: 120,
            child: MarqueeWidget(
              pauseDuration: const Duration(milliseconds: 100),
              animationDuration: const Duration(seconds: 1),
              child: Text(text, maxLines: 1),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        marquee(
          'A long track title that needs to scroll across this small area',
        ),
      );
      await tester.pump(const Duration(milliseconds: 110));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        greaterThan(0),
      );
      await tester.pumpWidget(marquee('New title'));
      await tester.pump();
      expect(
        tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
        0,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('disposing a marquee cancels its pending pause', (tester) async {
    await tester.pumpWidget(
      uiApp(
        const SizedBox(
          width: 100,
          child: MarqueeWidget(
            child: Text(
              'A very long label that is still waiting to start scrolling',
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    // The binding also verifies that no timers survive disposal.
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced-motion titles remain static', (tester) async {
    await tester.pumpWidget(
      uiApp(
        const SizedBox(
          width: 100,
          child: MarqueeWidget(
            child: Text('A long title that would otherwise animate'),
          ),
        ),
        reduceMotion: true,
      ),
    );
    await tester.pump(const Duration(seconds: 3));
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      0,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('mini-player changes tracks without overlapping the old title', (
    tester,
  ) async {
    const first = MediaItem(
      id: '0',
      title: 'First track',
      artist: 'First artist',
      extras: {'ytid': 'first'},
    );
    const second = MediaItem(
      id: '0',
      title: 'Second track',
      artist: 'Second artist',
      extras: {'ytid': 'second'},
    );
    audio.queue.add([first, second]);
    audio.mediaItem.add(first);
    await tester.pumpWidget(uiApp(const Center(child: MiniPlayer())));
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(find.text('First track'), findsOneWidget);
    audio.mediaItem.add(second);
    await tester.pump();
    await tester.pump();
    expect(find.text('Second track'), findsOneWidget);
    expect(find.text('First track'), findsNothing);
    expect(find.text('First artist'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a reused song row refreshes its identity and downloaded status',
    (tester) async {
      final first = {
        'ytid': 'one',
        'title': 'Old result',
        'artist': 'Old artist',
      };
      userOfflineSongs.value = [first];
      Widget row(Map song) =>
          uiApp(SongBar(song, true, key: const ValueKey('row')));
      await tester.pumpWidget(row(first));
      await tester.pumpAndSettle();
      expect(find.byType(DownloadedBadge), findsOneWidget);
      await tester.pumpWidget(
        row({'ytid': 'two', 'title': 'New result', 'artist': 'New artist'}),
      );
      await tester.pumpAndSettle();
      expect(find.text('Old result'), findsNothing);
      expect(find.text('New result'), findsOneWidget);
      expect(find.byType(DownloadedBadge), findsNothing);
      expect(tester.takeException(), isNull);
      userOfflineSongs.value = [];
    },
  );

  testWidgets('the home greeting has no V profile bubble', (tester) async {
    final original = playlists;
    playlists = [];
    globalSongs = [{}];
    wrappedEnabled.value = false;
    await tester.pumpWidget(uiApp(const HomePage()));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('V')),
      findsNothing,
    );
    expect(find.textContaining('Good '), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    playlists = original;
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'home greeting follows accounts and sign-out without a name editor',
    (tester) async {
      final service = CloudSyncService.instance;
      final settings = Hive.box('settings');
      final previousUser = service.currentUser.value;
      final previousPlaylists = playlists;
      final previousSongs = globalSongs;
      final previousWrapped = wrappedEnabled.value;
      final previousRecommendations = externalRecommendations.value;
      final previousSettings = {
        for (final key in [
          'customUserName',
          'cloudUserDisplayName',
          'auth_prompt_dismissed',
        ])
          key: settings.get(key),
      };
      addTearDown(() async {
        service.currentUser.value = previousUser;
        playlists = previousPlaylists;
        globalSongs = previousSongs;
        wrappedEnabled.value = previousWrapped;
        externalRecommendations.value = previousRecommendations;
        for (final entry in previousSettings.entries) {
          if (entry.value == null) {
            await settings.delete(entry.key);
          } else {
            await settings.put(entry.key, entry.value);
          }
        }
      });
      await settings.putAll({
        'customUserName': 'Deepak',
        'cloudUserDisplayName': 'Previous Account',
        'auth_prompt_dismissed': true,
      });
      playlists = [];
      globalSongs = [{}];
      wrappedEnabled.value = false;
      externalRecommendations.value = false;
      service.currentUser.value = TestAccountUser(
        uid: 'sasha',
        displayName: 'Sasha Verma',
      );

      await tester.pumpWidget(uiApp(const HomePage()));
      await tester.pumpAndSettle();
      final greeting = find.descendant(
        of: find.byType(AppBar),
        matching: find.textContaining('Good '),
      );
      String greetingText() => tester.widget<Text>(greeting).data!;
      expect(greetingText(), endsWith(', Sasha'));
      expect(greetingText(), isNot(contains('Deepak')));
      expect(find.byIcon(FluentIcons.edit_16_regular), findsNothing);
      await tester.tap(greeting);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);

      // Keep Home mounted while the account or its profile changes.
      service.currentUser.value = TestAccountUser(
        uid: 'morgan',
        displayName: 'Morgan Lee',
      );
      await tester.pumpAndSettle();
      expect(greetingText(), endsWith(', Morgan'));
      service.currentUser.value = TestAccountUser(
        uid: 'morgan',
        displayName: 'Sky Morgan',
      );
      await tester.pumpAndSettle();
      expect(greetingText(), endsWith(', Sky'));
      service.currentUser.value = TestAccountUser(
        uid: 'sana',
        email: 'sana.khan@example.com',
      );
      await tester.pumpAndSettle();
      expect(greetingText(), endsWith(', Sana'));

      service.currentUser.value = null;
      await tester.pumpAndSettle();
      expect(greetingText(), matches(r'^Good (morning|afternoon|evening)$'));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('a one-track playlist shows a singular song label', (
    tester,
  ) async {
    await tester.pumpWidget(
      uiApp(
        const PlaylistHeader(
          title: 'Liked songs',
          songsLength: 1,
          showTitle: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 song'), findsOneWidget);
    expect(find.text('1 Songs'), findsNothing);
  });
}
