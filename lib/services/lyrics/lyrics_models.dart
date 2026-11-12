/// A song a lyrics lookup is performed for.
class TrackInfo {
  const TrackInfo({
    required this.title,
    required this.artist,
    this.album,
    this.duration,
    this.videoId,
  });

  final String title;
  final String artist;
  final String? album;
  final Duration? duration;
  final String? videoId;

  TrackInfo copyWith({String? title, String? artist}) => TrackInfo(
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album,
    duration: duration,
    videoId: videoId,
  );
}

/// One timed line of a synchronized (LRC) lyrics file.
class LyricLine {
  const LyricLine(this.start, this.text, {this.wordCues = const []});

  final Duration start;
  final String text;
  final List<LyricWordCue> wordCues;

  @override
  String toString() => '[$start] $text';
}

/// A timestamp attached to a word in the first row of a lyric line.
typedef LyricWordCue = ({int wordIndex, Duration start});

/// Lyrics returned by a provider.
///
/// [plain] is always usable text. [synced] is only set by providers that
/// return timestamps (e.g. LRCLIB) and is sorted by start time.
class Lyrics {
  const Lyrics({required this.source, this.plain, this.synced});

  /// A small, provider-independent representation for the offline cache.
  Map<String, dynamic> toJson() => {
    'source': source,
    'plain': plain,
    if (isSynced)
      'synced': [
        for (final line in synced!)
          {
            'start': line.start.inMilliseconds,
            'text': line.text,
            if (line.wordCues.isNotEmpty)
              'wordCues': [
                for (final cue in line.wordCues)
                  {'word': cue.wordIndex, 'start': cue.start.inMilliseconds},
              ],
          },
      ],
  };

  static Lyrics? fromJson(dynamic value) {
    if (value is! Map || value['source'] is! String) return null;
    final lines = <LyricLine>[];
    final rawLines = value['synced'];
    if (rawLines is List) {
      for (final raw in rawLines) {
        if (raw is! Map || raw['start'] is! int || raw['text'] is! String) {
          return null;
        }
        final cues = <LyricWordCue>[];
        final rawCues = raw['wordCues'];
        if (rawCues is List) {
          for (final cue in rawCues.whereType<Map>()) {
            final word = cue['word'];
            final start = cue['start'];
            if (word is int && word >= 0 && start is int && start >= 0) {
              cues.add((wordIndex: word, start: Duration(milliseconds: start)));
            }
          }
        }
        lines.add(
          LyricLine(
            Duration(milliseconds: raw['start']),
            raw['text'],
            wordCues: cues,
          ),
        );
      }
      lines.sort((a, b) => a.start.compareTo(b.start));
    }
    final result = Lyrics(
      source: value['source'],
      plain: value['plain'] is String ? value['plain'] : null,
      synced: lines.isEmpty ? null : lines,
    );
    return result.isEmpty ? null : result;
  }

  /// Human readable provider name, e.g. `lrclib.net`.
  final String source;
  final String? plain;
  final List<LyricLine>? synced;

  bool get isSynced => synced != null && synced!.isNotEmpty;

  /// Plain text, derived from [synced] when the provider sent no plain text.
  String get text {
    final p = plain;
    if (p != null && p.trim().isNotEmpty) return p;
    return (synced ?? const <LyricLine>[]).map((l) => l.text).join('\n');
  }

  bool get isEmpty => text.trim().isEmpty;

  /// Index of the line that should be highlighted at [position], or -1 when
  /// the song has not reached the first line yet.
  int lineIndexAt(Duration position) {
    final lines = synced;
    if (lines == null || lines.isEmpty) return -1;
    var lo = 0;
    var hi = lines.length - 1;
    var result = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].start <= position) {
        result = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return result;
  }
}
