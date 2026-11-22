import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PlatformDispatcher;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/constants/app_constants.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/main.dart';
import 'package:vybe/services/cloud_sync_service.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/followed_artists_service.dart';
import 'package:vybe/services/home_feed_service.dart';
import 'package:vybe/services/home_playback_history.dart';
import 'package:vybe/services/listening_stats_service.dart';
import 'package:vybe/services/playlist_download_service.dart';
import 'package:vybe/services/playlists_manager.dart';
import 'package:vybe/services/router_service.dart';
import 'package:vybe/services/settings_manager.dart';
import 'package:vybe/utilities/account_name.dart';
import 'package:vybe/utilities/app_utils.dart';
import 'package:vybe/utilities/flutter_toast.dart';
import 'package:vybe/utilities/listening_stats_utils.dart';
import 'package:vybe/widgets/auth_dialog.dart';
import 'package:vybe/widgets/home_playlist_grid.dart';
import 'package:vybe/widgets/listening_recap_card.dart';
import 'package:vybe/widgets/mini_player_bottom_space.dart';
import 'package:vybe/widgets/playlist_artwork.dart';
import 'package:vybe/widgets/section_header.dart';
import 'package:vybe/widgets/shelf_card.dart';
import 'package:vybe/widgets/spotify_header.dart';
import 'package:vybe/widgets/whats_new_sheet.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.feedService});

  final HomeFeedService? feedService;

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List<HomeShelf>> _feed;
  Timer? _recentlyPlayedDebounce;
  Timer? _onlineFeedRefresh;
  late final AppLifecycleListener _appLifecycle;
  int _playRequest = 0;
  final _followed = FollowedArtistsService.instance.followedArtists;
  final _country = PlatformDispatcher.instance.locale.countryCode ?? 'IN';
  HomeFeedService get _feedService =>
      widget.feedService ?? HomeFeedService.instance;

  @override
  void initState() {
    super.initState();
    _feed = _feedService.load(_country);
    _appLifecycle = AppLifecycleListener(onResume: _refreshFeed);
    _onlineFeedRefresh = Timer.periodic(const Duration(minutes: 30), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _refreshFeed();
      }
    });
    externalRecommendations.addListener(_refreshFeed);
    userRecentlyPlayed.addListener(_scheduleFeedRefresh);
    userLikedSongsList.addListener(_scheduleFeedRefresh);
    _followed.addListener(_refreshFeed);
    CloudSyncService.instance.currentUser.addListener(_onAuthChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (CloudSyncService.instance.isFirebaseConfigured &&
          CloudSyncService.instance.currentUser.value == null) {
        final existing = FirebaseAuth.instance.currentUser;
        if (existing != null) {
          CloudSyncService.instance.currentUser.value = existing;
        }
      }
      if (CloudSyncService.instance.currentUser.value == null) {
        AuthDialog.show(context);
      } else {
        // Not on top of the sign-in dialog: it waits for a signed-in open.
        unawaited(showWhatsNewIfUpdated(context));
      }
    });
  }

  void _scheduleFeedRefresh() {
    if (!mounted) return;
    _recentlyPlayedDebounce?.cancel();
    _recentlyPlayedDebounce = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      _refreshFeed();
    });
  }

  void _onAuthChanged() {
    if (!mounted) return;
    if (CloudSyncService.instance.currentUser.value == null) {
      AuthDialog.show(context);
    }
  }

  @override
  void dispose() {
    _recentlyPlayedDebounce?.cancel();
    _onlineFeedRefresh?.cancel();
    _appLifecycle.dispose();
    userRecentlyPlayed.removeListener(_scheduleFeedRefresh);
    userLikedSongsList.removeListener(_scheduleFeedRefresh);
    _followed.removeListener(_refreshFeed);
    CloudSyncService.instance.currentUser.removeListener(_onAuthChanged);
    externalRecommendations.removeListener(_refreshFeed);
    super.dispose();
  }

  void _refreshFeed() {
    if (!mounted || offlineMode.value) return;
    final pending = _feedService.load(_country);
    if (identical(pending, _feed)) return;
    setState(() {
      _feed = pending;
    });
  }

  Future<void> _refreshFromGesture() async {
    if (!mounted || offlineMode.value) return;
    final pending = _feedService.load(_country, forceRefresh: true);
    setState(() {
      _feed = pending;
    });
    await pending;
  }

  /// 0 = everything, 1 = playlists only, 2 = songs only.
  int _filter = 0;

  String _getGreeting(User? user) {
    final hour = DateTime.now().hour;
    String greeting;
    if (hour < 12) {
      greeting = 'Good morning';
    } else if (hour < 17) {
      greeting = 'Good afternoon';
    } else {
      greeting = 'Good evening';
    }
    final name = accountFirstName(user);
    if (name.isNotEmpty) {
      return '$greeting, $name';
    }
    return greeting;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        toolbarHeight: 56,
        title: ValueListenableBuilder<User?>(
          valueListenable: CloudSyncService.instance.currentUser,
          builder: (context, user, _) => Text(
            _getGreeting(user),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(FluentIcons.history_24_regular),
            onPressed: () =>
                NavigationManager.router.go('/library/userSongs/recents'),
          ),
          IconButton(
            icon: const Icon(FluentIcons.settings_24_regular),
            onPressed: () =>
                NavigationManager.router.go(NavigationManager.settingsPath),
          ),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilterPills(
                labels: ['All', context.l10n!.playlists, context.l10n!.songs],
                selected: _filter,
                onSelected: (i) => setState(() => _filter = i),
              ),
            ),
          ),
        ),
      ),
      body: _buildPersonalizedFeed(),
    );
  }

  /// Keep shortcuts in sync with the library without fetching any new data.
  Widget _buildQuickAccessGrid() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        pinnedPlaylistIds,
        userCustomPlaylists,
        userPlaylistFolders,
        userLikedPlaylists,
        userPlaylists,
        onlinePlaylists,
        offlinePlaylistService.offlinePlaylists,
      ]),
      builder: (context, _) => HomePlaylistGrid(
        playlists: [
          ...resolvePinnedPlaylists(pinnedPlaylistIds.value),
          ...getUserCustomPlaylists(),
          for (final folder in userPlaylistFolders.value)
            ...(folder['playlists'] as List? ?? const []).whereType<Map>(),
          ...userLikedPlaylists.value,
          ...resolvePinnedPlaylists(userPlaylists.value),
          ...offlinePlaylistService.offlinePlaylists.value.whereType<Map>(),
        ],
        onLikedSongsTap: () => context.push('/library/userSongs/liked'),
        onPlaylistTap: (playlist) {
          final id = Uri.encodeComponent(playlist['ytid'].toString().trim());
          if (isArtistPlaylist(playlist)) {
            context.push('/home/artist/$id', extra: playlist);
          } else {
            context.push('/home/playlist/$id');
          }
        },
      ),
    );
  }

  Widget _buildJumpBackIn() {
    return AnimatedBuilder(
      animation: Listenable.merge([
        userRecentlyPlayed,
        HomePlaybackHistory.changed,
        userCustomPlaylists,
        userPlaylistFolders,
        offlinePlaylistService.offlinePlaylists,
      ]),
      builder: (context, _) {
        final livePlaylists = {
          for (final playlist in [
            ...getUserCustomPlaylists(),
            for (final folder in userPlaylistFolders.value)
              ...(folder['playlists'] as List? ?? const []).whereType<Map>(),
            ...offlinePlaylistService.offlinePlaylists.value.whereType<Map>(),
          ])
            homeItemId(playlist): playlist,
        };
        final collections = [
          for (final entry in HomePlaybackHistory.collections.where(
            (item) =>
                !homeItemId(item).startsWith('customId-') ||
                livePlaylists.containsKey(homeItemId(item)),
          ))
            if (entry['isAlbum'] == true
                    ? null
                    : livePlaylists[homeItemId(entry)]
                case final playlist?)
              {...entry, ...playlist, 'image': playlist['image']}
            else
              entry,
        ];
        return _buildShelf(
          HomeFeedService.jumpBackIn(userRecentlyPlayed.value, collections),
          resume: true,
        );
      },
    );
  }

  Widget _buildPersonalizedFeed() {
    return FutureBuilder<List<HomeShelf>>(
      future: _feed,
      builder: (context, snapshot) {
        final loading =
            !snapshot.hasData &&
            snapshot.connectionState != ConnectionState.done;
        return RefreshIndicator(
          onRefresh: _refreshFromGesture,
          child: ListView(
            key: const PageStorageKey('personalized-home'),
            physics: const AlwaysScrollableScrollPhysics(),
            padding: commonSingleChildScrollViewPadding,
            children: [
              if (_filter != 2) _buildQuickAccessGrid(),
              _buildJumpBackIn(),
              if (loading)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: LinearProgressIndicator(
                    semanticsLabel: context.l10n!.loading,
                  ),
                ),
              for (final shelf in snapshot.data ?? <HomeShelf>[])
                _buildShelf(shelf),
              if (_filter == 0) _buildCurrentMonthRecapSection(),
              const MiniPlayerBottomSpace(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildShelf(HomeShelf shelf, {bool resume = false}) {
    final items = shelf.items
        .where(
          (item) => switch (_filter) {
            1 => item.kind != HomeItemKind.song,
            2 => item.kind == HomeItemKind.song,
            _ => true,
          },
        )
        .toList();
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title: shelf.title),
          if (shelf.subtitle case final subtitle?)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 12.0;
              const minCardSize = 96.0;
              const maxCardSize = 128.0;
              final columns = math.max(
                1,
                ((constraints.maxWidth + gap) / (minCardSize + gap)).floor(),
              );
              final cardSize = math.min(
                maxCardSize,
                (constraints.maxWidth - gap * (columns - 1)) / columns,
              );
              final labelHeight = math.max(
                56,
                MediaQuery.textScalerOf(context).scale(14) +
                    MediaQuery.textScalerOf(context).scale(12) +
                    24,
              );
              return SizedBox(
                height: cardSize + labelHeight,
                child: PageView.builder(
                  key: PageStorageKey((shelf.title, _filter, columns)),
                  itemCount: (items.length + columns - 1) ~/ columns,
                  itemBuilder: (context, page) {
                    final start = page * columns;
                    final end = math.min(start + columns, items.length);
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var index = start; index < end; index++) ...[
                          if (index != start) const SizedBox(width: gap),
                          _buildShelfCard(
                            items[index],
                            cardSize,
                            resume: resume,
                          ),
                        ],
                      ],
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildShelfCard(HomeItem item, double size, {required bool resume}) {
    final data = item.data;
    final collection =
        item.kind == HomeItemKind.album || item.kind == HomeItemKind.playlist;
    final artist = (data['artist'] ?? data['author'])?.toString();
    final year = data['year']?.toString();
    final subtitle = [
      if (artist != null && artist.isNotEmpty) artist,
      if (year != null && year.isNotEmpty) year,
    ].join(' \u00b7 ');
    return ShelfCard(
      key: ValueKey((item.kind, homeItemId(data))),
      playlist: item.kind == HomeItemKind.artist
          ? {...data, 'isArtist': true}
          : data,
      size: size,
      artwork: item.kind == HomeItemKind.song
          ? _buildSongArtwork(data, size)
          : null,
      subtitle: subtitle.isNotEmpty
          ? subtitle
          : item.kind == HomeItemKind.song
          ? context.l10n!.songs
          : null,
      onTap: () => _activate(item, resume: resume),
      onOpen: resume && collection ? () => _open(item) : null,
    );
  }

  Widget _buildSongArtwork(Map song, double size) {
    final original =
        [
              song['artworkPath'],
              song['artWorkPath'],
              song['image'],
              song['highResImage'],
              song['lowResImage'],
            ]
            .whereType<String>()
            .map((value) => value.trim())
            .firstWhere(
              (value) => value.isNotEmpty && value != 'null',
              orElse: () => '',
            );
    final uri = Uri.tryParse(original);
    final parts = uri?.pathSegments ?? const <String>[];
    // YouTube's 4:3 SD/HQ thumbnails often contain black padding. The wide
    // thumbnail lets BoxFit.cover crop straight to the actual video image.
    final wide =
        uri != null &&
            (uri.host == 'i.ytimg.com' || uri.host == 'img.youtube.com') &&
            parts.length == 3 &&
            (parts.first == 'vi' || parts.first == 'vi_webp') &&
            const {
              'default',
              'hqdefault',
              'sddefault',
              'maxresdefault',
            }.contains(parts.last.split('.').first)
        ? uri
              .replace(pathSegments: ['vi', parts[1], 'mqdefault.jpg'])
              .toString()
        : original;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: PlaylistArtwork(
        playlistArtwork: wide,
        size: size,
        fallback: wide == original
            ? null
            : PlaylistArtwork(playlistArtwork: original, size: size),
      ),
    );
  }

  void _open(HomeItem item) {
    _playRequest++;
    final id = homeItemId(item.data);
    switch (item.kind) {
      case HomeItemKind.artist:
        context.push(
          NavigationManager.artistPath(context, id),
          extra: item.data,
        );
      case HomeItemKind.album:
        context.push(NavigationManager.albumPath(context, id));
      case HomeItemKind.playlist:
        context.push(NavigationManager.playlistPath(id));
      case HomeItemKind.song:
      case HomeItemKind.mix:
        break;
    }
  }

  Future<void> _activate(HomeItem item, {required bool resume}) async {
    final request = ++_playRequest;
    final id = homeItemId(item.data);
    switch (item.kind) {
      case HomeItemKind.song:
        if (resume &&
            audioHandler.isCurrentSongLoaded &&
            homeItemId(audioHandler.currentSong ?? {}) == id) {
          await audioHandler.play();
        } else {
          await audioHandler.playResumableSong(item.data);
        }
      case HomeItemKind.mix:
        await audioHandler.playPlaylistSong(playlist: item.data, songIndex: 0);
      case HomeItemKind.artist:
        _open(item);
      case HomeItemKind.album:
      case HomeItemKind.playlist:
        if (!resume) {
          _open(item);
          return;
        }
        final collection = await getPlaylistInfoForWidget(id);
        if (!mounted || request != _playRequest) return;
        final tracks = collection?['list'];
        if (tracks is! List || tracks.isEmpty) {
          showToast(context, context.l10n!.error);
          return;
        }
        final songId = item.data['songId']?.toString();
        final index = tracks.indexWhere(
          (track) => track is Map && homeItemId(track) == songId,
        );
        await audioHandler.playPlaylistSong(
          playlist: collection,
          songIndex: index < 0 ? 0 : index,
          shuffle: false,
        );
    }
  }

  Widget _buildCurrentMonthRecapSection() {
    return ValueListenableBuilder<bool>(
      valueListenable: wrappedEnabled,
      builder: (_, isEnabled, __) {
        if (!isEnabled) return const SizedBox.shrink();

        final currentMonthKey = listeningStatsMonthKey(DateTime.now());
        final monthStats = listeningStatsService.monthStats(currentMonthKey);
        final songs = listeningStatsService.monthTopSongs(currentMonthKey);
        final displayMinutes = monthDisplayMinutes(monthStats);
        if (displayMinutes <= 0 && songs.isEmpty) {
          return const SizedBox.shrink();
        }

        final previewSongs = songs.take(wrappedShareSongsLimit).toList();
        final periodLabel = formatMonthPeriodLabel(
          Localizations.localeOf(context),
          currentMonthKey,
        );

        return Column(
          children: [
            SectionHeader(
              title: context.l10n!.timeMachine,
              icon: FluentIcons.data_trending_24_filled,
            ),
            ListeningRecapCard(
              periodLabel: periodLabel,
              minutes: displayMinutes,
              songs: previewSongs,
              onSongTap: (index) => _playRecapSongs(previewSongs, index),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 0),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () => context.push('/home/timeMachine'),
                  icon: const Icon(FluentIcons.arrow_right_24_regular),
                  label: Text(context.l10n!.listeningStats),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _playRecapSongs(
    List<Map<String, dynamic>> songs,
    int index,
  ) async {
    if (songs.isEmpty) return;
    await audioHandler.playPlaylistSong(
      playlist: {'title': context.l10n!.timeMachine, 'list': songs},
      songIndex: index,
    );
  }
}
