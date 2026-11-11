import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:vybe/services/lyrics/lrc_parser.dart';
import 'package:vybe/services/lyrics/lyrics_models.dart';
import 'package:vybe/services/lyrics/lyrics_query.dart';

export 'package:vybe/services/lyrics/lyrics_models.dart';

class _CacheEntry {
  _CacheEntry(this.value) : storedAt = DateTime.now();
  final Lyrics? value;
  final DateTime storedAt;
}

/// Fetches lyrics from several sources.
///
/// Order: LRCLIB (synced + plain, open API) first, then the plain-text
/// fallbacks lyrics.ovh, paroles.net and lyricsmania.com, which are queried
/// concurrently and consumed in priority order.
class LyricsManager {
  LyricsManager({this._client});

  final http.Client? _client;

  static const _timeout = Duration(seconds: 8);
  static const _userAgent = 'Vybe (https://github.com/Shubham-Loshali/Vybe)';
  static const _maxCacheEntries = 50;
  static const _hitTtl = Duration(hours: 6);
  static const _missTtl = Duration(minutes: 5);

  // Shared between instances: callers create a new LyricsManager per request.
  static final LinkedHashMap<String, _CacheEntry> _cache =
      LinkedHashMap<String, _CacheEntry>();

  /// Clears the in-memory cache (mainly for tests).
  static void clearCache() => _cache.clear();

  /// Backwards compatible entry point: plain text with a source credit.
  Future<String?> fetchLyrics(
    String artistName,
    String title, {
    Duration? duration,
    String? album,
  }) async {
    final lyrics = await fetchLyricsResult(
      TrackInfo(
        title: title,
        artist: artistName,
        album: album,
        duration: duration,
      ),
    );
    if (lyrics == null) return null;
    return addCopyright(lyrics.text, lyrics.source);
  }

  /// Full result, including timestamps when the provider supplies them.
  Future<Lyrics?> fetchLyricsResult(TrackInfo track) async {
    if (track.title.trim().isEmpty) {
      return null;
    }

    final variants = buildSearchVariants(track);
    if (variants.isEmpty) {
      final cleanedTitle = cleanTitle(track.title);
      if (cleanedTitle.isNotEmpty) {
        variants.add(
          track.copyWith(
            title: cleanedTitle,
            artist: cleanArtist(track.artist),
          ),
        );
      } else {
        return null;
      }
    }

    final cacheKey = _cacheKey(variants.first);
    final cached = _readCache(cacheKey);
    if (cached != null) return cached.value;

    final result = await _search(variants);
    _writeCache(cacheKey, result);
    return result;
  }

  Future<Lyrics?> _search(List<TrackInfo> variants) async {
    for (final variant in variants.take(3)) {
      final lrclib = await _fetchFromLrclib(variant);
      if (lrclib != null) return lrclib;
    }

    for (final variant in variants.take(2)) {
      // Start every scraper at once, then consume in priority order so the
      // worst case is one timeout instead of the sum of all of them.
      final pending = <Future<Lyrics?>>[
        _fetchFromLyricsOvh(variant),
        _fetchFromParolesNet(variant),
        _fetchFromLyricsMania(variant),
      ];
      for (final future in pending) {
        final lyrics = await future;
        if (lyrics != null) return lyrics;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------- LRCLIB

  Future<Lyrics?> _fetchFromLrclib(TrackInfo track) async {
    try {
      final uri = Uri.https('lrclib.net', '/api/search', {
        'track_name': track.title,
        'artist_name': track.artist,
      });
      var response = await _get(uri);
      dynamic data = response.statusCode == 200
          ? jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true))
          : null;

      if (data is! List || data.isEmpty) {
        final queryUri = Uri.https('lrclib.net', '/api/search', {
          'q': '${track.artist} ${track.title}'.trim(),
        });
        response = await _get(queryUri);
        if (response.statusCode == 200) {
          data = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
        }
      }

      if (data is! List || data.isEmpty) {
        final titleUri = Uri.https('lrclib.net', '/api/search', {
          'q': track.title.trim(),
        });
        response = await _get(titleUri);
        if (response.statusCode == 200) {
          data = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true));
        }
      }

      if (data is! List || data.isEmpty) return null;

      final best = selectBestLrclibMatch(data, track);
      if (best == null) return null;

      final syncedRaw = best['syncedLyrics'];
      final plainRaw = best['plainLyrics'];
      final synced = syncedRaw is String && syncedRaw.trim().isNotEmpty
          ? parseLrc(syncedRaw)
          : null;
      final plain = plainRaw is String && plainRaw.trim().isNotEmpty
          ? plainRaw
          : null;

      final lyrics = Lyrics(
        source: 'lrclib.net',
        plain: plain,
        synced: synced != null && synced.isNotEmpty ? synced : null,
      );
      return lyrics.isEmpty ? null : lyrics;
    } catch (e, st) {
      _logError('LRCLIB lookup failed', e, st);
      return null;
    }
  }

  // ------------------------------------------------------------ lyrics.ovh

  Future<Lyrics?> _fetchFromLyricsOvh(TrackInfo track) async {
    try {
      // pathSegments percent-encodes each segment, so accents and non-Latin
      // scripts are sent as-is instead of being stripped.
      final uri = Uri(
        scheme: 'https',
        host: 'api.lyrics.ovh',
        pathSegments: ['v1', track.artist, track.title],
      );
      final response = await _get(uri);
      if (response.statusCode != 200) return null;

      final json = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      ) as Map<String, dynamic>;
      final lyrics = json['lyrics'];
      if (lyrics is String && lyrics.trim().isNotEmpty) {
        return Lyrics(source: 'lyrics.ovh', plain: lyrics);
      }
    } catch (e, st) {
      _logError('lyrics.ovh lookup failed', e, st);
    }
    return null;
  }

  // ------------------------------------------------------------ paroles.net

  Future<Lyrics?> _fetchFromParolesNet(TrackInfo track) async {
    final artist = lyricsSlug(track.artist);
    final title = lyricsSlug(track.title);
    if (artist.isEmpty || title.isEmpty) return null;

    try {
      final uri = Uri.parse('https://www.paroles.net/$artist/paroles-$title');
      final response = await _get(uri);
      if (response.statusCode != 200) return null;

      final document = html_parser.parse(response.body);
      final elements = document.querySelectorAll('.song-text');
      if (elements.isEmpty) return null;

      final lines = elements.first.text.split('\n');
      if (lines.length <= 1) return null;
      lines.removeAt(0);

      final text = _removeSpaces(lines.join('\n'));
      if (text.trim().isEmpty) return null;
      return Lyrics(source: 'www.paroles.net', plain: text);
    } catch (e, st) {
      _logError('paroles.net lookup failed', e, st);
    }
    return null;
  }

  // ------------------------------------------------------------ lyricsmania

  Future<Lyrics?> _fetchFromLyricsMania(TrackInfo track) async {
    final artist = lyricsManiaSlug(track.artist);
    final title = lyricsManiaSlug(track.title);
    if (artist.isEmpty || title.isEmpty) return null;

    try {
      final uri = Uri.parse(
        'https://www.lyricsmania.com/${title}_lyrics_$artist.html',
      );
      final response = await _get(uri);
      if (response.statusCode != 200) return null;

      final document = html_parser.parse(response.body);
      final elements = document.querySelectorAll('.lyrics-body');
      if (elements.isEmpty) return null;

      final text = elements.first.text;
      if (text.trim().isEmpty) return null;
      return Lyrics(source: 'www.lyricsmania.com', plain: text);
    } catch (e, st) {
      _logError('lyricsmania lookup failed', e, st);
    }
    return null;
  }

  // --------------------------------------------------------------- helpers

  Future<http.Response> _get(Uri uri) {
    final headers = {'User-Agent': _userAgent};
    final client = _client;
    final request = client != null
        ? client.get(uri, headers: headers)
        : http.get(uri, headers: headers);
    return request.timeout(_timeout);
  }

  void _logError(String message, Object error, StackTrace stackTrace) {
    developer.log(
      message,
      name: 'LyricsManager',
      error: error,
      stackTrace: stackTrace,
    );
  }

  String _cacheKey(TrackInfo t) {
    final seconds = t.duration?.inSeconds ?? 0;
    return '${foldDiacritics(t.artist)}|${foldDiacritics(t.title)}|$seconds';
  }

  _CacheEntry? _readCache(String key) {
    final entry = _cache.remove(key);
    if (entry == null) return null;
    final ttl = entry.value == null ? _missTtl : _hitTtl;
    if (DateTime.now().difference(entry.storedAt) > ttl) return null;
    _cache[key] = entry; // re-insert: most recently used goes last
    return entry;
  }

  void _writeCache(String key, Lyrics? value) {
    _cache.remove(key);
    _cache[key] = _CacheEntry(value);
    while (_cache.length > _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  String _removeSpaces(String input) {
    return input.replaceAll(RegExp(' {2,}'), ' ');
  }

  String addCopyright(String input, String copyright) {
    return '$input\n\n© $copyright';
  }
}

/// Picks the LRCLIB search result that best matches [track], or null when
/// nothing is convincing. Prefers matching duration (so live/remix versions
/// are not chosen) and results that carry synced lyrics.
Map<String, dynamic>? selectBestLrclibMatch(
  List<dynamic> results,
  TrackInfo track,
) {
  final wantTitle = foldDiacritics(cleanTitle(track.title));
  final wantArtist = foldDiacritics(cleanArtist(track.artist));
  final wantSeconds = track.duration?.inSeconds;

  int textScore(String have, String want) {
    if (have.isEmpty || want.isEmpty) return 0;
    if (have == want) return 5;
    if (have.contains(want) || want.contains(have)) return 3;
    final haveWords = have
        .split(RegExp(r'[\s,;&/_\-\(\)]+'))
        .where((w) => w.length >= 2)
        .toSet();
    final wantWords = want
        .split(RegExp(r'[\s,;&/_\-\(\)]+'))
        .where((w) => w.length >= 2)
        .toSet();
    if (haveWords.isNotEmpty && wantWords.isNotEmpty) {
      final common = haveWords.intersection(wantWords);
      if (common.isNotEmpty) {
        if (common.length == wantWords.length ||
            common.length == haveWords.length) {
          return 3;
        }
        return 2;
      }
    }
    return 0;
  }

  Map<String, dynamic>? best;
  var bestScore = -1 << 30;

  for (final raw in results) {
    if (raw is! Map<String, dynamic>) continue;
    if (raw['instrumental'] == true) continue;

    final hasPlain =
        (raw['plainLyrics'] as String?)?.trim().isNotEmpty ?? false;
    final hasSynced =
        (raw['syncedLyrics'] as String?)?.trim().isNotEmpty ?? false;
    if (!hasPlain && !hasSynced) continue;

    final titleScore = textScore(
      foldDiacritics(cleanTitle((raw['trackName'] ?? '').toString())),
      wantTitle,
    );
    final artistScore = textScore(
      foldDiacritics(cleanArtist((raw['artistName'] ?? '').toString())),
      wantArtist,
    );

    var durationScore = 0;
    var durationClose = false;
    final seconds = raw['duration'];
    if (wantSeconds != null && wantSeconds > 0 && seconds is num) {
      final diff = (seconds - wantSeconds).abs();
      if (diff <= 2) {
        durationScore = 6;
        durationClose = true;
      } else if (diff <= 5) {
        durationScore = 3;
        durationClose = true;
      } else if (diff > 15) {
        durationScore = -5;
      }
    }

    // Title must at least roughly match
    if (titleScore < 2) continue;

    // If artist score is low and duration is not close:
    if (artistScore < 2 && !durationClose) {
      final isDurationUnknown = wantSeconds == null || wantSeconds <= 0;
      final isDurationAcceptable =
          seconds is num &&
          wantSeconds != null &&
          (seconds - wantSeconds).abs() <= 12;
      // Accept if exact title match and duration is unknown or close enough
      if (titleScore < 4) continue;
      if (!isDurationUnknown && !isDurationAcceptable) continue;
    }

    final score =
        (titleScore * 2) + (artistScore * 2) + durationScore + (hasSynced ? 3 : 0);
    if (score > bestScore) {
      bestScore = score;
      best = raw;
    }
  }
  return best;
}
