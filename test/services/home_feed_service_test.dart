import 'package:flutter_test/flutter_test.dart';
import 'package:vybe/services/explore_service.dart';
import 'package:vybe/services/home_feed_service.dart';

Map _song(String id, String title, String artist, {List<String>? genres}) => {
  'ytid': id,
  'title': title,
  'artist': artist,
  if (genres != null) 'genres': genres,
};

Map _artist(String id, String title) => {
  'ytid': id,
  'title': title,
  'isArtist': true,
};

void main() {
  test(
    'song shelves reach ten with real candidates and a refresh reloads charts',
    () async {
      List<Map> tracks(String prefix, int count) => [
        for (var i = 0; i < count; i++)
          _song('$prefix-$i', '$prefix $i', 'Nova'),
      ];
      final year = DateTime.now().year;
      final service = HomeFeedService(
        loadProfile: (_) async => {
          'topSongs': [
            for (final track in tracks('top', 6)) {'song': track},
          ],
          'releases': [
            for (var i = 0; i < 10; i++)
              {
                'ytid': 'album-$i',
                'title': 'Single $i',
                'year': year,
                'releaseType': 'single',
              },
          ],
        },
        loadAlbum: (id) async => {
          'list': [_song('track-$id', 'Track $id', 'Nova')],
        },
        loadRelated: (seed) async => tracks(homeItemId(seed), 6),
        loadGeneral: () async => [],
        loadCharts: (_) async => tracks('chart', 18),
        refreshCharts: (_) async => tracks('updated-chart', 18),
        loadArtistSongs: (_) async => tracks('catalog', 12),
        loadExplore: () async => [],
      );
      Future<List<HomeShelf>> load({bool refresh = false}) => service.loadFor(
        recent: [
          _song('first', 'First', 'Nova'),
          _song('second', 'Second', 'Nova'),
        ],
        liked: [],
        followed: [_artist('UCNova', 'Nova')],
        external: true,
        countryCode: 'IN',
        forceRefresh: refresh,
      );
      final shelves = await load();
      for (final title in [
        'Trending Now',
        'More Like Nova',
        'Based on Your Recent Listening',
        'New From Artists You Follow',
      ]) {
        final tracks = shelves
            .singleWhere((shelf) => shelf.title == title)
            .items
            .where((item) => item.kind == HomeItemKind.song);
        expect(
          tracks.map((item) => homeItemId(item.data)).toSet(),
          hasLength(10),
          reason: title,
        );
      }
      final refreshed = await load(refresh: true);
      expect(refreshed.first.items.first.data['ytid'], 'updated-chart-0');
    },
  );

  test('Jump Back In interleaves old and new history formats by time', () {
    final shelf = HomeFeedService.jumpBackIn(
      [
        {
          ..._song('song', 'Song', 'Artist'),
          'lastPlayed': DateTime.fromMillisecondsSinceEpoch(2000),
        },
        _song('old', 'Old', 'Artist'),
      ],
      [
        {'ytid': 'list', 'title': 'List', 'lastPlayed': 3000},
        {
          'ytid': 'album',
          'title': 'Album',
          'isAlbum': true,
          'lastPlayed': 1000,
        },
      ],
    );
    expect(shelf.items.map((item) => homeItemId(item.data)), [
      'list',
      'song',
      'album',
      'old',
    ]);
    expect(shelf.items[2].kind, HomeItemKind.album);
  });

  test('personalizes from live inputs, avoids repeats, and reuses an unchanged feed', () async {
    final familiar = _song('known', 'Familiar', 'Nova', genres: ['Indie']);
    final collaboration = _song('collab', 'Collab', 'Nova feat. Asha');
    final related = _song('related', 'Related', 'Luna', genres: ['Indie']);
    final followed = _artist('UCNova', 'Nova');
    final profile = {
      ...followed,
      'topSongs': [
        {'song': collaboration},
        {'song': familiar},
      ],
      'relatedArtists': [
        _artist('UCAsha', 'Asha'),
        _artist('UCLuna', 'Luna'),
        _artist('UCNova', 'Nova'),
      ],
      'releases': [
        {
          'ytid': 'MPREsingle',
          'title': 'Single',
          'year': DateTime.now().year,
          'releaseType': 'single',
        },
        {'ytid': 'MPREundated', 'title': 'Undated'},
        {'ytid': 'MPREold', 'title': 'Old Album', 'year': 2001},
      ],
    };
    final seeds = <String>[];
    var profiles = 0;
    final service = HomeFeedService(
      loadProfile: (_) async {
        profiles++;
        return profile;
      },
      loadAlbum: (_) async => {
        'list': [_song('single-track', 'Single', 'Nova')],
      },
      loadRelated: (seed) async {
        seeds.add(homeItemId(seed));
        return [familiar, collaboration, related, related];
      },
      loadGeneral: () async => [],
      loadCharts: (country) async {
        expect(country, 'IN');
        return [
          related,
          _song('chart', 'Chart Song', 'Rae'),
          _artist('UCRae', 'Rae'),
          {'ytid': 'PLChart', 'title': 'India Chart', 'isChartPlaylist': true},
        ];
      },
      loadExplore: () async => [],
    );
    Future<List<HomeShelf>> load(List<Map> recent) => service.loadFor(
      recent: recent,
      liked: [],
      followed: [followed],
      countryCode: 'IN',
      external: true,
    );
    final initial = load([familiar]);
    expect(load([familiar]), same(initial));
    final feed = await initial;
    expect(feed.map((row) => row.title), [
      'Trending Now',
      'More Like Nova',
      'Based on Your Recent Listening',
      'New From Artists You Follow',
      'Discover New Artists',
      'Trending Artists',
      'Music Charts',
      'Mixes for You',
    ]);
    HomeShelf shelf(String title) =>
        feed.singleWhere((row) => row.title == title);
    expect(profiles, 1);
    expect(shelf('More Like Nova').items.first.data['ytid'], 'collab');
    expect(
      shelf('Based on Your Recent Listening').subtitle,
      'Because you listened to Familiar',
    );
    expect(
      shelf('Based on Your Recent Listening').items.single.data['ytid'],
      'related',
    );
    expect(
      shelf('New From Artists You Follow').items.single.kind,
      HomeItemKind.song,
    );
    expect(shelf('Trending Now').items.single.data['ytid'], 'chart');
    expect(shelf('Trending Artists').items.single.data['ytid'], 'UCRae');
    expect(shelf('Discover New Artists').items.single.data['ytid'], 'UCLuna');
    final mix = shelf('Mixes for You').items.single.data;
    expect(mix['title'], 'Indie Mix');
    expect((mix['list'] as List).map((track) => track['ytid']), [
      'known',
      'related',
    ]);
    await load([_song('different', 'Different', 'Nova'), familiar]);
    expect(seeds, ['known', 'different', 'known']);
  });

  test(
    'cold start and source failures leave the rest of Home usable',
    () async {
      final service = HomeFeedService(
        loadProfile: (_) async => null,
        loadAlbum: (_) async => null,
        loadRelated: (_) async => throw StateError('No related tracks'),
        loadGeneral: () async => [],
        loadCharts: (_) async => [],
        loadExplore: () async => [
          {'ytid': 'genre-list', 'title': 'Indie Hits'},
        ],
      );
      final shelves = await service.loadFor(
        recent: [],
        liked: [],
        followed: [],
        countryCode: 'IN',
        external: false,
      );
      expect(shelves.single.title, 'Explore Music');
      expect(shelves.single.items.single.kind, HomeItemKind.playlist);
    },
  );

  test('chart parser skips malformed rows and keeps valid neighbours', () {
    final entries = ExploreService.parseHomeCharts({
      'contents': [
        {
          'musicTwoRowItemRenderer': {
            'title': 'Unexpected title payload',
            'navigationEndpoint': 4,
          },
        },
        {
          'musicTwoRowItemRenderer': {
            'title': {
              'runs': [
                {'text': 'Playable song'},
              ],
            },
            'navigationEndpoint': {
              'watchEndpoint': {'videoId': 'retained-track'},
            },
            'thumbnailRenderer': false,
          },
        },
      ],
    });
    expect(entries.map(homeItemId), ['retained-track']);
    expect(entries.single['title'], 'Playable song');
  });

  test('chart parser keeps provider categories and playable identifiers', () {
    Map runs(String text) => {
      'runs': [
        {'text': text},
      ],
    };
    Map column(String text) => {
      'musicResponsiveListItemFlexColumnRenderer': {'text': runs(text)},
    };
    final entries = ExploreService.parseHomeCharts({
      'contents': [
        {
          'musicCarouselShelfRenderer': {
            'header': {
              'musicCarouselShelfBasicHeaderRenderer': {
                'title': runs('Top songs in India'),
              },
            },
            'contents': [
              {
                'musicResponsiveListItemRenderer': {
                  'playlistItemData': {'videoId': 'track'},
                  'flexColumns': [column('Track'), column('Artist')],
                },
              },
              {
                'musicTwoRowItemRenderer': {
                  'title': runs('Artist'),
                  'navigationEndpoint': {
                    'browseEndpoint': {'browseId': 'UCArtist'},
                  },
                },
              },
              {
                'musicTwoRowItemRenderer': {
                  'title': runs('Daily Top Songs India'),
                  'navigationEndpoint': {
                    'browseEndpoint': {'browseId': 'VLPLIndia'},
                  },
                },
              },
            ],
          },
        },
      ],
    });
    expect(entries.map(homeItemId), ['track', 'UCArtist', 'PLIndia']);
    expect(entries.first['artist'], 'Artist');
    expect(entries.first['chartTitle'], 'Top songs in India');
    expect(entries[1]['isArtist'], isTrue);
    expect(entries.last['isChartPlaylist'], isTrue);
    expect(ExploreService.parseHomeCharts({'error': {}}), isEmpty);
  });
}
