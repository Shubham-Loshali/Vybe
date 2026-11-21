import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PlatformDispatcher;

import 'package:http/http.dart' as http;
import 'package:vybe/main.dart' show logger;
import 'package:vybe/services/artist_service.dart' show ytMusicClient;
import 'package:vybe/services/data_manager.dart';
import 'package:vybe/services/proxy_manager.dart' show ytClient;
import 'package:vybe/utilities/formatter.dart';

/// Service responsible for YouTube Music Explore, Regional Charts (Bollywood/Hollywood),
/// trending artists, and music-filtered search suggestions.
class ExploreService {
  ExploreService._();
  static final ExploreService instance = ExploreService._();

  static const String _innertubeBase = 'https://music.youtube.com/youtubei/v1';
  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Referer': 'https://music.youtube.com/',
  };

  /// Fallback curated Indian and Global chart playlists if offline or network failure.
  static const List<Map<String, dynamic>> fallbackChartPlaylists = [
    {
      'ytid': 'PL4fGSI1pDJn40WjZ6utkIuj2rNg-7iGsq',
      'title': 'Top 100 Music Videos India',
      'image': 'https://charts-images.scdn.co/assets/locale_en/regional/daily/region_in_large.jpg',
      'source': 'youtube',
      'isAlbum': false,
      'isArtist': false,
      'list': [],
    },
    {
      'ytid': 'PL4fGSI1pDJn5oibdgJt8Hy0-dr2B7kSs2',
      'title': 'Daily Top Music Videos - India',
      'image': 'https://charts-images.scdn.co/assets/locale_en/regional/daily/region_in_large.jpg',
      'source': 'youtube',
      'isAlbum': false,
      'isArtist': false,
      'list': [],
    },
    {
      'ytid': 'PL4fGSI1pDJn4-6xbBC3u1WtagjLthsmw5',
      'title': 'Top 100 Music Videos Global',
      'image': 'https://charts-images.scdn.co/assets/locale_en/regional/daily/region_global_large.jpg',
      'source': 'youtube',
      'isAlbum': false,
      'isArtist': false,
      'list': [],
    },
    {
      'ytid': 'PLrEnWoR732-BHrPp_Ow42bjPVUR67285l',
      'title': 'Today’s Top Hits (Hollywood)',
      'image': 'https://charts-images.scdn.co/assets/locale_en/regional/daily/region_global_large.jpg',
      'source': 'youtube',
      'isAlbum': false,
      'isArtist': false,
      'list': [],
    },
    {
      'ytid': 'PL4fGSI1pDJn4WX22qg1Po7qKOwOb4H6Sk',
      'title': 'Top Weekly Videos Tamil',
      'image': 'https://charts-images.scdn.co/assets/locale_en/regional/daily/region_in_large.jpg',
      'source': 'youtube',
      'isAlbum': false,
      'isArtist': false,
      'list': [],
    },
    {
      'ytid': 'PL4fGSI1pDJn5ALuqpEj_YZ8mEyw9WN8jd',
      'title': 'Top Weekly Videos Telugu',
      'image': 'https://charts-images.scdn.co/assets/locale_en/regional/daily/region_in_large.jpg',
      'source': 'youtube',
      'isAlbum': false,
      'isArtist': false,
      'list': [],
    },
  ];

  /// Fallback curated popular Bollywood & Global artists if offline.
  static const List<Map<String, dynamic>> fallbackArtists = [
    {
      'title': 'Arijit Singh',
      'ytid': 'UCDxKh1gFWeYsqePvgVzmPoQ',
      'image': 'https://lh3.googleusercontent.com/W_yOqnKSDYyeVOY_AsXhuAtb6rW3vCL3GtJ9DA1GxW5G-g',
      'source': 'youtube-artist',
      'isArtist': true,
      'list': [],
    },
    {
      'title': 'Shreya Ghoshal',
      'ytid': 'UCrC-7fsdTCYeaRBpwA6j-Eg',
      'image': 'https://yt3.googleusercontent.com/PgINZNe0qVxgMSXKG5vF82bNN4WCC12zgWsz9I7OLs',
      'source': 'youtube-artist',
      'isArtist': true,
      'list': [],
    },
    {
      'title': 'Diljit Dosanjh',
      'ytid': 'UCbRSywya_rl8YS15Lo9ttsA',
      'image': 'https://lh3.googleusercontent.com/dK3f0wYh_sA',
      'source': 'youtube-artist',
      'isArtist': true,
      'list': [],
    },
    {
      'title': 'Alka Yagnik',
      'ytid': 'UCptBkLZ6XRxoyn8SkUMc_Iw',
      'image': 'https://lh3.googleusercontent.com/_wPXKRCH5rAX8AK1kJZ1bNhSpNyyEgBRNmREdPmLbvTy3sX_ldiKMRYFc5uChygV_KRx_SDrH1KgUifk',
      'source': 'youtube-artist',
      'isArtist': true,
      'list': [],
    },
    {
      'title': 'Udit Narayan',
      'ytid': 'UC13ToEQgfmTe8_GW19LYtCg',
      'image': 'https://yt3.googleusercontent.com/coesV4OVEVkua3_wJG-2BVvTc95yHF9sS1W6mOAtl4',
      'source': 'youtube-artist',
      'isArtist': true,
      'list': [],
    },
    {
      'title': 'The Weeknd',
      'ytid': 'UC0WP5P-ufpRfjbNrmOWwLBQ',
      'image': 'https://lh3.googleusercontent.com/47_w4P',
      'source': 'youtube-artist',
      'isArtist': true,
      'list': [],
    },
    {
      'title': 'Taylor Swift',
      'ytid': 'UCqECaJ8Gagnn7YCbPEzWH6g',
      'image': 'https://lh3.googleusercontent.com/2s_1',
      'source': 'youtube-artist',
      'isArtist': true,
      'list': [],
    },
  ];

  String get _deviceCountryCode {
    try {
      final code = PlatformDispatcher.instance.locale.countryCode;
      if (code != null && code.length == 2) {
        return code.toUpperCase();
      }
    } catch (_) {}
    return 'IN';
  }

  Map<String, dynamic> _buildRemixContext({String? countryCode}) {
    return {
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': '1.20240101.01.00',
          'gl': countryCode ?? _deviceCountryCode,
          'hl': 'en',
        },
      },
    };
  }

  /// Fetches pure music autocomplete suggestions from YouTube Music.
  /// Eliminates non-music results (recipes, vlogs, yoga).
  Future<List<String>> getSearchSuggestions(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    try {
      final body = {
        ..._buildRemixContext(),
        'input': trimmed,
      };

      final response = await http
          .post(
            Uri.parse('$_innertubeBase/music/get_search_suggestions'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final suggestions = <String>[];
        final contents = (decoded['contents'] as List?) ?? [];
        for (final section in contents) {
          if (section is! Map) continue;
          final shelf = section['searchSuggestionsSectionRenderer'] as Map?;
          final items = (shelf?['contents'] as List?) ?? [];
          for (final item in items) {
            if (item is! Map) continue;
            final renderer = item['searchSuggestionRenderer'] as Map?;
            final runs = renderer?['suggestion']?['runs'] as List?;
            if (runs != null) {
              final text =
                  runs.map((r) => r['text']?.toString() ?? '').join().trim();
              if (text.isNotEmpty && !suggestions.contains(text)) {
                suggestions.add(text);
              }
            }
          }
        }
        if (suggestions.isNotEmpty) {
          return suggestions;
        }
      }
    } catch (e, st) {
      logger.log(
        'YouTube Music search suggestions error for "$trimmed"',
        error: e,
        stackTrace: st,
      );
    }

    // Graceful fallback to YouTube standard suggestions if network failed
    try {
      return await ytClient.search.getQuerySuggestions(trimmed);
    } catch (_) {
      return const [];
    }
  }

  /// Searches songs with YouTube Music strict song filtering.
  Future<List<Map<String, dynamic>>> searchSongs(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    // 1. First attempt: search via YoutubeMusicExplode
    try {
      final tracks = await ytMusicClient.music
          .searchSongs(trimmed)
          .timeout(const Duration(seconds: 8));
      if (tracks.isNotEmpty) {
        return tracks
            .map((track) => returnSongLayout(0, track, isCatalogTrack: true))
            .toList();
      }
    } catch (error, stackTrace) {
      logger.log(
        'YoutubeMusicExplode searchSongs failed for "$trimmed"',
        error: error,
        stackTrace: stackTrace,
      );
    }

    // 2. Second attempt: direct Innertube YouTube Music songs search
    try {
      final body = {
        ..._buildRemixContext(),
        'query': trimmed,
        'params': 'Eg-KAQwIARAAGAAgACgAMABqChAEEAMQCRAFEAo%3D', // Songs filter
      };

      final response = await http
          .post(
            Uri.parse('$_innertubeBase/search'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        final songs = <Map<String, dynamic>>[];
        final tabs = decoded['contents']?['tabbedSearchResultsRenderer']
            ?['tabs'] as List?;
        final tabRenderer = (tabs?.isNotEmpty ?? false) ? tabs![0]['tabRenderer'] : null;
        final sectionList =
            tabRenderer?['content']?['sectionListRenderer']?['contents'] as List?;
        if (sectionList != null) {
          for (final section in sectionList) {
            final shelf = section['musicShelfRenderer'] as Map?;
            final contents = (shelf?['contents'] as List?) ?? [];
            for (final item in contents) {
              final renderer = item['musicResponsiveListItemRenderer'] as Map?;
              if (renderer == null) continue;
              final videoId =
                  renderer['playlistItemData']?['videoId']?.toString();
              if (videoId == null || videoId.isEmpty) continue;

              final flexCols = (renderer['flexColumns'] as List?) ?? [];
              var title = '';
              var artist = '';
              if (flexCols.isNotEmpty) {
                final runs =
                    flexCols[0]?['musicResponsiveListItemFlexColumnRenderer']
                        ?['text']?['runs'] as List?;
                if (runs != null) {
                  title = runs.map((r) => r['text'] ?? '').join().trim();
                }
              }
              if (flexCols.length > 1) {
                final runs =
                    flexCols[1]?['musicResponsiveListItemFlexColumnRenderer']
                        ?['text']?['runs'] as List?;
                if (runs != null) {
                  final text = runs.map((r) => r['text'] ?? '').join().trim();
                  final parts = text.split('•').map((p) => p.trim()).toList();
                  artist = parts.length > 1 ? parts[1] : parts.first;
                }
              }
              final thumbnails = renderer['thumbnail']?['musicThumbnailRenderer']
                  ?['thumbnail']?['thumbnails'] as List?;
              final imageUrl = (thumbnails != null && thumbnails.isNotEmpty)
                  ? thumbnails.last['url']?.toString()
                  : null;

              songs.add({
                'ytid': videoId,
                'title': title,
                'artist': artist,
                'image': imageUrl,
                'lowResImage': imageUrl,
                'highResImage': imageUrl,
                'source': 'youtube',
              });
            }
          }
        }
        if (songs.isNotEmpty) {
          return songs;
        }
      }
    } catch (e, st) {
      logger.log(
        'Direct YouTube Music search failed for "$trimmed"',
        error: e,
        stackTrace: st,
      );
    }

    // 3. Fallback: standard YouTube Explode search with song query and filtering
    try {
      final searchResults = await ytClient.search.search('$trimmed song');
      return searchResults
          .where((video) => (video.duration?.inSeconds ?? 0) <= 900)
          .map((video) => returnSongLayout(0, video))
          .toList();
    } catch (e, stackTrace) {
      logger.log('Fallback YouTube search failed', error: e, stackTrace: stackTrace);
      return const [];
    }
  }

  /// Fetches explore playlists and regional charts (Bollywood & Hollywood).
  Future<List<Map<String, dynamic>>> fetchExplorePlaylists({
    bool forceRefresh = false,
  }) async {
    const cacheKey = 'explore_charts_playlists_v2';
    if (!forceRefresh) {
      try {
        final cached = await getData('cache', cacheKey, cachingDuration: const Duration(hours: 12));
        if (cached is List && cached.isNotEmpty) {
          return cached
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .toList();
        }
      } catch (_) {}
    }

    final playlists = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    void addPlaylist(String browseId, String title, String? imageUrl, {bool isAlbum = false}) {
      final cleanId = browseId.startsWith('VL') ? browseId.substring(2) : browseId;
      if (cleanId.isEmpty || !seenIds.add(cleanId)) return;
      playlists.add({
        'ytid': cleanId,
        'title': title,
        'image': imageUrl,
        'source': 'youtube',
        'isAlbum': isAlbum,
        'isArtist': false,
        'list': [],
      });
    }

    // Query 1: Regional Charts (India - Bollywood / Regional hits)
    try {
      final bodyIndia = {
        ..._buildRemixContext(countryCode: 'IN'),
        'browseId': 'FEmusic_charts',
      };
      final res = await http
          .post(
            Uri.parse('$_innertubeBase/browse'),
            headers: _headers,
            body: jsonEncode(bodyIndia),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        _parsePlaylistsFromBrowse(jsonDecode(res.body), addPlaylist);
      }
    } catch (e, st) {
      logger.log('Error fetching India music charts', error: e, stackTrace: st);
    }

    // Query 2: Explore feed (New albums, Moods & Genres)
    try {
      final bodyExplore = {
        ..._buildRemixContext(countryCode: 'IN'),
        'browseId': 'FEmusic_explore',
      };
      final res = await http
          .post(
            Uri.parse('$_innertubeBase/browse'),
            headers: _headers,
            body: jsonEncode(bodyExplore),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        _parsePlaylistsFromBrowse(jsonDecode(res.body), addPlaylist);
      }
    } catch (e, st) {
      logger.log('Error fetching explore playlists', error: e, stackTrace: st);
    }

    // Query 3: Global / Hollywood charts
    try {
      final bodyUS = {
        ..._buildRemixContext(countryCode: 'US'),
        'browseId': 'FEmusic_charts',
      };
      final res = await http
          .post(
            Uri.parse('$_innertubeBase/browse'),
            headers: _headers,
            body: jsonEncode(bodyUS),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        _parsePlaylistsFromBrowse(jsonDecode(res.body), addPlaylist);
      }
    } catch (_) {}

    // Add fallback chart playlists if needed to ensure rich variety
    for (final fallback in fallbackChartPlaylists) {
      addPlaylist(
        fallback['ytid'] as String,
        fallback['title'] as String,
        fallback['image'] as String?,
      );
    }

    if (playlists.isNotEmpty) {
      unawaited(addOrUpdateData<List>('cache', cacheKey, playlists));
    }

    return playlists;
  }

  /// Fetches top trending artists (Bollywood & Global singers).
  Future<List<Map<String, dynamic>>> fetchTrendingArtists({
    bool forceRefresh = false,
  }) async {
    const cacheKey = 'trending_artists_v2';
    if (!forceRefresh) {
      try {
        final cached = await getData('cache', cacheKey, cachingDuration: const Duration(hours: 12));
        if (cached is List && cached.isNotEmpty) {
          return cached
              .whereType<Map>()
              .map(Map<String, dynamic>.from)
              .toList();
        }
      } catch (_) {}
    }

    final artists = <Map<String, dynamic>>[];
    final seenIds = <String>{};

    void addArtist(String channelId, String name, String? imageUrl) {
      if (channelId.isEmpty || !channelId.startsWith('UC') || !seenIds.add(channelId)) {
        return;
      }
      artists.add({
        'title': name,
        'ytid': channelId,
        'image': imageUrl,
        'source': 'youtube-artist',
        'isArtist': true,
        'list': [],
      });
    }

    try {
      final body = {
        ..._buildRemixContext(countryCode: 'IN'),
        'browseId': 'FEmusic_charts',
      };
      final res = await http
          .post(
            Uri.parse('$_innertubeBase/browse'),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        final sections = decoded['contents']
            ?['singleColumnBrowseResultsRenderer']
            ?['tabs']?[0]?['tabRenderer']?['content']
            ?['sectionListRenderer']?['contents'] as List?;

        if (sections != null) {
          for (final section in sections) {
            final carousel = section['musicCarouselShelfRenderer'] as Map?;
            if (carousel == null) continue;
            final items = (carousel['contents'] as List?) ?? [];
            for (final item in items) {
              final rResp = item['musicResponsiveListItemRenderer'] as Map?;
              if (rResp != null) {
                final pageType = rResp['navigationEndpoint']?['browseEndpoint']
                    ?['browseEndpointContextSupportedConfigs']
                    ?['browseEndpointContextMusicConfig']?['pageType']
                    ?.toString();
                if (pageType == 'MUSIC_PAGE_TYPE_ARTIST') {
                  final channelId =
                      rResp['navigationEndpoint']?['browseEndpoint']?['browseId']
                          ?.toString();
                  final runs = rResp['flexColumns']?[0]
                      ?['musicResponsiveListItemFlexColumnRenderer']?['text']
                      ?['runs'] as List?;
                  final name = runs != null
                      ? runs.map((r) => r['text'] ?? '').join().trim()
                      : '';
                  final thumbs = rResp['thumbnail']?['musicThumbnailRenderer']
                      ?['thumbnail']?['thumbnails'] as List?;
                  final imageUrl = (thumbs != null && thumbs.isNotEmpty)
                      ? thumbs.last['url']?.toString()
                      : null;
                  if (channelId != null && name.isNotEmpty) {
                    addArtist(channelId, name, imageUrl);
                  }
                }
              }

              final rTwoRow = item['musicTwoRowItemRenderer'] as Map?;
              if (rTwoRow != null) {
                final pageType = rTwoRow['navigationEndpoint']?['browseEndpoint']
                    ?['browseEndpointContextSupportedConfigs']
                    ?['browseEndpointContextMusicConfig']?['pageType']
                    ?.toString();
                if (pageType == 'MUSIC_PAGE_TYPE_ARTIST') {
                  final channelId =
                      rTwoRow['navigationEndpoint']?['browseEndpoint']?['browseId']
                          ?.toString();
                  final runs = rTwoRow['title']?['runs'] as List?;
                  final name = runs != null
                      ? runs.map((r) => r['text'] ?? '').join().trim()
                      : '';
                  final thumbs = rTwoRow['thumbnailRenderer']
                      ?['musicThumbnailRenderer']?['thumbnail']?['thumbnails']
                      as List?;
                  final imageUrl = (thumbs != null && thumbs.isNotEmpty)
                      ? thumbs.last['url']?.toString()
                      : null;
                  if (channelId != null && name.isNotEmpty) {
                    addArtist(channelId, name, imageUrl);
                  }
                }
              }
            }
          }
        }
      }
    } catch (e, st) {
      logger.log('Error fetching trending artists', error: e, stackTrace: st);
    }

    // Blend fallback artists if list is short
    for (final fallback in fallbackArtists) {
      addArtist(
        fallback['ytid'] as String,
        fallback['title'] as String,
        fallback['image'] as String?,
      );
    }

    if (artists.isNotEmpty) {
      unawaited(addOrUpdateData<List>('cache', cacheKey, artists));
    }

    return artists;
  }

  void _parsePlaylistsFromBrowse(
    dynamic root,
    void Function(String browseId, String title, String? imageUrl, {bool isAlbum}) onPlaylist,
  ) {
    if (root is! Map) return;
    final sections = root['contents']?['singleColumnBrowseResultsRenderer']
        ?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']
        ?['contents'] as List?;
    if (sections == null) return;

    for (final section in sections) {
      final carousel = section['musicCarouselShelfRenderer'] as Map?;
      if (carousel == null) continue;
      final items = (carousel['contents'] as List?) ?? [];
      for (final item in items) {
        final r = item['musicTwoRowItemRenderer'] as Map?;
        if (r == null) continue;
        final browseId =
            r['navigationEndpoint']?['browseEndpoint']?['browseId']?.toString();
        if (browseId == null || browseId.isEmpty) continue;
        if (browseId.startsWith('UC')) continue; // Skip artists here

        final runs = r['title']?['runs'] as List?;
        final title =
            runs != null ? runs.map((e) => e['text'] ?? '').join().trim() : '';
        if (title.isEmpty) continue;

        final thumbs = r['thumbnailRenderer']?['musicThumbnailRenderer']
            ?['thumbnail']?['thumbnails'] as List?;
        final img = (thumbs != null && thumbs.isNotEmpty)
            ? thumbs.last['url']?.toString()
            : null;

        final isAlbum = browseId.startsWith('MPRE');
        onPlaylist(browseId, title, img, isAlbum: isAlbum);
      }
    }
  }
}
