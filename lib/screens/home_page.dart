import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/constants/app_constants.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/main.dart';
import 'package:vybe/services/cloud_sync_service.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/listening_stats_service.dart';
import 'package:vybe/services/playlist_download_service.dart';
import 'package:vybe/services/playlists_manager.dart';
import 'package:vybe/services/recommendation_service.dart';
import 'package:vybe/services/router_service.dart';
import 'package:vybe/services/settings_manager.dart';
import 'package:vybe/utilities/account_name.dart';
import 'package:vybe/utilities/app_utils.dart';
import 'package:vybe/utilities/async_loader.dart';
import 'package:vybe/utilities/listening_stats_utils.dart';
import 'package:vybe/widgets/auth_dialog.dart';
import 'package:vybe/widgets/home_playlist_grid.dart';
import 'package:vybe/widgets/listening_recap_card.dart';
import 'package:vybe/widgets/mini_player_bottom_space.dart';
import 'package:vybe/widgets/recommended_songs_section.dart';
import 'package:vybe/widgets/section_header.dart';
import 'package:vybe/widgets/shelf_card.dart';
import 'package:vybe/widgets/spotify_header.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<List> _suggestedPlaylistsFuture;
  late Future<List> _trendingArtistsFuture;
  late Future<List> _recommendedSongsFuture;
  Timer? _recentlyPlayedDebounce;

  @override
  void initState() {
    super.initState();
    _suggestedPlaylistsFuture =
        RecommendationService.instance.getSuggestedPlaylists();
    _trendingArtistsFuture =
        RecommendationService.instance.getSuggestedArtists();
    _recommendedSongsFuture =
        RecommendationService.instance.getRecommendedSongs();
    externalRecommendations.addListener(_refreshAllRecommendations);
    userRecentlyPlayed.addListener(_onRecentlyPlayedChanged);
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
      }
    });
  }

  void _onRecentlyPlayedChanged() {
    if (!mounted) return;
    _recentlyPlayedDebounce?.cancel();
    _recentlyPlayedDebounce = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      _refreshAllRecommendations();
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
    userRecentlyPlayed.removeListener(_onRecentlyPlayedChanged);
    CloudSyncService.instance.currentUser.removeListener(_onAuthChanged);
    externalRecommendations.removeListener(_refreshAllRecommendations);
    super.dispose();
  }

  void _refreshAllRecommendations() {
    if (!mounted) return;
    setState(() {
      _suggestedPlaylistsFuture =
          RecommendationService.instance.getSuggestedPlaylists(forceRefresh: true);
      _trendingArtistsFuture =
          RecommendationService.instance.getSuggestedArtists(forceRefresh: true);
      _recommendedSongsFuture =
          RecommendationService.instance.getRecommendedSongs();
    });
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
              alignment: Alignment.centerLeft,
              child: FilterPills(
                labels: ['All', context.l10n!.playlists, context.l10n!.songs],
                selected: _filter,
                onSelected: (i) => setState(() => _filter = i),
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: commonSingleChildScrollViewPadding,
        child: Column(
          children: [
            if (_filter != 2) _buildQuickAccessGrid(),
            if (_filter != 2) _buildSuggestedPlaylists(),
            if (_filter != 2) _buildTrendingArtists(),
            if (_filter == 0) _buildCurrentMonthRecapSection(),
            if (_filter != 1) _buildRecommendedSongsSection(),
            const MiniPlayerBottomSpace(),
          ],
        ),
      ),
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

  Widget _buildSuggestedPlaylists() {
    return AsyncLoader<List<dynamic>>(
      future: _suggestedPlaylistsFuture,
      builder: (context, playlists) {
        if (playlists.isEmpty) return const SizedBox.shrink();

        const cardSize = 150.0;
        final itemCount = playlists.length.clamp(0, recommendedCubesNumber);

        return Column(
          children: [
            SectionHeader(title: context.l10n!.suggestedPlaylists),
            SizedBox(
              height: cardSize + 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: itemCount,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return ShelfCard(
                    playlist: playlist,
                    onTap: () {
                      final id = Uri.encodeComponent(
                        playlist['ytid'].toString().trim(),
                      );
                      if (isArtistPlaylist(playlist)) {
                        context.push('/home/artist/$id', extra: playlist);
                      } else {
                        context.push('/home/playlist/$id');
                      }
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTrendingArtists() {
    return AsyncLoader<List<dynamic>>(
      future: _trendingArtistsFuture,
      builder: (context, artists) {
        if (artists.isEmpty) return const SizedBox.shrink();

        const cardSize = 120.0;
        final itemCount = artists.length.clamp(0, 15);

        return Column(
          children: [
            SectionHeader(title: context.l10n!.suggestedArtists),
            SizedBox(
              height: cardSize + 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: itemCount,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final artist = artists[index];
                  return ShelfCard(
                    playlist: artist,
                    size: cardSize,
                    onTap: () {
                      final id = Uri.encodeComponent(
                        artist['ytid'].toString().trim(),
                      );
                      context.push('/home/artist/$id', extra: artist);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRecommendedSongsSection() {
    return AsyncLoader<List<dynamic>>(
      future: _recommendedSongsFuture,
      builder: (context, data) {
        if (data.isEmpty) return const SizedBox.shrink();
        return _buildRecommendedForYouSection(context, data);
      },
    );
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

  Widget _buildRecommendedForYouSection(
    BuildContext context,
    List<dynamic> data,
  ) {
    return RecommendedSongsSection(
      title: context.l10n!.recommendedForYou,
      songs: data,
      listKeyPrefix: 'home_recommended',
    );
  }
}
