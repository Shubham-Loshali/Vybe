import 'package:audio_service/audio_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/utilities/artwork_provider.dart';
import 'package:vybe/widgets/no_artwork_cube.dart';

class SongArtworkWidget extends StatelessWidget {
  const SongArtworkWidget({
    super.key,
    required this.size,
    required this.metadata,
    this.borderRadius = 10.0,
    this.errorWidgetIconSize = 20.0,
  });
  final double size;
  final MediaItem metadata;
  final double borderRadius;
  final double errorWidgetIconSize;

  @override
  Widget build(BuildContext context) {
    final artwork = metadata.artUri?.toString();
    Widget fallback() =>
        NullArtworkWidget(iconSize: errorWidgetIconSize, size: size);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: artwork == null || artwork.isEmpty || artwork == 'null'
          ? fallback()
          : Image(
              image: ArtworkProvider.get(artwork),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, error, stack) => fallback(),
            ),
    );
  }
}
