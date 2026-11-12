import 'package:vybe/services/lyrics/lyrics_models.dart';

final RegExp _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
final RegExp _offsetTag = RegExp(
  r'^\s*\[offset:\s*([+-]?\d+)\s*\]\s*$',
  caseSensitive: false,
);
final RegExp _wordTag = RegExp(r'<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>');

/// Parses LRC text into time-sorted lines.
///
/// Supports `[mm:ss]`, `[mm:ss.xx]`, `[mm:ss.xxx]`, several timestamps on one
/// line, the `[offset:ms]` header and enhanced `<mm:ss.xx>` word tags (which
/// supply word timestamps). Metadata tags such as `[ar:...]` are ignored.
List<LyricLine> parseLrc(String input) {
  final lines = <LyricLine>[];
  // The offset is file-wide, including when it appears after timed lines.
  var offsetMs = 0;
  final rawLines = input.replaceFirst('\ufeff', '').split(RegExp(r'\r\n?|\n'));
  for (final raw in rawLines) {
    final match = _offsetTag.firstMatch(raw);
    if (match != null) offsetMs = int.tryParse(match.group(1)!) ?? 0;
  }

  for (final raw in rawLines) {
    final offsetMatch = _offsetTag.firstMatch(raw);
    if (offsetMatch != null) {
      offsetMs = int.tryParse(offsetMatch.group(1)!) ?? 0;
      continue;
    }

    final matches = _timeTag.allMatches(raw).toList();
    if (matches.isEmpty) continue;

    final lyric = raw.substring(matches.last.end);
    final text = lyric
        .replaceAll(_wordTag, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final cues = <LyricWordCue>[];
    for (final tag in _wordTag.allMatches(lyric)) {
      final following = lyric.substring(tag.end).trimLeft();
      if (following.isEmpty || following.startsWith('<')) continue;
      final preceding = lyric.substring(0, tag.start).replaceAll(_wordTag, '');
      final wordIndex = RegExp(r'\S+').allMatches(preceding).length;
      cues.add((wordIndex: wordIndex, start: _timestamp(tag, offsetMs)));
    }

    final firstStart = _timestamp(matches.first, offsetMs);
    for (final tag in matches) {
      final start = _timestamp(tag, offsetMs);
      lines.add(
        LyricLine(
          start,
          text,
          wordCues: [
            for (final cue in cues)
              (
                wordIndex: cue.wordIndex,
                start: start + (cue.start - firstStart),
              ),
          ],
        ),
      );
    }
  }

  // Stable sort so equal timestamps keep their file order.
  final indexed = lines.asMap().entries.toList()
    ..sort((a, b) {
      final c = a.value.start.compareTo(b.value.start);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  // Some providers repeat timestamps; preserve translations at the same time
  // as a single line so neither disappears behind the active-line lookup.
  final merged = <LyricLine>[];
  for (final entry in indexed) {
    final line = entry.value;
    if (merged.isNotEmpty && merged.last.start == line.start) {
      final previous = merged.removeLast();
      final texts = <String>{
        if (previous.text.isNotEmpty) previous.text,
        if (line.text.isNotEmpty) line.text,
      };
      merged.add(
        LyricLine(
          line.start,
          texts.join('\n'),
          wordCues:
              previous.text.isEmpty ||
                  previous.text == line.text && previous.wordCues.isEmpty
              ? line.wordCues
              : previous.wordCues,
        ),
      );
    } else {
      merged.add(line);
    }
  }
  return merged;
}

Duration _timestamp(Match tag, int offsetMs) {
  final fraction = tag.group(3);
  final milliseconds = fraction == null
      ? 0
      : int.parse(fraction.padRight(3, '0'));
  // Positive LRC offsets show the words sooner.
  final time = Duration(
    minutes: int.parse(tag.group(1)!),
    seconds: int.parse(tag.group(2)!),
    milliseconds: milliseconds - offsetMs,
  );
  return time.isNegative ? Duration.zero : time;
}
