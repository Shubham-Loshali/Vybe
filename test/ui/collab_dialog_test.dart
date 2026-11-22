// ignore_for_file: depend_on_referenced_packages, avoid_print, prefer_const_constructors

import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/localization/app_localizations.dart';
import 'package:vybe/screens/library_page.dart';
import 'package:vybe/screens/listen_together_page.dart';
import 'package:vybe/screens/playlist_page.dart';
import 'package:vybe/services/cloud_sync_service.dart';
import 'package:vybe/services/listen_together_service.dart';
import 'package:vybe/services/playlists_manager.dart';
import 'package:vybe/theme/app_themes.dart';
import 'package:vybe/utilities/collaborative_playlist_dialogs.dart';
import 'package:vybe/utilities/playlist_dialogs.dart';
import 'package:vybe/widgets/overflow_menu_button.dart';

import '../support/test_account_user.dart';
import '../support/ui_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final audio = UiTestAudioHandler();
  late Directory directory;
  setUpAll(() async {
    directory = await openUiLibrary(audio);
    final fontLoader = FontLoader('Figtree')
      ..addFont(rootBundle.load('assets/fonts/figtree/Figtree_400Regular.ttf'));
    await fontLoader.load();
  });
  tearDownAll(() async {
    await audio.close();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets(
    'Selecting the host playlist reports failure when the shared add cannot sync',
    (tester) async {
      final shared = {
        'id': 'legacy-guest-playlist',
        'collabId': 'ABC123',
        'source': 'user-created',
        'isCollaborative': true,
        'ownerUid': 'host',
        'title': 'Friend favorites',
        'list': <Map>[],
      };
      final previous = userCustomPlaylists.value;
      userCustomPlaylists.value = [shared];
      addTearDown(() => userCustomPlaylists.value = previous);
      final account = CloudSyncService.instance.currentUser;
      final previousAccount = account.value;
      account.value = TestAccountUser(uid: 'guest');
      addTearDown(() => account.value = previousAccount);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAddToPlaylistDialog(
                  context,
                  song: {'ytid': 'guest-track', 'title': 'Guest contribution'},
                ),
                child: const Text('Pick a playlist'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pick a playlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Friend favorites'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        find.textContaining('Could not add to the shared playlist'),
        findsOneWidget,
      );
      expect(find.text('Song added'), findsNothing);
      expect(userCustomPlaylists.value.single['list'], isEmpty);
    },
  );

  testWidgets(
    'Library and playlist controls open the correct Jam and collaboration screens',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 880);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      const playlistId = 'customId-collaboration-test';
      final previousPlaylists = userCustomPlaylists.value;
      userCustomPlaylists.value = [
        {
          'ytid': playlistId,
          'title': 'Shared favorites',
          'source': 'user-created',
          'isCollaborative': true,
          'collabId': 'ABC123',
          'list': [],
        },
      ];
      addTearDown(() => userCustomPlaylists.value = previousPlaylists);
      final router = GoRouter(
        initialLocation: '/library',
        routes: [
          ShellRoute(
            builder: (_, _, child) => Stack(
              children: [
                child,
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 78,
                  child: Material(child: Text('Mini player')),
                ),
              ],
            ),
            routes: [
              GoRoute(path: '/library', builder: (_, _) => const LibraryPage()),
              GoRoute(
                path: '/home/playlist/:playlistId',
                builder: (_, state) => PlaylistPage(
                  playlistId: state.pathParameters['playlistId'],
                ),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: getAppTheme(getAppColorScheme(null, null)),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(OverflowMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invite Collaborators'));
      await tester.pumpAndSettle();
      expect(find.text('ABC123'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      final account = CloudSyncService.instance.currentUser;
      final previousAccount = account.value;
      account.value = TestAccountUser(uid: 'library-jam-guest');
      addTearDown(() => account.value = previousAccount);
      audio.selectedSongs.clear();

      await tester.tap(find.byIcon(FluentIcons.add_24_regular));
      await tester.pumpAndSettle();
      expect(find.text('Join Collaborative Playlist'), findsOneWidget);
      await tester.tap(find.text('Join Jam'));
      await tester.pumpAndSettle();
      expect(find.byType(ListenTogetherPage), findsOneWidget);
      expect(find.text('Start a Jam'), findsNothing);
      await tester.enterText(find.byType(TextField), 'vybe://listen/ABC123');
      expect(find.text('vybe://listen/ABC123'), findsOneWidget);
      expect(audio.selectedSongs, isEmpty);
      final busy = ListenTogetherService.instance.busy;
      final previousBusy = busy.value;
      addTearDown(() => busy.value = previousBusy);
      busy.value = true;
      await tester.pumpAndSettle();
      expect(find.text('Joining…'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      final close = find.widgetWithIcon(IconButton, FluentIcons.dismiss_24_regular);
      expect(tester.widget<IconButton>(close).onPressed, isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ListenTogetherPage), findsOneWidget);
      busy.value = false;
      await tester.pumpAndSettle();
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(find.byType(ListenTogetherPage), findsNothing);
      expect(find.text('Join Jam'), findsNothing);

      await tester.tap(find.byIcon(FluentIcons.add_24_regular));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join Collaborative Playlist'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join Playlist'));
      await tester.pumpAndSettle();
      expect(find.text('Enter a 6-character code or link.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'vybe://collab/ABC123');
      await tester.tap(find.text('Join Playlist'));
      await tester.pumpAndSettle();

      expect(find.byType(PlaylistPage), findsOneWidget);
      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is IconButton &&
              widget.tooltip == 'Collaborator Settings & Invite',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ABC123'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Collaborative •'));
      await tester.pumpAndSettle();
      expect(find.text('ABC123'), findsOneWidget);
    },
  );

  testWidgets('showCollaborativePlaylistShareDialog renders without error', (
    tester,
  ) async {
    final playlist = {
      'title': 'fav',
      'collabId': 'ABC123',
      'inviteCode': 'ABC123',
      'isCollaborative': true,
      'collaborators': [
        {'name': 'harsh khatri', 'isOwner': true, 'uid': 'user_1'},
      ],
    };

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () =>
                showCollaborativePlaylistShareDialog(context, playlist),
            child: const Text('Open Share Dialog'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Share Dialog'));
    await tester.pumpAndSettle();

    expect(find.text('INVITE CODE'), findsOneWidget);
    expect(find.text('ABC123'), findsOneWidget);
    expect(find.text('harsh khatri'), findsOneWidget);
  });

  testWidgets(
    'showCollaborativePlaylistShareDialog handles empty collaborator name without crash',
    (tester) async {
      final playlist = {
        'title': 'Empty Name Collab',
        'collabId': 'DEF456',
        'isCollaborative': true,
        'collaborators': [
          {'name': '', 'isOwner': false, 'uid': 'user_2'},
          {'name': null, 'isOwner': false, 'uid': 'user_3'},
        ],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () =>
                  showCollaborativePlaylistShareDialog(context, playlist),
              child: const Text('Open Share Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Share Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('INVITE CODE'), findsOneWidget);
    },
  );

  testWidgets(
    'showJoinCollaborativePlaylistDialog renders and handles inputs',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showJoinCollaborativePlaylistDialog(context),
              child: const Text('Open Join Dialog'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Join Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Join Collaborative Playlist'), findsOneWidget);
      expect(find.text('Join Playlist'), findsOneWidget);
    },
  );
}
