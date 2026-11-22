import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/constants/app_constants.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/main.dart';
import 'package:vybe/services/artist_service.dart';
import 'package:vybe/services/collaborative_playlist_service.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/data_manager.dart';
import 'package:vybe/services/playlist_download_service.dart';
import 'package:vybe/services/playlist_sharing.dart';
import 'package:vybe/services/playlists_manager.dart';
import 'package:vybe/services/settings_manager.dart';
import 'package:vybe/utilities/app_utils.dart';
import 'package:vybe/utilities/async_loader.dart';
import 'package:vybe/utilities/collaborative_playlist_dialogs.dart';
import 'package:vybe/utilities/flutter_toast.dart';
import 'package:vybe/utilities/playlist_utils.dart';
import 'package:vybe/utilities/song_filtering.dart';
import 'package:vybe/utilities/sort_utils.dart';
import 'package:vybe/widgets/edit_playlist_dialog.dart';
import 'package:vybe/widgets/mini_player_bottom_space.dart';
import 'package:vybe/widgets/playlist_hero_artwork.dart';
import 'package:vybe/widgets/playlist_page/add_to_playlist_button.dart';
import 'package:vybe/widgets/playlist_page/download_button.dart';
import 'package:vybe/widgets/playlist_page/empty_playlist_state.dart';
import 'package:vybe/widgets/playlist_page/like_button.dart';
import 'package:vybe/widgets/playlist_page/playlist_action_buttons.dart';
import 'package:vybe/widgets/playlist_page/playlist_header.dart';
import 'package:vybe/widgets/playlist_page/playlist_sliver_app_bar.dart';
import 'package:vybe/widgets/playlist_page/search_bar_section.dart';
import 'package:vybe/widgets/recommended_songs_section.dart';
import 'package:vybe/widgets/song_bar.dart';
import 'package:vybe/widgets/sort_chips.dart';
import 'package:vybe/widgets/spinner.dart';

enum PlaylistSortType { default_, title, artist, dateAdded }

class PlaylistPage extends StatefulWidget {
  const PlaylistPage({
    super.key,
    this.playlistId,
    this.playlistData,
    this.cubeIcon = FluentIcons.text_bullet_list_24_filled,
    this.isArtist = false,
  });

  final String? playlistId;
  final dynamic playlistData;
  final IconData cubeIcon;
  final bool isArtist;

  @override
  _PlaylistPageState createState() => _PlaylistPageState();
}

class _PlaylistPageState extends State<PlaylistPage> {
  dynamic _playlist;

  /// Canonical (storage) order; `_playlist['list']` is always derived from it.
  List<dynamic> _originalPlaylistList = [];

  bool _isInitializingPlaylist = true;

  /// Playlist-seeded recommendations for eligible online custom playlists.
  Future<List>? _recommendedSongsFuture;

  /// Ytids added during this visit, removed from the fetched recommendations immediately.
  final Set<String> _addedRecommendedSongIds = {};

  /// Maximum recommendations rendered at once to bound artwork loads per frame.
  static const _visibleRecommendedSongsCount = 5;

  String? get _resolvedPlaylistId =>
      _playlist?['ytid']?.toString() ??
      widget.playlistData?['ytid']?.toString() ??
      widget.playlistId;

  // Sorting
  late PlaylistSortType _sortType = PlaylistSortType.values.firstWhere(
    (e) => e.name == playlistSortSetting,
    orElse: () => PlaylistSortType.default_,
  );

  // Search
  final ValueNotifier<String> _searchQueryNotifier = ValueNotifier('');
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;

  List _getSourceList(String searchQuery) {
    final list = _playlist?['list'] as List? ?? [];
    return filterSongsByQuery(list, searchQuery);
  }

  bool get _isArtistCatalogFailed =>
      widget.isArtist && _playlist?['catalogStatus'] == 'failed';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    userCustomPlaylists.addListener(_onCustomPlaylistsChanged);
    userPlaylistFolders.addListener(_onCustomPlaylistsChanged);
    _initializePlaylist();
  }

  @override
  void dispose() {
    userCustomPlaylists.removeListener(_onCustomPlaylistsChanged);
    userPlaylistFolders.removeListener(_onCustomPlaylistsChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchQueryNotifier.dispose();
    super.dispose();
  }

  void _onCustomPlaylistsChanged() {
    final resolvedId = _resolvedPlaylistId;
    if (resolvedId == null || !mounted) return;
    for (final p in storedCustomPlaylists) {
      if ((p['ytid'] ?? p['id'])?.toString() == resolvedId) {
        if (mounted) {
          setState(() {
            _playlist = p;
            _adoptPlaylist(p);
          });
        }
        break;
      }
    }
  }

  Future<void> _initializePlaylist() async {
    try {
      final initialPlaylist = widget.playlistData;
      final resolvedId =
          initialPlaylist?['ytid']?.toString() ?? widget.playlistId;

      if (initialPlaylist != null) {
        _playlist = initialPlaylist;
        final playlistList = _playlist?['list'] as List?;
        final shouldFetchInitialPlaylist =
            playlistList == null || (!widget.isArtist && playlistList.isEmpty);
        if (shouldFetchInitialPlaylist && resolvedId != null) {
          _playlist =
              await getPlaylistInfoForWidget(
                resolvedId,
                isArtist: widget.isArtist,
                artistName: initialPlaylist?['title']?.toString(),
                artistImage: initialPlaylist?['image']?.toString(),
                sourceSongId: initialPlaylist?['sourceSongId']?.toString(),
                sourceVideoAuthor: initialPlaylist?['videoAuthor']?.toString(),
                preferredVerified: initialPlaylist?['isVerifiedArtist'] == true,
              ) ??
              initialPlaylist;
        }
      } else {
        _playlist = await getPlaylistInfoForWidget(
          resolvedId,
          isArtist: widget.isArtist,
          artistName: initialPlaylist?['title']?.toString(),
          artistImage: initialPlaylist?['image']?.toString(),
          sourceSongId: initialPlaylist?['sourceSongId']?.toString(),
          sourceVideoAuthor: initialPlaylist?['videoAuthor']?.toString(),
          preferredVerified: initialPlaylist?['isVerifiedArtist'] == true,
        );
      }

      if (_playlist != null && _playlist['list'] != null) {
        _adoptPlaylist(_playlist);
        // Play and the first rows start instantly once these are ready.
        prefetchSongStreamUrls(_originalPlaylistList, limit: 2);
      }
      _maybeLoadRecommendations();
    } catch (e, stackTrace) {
      logger.log(
        'Error initializing playlist:',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) {
        showToast(context, context.l10n!.error);
      }
    } finally {
      _isInitializingPlaylist = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: commonSingleChildScrollViewPadding,
        child: _isInitializingPlaylist
            ? SizedBox(
                height: MediaQuery.sizeOf(context).height - 100,
                child: const Spinner(),
              )
            : _playlist != null
            ? CustomScrollView(
                slivers: [
                  PlaylistSliverAppBar(
                    leading: _buildBackButton(context),
                    title: _playlistTitle,
                    artwork: PlaylistHeroArtwork({
                      ..._playlist,
                      'list': _originalPlaylistList,
                    }, cubeIcon: widget.cubeIcon),
                  ),
                  SliverToBoxAdapter(child: _buildHeaderSection()),
                  if ((_playlist['list'] as List? ?? const []).isNotEmpty) ...[
                    ValueListenableBuilder<String>(
                      valueListenable: _searchQueryNotifier,
                      builder: (context, searchQuery, _) {
                        final sourceList = _getSourceList(searchQuery);
                        return SliverPadding(
                          padding: commonListViewBottomPadding,
                          sliver: SliverList.builder(
                            itemCount: sourceList.length,
                            itemBuilder: (context, index) {
                              final isRemovable =
                                  _playlist['source'] == 'user-created';
                              return _buildSongListItem(
                                sourceList[index],
                                index,
                                isRemovable,
                                sourceList,
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ] else if (_isArtistCatalogFailed)
                    EmptyPlaylistState(message: context.l10n!.error)
                  else
                    EmptyPlaylistState(
                      message: context.l10n!.noSongsInPlaylist,
                    ),
                  _buildRecommendedSongsSliver(),
                  const SliverMiniPlayerBottomSpace(),
                ],
              )
            : EmptyPlaylistState(message: context.l10n!.error),
      ),
    );
  }

  Widget _buildRecommendedSongsSliver() {
    final future = _recommendedSongsFuture;
    if (future == null) return const SliverToBoxAdapter();

    return SliverToBoxAdapter(
      child: AsyncLoader<List<dynamic>>(
        future: future,
        // Keep the section hidden when recommendations fail or are empty.
        loadingWidget: const SizedBox.shrink(),
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        builder: (context, data) {
          // Cap rendered rows to limit simultaneous artwork loads; do not refetch or backfill.
          final visibleSongs = data
              .where(
                (song) => !_addedRecommendedSongIds.contains(
                  song['ytid']?.toString(),
                ),
              )
              .take(_visibleRecommendedSongsCount)
              .toList();
          if (visibleSongs.isEmpty) return const SizedBox.shrink();

          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: RecommendedSongsSection(
              title: context.l10n!.recommendedSongs,
              songs: visibleSongs,
              listKeyPrefix: 'playlist_recommended',
              onAddSong: _handleAddRecommendedSong,
            ),
          );
        },
      ),
    );
  }

  /// Adds a recommendation directly to the current playlist with one tap.
  Future<void> _handleAddRecommendedSong(Map song) async {
    final playlistId = _resolvedPlaylistId;
    if (playlistId == null) return;

    final result = await addSongInCustomPlaylist(context, playlistId, song);
    if (!mounted) return;
    showToast(context, result);

    if (result == context.l10n!.songAdded) {
      setState(() {
        _addedRecommendedSongIds.add(song['ytid']?.toString() ?? '');
      });
    }
  }

  Widget _buildBackButton(BuildContext context) {
    return IconButton(
      icon: const Icon(FluentIcons.arrow_left_24_regular),
      onPressed: () => Navigator.pop(context, widget.playlistData == _playlist),
      tooltip: context.l10n!.back,
    );
  }

  String get _playlistTitle => widget.isArtist
      ? normalizeArtistDisplayTitle(_playlist['title']?.toString() ?? '')
      : _playlist['title']?.toString() ?? '';

  Widget _buildHeaderSection() {
    final songsLength = (_playlist['list'] as List? ?? const []).length;
    final isUserCreated = _playlist['source'] == 'user-created';
    final isCollaborative = _playlist['isCollaborative'] == true;
    final secondaryActions = <Widget>[
      if (widget.playlistId != null && !isUserCreated && !offlineMode.value)
        PlaylistLikeButton(
          playlistId: _resolvedPlaylistId ?? '',
          playlistData: () => _playlist,
        ),
      if (songsLength > 0) _buildDownloadButton(),
      if (!offlineMode.value) ...[
        PlaylistAddToPlaylistButton(resolvePlaylist: () async => _playlist),
        if (!isUserCreated) _buildSyncButton(),
      ],
      if (isUserCreated) ...[
        if (isCollaborative)
          IconButton.filledTonal(
            icon: const Icon(FluentIcons.people_team_24_filled),
            iconSize: 24,
            color: const Color(0xFF1DB954),
            onPressed: () =>
                showCollaborativePlaylistShareDialog(context, _playlist),
            tooltip: 'Collaborator Settings & Invite',
          )
        else
          IconButton.filledTonal(
            icon: const Icon(FluentIcons.person_add_24_regular),
            iconSize: 24,
            onPressed: () async {
              final playlistId = _resolvedPlaylistId;
              if (playlistId != null) {
                final res = await CollaborativePlaylistService.instance
                    .makePlaylistCollaborative(playlistId);
                if (!mounted) return;
                showToast(context, res.message);
                if (res.success) {
                  for (final p in storedCustomPlaylists) {
                    if ((p['ytid'] ?? p['id'])?.toString() == playlistId) {
                      setState(() {
                        _playlist = p;
                      });
                      if (mounted) {
                        showCollaborativePlaylistShareDialog(
                          context,
                          _playlist,
                        );
                      }
                      break;
                    }
                  }
                }
              }
            },
            tooltip: 'Make Collaborative',
          ),
        _buildShareButton(),
        _buildEditButton(),
      ],
    ];

    return Column(
      children: [
        PlaylistHeader(
          title: _playlistTitle,
          songsLength: songsLength,
          isAlbum: _playlist['isAlbum'] == true,
          isArtist: widget.isArtist,
          showTitle: false,
        ),
        if (isCollaborative) ...[
          const SizedBox(height: 6),
          InkWell(
            onTap: () =>
                showCollaborativePlaylistShareDialog(context, _playlist),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF1DB954).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF1DB954).withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    FluentIcons.people_team_16_filled,
                    size: 16,
                    color: Color(0xFF1DB954),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Collaborative • ${((_playlist['collaborators'] as List?) ?? []).length} members',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1DB954),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    FluentIcons.chevron_right_12_regular,
                    size: 12,
                    color: Color(0xFF1DB954),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (songsLength > 0)
          PlaylistActionButtons(
            leading: secondaryActions,
            onPlay: () => audioHandler.playPlaylistSong(
              playlist: _playlist,
              songIndex: 0,
              shuffle: false,
            ),
            onShuffle: () => audioHandler.playPlaylistSong(
              playlist: {
                ..._playlist,
                'list': (_playlist['list'] as List).whereType<Map>().toList(),
              },
              songIndex: 0,
              shuffle: true,
            ),
          )
        else if (secondaryActions.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: secondaryActions,
          ),
        if (songsLength > 1) ...[
          const SizedBox(height: 12),
          SortChips<PlaylistSortType>(
            currentSortType: _sortType,
            sortTypes: PlaylistSortType.values,
            sortTypeToString: _getSortTypeDisplayText,
            onSelected: (type) {
              setState(() {
                _sortType = type;
                addOrUpdateData<String>(
                  'settings',
                  'playlistSortType',
                  type.name,
                );
                playlistSortSetting = type.name;
                _applySort();
              });
            },
          ),
        ],
        if (songsLength > 0) ...[
          const SizedBox(height: 16),
          SearchBarSection(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onSearchChanged: (value) => _searchQueryNotifier.value = value,
            labelText: context.l10n!.search,
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildShareButton() {
    return IconButton.filledTonal(
      icon: const Icon(FluentIcons.share_24_regular),
      iconSize: 24,
      onPressed: () async {
        try {
          final encodedPlaylist = PlaylistSharingService.encodePlaylist(
            _playlist,
          );
          final url = 'vybe://playlist/custom/$encodedPlaylist';
          await Clipboard.setData(ClipboardData(text: url));
          if (mounted) {
            showToast(context, context.l10n!.linkCopied);
          }
        } catch (e, stackTrace) {
          logger.log(
            'Error sharing playlist',
            error: e,
            stackTrace: stackTrace,
          );
          if (mounted) {
            showToast(context, context.l10n!.error);
          }
        }
      },
      tooltip: context.l10n!.share,
    );
  }

  Widget _buildSyncButton() {
    return IconButton.filledTonal(
      icon: const Icon(FluentIcons.arrow_sync_24_filled),
      iconSize: 24,
      onPressed: _handleSyncPlaylist,
      tooltip: context.l10n!.update,
    );
  }

  Widget _buildEditButton() {
    return IconButton.filledTonal(
      icon: const Icon(FluentIcons.edit_24_filled),
      iconSize: 24,
      onPressed: () async {
        final result = await showDialog<Map?>(
          context: context,
          builder: (context) => EditPlaylistDialog(playlistData: _playlist),
        );

        if (result == null || !mounted) return;
        final playlistId = _resolvedPlaylistId;
        if (playlistId == null || playlistId.isEmpty || playlistId == 'null') {
          showToast(context, context.l10n!.error);
          return;
        }
        final updated =
            updateStoredCustomPlaylist(playlistId, result) ??
            {..._playlist, ...result, 'ytid': playlistId};
        unawaited(syncOfflinePlaylistMetadata(updated));
        setState(() => _adoptPlaylist(updated));
        showToast(context, context.l10n!.playlistUpdated);
      },
      tooltip: context.l10n!.editPlaylist,
    );
  }

  Widget _buildDownloadButton() {
    final playlistId = _playlist?['ytid']?.toString() ?? widget.playlistId;
    if (playlistId == null || playlistId.isEmpty) {
      return const SizedBox.shrink();
    }

    return PlaylistDownloadButton(
      playlistId: playlistId,
      songs: _playlist?['list'] as List? ?? const [],
      resolvePlaylist: () async => _playlist,
    );
  }

  void _handleSyncPlaylist() async {
    final playlistId = _playlist?['ytid']?.toString();
    if (playlistId == null || playlistId.isEmpty) return;

    if (offlineMode.value &&
        offlinePlaylistService.isPlaylistDownloaded(playlistId)) {
      if (mounted) {
        showToast(context, context.l10n!.removeOffline);
      }
      return;
    }

    // Artists/releases aren't built-in playlists; refresh by dropping their cache entry.
    final isCachedPage = widget.isArtist || playlistId.startsWith('MPRE');
    final updated = widget.isArtist
        ? await getPlaylistInfoForWidget(
            playlistId,
            isArtist: true,
            artistName: _playlist?['title']?.toString(),
            artistImage: _playlist?['image']?.toString(),
            preferredVerified: _playlist?['isVerifiedArtist'] == true,
            forceRefresh: true,
          )
        : isCachedPage
        ? await getPlaylistInfoForWidget(playlistId, forceRefresh: true)
        : await updatePlaylistList(context, playlistId);
    if (updated?['catalogStatus'] == 'failed') {
      if (mounted) showToast(context, context.l10n!.error);
      return;
    }
    if (updated != null && mounted) {
      setState(() => _adoptPlaylist(updated));
      if (isCachedPage) {
        showToast(context, context.l10n!.playlistUpdated);
      }
    }
  }

  /// Removes [song] from the canonical list (and storage), then re-derives the view.
  void _removeSong(Map song) {
    final songId = (song['ytid'] ?? song['id'])?.toString();
    final canonicalIndex = _originalPlaylistList.indexWhere(
      (s) => s is Map && (s['ytid'] ?? s['id'])?.toString() == songId,
    );
    if (canonicalIndex == -1) return;

    // Persist in canonical order, never the sorted view order.
    final canonicalPlaylist = {..._playlist, 'list': _originalPlaylistList};
    if (!removeSongFromPlaylist(
      canonicalPlaylist,
      song,
      removeOneAtIndex: canonicalIndex,
    )) {
      return;
    }
    _updateSongsListOnRemove(
      canonicalPlaylist['list'] as List,
      canonicalIndex,
      song,
    );
  }

  void _updateSongsListOnRemove(
    List<dynamic> updatedSongs,
    int indexToRestore,
    Map songToRemove,
  ) {
    _originalPlaylistList = updatedSongs;
    _applySort();
    final playlistId = (_playlist['ytid'] ?? _playlist['id'])?.toString();
    if (playlistId == null) {
      if (mounted) setState(() {});
      return;
    }
    if (mounted) {
      setState(() {});
      showToastWithButton(
        context,
        context.l10n!.songRemoved,
        context.l10n!.undo.toUpperCase(),
        () async {
          if (!mounted) return;
          final result = await addSongInCustomPlaylist(
            context,
            playlistId,
            songToRemove,
            indexToInsert: indexToRestore,
          );
          if (mounted && result != context.l10n!.songAdded) {
            showToast(context, result);
          }
        },
      );
    } else {
      logger.log(
        '(_updateSongsListOnRemove): Widget not mounted, cannot show undo toast.',
      );
    }
  }

  String _getSortTypeDisplayText(PlaylistSortType type) {
    switch (type) {
      case PlaylistSortType.default_:
        return context.l10n!.default_;
      case PlaylistSortType.title:
        return context.l10n!.name;
      case PlaylistSortType.artist:
        return context.l10n!.artist;
      case PlaylistSortType.dateAdded:
        return context.l10n!.dateAdded;
    }
  }

  /// Loads recommendations only for non-empty online user-created playlists.
  void _maybeLoadRecommendations() {
    final isUserCreated = _playlist?['source'] == 'user-created';
    final songs = _playlist?['list'] as List? ?? const [];
    final playlistId = _resolvedPlaylistId;

    if (isUserCreated &&
        !offlineMode.value &&
        songs.isNotEmpty &&
        playlistId != null) {
      _recommendedSongsFuture = getRecommendedSongsForPlaylist(
        playlistId,
        songs,
      );
    } else {
      _recommendedSongsFuture = null;
    }
  }

  /// Copy source, snapshot its canonical order and apply the current sort.
  /// Prevents sorting changes from affecting shared cached playlist data.
  void _adoptPlaylist(dynamic source) {
    if (source is! Map) {
      _playlist = source;
      _originalPlaylistList = <dynamic>[];
      return;
    }
    _playlist = Map<String, dynamic>.from(source);
    final list = source['list'];
    _originalPlaylistList = list is List
        ? List<dynamic>.from(list)
        : <dynamic>[];
    _applySort();
  }

  /// Rebuilds the displayed list from the canonical list for [_sortType].
  void _applySort() {
    if (_playlist is! Map || _playlist['list'] == null) return;

    _playlist['list'] = switch (_sortType) {
      PlaylistSortType.default_ => List<dynamic>.of(_originalPlaylistList),
      PlaylistSortType.title => sortSongsByKey(_originalPlaylistList, 'title'),
      PlaylistSortType.artist => sortSongsByKey(
        _originalPlaylistList,
        'artist',
      ),
      PlaylistSortType.dateAdded => sortSongsNewestFirst(_originalPlaylistList),
    };
  }

  Widget _buildSongListItem(
    Map song,
    int index,
    bool isRemovable,
    List sourceList,
  ) {
    final totalItems = sourceList.length;
    final borderRadius = getItemBorderRadius(index, totalItems);
    final isUserCreatedPlaylist = _playlist?['source'] == 'user-created';
    final playlistId = isUserCreatedPlaylist ? _playlist!['ytid'] : null;
    final songId = (song['ytid'] ?? song['id'])?.toString();
    final isSearching = _searchQueryNotifier.value.isNotEmpty;
    final fullIndex = isSearching && songId != null
        ? PlaylistUtils.findSongIndexByYtid(_playlist, songId)
        : index;

    if (isSearching && fullIndex == -1) {
      logger.log('Warning: Song $songId not found in full playlist');
    }

    return SongBar(
      song,
      true,
      key: listItemKey('playlist_song', index, song),
      onRemove: (isRemovable && !isSearching) ? () => _removeSong(song) : null,
      onPlay: () {
        audioHandler.playPlaylistSong(
          playlist: _playlist,
          songIndex: fullIndex != -1 ? fullIndex : index,
        );
      },
      borderRadius: borderRadius,
      playlistId: playlistId,
      onRenamed: () => setState(() {}),
    );
  }
}
