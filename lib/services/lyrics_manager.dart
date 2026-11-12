import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;
import 'package:vybe/services/lyrics/lrc_parser.dart';
import 'package:vybe/services/lyrics/lyrics_models.dart';
import 'package:vybe/services/lyrics/lyrics_query.dart';
import 'package:vybe/services/lyrics/youtube_music_lyrics.dart';

export 'package:vybe/services/lyrics/lyrics_models.dart';

const _plainMatchToleranceSeconds = 35;

class _CacheEntry {
  _CacheEntry(this.value) : storedAt = DateTime.now();
  final Lyrics? value;
  final DateTime storedAt;
}

/// Fetches lyrics from several sources.
///
/// Prefers verified timed lyrics, then falls back to plain text. Requests to
/// LRCLIB are serialized and throttled, with a bounded search budget.
class LyricsManager {
  LyricsManager({this.client});

  final http.Client? client;

  static const _timeout = Duration(seconds: 4);
  static const _searchBudget = Duration(seconds: 12);
  static const _userAgent =
      'Vybe v10.6.2 (https://github.com/Shubham-Loshali/Vybe)';
  static const _maxCacheEntries = 50;
  static const _hitTtl = Duration(hours: 6);
  static const _missTtl = Duration(seconds: 30);

  // Shared between instances: callers create a new LyricsManager per request.
  static final LinkedHashMap<String, _CacheEntry> _cache =
      LinkedHashMap<String, _CacheEntry>();
  static final Map<String, Future<Lyrics?>> _inFlight = {};
  static Future<void> _lrclibQueue = Future<void>.value();
  static DateTime _nextLrclibRequest = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _lrclibBlockedUntil = DateTime.fromMillisecondsSinceEpoch(0);

  /// Clears the in-memory cache (mainly for tests).
  static void clearCache() {
    _cache.clear();
  }

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
  Future<Lyrics?> fetchLyricsResult(
    TrackInfo track, {
    bool forceRefresh = false,
  }) async {
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

    // Use the original metadata: inferred title/artist pairs can be ambiguous.
    final cacheKey = _cacheKey(track);
    final pending = _inFlight[cacheKey];
    if (pending != null) return pending;
    final cached = _readCache(cacheKey);
    if (!forceRefresh && cached != null) return cached.value;

    final search = _search(track, variants);
    _inFlight[cacheKey] = search;
    try {
      final result = await search;
      _writeCache(cacheKey, result);
      return result;
    } finally {
      unawaited(_inFlight.remove(cacheKey));
    }
  }

  Future<Lyrics?> _search(TrackInfo track, List<TrackInfo> variants) async {
    final elapsed = Stopwatch()..start();
    final youtubeLookup = YouTubeMusicLyrics(client: client).lookup(track);
    final candidates = <dynamic>[];
    Lyrics? plain;
    final requests = <Uri>[];
    final first = variants.first;
    if (first.artist.isNotEmpty) {
      candidates.addAll(
        await _fetchLrclibRecords(
          Uri.https('lrclib.net', '/api/get', {
            'track_name': first.title,
            'artist_name': first.artist,
            if (first.album?.trim().isNotEmpty ?? false)
              'album_name': first.album,
            if (first.duration != null &&
                first.duration!.inSeconds > 0 &&
                first.duration!.inSeconds <= 3600)
              'duration': '${first.duration!.inSeconds}',
          }),
          elapsed,
        ),
      );
      final exact = selectBestLrclibMatch(candidates, first);
      if (exact != null) {
        plain = _lyricsFromRecord(exact, first);
        if (plain?.isSynced == true) return plain;
      }
    }

    final youtube = await youtubeLookup;
    if (youtube?.track case final canonical?) {
      // Canonical metadata from the requested video takes priority over an
      // upload title such as "Sitaare Ikkis Agastya Nanda ...".
      variants = [...buildSearchVariants(canonical), ...variants];
    }
    plain ??= youtube?.lyrics;

    // Broad title searches recover label-channel metadata and collaborations.
    // They also run when a structured search returned unrelated candidates.
    // Try a title-only search immediately, before spending the budget on every
    // collaborator. A channel name can be unrelated to the credited singer.
    for (final variant in variants.take(3)) {
      requests
        ..add(
          Uri.https('lrclib.net', '/api/search', {
            'track_name': variant.title,
            if (variant.artist.isNotEmpty) 'artist_name': variant.artist,
          }),
        )
        ..add(
          Uri.https('lrclib.net', '/api/search', {'track_name': variant.title}),
        );
    }
    for (final uri in requests.toSet()) {
      if (elapsed.elapsed >= _searchBudget) break;
      candidates.addAll(await _fetchLrclibRecords(uri, elapsed));
      for (final variant in variants) {
        final best = selectBestLrclibMatch(candidates, variant);
        if (best == null) continue;
        final result = _lyricsFromRecord(best, variant);
        if (result == null) continue;
        if (result.isSynced) return result;
        plain ??= result;
      }
    }
    if (plain != null) return plain;

    for (final variant in variants.take(3)) {
      if (variant.artist.isEmpty) continue;
      // Return the first usable fallback instead of waiting for a slow source
      // ahead of a source that has already succeeded.
      final result = await _firstAvailable([
        _fetchFromLyricsOvh(variant),
        _fetchFromParolesNet(variant),
        _fetchFromLyricsMania(variant),
      ]);
      if (result != null) return result;
    }
    return null;
  }

  Future<Lyrics?> _firstAvailable(List<Future<Lyrics?>> requests) {
    final completer = Completer<Lyrics?>();
    var remaining = requests.length;
    for (final request in requests) {
      unawaited(
        request.catchError((Object _) => null).then((result) {
          if (result != null && !completer.isCompleted)
            completer.complete(result);
          remaining--;
          if (remaining == 0 && !completer.isCompleted)
            completer.complete(null);
        }),
      );
    }
    return completer.future;
  }

  Future<List<dynamic>> _fetchLrclibRecords(Uri uri, Stopwatch elapsed) async {
    final previous = _lrclibQueue;
    final done = Completer<void>();
    _lrclibQueue = done.future;
    try {
      await previous;
      if (elapsed.elapsed >= _searchBudget ||
          DateTime.now().isBefore(_lrclibBlockedUntil))
        return [];
      final wait = _nextLrclibRequest.difference(DateTime.now());
      if (!wait.isNegative) await Future<void>.delayed(wait);
      if (elapsed.elapsed >= _searchBudget) return [];
      final response = await _get(uri);
      if (response.statusCode == 429 || response.statusCode == 503) {
        final seconds =
            int.tryParse(response.headers['retry-after'] ?? '') ?? 60;
        _lrclibBlockedUntil = DateTime.now().add(
          Duration(seconds: seconds < 1 ? 1 : seconds),
        );
      }
      if (response.statusCode != 200) return [];
      final data = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
      return data is List ? data : (data is Map<String, dynamic> ? [data] : []);
    } catch (e, st) {
      _logError('LRCLIB lookup failed', e, st);
      return [];
    } finally {
      _nextLrclibRequest = DateTime.now().add(
        const Duration(milliseconds: 200),
      );
      done.complete();
    }
  }

  Lyrics? _lyricsFromRecord(Map<String, dynamic> record, TrackInfo track) {
    final raw = record['syncedLyrics'];
    final lines = raw is String ? parseLrc(raw) : <LyricLine>[];
    final seconds = record['duration'];
    final durationMatches =
        track.duration == null ||
        track.duration == Duration.zero ||
        seconds is! num ||
        (seconds - track.duration!.inSeconds).abs() <= 15;
    final result = Lyrics(
      source: 'lrclib.net',
      plain:
          record['plainLyrics'] is String &&
              (record['plainLyrics'] as String).trim().isNotEmpty
          ? record['plainLyrics']
          : lines.map((l) => l.text).join('\n'),
      // A different cut can have useful words but incorrect timestamps.
      synced: lines.isNotEmpty && durationMatches ? lines : null,
    );
    return result.isEmpty ? null : result;
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

  Future<http.Response> _get(Uri uri) async {
    final headers = {'User-Agent': _userAgent};
    final requestClient = client ?? http.Client();
    try {
      return await requestClient.get(uri, headers: headers).timeout(_timeout);
    } finally {
      if (client == null) requestClient.close();
    }
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
    return '${foldDiacritics(t.artist)}|${foldDiacritics(t.title)}|'
        '${foldDiacritics(t.album ?? '')}|$seconds|${t.videoId ?? ''}';
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
    String normalize(String value) => value
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    have = normalize(have);
    want = normalize(want);
    if (have == want) return 5;
    final haveWords = have.split(' ').where((w) => w.isNotEmpty).toSet();
    final wantWords = want.split(' ').where((w) => w.isNotEmpty).toSet();
    if (haveWords.isNotEmpty && wantWords.isNotEmpty) {
      final common = haveWords.intersection(wantWords);
      if (common.length / wantWords.length >= 0.75 &&
          common.length / haveWords.length >= 0.75)
        return 3;
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
      } else if (diff > _plainMatchToleranceSeconds) {
        durationScore = -8;
      } else if (diff > 15) {
        durationScore = -5;
      }
    }

    // Title must at least roughly match
    if (titleScore < 3) continue;

    // Do not attach a live/remix/cover timeline to the studio recording.
    final versionWords = RegExp(
      r'\b(live|remix|cover|slowed|sped|acoustic|instrumental|karaoke)\b',
      caseSensitive: false,
    );
    final wantedVersions = versionWords
        .allMatches(track.title)
        .map((m) => m.group(1)!.toLowerCase())
        .toSet();
    final candidateVersions = versionWords
        .allMatches('${raw['trackName']}')
        .map((m) => m.group(1)!.toLowerCase())
        .toSet();
    if (wantedVersions.difference(candidateVersions).isNotEmpty ||
        candidateVersions.difference(wantedVersions).isNotEmpty)
      continue;

    // If artist score is low and duration is not close:
    if (artistScore < 2 && !durationClose) {
      final isDurationUnknown = wantSeconds == null || wantSeconds <= 0;
      final isDurationAcceptable =
          seconds is num &&
          wantSeconds != null &&
          (seconds - wantSeconds).abs() <=
              (wantArtist.isEmpty ? 12 : _plainMatchToleranceSeconds);
      // Accept if exact title match and duration is unknown or close enough
      if (titleScore < 4) continue;
      // With weak artist evidence, a larger gap is only safe for an
      // unambiguous title in the returned records.
      if (seconds is num &&
          wantSeconds != null &&
          (seconds - wantSeconds).abs() > 12 &&
          results.whereType<Map<String, dynamic>>().any(
            (other) =>
                other['instrumental'] != true &&
                (other['plainLyrics'] is String ||
                    other['syncedLyrics'] is String) &&
                textScore(
                      foldDiacritics(cleanTitle('${other['trackName']}')),
                      wantTitle,
                    ) ==
                    5 &&
                textScore(
                      foldDiacritics(cleanArtist('${other['artistName']}')),
                      foldDiacritics(cleanArtist('${raw['artistName']}')),
                    ) ==
                    0,
          )) {
        continue;
      }
      if (!isDurationUnknown && !isDurationAcceptable) continue;
    }

    final score =
        (titleScore * 2) +
        (artistScore * 2) +
        durationScore +
        (hasSynced ? 3 : 0);
    if (score > bestScore) {
      bestScore = score;
      best = raw;
    }
  }
  return best;
}
