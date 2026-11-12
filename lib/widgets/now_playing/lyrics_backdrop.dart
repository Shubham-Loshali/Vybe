import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:vybe/utilities/artwork_provider.dart';

/// Artwork supplies the atmosphere; a dark scrim keeps every lyric readable.
class LyricsBackdrop extends StatelessWidget {
  const LyricsBackdrop({super.key, required this.artwork, required this.color});

  final String? artwork;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: Color.alphaBlend(
                color.withValues(alpha: 0.7),
                const Color(0xFF121018),
              ),
            ),
            if (artwork?.isNotEmpty ?? false)
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                child: Transform.scale(
                  scale: 1.15,
                  child: Image(
                    image: ArtworkProvider.get(artwork!),
                    fit: BoxFit.cover,
                    opacity: const AlwaysStoppedAnimation(0.65),
                    errorBuilder: (_, error, stack) => const SizedBox.expand(),
                  ),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.8, -0.5),
                  radius: 1.5,
                  colors: [color.withValues(alpha: 0.35), Colors.transparent],
                ),
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0x66302A30),
                    Color(0x9908070B),
                    Color(0xE608070B),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
