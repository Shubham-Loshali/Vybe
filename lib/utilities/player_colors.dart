import 'package:material_ui/material_ui.dart';

/// A dark artwork tint keeps white controls and secondary text readable,
/// including when the album cover is bright yellow or white.
Color miniPlayerSurface(Color artworkColor) => Color.alphaBlend(
  Colors.black.withValues(alpha: 0.66),
  artworkColor.withValues(alpha: 1),
);
