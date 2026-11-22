import 'dart:async';
import 'dart:convert';

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
import 'package:vybe/utilities/artwork_provider.dart';
import 'package:vybe/utilities/flutter_toast.dart';
import 'package:vybe/widgets/artist_bar.dart';
import 'package:vybe/widgets/browse_all_grid.dart';
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

/// Parses a song map or a stringified map representation (e.g. from Dart's `Map.toString()`)
/// into a structured Map containing title, artist, image URL, ytid, etc.
Map<String, dynamic>? parseStringifiedSongMap(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map) {
    final title = (raw['title'] ?? raw['name'] ?? '').toString().trim();
    if (title.isEmpty) return null;
    return Map<String, dynamic>.from(raw);
  }
  if (raw is! String) return null;
  final str = raw.trim();
  if (!str.startsWith('{') || !str.endsWith('}')) return null;

  try {
    final decoded = jsonDecode(str);
    if (decoded is Map) {
      final title = (decoded['title'] ?? decoded['name'] ?? '')
          .toString()
          .trim();
      if (title.isEmpty) return null;
      return Map<String, dynamic>.from(decoded);
    }
  } catch (_) {
    // Not JSON, parse Dart Map.toString() output
  }

  final content = str.substring(1, str.length - 1).trim();
  if (content.isEmpty) return null;

  const knownKeys = [
    'title',
    'artist',
    'image',
    'lowResImage',
    'highResImage',
    'artworkPath',
    'artWorkPath',
    'ytid',
    'id',
    'album',
    'duration',
    'isSong',
    'isArtist',
    'audioPath',
    'lyrics',
    'name',
  ];

  final pattern = RegExp(
    '(?:^|,\\s*)(${knownKeys.join('|')})\\s*:\\s*',
    caseSensitive: false,
  );

  final matches = pattern.allMatches(content).toList();
  if (matches.isEmpty) return null;

  final result = <String, dynamic>{};
  for (var i = 0; i < matches.length; i++) {
    final match = matches[i];
    final key = match.group(1)!.toLowerCase();
    final valueStart = match.end;
    final valueEnd = (i + 1 < matches.length)
        ? matches[i + 1].start
        : content.length;

    var val = content.substring(valueStart, valueEnd).trim();
    if (val.endsWith(',')) {
      val = val.substring(0, val.length - 1).trim();
    }
    if ((val.startsWith('"') && val.endsWith('"')) ||
        (val.startsWith("'") && val.endsWith("'"))) {
      val = val.substring(1, val.length - 1).trim();
    }
    if (val == 'null') continue;
    if (val.isEmpty) continue;

    if (key == 'issong') {
      result['isSong'] = val.toLowerCase() == 'true';
    } else if (key == 'isartist') {
      result['isArtist'] = val.toLowerCase() == 'true';
    } else {
      result[key] = val;
    }
  }

  if (result.containsKey('title') || result.containsKey('name')) {
    final title = (result['title'] ?? result['name'] ?? '').toString().trim();
    if (title.isEmpty) return null;
    final ytid = (result['ytid'] ?? result['id'] ?? '').toString().trim();
    var imageUrl =
        (result['image'] ??
                result['lowResImage'] ??
                result['highResImage'] ??
                result['artworkPath'] ??
                result['artWorkPath'] ??
                '')
            .toString()
            .trim();

    if ((imageUrl.isEmpty || imageUrl == 'null') && ytid.isNotEmpty) {
      imageUrl = 'https://i.ytimg.com/vi/$ytid/mqdefault.jpg';
    }

    if (imageUrl.isEmpty || imageUrl == 'null') {
      final recent = userRecentlyPlayed.value.firstWhere(
        (s) =>
            s is Map &&
            (s['title']?.toString().toLowerCase() == title.toLowerCase() ||
                (ytid.isNotEmpty && s['ytid']?.toString() == ytid)),
        orElse: () => null,
      );
      if (recent != null && recent is Map) {
        imageUrl =
            (recent['image'] ??
                    recent['lowResImage'] ??
                    recent['highResImage'] ??
                    recent['artworkPath'])
                ?.toString() ??
            '';
        if (result['artist'] == null ||
            result['artist'].toString().trim().isEmpty) {
          result['artist'] = recent['artist']?.toString() ?? '';
        }
      }
    }

    return {
      'title': title,
      'artist': (result['artist'] ?? '').toString().trim(),
      'image': imageUrl,
      'lowResImage': (result['lowResImage'] ?? imageUrl).toString().trim(),
      'highResImage': (result['highResImage'] ?? imageUrl).toString().trim(),
      'ytid': ytid,
      if (result['isArtist'] == true) 'isArtist': true else 'isSong': true,
    };
  }

  return null;
}

/// Sanitizes search history items, converting any raw stringified maps into clean
/// Song maps with thumbnail artwork, keeping only actual music items (songs/artists),
/// and deduplicating entries.
List<dynamic> sanitizeSearchHistory(List rawHistory) {
  final sanitized = <dynamic>[];
  final seenKeys = <String>{};

  for (final item in rawHistory) {
    if (item == null) continue;
    dynamic resolved = item;
    if (item is String &&
        item.trim().startsWith('{') &&
        (item.contains('title:') || item.contains('name:'))) {
      final parsed = parseStringifiedSongMap(item);
      if (parsed != null) {
        resolved = parsed;
      }
    }

    // Only keep actual music items (songs, artists) in recent searches
    if (resolved is! Map) {
      continue;
    }

    final title = (resolved['title'] ?? resolved['name'] ?? '')
        .toString()
        .toLowerCase()
        .trim();
    if (title.isEmpty) {
      continue;
    }
    final ytid = resolved['ytid']?.toString() ?? '';
    final dedupKey = ytid.isNotEmpty ? 'song:ytid:$ytid' : 'song:title:$title';

    if (dedupKey.isNotEmpty && !seenKeys.contains(dedupKey)) {
      seenKeys.add(dedupKey);
      sanitized.add(resolved);
    }
  }

  return sanitized;
}

List _loadAndSanitizeSearchHistory() {
  try {
    final raw = Hive.box('user').get('searchHistory', defaultValue: []);
    final rawList = raw is List ? raw : [];
    final sanitized = sanitizeSearchHistory(rawList);
    // If raw list had any stringified maps or plain search queries, persist the cured song-only list to Hive
    if (rawList.length != sanitized.length || rawList.any((e) => e is String)) {
      unawaited(addOrUpdateData<List>('user', 'searchHistory', sanitized));
    }
    return sanitized;
  } catch (_) {
    return [];
  }
}

// Global ValueNotifier for search history to make it reactive
final ValueNotifier<List> searchHistoryNotifier = ValueNotifier<List>(
  _loadAndSanitizeSearchHistory(),
);

void reloadSearchHistoryFromStorage() {
  searchHistoryNotifier.value = _loadAndSanitizeSearchHistory();
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

  /// Songs shown under the suggestions while typing, before submitting.
  List<dynamic> _liveSongs = [];

  /// Which result type the chips above the results show; null shows all.
  String? _resultFilter;
  Timer? _debounce;
  int _latestSuggestionRequest = 0;
  int _latestSearchRequest = 0;
  bool _editingQuery = false;

  @override
  void initState() {
    super.initState();
    _inputNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _cancelSearch() {
    _debounce?.cancel();
    _latestSearchRequest++;
    _latestSuggestionRequest++;
    _searchBar.clear();
    _inputNode.unfocus();
    _editingQuery = false;
    _fetchingSongs.value = false;
    _songsSearchResult = [];
    _artistsSearchResult = [];
    _albumsSearchResult = [];
    _playlistsSearchResult = [];
    _radioStationsSearchResult = [];
    _suggestionsList = [];
    _liveSongs = [];
    _resultFilter = null;
    if (mounted) setState(() {});
  }

  /// Puts [suggestion] in the field to keep refining it, without searching.
  void _fillQuery(String suggestion) {
    final text = '$suggestion ';
    _searchBar.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _inputNode.requestFocus();
    _onQueryChanged(text);
  }

  void _playSong(dynamic song) {
    _addSongToRecents(song);
    audioHandler.addPlaylistToQueue([song], replace: true, startIndex: 0);
  }

  void _addSongToRecents(dynamic song) {
    if (song == null) return;
    final map = song is Map
        ? Map<String, dynamic>.from(song)
        : (song is String &&
                  song.trim().startsWith('{') &&
                  (song.contains('title:') || song.contains('name:'))
              ? parseStringifiedSongMap(song)
              : null);
    final title = (map?['title'] ?? song.toString()).trim();
    if (title.isEmpty) return;

    final ytid = map?['ytid']?.toString() ?? '';
    var image =
        (map?['image'] ??
                map?['lowResImage'] ??
                map?['highResImage'] ??
                map?['artworkPath'] ??
                map?['artWorkPath'])
            ?.toString() ??
        '';
    if (image.contains('/sddefault.jpg')) {
      image = image.replaceAll('/sddefault.jpg', '/mqdefault.jpg');
    }
    if ((image.isEmpty || image == 'null') && ytid.isNotEmpty) {
      image = 'https://i.ytimg.com/vi/$ytid/mqdefault.jpg';
    }

    final entry = {
      'title': title,
      'artist': map?['artist']?.toString() ?? '',
      'image': image,
      'lowResImage': map?['lowResImage']?.toString() ?? image,
      'highResImage': map?['highResImage']?.toString() ?? image,
      'ytid': ytid,
      'isSong': true,
    };

    final current = List.from(searchHistoryNotifier.value)
      ..removeWhere((item) {
        if (item is Map) {
          if (ytid.isNotEmpty && item['ytid'] == ytid) return true;
          return item['title']?.toString().toLowerCase() == title.toLowerCase();
        } else if (item is String) {
          return item.toLowerCase() == title.toLowerCase();
        }
        return false;
      })
      ..insert(0, entry);
    if (current.length > 20) current.removeRange(20, current.length);
    searchHistoryNotifier.value = current;
    unawaited(addOrUpdateData<List>('user', 'searchHistory', current));
  }

  void _addArtistToRecents(Map artist) {
    final title = artist['title']?.toString().trim() ?? '';
    if (title.isEmpty) return;
    final ytid = artist['ytid']?.toString() ?? '';
    final entry = {
      'title': title,
      'artist': 'Artist',
      'image':
          (artist['image'] ?? artist['lowResImage'] ?? artist['highResImage'])
              ?.toString() ??
          '',
      'ytid': ytid,
      'isArtist': true,
    };
    final current = List.from(searchHistoryNotifier.value)
      ..removeWhere((item) {
        if (item is Map) {
          if (ytid.isNotEmpty && item['ytid'] == ytid) return true;
          return item['title']?.toString().toLowerCase() == title.toLowerCase();
        } else if (item is String) {
          return item.toLowerCase() == title.toLowerCase();
        }
        return false;
      })
      ..insert(0, entry);
    if (current.length > 20) current.removeRange(20, current.length);
    searchHistoryNotifier.value = current;
    unawaited(addOrUpdateData<List>('user', 'searchHistory', current));
  }

  void _removeFromRecents(dynamic item) {
    dynamic target = item;
    if (item is String &&
        item.trim().startsWith('{') &&
        (item.contains('title:') || item.contains('name:'))) {
      final parsed = parseStringifiedSongMap(item);
      if (parsed != null) {
        target = parsed;
      }
    }

    final current = List.from(searchHistoryNotifier.value)
      ..removeWhere((e) {
        if (identical(e, item) || e == item) return true;
        if (target is Map && e is Map) {
          final tYtid = target['ytid']?.toString() ?? '';
          final eYtid = e['ytid']?.toString() ?? '';
          if (tYtid.isNotEmpty && eYtid.isNotEmpty && tYtid == eYtid)
            return true;
          final tTitle = (target['title'] ?? '')
              .toString()
              .toLowerCase()
              .trim();
          final eTitle = (e['title'] ?? '').toString().toLowerCase().trim();
          if (tTitle.isNotEmpty && tTitle == eTitle) return true;
        } else if (target is String && e is String) {
          return target.toLowerCase().trim() == e.toLowerCase().trim();
        }
        return false;
      });
    searchHistoryNotifier.value = current;
    unawaited(addOrUpdateData<List>('user', 'searchHistory', current));
  }

  void _clearAllRecents() {
    searchHistoryNotifier.value = [];
    unawaited(addOrUpdateData<List>('user', 'searchHistory', []));
  }

  void _onRecentItemTap(dynamic item) {
    dynamic resolved = item;
    if (item is String &&
        item.trim().startsWith('{') &&
        (item.contains('title:') || item.contains('name:'))) {
      final parsed = parseStringifiedSongMap(item);
      if (parsed != null) {
        resolved = parsed;
      }
    }

    if (resolved is Map) {
      if (resolved['isArtist'] == true) {
        final artistId =
            resolved['ytid']?.toString() ?? resolved['title']?.toString() ?? '';
        context.push(
          '${NavigationManager.searchPath}/artist/${Uri.encodeComponent(artistId)}',
          extra: resolved,
        );
        return;
      }
      _addSongToRecents(resolved);
      final ytid = resolved['ytid']?.toString() ?? '';
      if (ytid.isNotEmpty) {
        audioHandler.addPlaylistToQueue(
          [resolved],
          replace: true,
          startIndex: 0,
        );
      } else {
        final title = (resolved['title'] ?? '').toString().trim();
        _submitSearch(title);
      }
    } else if (resolved is String) {
      final match = userRecentlyPlayed.value.firstWhere(
        (s) =>
            s is Map &&
            s['title']?.toString().toLowerCase() == resolved.toLowerCase(),
        orElse: () => null,
      );
      if (match != null && match is Map) {
        _addSongToRecents(match);
        audioHandler.addPlaylistToQueue([match], replace: true, startIndex: 0);
      } else {
        _submitSearch(resolved);
      }
    }
  }

  Future<void> _submitSearch([String? query]) async {
    if (!mounted) return;
    if (query != null) {
      var cleanQuery = query.trim();
      if (cleanQuery.startsWith('{') &&
          (cleanQuery.contains('title:') || cleanQuery.contains('name:'))) {
        final parsed = parseStringifiedSongMap(cleanQuery);
        if (parsed != null && parsed['title'] != null) {
          cleanQuery = parsed['title'].toString().trim();
        }
      }
      _searchBar.text = cleanQuery;
      _searchBar.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchBar.text.length),
      );
    }

    _latestSuggestionRequest++;
    _debounce?.cancel();
    _suggestionsList = [];
    _liveSongs = [];
    _resultFilter = null;
    _editingQuery = false;
    _inputNode.unfocus();
    setState(() {});

    await search();
  }

  @override
  void dispose() {
    _inputNode.removeListener(_onFocusChanged);
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
          // The top results are the ones usually tapped: get them ready.
          prefetchSongStreamUrls(songs, limit: 2);
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
      if (value.trim().isEmpty) _liveSongs = [];
      _songsSearchResult = [];
      _artistsSearchResult = [];
      _albumsSearchResult = [];
      _playlistsSearchResult = [];
      _radioStationsSearchResult = [];
    });
    final query = value.trim();
    if (query.isEmpty) return;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      bool stillCurrent() =>
          mounted &&
          suggestionRequest == _latestSuggestionRequest &&
          _searchBar.text.trim() == query &&
          _editingQuery;

      // Songs appear under the suggestions as you type, like Spotify.
      unawaited(
        (widget.songSearch?.call(query) ?? fetchSongsList(query))
            .then((songs) {
              if (!stillCurrent()) return;
              setState(() => _liveSongs = songs);
              prefetchSongStreamUrls(songs, limit: 1);
            })
            .catchError((Object error) {
              logger.log('Live song results unavailable', error: error);
            }),
      );
      try {
        final suggestions =
            await (widget.suggestionSearch?.call(query) ??
                getSearchSuggestions(query));
        if (!stillCurrent()) return;
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
    final isSearching =
        _inputNode.hasFocus || _searchBar.text.isNotEmpty || _hasResults;

    return PopScope(
      canPop: !isSearching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _cancelSearch();
        }
      },
      child: Scaffold(
        // While searching the field takes over the top, with a back arrow,
        // like Spotify. Otherwise the page shows its title and a white field.
        appBar: isSearching ? null : AppBar(title: Text(context.l10n!.search)),
        body: SafeArea(
          bottom: false,
          top: isSearching,
          child: SingleChildScrollView(
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
                      child: Row(
                        children: [
                          if (isSearching) ...[
                            IconButton(
                              onPressed: _cancelSearch,
                              tooltip: context.l10n!.back,
                              icon: const Icon(
                                FluentIcons.arrow_left_24_regular,
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: CustomSearchBar(
                              prominent: !isSearching,
                              loadingProgressNotifier: _fetchingSongs,
                              controller: _searchBar,
                              focusNode: _inputNode,
                              labelText: context.l10n!.searchPlaceholder,
                              onChanged: _onQueryChanged,
                              onSubmitted: (String value) {
                                _submitSearch();
                              },
                            ),
                          ),
                        ],
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
    // 1. While typing: suggestions, then matching songs right below them.
    if (_editingQuery && _searchBar.text.trim().isNotEmpty) {
      final typed = _searchBar.text.trim();
      return Column(
        children: [
          for (final suggestion in _suggestionsList.take(5))
            _SuggestionTile(
              suggestion: suggestion,
              typed: typed,
              onTap: () => _submitSearch(suggestion),
              onFill: () => _fillQuery(suggestion),
            ),
          if (_suggestionsList.isNotEmpty && _liveSongs.isNotEmpty)
            const SizedBox(height: 8),
          for (final song in _liveSongs.take(8))
            SongBar(
              song,
              true,
              key: ValueKey('live-song-$typed-${song['ytid']}'),
              typeLabel: context.l10n!.songType,
              showLikeButton: true,
              onPlay: () => _playSong(song),
            ),
        ],
      );
    }

    // 2. Query is submitted (non-empty)
    if (_searchBar.text.trim().isNotEmpty) {
      if (!_hasResults) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: _fetchingSongs.value
              ? const Center(child: CircularProgressIndicator())
              : Text(
                  context.l10n!.searchNoResults,
                  textAlign: TextAlign.center,
                ),
        );
      }
      return _buildSearchResults(context, primaryColor);
    }

    // 3. Search bar is focused and query is empty -> show Spotify-style Recent searches
    if (_inputNode.hasFocus) {
      return ValueListenableBuilder<List>(
        valueListenable: searchHistoryNotifier,
        builder: (context, history, _) {
          if (history.isEmpty) {
            return BrowseAllGrid(onTap: _submitSearch);
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                  top: 8,
                  bottom: 8,
                  left: 4,
                  right: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.l10n!.recentSearches,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    TextButton(
                      onPressed: _clearAllRecents,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        context.l10n!.clear,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              for (final item in history)
                _RecentSearchTile(
                  key: ValueKey(
                    'recent-${item is Map ? (item['ytid'] ?? item['title']) : item}',
                  ),
                  item: item,
                  onTap: () => _onRecentItemTap(item),
                  onRemove: () => _removeFromRecents(item),
                ),
            ],
          );
        },
      );
    }

    // 4. Search bar is NOT focused and query is empty -> Landing page: ONLY Browse all
    return BrowseAllGrid(onTap: _submitSearch);
  }

  Widget _buildFilterChips(BuildContext context) {
    final l10n = context.l10n!;
    final colorScheme = Theme.of(context).colorScheme;
    final filters = <(String?, String)>[
      (null, l10n.allResults),
      if (_songsSearchResult.isNotEmpty) ('songs', l10n.songs),
      if (_artistsSearchResult.isNotEmpty) ('artists', l10n.artists),
      if (_albumsSearchResult.isNotEmpty) ('albums', l10n.albums),
      if (_playlistsSearchResult.isNotEmpty) ('playlists', l10n.playlists),
      if (_radioStationsSearchResult.isNotEmpty) ('radio', l10n.radioStations),
    ];
    if (filters.length < 3) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (value, label) = filters[index];
          final selected = _resultFilter == value;
          return Center(
            child: Material(
              color: selected
                  ? colorScheme.primary
                  : colorScheme.surfaceContainerHigh,
              shape: const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: () => setState(() => _resultFilter = value),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: selected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurface,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  bool _showsResults(String type) =>
      _resultFilter == null || _resultFilter == type;

  Widget _buildSearchResults(BuildContext context, Color primaryColor) {
    final widgets = <Widget>[_buildFilterChips(context)];

    // Songs section
    if (_songsSearchResult.isNotEmpty && _showsResults('songs')) {
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
            borderRadius: borderRadius,
            typeLabel: context.l10n!.songType,
            showLikeButton: true,
            onPlay: () => _playSong(song),
          ),
        );
      }
    }

    // Artists section
    if (_artistsSearchResult.isNotEmpty && _showsResults('artists')) {
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
              _addArtistToRecents(artist);
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
    if (_albumsSearchResult.isNotEmpty && _showsResults('albums')) {
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
    if (_playlistsSearchResult.isNotEmpty && _showsResults('playlists')) {
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
    if (_radioStationsSearchResult.isNotEmpty && _showsResults('radio')) {
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
}

class _RecentSearchTile extends StatelessWidget {
  const _RecentSearchTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  final dynamic item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    var title = '';
    String? subtitle;
    String? imageUrl;
    var isSong = false;
    var isArtist = false;

    dynamic resolved = item;
    if (item is String &&
        item.trim().startsWith('{') &&
        (item.contains('title:') || item.contains('name:'))) {
      final parsed = parseStringifiedSongMap(item);
      if (parsed != null) {
        resolved = parsed;
      }
    }

    if (resolved is Map) {
      final map = Map<String, dynamic>.from(resolved);
      title = (map['title'] ?? map['name'] ?? '').toString().trim();
      isArtist = map['isArtist'] == true;
      if (isArtist) {
        subtitle = 'Artist';
      } else {
        subtitle = (map['artist'] ?? (map['isSong'] == true ? 'Song' : null))
            ?.toString()
            .trim();
        isSong = true;
      }
      imageUrl =
          (map['image'] ??
                  map['lowResImage'] ??
                  map['highResImage'] ??
                  map['artworkPath'] ??
                  map['artWorkPath'])
              ?.toString()
              .trim();

      final ytid = (map['ytid'] ?? map['id'] ?? '').toString().trim();
      if ((imageUrl == null || imageUrl.isEmpty || imageUrl == 'null') &&
          ytid.isNotEmpty) {
        imageUrl = 'https://i.ytimg.com/vi/$ytid/mqdefault.jpg';
      }

      if ((imageUrl == null || imageUrl.isEmpty || imageUrl == 'null') &&
          title.isNotEmpty) {
        final recent = userRecentlyPlayed.value.firstWhere(
          (s) =>
              s is Map &&
              s['title']?.toString().toLowerCase() == title.toLowerCase(),
          orElse: () => null,
        );
        if (recent != null && recent is Map) {
          imageUrl =
              (recent['image'] ??
                      recent['lowResImage'] ??
                      recent['highResImage'] ??
                      recent['artworkPath'])
                  ?.toString()
                  .trim();
          if (subtitle == null || subtitle == 'Song') {
            subtitle = recent['artist']?.toString().trim();
          }
        }
      }
    } else if (resolved is String) {
      title = resolved.trim();
      final match = userRecentlyPlayed.value.firstWhere(
        (s) =>
            s is Map &&
            s['title']?.toString().toLowerCase() ==
                resolved.toLowerCase().trim(),
        orElse: () => null,
      );
      if (match != null && match is Map) {
        subtitle = match['artist']?.toString().trim();
        imageUrl =
            (match['image'] ??
                    match['lowResImage'] ??
                    match['highResImage'] ??
                    match['artworkPath'])
                ?.toString()
                .trim();
        isSong = true;
      } else {
        subtitle = 'Search';
      }
    }

    if (imageUrl != null) {
      if (imageUrl.contains('/sddefault.jpg')) {
        imageUrl = imageUrl.replaceAll('/sddefault.jpg', '/mqdefault.jpg');
      }
      imageUrl = imageUrl.trim();
      if (imageUrl == 'null' || imageUrl == 'none' || imageUrl.isEmpty) {
        imageUrl = null;
      }
    }

    if (title.isEmpty) return const SizedBox.shrink();

    const artSize = 52.0;
    Widget leadingWidget;

    if (imageUrl != null && imageUrl.isNotEmpty) {
      leadingWidget = ClipRRect(
        borderRadius: BorderRadius.circular(isArtist ? artSize / 2 : 4),
        child: SizedBox(
          width: artSize,
          height: artSize,
          child: Image(
            image: ArtworkProvider.get(imageUrl),
            width: artSize,
            height: artSize,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _buildPlaceholder(
              colorScheme,
              isSong: isSong,
              isArtist: isArtist,
            ),
          ),
        ),
      );
    } else {
      leadingWidget = _buildPlaceholder(
        colorScheme,
        isSong: isSong,
        isArtist: isArtist,
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            leadingWidget,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove',
              icon: Icon(
                FluentIcons.dismiss_20_regular,
                color: colorScheme.onSurfaceVariant,
                size: 20,
              ),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(
    ColorScheme colorScheme, {
    required bool isSong,
    required bool isArtist,
  }) {
    const artSize = 52.0;
    return Container(
      width: artSize,
      height: artSize,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(isArtist ? artSize / 2 : 4),
      ),
      child: Icon(
        isArtist
            ? FluentIcons.person_24_regular
            : isSong
            ? FluentIcons.music_note_2_24_regular
            : FluentIcons.search_24_regular,
        color: colorScheme.onSurfaceVariant,
        size: 24,
      ),
    );
  }
}

/// One autocomplete row: the typed part dimmed and the rest bright, so the
/// completion stands out, with an arrow that copies it into the field to keep
/// typing instead of searching.
class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.suggestion,
    required this.typed,
    required this.onTap,
    required this.onFill,
  });

  final String suggestion;
  final String typed;
  final VoidCallback onTap;
  final VoidCallback onFill;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final startsWithTyped = suggestion.toLowerCase().startsWith(
      typed.toLowerCase(),
    );
    final typedPart = startsWithTyped
        ? suggestion.substring(0, typed.length)
        : '';
    final rest = startsWithTyped
        ? suggestion.substring(typed.length)
        : suggestion;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
        child: Row(
          children: [
            Icon(
              FluentIcons.search_24_regular,
              color: colorScheme.onSurfaceVariant,
              size: 22,
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: typedPart,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    TextSpan(
                      text: rest,
                      style: TextStyle(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16),
              ),
            ),
            IconButton(
              onPressed: onFill,
              tooltip: suggestion,
              icon: Icon(
                FluentIcons.arrow_up_left_24_regular,
                color: colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
