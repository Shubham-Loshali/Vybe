import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/screens/artist_page.dart';
import 'package:vybe/screens/listen_together_page.dart';
import 'package:vybe/screens/playlist_folder_page.dart';
import 'package:vybe/screens/startup_splash.dart';
import 'package:vybe/services/artist_service.dart';
import 'package:vybe/services/cloud_sync_service.dart';
import 'package:vybe/services/followed_artists_service.dart';
import 'package:vybe/services/playlists_manager.dart';
import 'package:vybe/services/settings_manager.dart';
import 'package:vybe/utilities/platform_utils.dart';

import '../support/test_account_user.dart';
import '../support/ui_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final audio = UiTestAudioHandler();
  late Directory directory;
  setUpAll(() async {
    directory = await openUiLibrary(audio);
  });
  tearDownAll(() async {
    await audio.close();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets('folder title reflects only a rename that was accepted', (
    tester,
  ) async {
    final previous = userPlaylistFolders.value;
    userPlaylistFolders.value = [
      {'id': 'qa-folder', 'name': 'Original', 'playlists': <Map>[]},
      {'id': 'qa-other', 'name': 'Already used', 'playlists': <Map>[]},
    ];
    addTearDown(() => userPlaylistFolders.value = previous);
    await tester.pumpWidget(
      uiApp(
        const PlaylistFolderPage(folderId: 'qa-folder', folderName: 'Original'),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> rename(String newName) async {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit folder'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), newName);
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
    }

    await rename('Already used');
    expect(find.text('Original'), findsOneWidget);
    expect(userPlaylistFolders.value.first['name'], 'Original');
    await rename('New name');
    expect(find.text('New name'), findsOneWidget);
    expect(Hive.box('user').get('playlistFolders').first['name'], 'New name');
  });

  testWidgets('artist opens with cached catalog and follow toggles work', (
    tester,
  ) async {
    const id = 'UC1234567890123456789012';
    final following = FollowedArtistsService.instance.followedArtists;
    final previous = following.value;
    final previousOffline = offlineMode.value;
    offlineMode.value = false;
    addTearDown(() {
      following.value = previous;
      offlineMode.value = previousOffline;
    });
    await cacheArtistProfile({
      'ytid': id,
      'title': 'Test Artist',
      'topSongs': [
        {
          'song': {
            'ytid': 'qa-artist-track',
            'title': 'Artist Track',
            'artist': 'Test Artist',
          },
        },
      ],
      'releases': [],
      'relatedArtists': [],
    });
    await tester.pumpWidget(uiApp(const ArtistPage(artistId: id)));
    await tester.pumpAndSettle();
    expect(find.text('Artist Track'), findsOneWidget);
    final follow = find.text('Follow');
    await tester.ensureVisible(follow);
    await tester.tap(follow);
    await tester.pumpAndSettle();
    expect(following.value.any((artist) => artist['ytid'] == id), isTrue);
    await tester.tap(find.text('Following'));
    await tester.pumpAndSettle();
    expect(following.value.any((artist) => artist['ytid'] == id), isFalse);
  });

  testWidgets('Jam accepts an invite code and reports an unavailable session', (
    tester,
  ) async {
    final currentUser = CloudSyncService.instance.currentUser;
    final previous = currentUser.value;
    currentUser.value = TestAccountUser(uid: 'qa-jam');
    addTearDown(() => currentUser.value = previous);
    await tester.pumpWidget(
      uiApp(const ListenTogetherPage(initialCode: 'abc123')),
    );
    await tester.pumpAndSettle();
    final code = find.byType(TextField);
    final join = find.text('Join with code');
    await tester.ensureVisible(join);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(code).controller?.text, 'ABC123');
    await tester.tap(join);
    await tester.pumpAndSettle();
    final message = isMobilePlatform
        ? 'Listen Together is not available right now.'
        : 'Listen Together is available on Android.';
    expect(find.text(message), findsOneWidget);
  });

  testWidgets('startup splash exposes the failure state at a compact height', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(540, 320);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      uiApp(const StartupSplash(failed: true), reduceMotion: true),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Vybe could not start'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}
