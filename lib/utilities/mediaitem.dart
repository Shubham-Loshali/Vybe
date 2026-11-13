import 'package:audio_service/audio_service.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/utilities/media_duration.dart';

Map mediaItemToMap(MediaItem mediaItem) {
  final extras = mediaItem.extras;
  return {
    'id': mediaItem.id,
    'ytid': extras?['ytid'],
    'album': mediaItem.album.toString(),
    'artist': mediaItem.artist.toString(),
    'title': mediaItem.title,
    'artistId': extras?['artistId'],
    'videoAuthor': extras?['videoAuthor'],
    'highResImage': extras?['highResImage'] ?? mediaItem.artUri.toString(),
    'lowResImage': extras?['lowResImage'],
    'isLive': extras?['isLive'] ?? false,
    if (mediaItem.duration case final duration?) 'duration': duration.inSeconds,
  };
}

MediaItem mapToMediaItem(Map song) {
  final ytid = song['ytid']?.toString();
  final offlineSong = ytid != null
      ? getOfflineSongByYtid(ytid)
      : <String, dynamic>{};
  final isOffline = offlineSong.isNotEmpty;

  Uri? artUri;
  final artworkPath = offlineSong['artworkPath']?.toString();
  if (isOffline && artworkPath != null && artworkPath.isNotEmpty) {
    artUri = Uri.file(artworkPath);
  } else {
    final highRes = song['highResImage']?.toString();
    final lowRes = song['lowResImage']?.toString();
    final candidate = (highRes != null && highRes.isNotEmpty && highRes != 'null')
        ? highRes
        : (lowRes != null && lowRes.isNotEmpty && lowRes != 'null' ? lowRes : null);
    if (candidate != null) {
      artUri = Uri.tryParse(candidate);
    }
  }

  return MediaItem(
    id: song['id']?.toString() ?? '',
    artist: song['artist']?.toString().trim() ?? '',
    title: song['title']?.toString() ?? '',
    artUri: artUri,
    duration: readMediaDuration(song['duration']),
    extras: {
      'lowResImage': song['lowResImage'],
      'ytid': song['ytid'],
      'artistId': song['artistId'],
      'videoAuthor': song['videoAuthor'],
      'isLive': song['isLive'],
      'highResImage': song['highResImage'],
      'artWorkPath':
          (isOffline ? offlineSong['artworkPath'] : song['highResImage'])
              ?.toString() ??
          '',
    },
  );
}

/// Compares two Duration objects with tolerance for minor differences.
///
/// This prevents unnecessary updates when duration values have minor variations
/// (e.g., due to buffering or precision differences).
bool durationEquals(Duration? prev, Duration? curr) {
  if (prev == curr) return true;
  if (prev == null || curr == null) return prev == curr;

  // Consider durations equal if they differ by less than 1 second
  return (prev - curr).abs() < const Duration(seconds: 1);
}
