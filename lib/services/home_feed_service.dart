import 'package:vybe/database/playlists.db.dart';
import 'package:vybe/main.dart' show logger;
import 'package:vybe/services/artist_service.dart';
import 'package:vybe/services/common_services.dart' as songs;
import 'package:vybe/services/data_manager.dart';
import 'package:vybe/services/explore_service.dart';
import 'package:vybe/services/followed_artists_service.dart';
import 'package:vybe/services/settings_manager.dart';

enum HomeItemKind { song, artist, album, playlist, mix }

typedef HomeItem = ({HomeItemKind kind, Map data});
typedef HomeShelf = ({String title, String? subtitle, List<HomeItem> items});

String homeItemId(Map data) =>
    (data['ytid'] ?? data['id'])?.toString().trim() ?? '';
String _label(dynamic value) => value?.toString().trim() ?? '';
String _name(dynamic value) => _label(value).toLowerCase();
List<Map> _maps(dynamic value) =>
    value is List ? value.whereType<Map>().toList() : [];

HomeItem _item(HomeItemKind kind, Map data) => (kind: kind, data: data);

HomeItem _collection(Map data) => _item(
  data['isAlbum'] == true ? HomeItemKind.album : HomeItemKind.playlist,
  data,
);

Iterable<String> _artistNames(Map song) =>
    _label(song['artist'] ?? song['author'])
        .split(
          RegExp(r',|\s+(?:feat\.?|ft\.?)\s+|\s+&\s+', caseSensitive: false),
        )
        .map((name) => name.trim())
        .where((name) => name.isNotEmpty && _name(name) != 'unknown artist');

int _playedAt(Map data) {
  final value = data['lastPlayed'];
  if (value is DateTime) return value.millisecondsSinceEpoch;
  if (value is int) return value;
  return DateTime.tryParse(_label(value))?.millisecondsSinceEpoch ?? 0;
}

class HomeFeedService {
  HomeFeedService({
    required this.loadProfile,
    required this.loadAlbum,
    required this.loadRelated,
    required this.loadGeneral,
    required this.loadCharts,
    required this.loadExplore,
    this.refreshCharts,
    this.loadArtistSongs,
  });

  static const _songLimit = 10;

  static final instance = HomeFeedService(
    loadProfile: (artist) => getArtistProfile(
      homeItemId(artist).isEmpty ? _label(artist['title']) : homeItemId(artist),
      preferredName: artist['title']?.toString(),
      preferredImage: artist['image']?.toString(),
      cacheDuration: const Duration(hours: 4),
    ),
    loadAlbum: getArtistAlbum,
    loadRelated: songs.getHomeSeedRecommendations,
    loadGeneral: songs.getRecommendedSongs,
    loadCharts: ExploreService.instance.fetchHomeCharts,
    refreshCharts: (country) =>
        ExploreService.instance.fetchHomeCharts(country, forceRefresh: true),
    loadArtistSongs: (name) async {
      final key = 'home_artist_tracks_${_name(name)}';
      final cached = await getData(
        'cache',
        key,
        cachingDuration: const Duration(hours: 4),
      );
      if (cached is List) return _maps(cached);
      final tracks = (await ExploreService.instance.searchSongs(name))
          .where(
            (song) =>
                _artistNames(song)
                    .any((artist) => _name(artist) == _name(name)),
          )
          .take(30)
          .toList();
      if (tracks.isNotEmpty) await addOrUpdateData('cache', key, tracks);
      return tracks;
    },
    loadExplore: () async {
      final genre = RegExp(
        r'\b(?:pop|lofi|indie|rock|hip.hop)\b',
        caseSensitive: false,
      );
      return [
        ...playlistsDB
            .where((playlist) => genre.hasMatch(_label(playlist['title'])))
            .take(6),
        ...ExploreService.fallbackChartPlaylists,
      ];
    },
  );

  final Future<Map?> Function(Map) loadProfile;
  final Future<Map?> Function(String) loadAlbum;
  final Future<List> Function(Map) loadRelated;
  final Future<List> Function() loadGeneral;
  final Future<List<Map>> Function(String) loadCharts;
  final Future<List<Map>> Function() loadExplore;
  final Future<List<Map>> Function(String)? refreshCharts;
  final Future<List<Map>> Function(String)? loadArtistSongs;

  Object? _requestKey;
  Future<List<HomeShelf>>? _pending;
  DateTime? _requestedAt;

  static HomeShelf jumpBackIn(List recent, List<Map> collections) {
    final items = [
      for (final song in recent.whereType<Map>().take(15))
        _item(HomeItemKind.song, song),
      for (final collection in collections) _collection(collection),
    ]..sort((a, b) => _playedAt(b.data).compareTo(_playedAt(a.data)));
    return (
      title: 'Jump Back In',
      subtitle: null,
      items: _unique(items).take(14).toList(),
    );
  }

  Future<List<HomeShelf>> load(
    String countryCode, {
    bool forceRefresh = false,
  }) => loadFor(
    recent: _maps(songs.userRecentlyPlayed.value),
    liked: _maps(songs.userLikedSongsList.value),
    followed: FollowedArtistsService.instance.followedArtists.value,
    countryCode: countryCode,
    external: externalRecommendations.value,
    forceRefresh: forceRefresh,
  );

  Future<List<HomeShelf>> loadFor({
    required List<Map> recent,
    required List<Map> liked,
    required List<Map> followed,
    required String countryCode,
    required bool external,
    bool forceRefresh = false,
  }) {
    final familiar = [
      ..._uniqueSongs([...recent, ...liked]),
    ];
    final seed = recent
        .where((song) => homeItemId(song).isNotEmpty)
        .firstOrNull;
    final favorite = _favoriteArtist(recent, liked);
    final key = (
      countryCode,
      external,
      seed == null ? '' : homeItemId(seed),
      _name(favorite?['title']),
      Object.hashAll(familiar.map(homeItemId)),
      Object.hashAll(followed.map(homeItemId)),
    );
    final now = DateTime.now();
    if (!forceRefresh &&
        _requestKey == key &&
        now.difference(_requestedAt!) < const Duration(minutes: 5)) {
      return _pending!;
    }
    _requestKey = key;
    _requestedAt = now;
    return _pending = _build(
      recent: recent,
      familiar: familiar,
      followed: followed,
      countryCode: countryCode,
      external: external,
      favorite: favorite,
      seed: seed,
      forceRefresh: forceRefresh,
      now: now,
    );
  }

  Future<List<HomeShelf>> _build({
    required List<Map> recent,
    required List<Map> familiar,
    required List<Map> followed,
    required String countryCode,
    required bool external,
    required Map? favorite,
    required Map? seed,
    required bool forceRefresh,
    required DateTime now,
  }) async {
    // Start independent sources together. Reuse a followed profile when it is
    // also the favorite artist, and limit network work on each Home refresh.
    final profiles = {
      for (final artist in followed.take(5))
        _name(artist['title']): _attempt(() => loadProfile(artist)),
    };
    final favoriteProfile = favorite == null
        ? null
        : profiles.putIfAbsent(
            _name(favorite['title']),
            () => _attempt(() => loadProfile(favorite)),
          );
    final chartLoader = forceRefresh ? refreshCharts ?? loadCharts : loadCharts;
    final chartsFuture = _attempt(() => chartLoader(countryCode));
    final relatedFuture = external && seed != null
        ? _attempt(() => loadRelated(seed))
        : _attempt(loadGeneral);
    final exploreFuture = familiar.isEmpty ? _attempt(loadExplore) : null;

    final followedProfiles = await Future.wait(
      followed.take(5).map((artist) => profiles[_name(artist['title'])]!),
    );
    final profile = await favoriteProfile;
    final charts = await chartsFuture ?? [];
    final related = _maps(await relatedFuture);
    final explore = await exploreFuture ?? [];
    final familiarIds = familiar.map(homeItemId).toSet();
    final followedIds = followed.map(homeItemId).toSet();
    final knownNames = {
      ...familiar.expand(_artistNames).map(_name),
      ...followed.map((artist) => _name(artist['title'])),
    };
    final knownArtistIds = {
      ...followedIds,
      ...familiar.map((song) => _label(song['artistId'])),
      if (profile != null) homeItemId(profile),
    };
    final recentIds = recent.take(14).map(homeItemId).toSet();
    final displayed = <(HomeItemKind, String)>{
      for (final id in recentIds) (HomeItemKind.song, id),
    };
    final trending = <HomeShelf>[];
    final chartsAfterDiscovery = <HomeShelf>[];
    final sections = <HomeShelf>[];

    void add(
      String title,
      Iterable<HomeItem> candidates, {
      String? subtitle,
      int limit = 12,
      List<HomeShelf>? target,
    }) {
      final items = _unique(candidates)
          .where(
            (item) => !displayed.contains((item.kind, homeItemId(item.data))),
          )
          .take(limit)
          .toList();
      if (items.isEmpty) return;
      displayed.addAll(items.map((item) => (item.kind, homeItemId(item.data))));
      (target ?? sections).add((
        title: title,
        subtitle: subtitle,
        items: items,
      ));
    }

    final connectedArtists = _maps(profile?['relatedArtists']);
    final artistSongs = _maps(profile?['topSongs'])
        .map((track) => track['song'])
        .whereType<Map>()
        .where((song) => !familiarIds.contains(homeItemId(song)))
        .toList();
    final lookup = loadArtistSongs;
    if (favorite != null &&
        lookup != null &&
        _uniqueSongs(artistSongs).length < _songLimit) {
      final supplemental = await _attempt(
        () => lookup(favorite['title'] as String),
      );
      artistSongs.addAll(
        (supplemental ?? []).where(
          (song) => !familiarIds.contains(homeItemId(song)),
        ),
      );
    }

    if (favorite != null) {
      // Give collaborations a place when the catalog provides multiple credits.
      final tracks = _uniqueSongs([
        ...artistSongs.where((song) => _artistNames(song).length > 1),
        ...artistSongs,
      ]).take(_songLimit);
      add('More Like ${favorite['title']}', [
        ...tracks.map((song) => _item(HomeItemKind.song, song)),
        ...connectedArtists
            .take(1)
            .map((artist) => _item(HomeItemKind.artist, artist)),
      ]);
    }

    bool canShowRecommendation(Map song) =>
        !familiarIds.contains(homeItemId(song)) &&
        !displayed.contains((HomeItemKind.song, homeItemId(song)));
    var includesOtherSeeds = false;
    if (external &&
        seed != null &&
        _uniqueSongs(related).where(canShowRecommendation).length <
            _songLimit) {
      final extraSeeds = _uniqueSongs(recent)
          .where((song) => homeItemId(song) != homeItemId(seed))
          .take(2);
      final alternatives = await Future.wait(
        extraSeeds.map((song) => _attempt(() => loadRelated(song))),
      );
      final existingIds = related.map(homeItemId).toSet();
      for (final batch in alternatives) {
        for (final song in _maps(batch).where(canShowRecommendation)) {
          if (existingIds.add(homeItemId(song))) {
            related.add(song);
            includesOtherSeeds = true;
          }
        }
      }
    }
    add(
      external && seed != null
          ? 'Based on Your Recent Listening'
          : 'Recommended for You',
      related
          .where((song) => !familiarIds.contains(homeItemId(song)))
          .map((song) => _item(HomeItemKind.song, song)),
      subtitle: external && seed != null && _label(seed['title']).isNotEmpty
          ? includesOtherSeeds
                ? 'Inspired by ${seed['title']} and your recent plays'
                : 'Because you listened to ${seed['title']}'
          : null,
      limit: _songLimit,
    );

    final releases = [
      for (final artist in followedProfiles.whereType<Map>())
        ..._maps(artist['releases'])
            .where((release) => _isRecentRelease(release, now))
            .take(_songLimit),
    ]..sort((a, b) => _releaseYear(b).compareTo(_releaseYear(a)));
    final singles = releases
        .where((release) => _name(release['releaseType']) == 'single')
        .take(_songLimit);
    final singleAlbums = await Future.wait(
      singles.map((release) async {
        final album = await _attempt(() => loadAlbum(homeItemId(release)));
        return (release: release, tracks: _maps(album?['list']));
      }),
    );
    final singleTracks = {
      for (final single in singleAlbums)
        if (single.tracks.length == 1)
          homeItemId(single.release): single.tracks.single,
    };
    add('New From Artists You Follow', [
      for (final release in releases)
        if (singleTracks[homeItemId(release)] case final track?)
          _item(HomeItemKind.song, {...track, 'year': release['year']}),
      for (final release in releases)
        if (!singleTracks.containsKey(homeItemId(release)))
          _item(HomeItemKind.album, release),
    ], limit: 16);

    final chartCollections = charts.where(
      (item) => item['isChartPlaylist'] == true,
    );
    final chartSongs = charts.where(
      (item) => item['isChartPlaylist'] != true && item['isArtist'] != true,
    );
    final chartArtists = charts.where((item) => item['isArtist'] == true);
    final categories = chartSongs
        .map((song) => _label(song['chartTitle']))
        .where((title) => title.isNotEmpty)
        .toSet();
    add(
      'Trending Now',
      chartSongs.isEmpty
          ? chartCollections.map(_collection)
          : chartSongs.map((song) => _item(HomeItemKind.song, song)),
      subtitle: categories.length == 1 ? categories.single : null,
      target: trending,
      limit: _songLimit,
    );
    add(
      'Trending Artists',
      chartArtists.map((artist) => _item(HomeItemKind.artist, artist)),
      target: chartsAfterDiscovery,
    );
    if (chartSongs.isNotEmpty && chartCollections.isNotEmpty) {
      add(
        'Music Charts',
        chartCollections.map(_collection),
        target: chartsAfterDiscovery,
      );
    }

    final discoveries = [
      ...connectedArtists,
      for (final artist in followedProfiles.whereType<Map>())
        ..._maps(artist['relatedArtists']),
      for (final song in [...related, ...artistSongs])
        if (_label(song['artistId']).startsWith('UC') &&
            _artistNames(song).length == 1 &&
            _name(song['videoAuthor']).replaceFirst(RegExp(r' - topic$'), '') ==
                _name(_artistNames(song).first))
          {
            'ytid': song['artistId'],
            'title': _artistNames(song).first,
            'isArtist': true,
          },
    ];
    if (familiar.isNotEmpty || followed.isNotEmpty) {
      add(
        'Discover New Artists',
        discoveries
            .where(
              (artist) =>
                  !knownArtistIds.contains(homeItemId(artist)) &&
                  !knownNames.contains(_name(artist['title'])),
            )
            .map((artist) => _item(HomeItemKind.artist, artist)),
      );
    }

    sections.addAll(chartsAfterDiscovery);
    add(
      'Mixes for You',
      _mixes(familiar, [...related, ...artistSongs], favorite, artistSongs),
    );
    if (explore.isNotEmpty) add('Explore Music', explore.map(_collection));
    return [...trending, ...sections];
  }

  static Future<T?> _attempt<T>(Future<T?> Function() request) async {
    try {
      return await request().timeout(const Duration(seconds: 14));
    } catch (error, stackTrace) {
      logger.log(
        'Home feed source unavailable',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  static Map? _favoriteArtist(List<Map> recent, List<Map> liked) {
    final scores = <String, int>{};
    final names = <String, String>{};
    for (final (index, song) in [
      ...recent.take(45),
      ...liked.take(25),
    ].indexed) {
      final count = int.tryParse(_label(song['listeningCount'])) ?? 1;
      final weight = index < 8 ? 3 : 1;
      for (final name in _artistNames(song).toSet()) {
        final key = _name(name);
        names.putIfAbsent(key, () => name);
        scores.update(
          key,
          (score) => score + count.clamp(1, 15) + weight,
          ifAbsent: () => count.clamp(1, 15) + weight,
        );
      }
    }
    if (scores.isEmpty) return null;
    final best = scores.keys.reduce((a, b) => scores[a]! >= scores[b]! ? a : b);
    return {'title': names[best]};
  }

  static int _releaseYear(Map release) =>
      int.tryParse(_label(release['year'])) ?? 0;

  static bool _isRecentRelease(Map release, DateTime now) {
    final date = DateTime.tryParse(_label(release['releaseDate']));
    if (date != null) {
      return !date.isAfter(now) &&
          now.difference(date) <= const Duration(days: 365);
    }
    final year = _releaseYear(release);
    return year == now.year || year == now.year - 1;
  }

  static Iterable<HomeItem> _mixes(
    List<Map> familiar,
    List<Map> suggested,
    Map? favorite,
    List<Map> artistSongs,
  ) sync* {
    final knownIds = familiar.map(homeItemId).toSet();
    final fresh = _uniqueSongs(suggested)
        .where((song) => !knownIds.contains(homeItemId(song)))
        .toList();
    final used = <String>{};
    for (final facet in ['genre', 'language', 'mood']) {
      final tags = <String, String>{};
      final scores = <String, int>{};
      for (final song in familiar) {
        for (final tag in _tags(song, facet)) {
          tags[_name(tag)] = tag;
          scores.update(_name(tag), (score) => score + 1, ifAbsent: () => 1);
        }
      }
      final ranked = tags.keys.toList()
        ..sort((a, b) => scores[b]!.compareTo(scores[a]!));
      for (final tag in ranked) {
        final known = familiar.where(
          (song) => _tags(song, facet).any((name) => _name(name) == tag),
        );
        final newSongs = fresh.where(
          (song) => _tags(song, facet).any((name) => _name(name) == tag),
        );
        if (known.isEmpty || newSongs.isEmpty || !used.add(tag)) continue;
        yield _mix(tags[tag]!, known, newSongs);
        break;
      }
    }
    if (used.isEmpty && favorite != null && artistSongs.isNotEmpty) {
      final name = _name(favorite['title']);
      final known = familiar.where(
        (song) => _artistNames(song).any((credit) => _name(credit) == name),
      );
      if (known.isNotEmpty)
        yield _mix(_label(favorite['title']), known, artistSongs);
    }
  }

  static Set<String> _tags(Map song, String field) {
    final value = song['${field}s'] ?? song[field];
    final parts = value is List ? value : _label(value).split(RegExp('[,;]'));
    return parts.map(_label).where((part) => part.isNotEmpty).toSet();
  }

  static HomeItem _mix(
    String name,
    Iterable<Map> familiar,
    Iterable<Map> fresh,
  ) {
    final known = familiar.take(6).toList();
    final discoveries = fresh.take(8).toList();
    final tracks = [
      for (var i = 0; i < discoveries.length || i < known.length; i++) ...[
        if (i < known.length) known[i],
        if (i < discoveries.length) discoveries[i],
      ],
    ];
    return _item(HomeItemKind.mix, {
      'id': name,
      'title': '$name Mix',
      'list': tracks,
    });
  }

  static Iterable<Map> _uniqueSongs(Iterable<Map> songs) =>
      _unique(songs.map((song) => _item(HomeItemKind.song, song)))
          .map((item) => item.data);

  static Iterable<HomeItem> _unique(Iterable<HomeItem> items) {
    final seen = <(HomeItemKind, String)>{};
    return items.where((item) {
      final id = homeItemId(item.data);
      return id.isNotEmpty &&
          _label(item.data['title']).isNotEmpty &&
          seen.add((item.kind, id));
    });
  }
}
