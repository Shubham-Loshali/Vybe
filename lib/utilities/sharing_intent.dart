import 'package:vybe/services/audio_service.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/utilities/formatter.dart';

final _youtubeLinkRegex = RegExp(r'(youtube\.com|youtu\.be)');
int _latestShareRequest = 0;

Future<void> handleYoutubeSharedTextIntent(
  String? value, {
  required VybeAudioHandler audioHandler,
  required void Function(Object error, StackTrace stackTrace) onError,
  Future<Map<String, dynamic>> Function(int, String) getSong = getSongDetails,
}) async {
  if (value == null || !_youtubeLinkRegex.hasMatch(value)) {
    return;
  }

  final songId = getSongId(value);
  if (songId == null) {
    return;
  }

  final request = ++_latestShareRequest;
  try {
    final song = await getSong(0, songId);
    if (request != _latestShareRequest) return;
    await audioHandler.addPlaylistToQueue([song], replace: true);
  } catch (e, stackTrace) {
    if (request == _latestShareRequest) onError(e, stackTrace);
  }
}

Future<void> consumeYoutubeSharedTextIntent(
  String? value, {
  required VybeAudioHandler audioHandler,
  required void Function(Object error, StackTrace stackTrace) onError,
}) async {
  if (value == null || value.isEmpty) {
    return;
  }

  final normalizedValue = value.trim();
  if (normalizedValue.isEmpty) {
    return;
  }

  await handleYoutubeSharedTextIntent(
    normalizedValue,
    audioHandler: audioHandler,
    onError: onError,
  );
}
