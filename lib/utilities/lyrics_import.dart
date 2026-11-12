import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/services/lyrics/lrc_parser.dart';
import 'package:vybe/services/lyrics/lyrics_models.dart';

Future<Lyrics?> importLyricsFile(BuildContext context, MediaItem song) async {
  try {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['lrc', 'txt'],
    );
    if (file == null) return null;
    if ((await file.length() ?? 0) > 2 * 1024 * 1024)
      throw const FormatException('Lyrics file is too large');
    final bytes = await file.readAsBytes();
    final text = utf8.decode(bytes).replaceFirst('\ufeff', '').trim();
    if (text.isEmpty) throw const FormatException('Lyrics file is empty');
    final lines = parseLrc(text);
    final result = Lyrics(
      source: 'Local file',
      plain: lines.isEmpty ? text : null,
      synced: lines.isEmpty ? null : lines,
    );
    if (result.isEmpty) throw const FormatException('Lyrics file has no words');
    await saveCustomSongLyrics(
      result,
      song.artist,
      song.title,
      album: song.album,
    );
    return result;
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not import lyrics. Choose a UTF-8 .lrc or .txt file.',
          ),
        ),
      );
    }
    return null;
  }
}
