import 'dart:async';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/constants/app_constants.dart';
import 'package:vybe/database/radio_stations.db.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/main.dart';
import 'package:vybe/models/radio_model.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/data_manager.dart';
import 'package:vybe/services/playlists_manager.dart';
import 'package:vybe/services/router_service.dart';
import 'package:vybe/utilities/app_utils.dart';
import 'package:vybe/utilities/flutter_toast.dart';
import 'package:vybe/widgets/artist_bar.dart';
import 'package:vybe/widgets/browse_all_grid.dart';
import 'package:vybe/widgets/confirmation_dialog.dart';
import 'package:vybe/widgets/custom_bar.dart';
import 'package:vybe/widgets/custom_search_bar.dart';
import 'package:vybe/widgets/mini_player_bottom_space.dart';
import 'package:vybe/widgets/playlist_bar.dart';
import 'package:vybe/widgets/radio_station_card.dart';
import 'package:vybe/widgets/section_title.dart';
import 'package:vybe/widgets/song_bar.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({
    super.key,
    this.songSearch,
    this.artistSearch,
    this.playlistSearch,
    this.suggestionSearch,
  });

  final Future<List<dynamic>> Function(String query)? songSearch;
  final Future<List<dynamic>> Function(String query)? artistSearch;
  final Future<List<dynamic>> Function(String query, String type)?
  playlistSearch;
  final Future<List<String>> Function(String query)? suggestionSearch;

  @override
  _SearchPageState createState() => _SearchPageState();
}

// Global ValueNotifier for search history to make it reactive
final ValueNotifier<List> searchHistoryNotifier = ValueNotifier<List>(
  Hive.box('user').get('searchHistory', defaultValue: []),
);

void reloadSearchHistoryFromStorage() {
  searchHistoryNotifier.value = Hive.box('user')
      .get('searchHistory', defaultValue: []);
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _searchBar = TextEditingController();
  final FocusNode _inputNode = FocusNode();
  final ValueNotifier<bool> _fetchingSongs = ValueNotifier(false);
  int maxSongsInList = 15;
  List<dynamic> _songsSearchResult = [];
  List<Map<String, dynamic>> _artistsSearchResult = [];
  List<dynamic> _albumsSearchResult = [];
  List<dynamic> _playlistsSearchResult = [];
  List<RadioStation> _radioStationsSearchResult = [];
  List<String> _suggestionsList = [];
  Timer? _debounce;
  int _latestSuggestionRequest = 0;
  int _latestSearchRequest = 0;
  bool _editingQuery = false;

  Future<void> _submitSearch([String? query]) async {
    if (!mounted) return;
    if (query != null) {
      _searchBar.text = query;
      _searchBar.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchBar.text.length),
      );
    }

    _latestSuggestionRequest++;
    _debounce?.cancel();
    _suggestionsList = [];
    _editingQuery = false;
    _inputNode.unfocus();
    setState(() {});

    await search();
  }

  @override
  void dispose() {
    _latestSearchRequest++;
    _latestSuggestionRequest++;
    _searchBar.dispose();
    _inputNode.dispose();
    _fetchingSongs.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> search() async {
    if (!mounted) return;
    final query = _searchBar.text.trim();
    final requestId = ++_latestSearchRequest;

    if (query.isEmpty) {
      _songsSearchResult = [];
      _artistsSearchResult = [];
      _albumsSearchResult = [];
      _playlistsSearchResult = [];
      _radioStationsSearchResult = [];
      _suggestionsList = [];
      _fetchingSongs.value = false;
      if (mounted) setState(() {});
      return;
    }
    _fetchingSongs.value = true;

    _songsSearchResult = [];
    _artistsSearchResult = [];
    _albumsSearchResult = [];
    _playlistsSearchResult = [];
    _radioStationsSearchResult = radioStationsDB
        .where(
          (station) =>
              station.name.toLowerCase().contains(query.toLowerCase()) ||
              (station.genre?.toLowerCase().contains(query.toLowerCase()) ??
                  false),
        )
        .toList();
    if (mounted) setState(() {});

    if (!searchHistoryNotifier.value.contains(query)) {
      final updatedHistory = List.from(searchHistoryNotifier.value)
        ..insert(0, query);
      searchHistoryNotifier.value = updatedHistory;
      unawaited(addOrUpdateData<List>('user', 'searchHistory', updatedHistory));
    }

    try {
      final artistsFuture =
          widget.artistSearch?.call(query) ?? searchArtists(query);

      Future<void> publishSongs() async {
        try {
          var songs =
              await (widget.songSearch?.call(query) ?? fetchSongsList(query));
          if (!mounted || requestId != _latestSearchRequest) return;

          if (songs.isEmpty) {
            final artists = await artistsFuture;
            if (!mounted || requestId != _latestSearchRequest) return;
            if (_artistsSearchResult.isEmpty) {
              _artistsSearchResult = artists
                  .whereType<Map>()
                  .map(Map<String, dynamic>.from)
                  .toList();
            }
            if (_artistsSearchResult.isNotEmpty) {
              songs = await _fetchSongsForResolvedArtist(query, requestId);
            }
          }

          if (!mounted || requestId != _latestSearchRequest) return;
          setState(() => _songsSearchResult = songs);
        } catch (e, stackTrace) {
          logger.log(
            'Error while searching online songs',
            error: e,
            stackTrace: stackTrace,
          );
        }
      }

      Future<void> publishArtists() async {
        try {
          final artists = await artistsFuture;
          if (!mounted || requestId != _latestSearchRequest) return;
          setState(() {
            _artistsSearchResult = artists
                .whereType<Map>()
                .map(Map<String, dynamic>.from)
                .toList();
          });
        } catch (e, stackTrace) {
          logger.log(
            'Error while searching online artists',
            error: e,
            stackTrace: stackTrace,
          );
        }
      }

      Future<void> publishAlbums() async {
        try {
          final albums =
              await (widget.playlistSearch?.call(query, 'album') ??
                  getPlaylists(query: query, type: 'album'));
          if (!mounted || requestId != _latestSearchRequest) return;
          setState(() => _albumsSearchResult = albums);
        } catch (e, stackTrace) {
          logger.log(
            'Error while searching online albums',
            error: e,
            stackTrace: stackTrace,
          );
        }
      }

      Future<void> publishPlaylists() async {
        try {
          final playlists =
              await (widget.playlistSearch?.call(query, 'playlist') ??
                  getPlaylists(query: query, type: 'playlist'));
          if (!mounted || requestId != _latestSearchRequest) return;
          setState(() => _playlistsSearchResult = playlists);
        } catch (e, stackTrace) {
          logger.log(
            'Error while searching online playlists',
            error: e,
            stackTrace: stackTrace,
          );
        }
      }

      await Future.wait([
        publishSongs(),
        publishArtists(),
        publishAlbums(),
        publishPlaylists(),
      ]);
    } catch (e, stackTrace) {
      logger.log(
        'Error while searching online songs',
        error: e,
        stackTrace: stackTrace,
      );
    } finally {
      if (mounted && requestId == _latestSearchRequest) {
        _fetchingSongs.value = false;
        if (mounted) setState(() {});
      }
    }
  }

  Future<List<dynamic>> _fetchSongsForResolvedArtist(
    String query,
    int requestId,
  ) async {
    final artistName = _artistsSearchResult.first['title']?.toString().trim();
    if (artistName == null || artistName.isEmpty) return [];

    final fallbackQueries = <String>{
      if (artistName.toLowerCase() != query.trim().toLowerCase()) artistName,
      '$artistName songs',
      '$artistName music',
    };

    for (final fallbackQuery in fallbackQueries) {
      if (!mounted || requestId != _latestSearchRequest) return [];
      final songs =
          await (widget.songSearch?.call(fallbackQuery) ??
              fetchSongsList(fallbackQuery));
      if (!mounted || requestId != _latestSearchRequest) return [];
      if (songs.isNotEmpty) return songs;
    }

    return [];
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final suggestionRequest = ++_latestSuggestionRequest;
    // Typing invalidates an older submitted search immediately, before its
    // requests can publish stale rows or change the keyboard focus.
    _latestSearchRequest++;
    _fetchingSongs.value = false;
    setState(() {
      _editingQuery = value.trim().isNotEmpty;
      _suggestionsList = [];
      _songsSearchResult = [];
      _artistsSearchResult = [];
      _albumsSearchResult = [];
      _playlistsSearchResult = [];
      _radioStationsSearchResult = [];
    });
    final query = value.trim();
    if (query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final suggestions =
            await (widget.suggestionSearch?.call(query) ??
                getSearchSuggestions(query));
        if (!mounted ||
            suggestionRequest != _latestSuggestionRequest ||
            _searchBar.text.trim() != query ||
            !_editingQuery)
          return;
        setState(() => _suggestionsList = suggestions.toSet().toList());
      } catch (error, stack) {
        if (!mounted || suggestionRequest != _latestSuggestionRequest) return;
        logger.log(
          'Search suggestions unavailable',
          error: error,
          stackTrace: stack,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n!.search)),
      body: SingleChildScrollView(
        padding: commonSingleChildScrollViewPadding,
        child: Column(
          children: <Widget>[
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 600;
                final bar = ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isWide ? 600 : double.infinity,
                  ),
                  child: CustomSearchBar(
                    prominent: true,
                    loadingProgressNotifier: _fetchingSongs,
                    controller: _searchBar,
                    focusNode: _inputNode,
                    labelText: '${context.l10n!.search}...',
                    onChanged: _onQueryChanged,
                    onSubmitted: (String value) {
                      _submitSearch();
                    },
                  ),
                );
                if (isWide) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [bar],
                  );
                } else {
                  return bar;
                }
              },
            ),

            _buildSearchBody(context, primaryColor),
            const MiniPlayerBottomSpace(),
          ],
        ),
      ),
    );
  }

  bool get _hasResults =>
      _songsSearchResult.isNotEmpty ||
      _artistsSearchResult.isNotEmpty ||
      _albumsSearchResult.isNotEmpty ||
      _playlistsSearchResult.isNotEmpty ||
      _radioStationsSearchResult.isNotEmpty;

  Widget _buildSearchBody(BuildContext context, Color primaryColor) {
    if (_editingQuery || _searchBar.text.trim().isEmpty) {
      return ValueListenableBuilder<List>(
        valueListenable: searchHistoryNotifier,
        builder: (context, history, _) {
          final emptyQuery = _searchBar.text.trim().isEmpty;
          final items = emptyQuery ? history : _suggestionsList;
          return Column(
            children: [
              for (var index = 0; index < items.length; index++)
                CustomBar(
                  items[index].toString(),
                  FluentIcons.search_24_regular,
                  borderRadius: getItemBorderRadius(index, items.length),
                  onTap: () => _submitSearch(items[index].toString()),
                  onLongPress: !emptyQuery
                      ? null
                      : () async {
                          final query = items[index];
                          final confirmed =
                              await _showConfirmationDialog(context) ?? false;
                          if (!mounted || !confirmed) return;
                          final updated = List.from(searchHistoryNotifier.value)
                            ..remove(query);
                          searchHistoryNotifier.value = updated;
                          unawaited(
                            addOrUpdateData<List>(
                              'user',
                              'searchHistory',
                              updated,
                            ),
                          );
                        },
                ),
              if (emptyQuery) BrowseAllGrid(onTap: _submitSearch),
            ],
          );
        },
      );
    }
    if (!_hasResults) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: _fetchingSongs.value
            ? const Center(child: CircularProgressIndicator())
            : const Text(
                'No results found. Try another search.',
                textAlign: TextAlign.center,
              ),
      );
    }
    return _buildSearchResults(context, primaryColor);
  }

  Widget _buildSearchResults(BuildContext context, Color primaryColor) {
    final widgets = <Widget>[];

    // Songs section
    if (_songsSearchResult.isNotEmpty) {
      widgets.add(
        SectionTitle(
          context.l10n!.songs,
          primaryColor,
          icon: FluentIcons.music_note_1_24_filled,
        ),
      );

      final songsCount = _songsSearchResult.length > maxSongsInList
          ? maxSongsInList
          : _songsSearchResult.length;

      for (var index = 0; index < songsCount; index++) {
        final song = _songsSearchResult[index];
        final borderRadius = getItemBorderRadius(index, songsCount);
        widgets.add(
          SongBar(
            song,
            true,
            key: ValueKey(
              'search-song-${_searchBar.text.trim()}-${song['ytid'] ?? index}',
            ),
            showMusicDuration: true,
            borderRadius: borderRadius,
          ),
        );
      }
    }

    // Artists section
    if (_artistsSearchResult.isNotEmpty) {
      widgets.add(
        SectionTitle(
          context.l10n!.artists,
          primaryColor,
          icon: FluentIcons.person_24_filled,
        ),
      );

      final artists = _artistsSearchResult.take(3).toList();
      for (var index = 0; index < artists.length; index++) {
        final artist = Map<String, dynamic>.from(artists[index]);
        final artistId =
            artist['ytid']?.toString() ?? artist['title']?.toString() ?? '';
        if (artistId.isEmpty) continue;

        final borderRadius = getItemBorderRadius(index, artists.length);
        widgets.add(
          ArtistBar(
            key: listItemKey('search_artist', index, artist),
            artist: artist,
            borderRadius: borderRadius,
            onTap: () {
              context.push(
                '${NavigationManager.searchPath}/artist/${Uri.encodeComponent(artistId)}',
                extra: artist,
              );
            },
          ),
        );
      }
    }

    // Albums section
    if (_albumsSearchResult.isNotEmpty) {
      widgets.add(
        SectionTitle(
          context.l10n!.albums,
          primaryColor,
          icon: FluentIcons.album_24_filled,
        ),
      );

      final albumsCount = _albumsSearchResult.length > maxSongsInList
          ? maxSongsInList
          : _albumsSearchResult.length;

      for (var index = 0; index < albumsCount; index++) {
        final playlist = _albumsSearchResult[index];
        final borderRadius = getItemBorderRadius(index, albumsCount);

        widgets.add(
          PlaylistBar(
            key: listItemKey('search_album', index, playlist),
            playlist['title'],
            playlistId: playlist['ytid'],
            playlistArtwork: playlist['image'],
            cubeIcon: FluentIcons.cd_16_filled,
            isAlbum: true,
            borderRadius: borderRadius,
          ),
        );
      }
    }

    // Playlists section
    if (_playlistsSearchResult.isNotEmpty) {
      widgets.add(
        SectionTitle(
          context.l10n!.playlists,
          primaryColor,
          icon: FluentIcons.text_bullet_list_24_filled,
        ),
      );

      final playlistsCount = _playlistsSearchResult.length > maxSongsInList
          ? maxSongsInList
          : _playlistsSearchResult.length;

      for (var index = 0; index < playlistsCount; index++) {
        final playlist = _playlistsSearchResult[index];
        final isLast = index == playlistsCount - 1;
        final borderRadius = getItemBorderRadius(index, playlistsCount);

        widgets.add(
          Padding(
            padding: isLast ? commonListViewBottomPadding : EdgeInsets.zero,
            child: PlaylistBar(
              key: listItemKey('search_playlist', index, playlist),
              playlist['title'],
              playlistId: playlist['ytid'],
              playlistArtwork: playlist['image'],
              cubeIcon: FluentIcons.apps_list_24_filled,
              borderRadius: borderRadius,
            ),
          ),
        );
      }
    }

    // Radio Stations section
    if (_radioStationsSearchResult.isNotEmpty) {
      widgets.add(
        SectionTitle(
          context.l10n!.radioStations,
          primaryColor,
          icon: FluentIcons.speaker_2_24_filled,
        ),
      );

      final stationsCount = _radioStationsSearchResult.length > maxSongsInList
          ? maxSongsInList
          : _radioStationsSearchResult.length;

      for (var index = 0; index < stationsCount; index++) {
        final station = _radioStationsSearchResult[index];
        final isLast = index == stationsCount - 1;

        widgets.add(
          Padding(
            padding: isLast ? commonListViewBottomPadding : EdgeInsets.zero,
            child: RadioStationCard(
              key: listItemKey('search_radio_station', index, station),
              station: station,
              onPressed: () async {
                final success = await audioHandler.playRadioStream(
                  id: station.id,
                  name: station.name,
                  streamUrl: station.streamUrl,
                  image: station.image,
                  genre: station.genre,
                );
                if (!success && context.mounted) {
                  showToast(context, context.l10n!.failedPlayingRadio);
                }
              },
            ),
          ),
        );
      }
    }

    return Column(children: widgets);
  }

  Future<bool?> _showConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return ConfirmationDialog(
          confirmationMessage: context.l10n!.removeSearchQueryQuestion,
          submitMessage: context.l10n!.confirm,
          onCancel: () {
            Navigator.of(context).pop(false);
          },
          onSubmit: () {
            Navigator.of(context).pop(true);
          },
        );
      },
    );
  }
}
