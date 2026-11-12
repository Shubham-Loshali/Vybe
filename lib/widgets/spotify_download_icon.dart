import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:material_ui/material_ui.dart';

/// Spotify's download glyph: a grey ring with a down arrow while the content
/// is not downloaded, a solid green circle once it is.
class SpotifyDownloadIcon extends StatelessWidget {
  const SpotifyDownloadIcon({super.key, required this.downloaded, this.size = 26});

  final bool downloaded;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: downloaded ? const Color(0xFF1DB954) : Colors.transparent,
        border: downloaded
            ? null
            : Border.all(color: const Color(0xFFB3B3B3), width: 2),
      ),
      child: Icon(
        FluentIcons.arrow_download_20_filled,
        size: size * 0.6,
        color: downloaded ? Colors.black : const Color(0xFFB3B3B3),
      ),
    );
  }
}

/// The tiny green "downloaded" mark Spotify puts before the artist name.
class DownloadedBadge extends StatelessWidget {
  const DownloadedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 15,
      height: 15,
      margin: const EdgeInsets.only(right: 6),
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFF1DB954),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        FluentIcons.arrow_download_20_filled,
        size: 10,
        color: Colors.black,
      ),
    );
  }
}
