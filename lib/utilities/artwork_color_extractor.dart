import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vybe/utilities/artwork_provider.dart';

class ArtworkColorExtractor {
  ArtworkColorExtractor._();

  static final Map<String, Color> _colorCache = {};
  static const Color defaultGradientColor = Color(0xFF282828);
  static const Color defaultBackgroundBottom = Color(0xFF121212);

  /// Extracts a vibrant/dominant dark color suitable for Now Playing gradient backdrop.
  static Future<Color> extractDominantColor(String? artworkUri) async {
    if (artworkUri == null || artworkUri.trim().isEmpty) {
      return defaultGradientColor;
    }

    final key = artworkUri.trim();
    if (_colorCache.containsKey(key)) {
      return _colorCache[key]!;
    }

    try {
      final imageProvider = ArtworkProvider.get(key);
      final completer = Completer<ui.Image>();
      final stream = imageProvider.resolve(
        const ImageConfiguration(size: Size(24, 24)),
      );

      late final ImageStreamListener listener;
      listener = ImageStreamListener(
        (ImageInfo info, bool _) {
          stream.removeListener(listener);
          completer.complete(info.image);
        },
        onError: (dynamic error, StackTrace? _) {
          stream.removeListener(listener);
          completer.completeError(error);
        },
      );
      stream.addListener(listener);

      final image = await completer.future.timeout(
        const Duration(milliseconds: 1500),
      );

      final byteData = await image.toByteData();
      if (byteData == null) {
        _colorCache[key] = defaultGradientColor;
        return defaultGradientColor;
      }

      final bytes = byteData.buffer.asUint8List();
      final length = bytes.length;

      var bestScore = -1.0;
      var bestColor = defaultGradientColor;

      for (var i = 0; i < length; i += 4) {
        final r = bytes[i];
        final g = bytes[i + 1];
        final b = bytes[i + 2];
        final a = bytes[i + 3];

        if (a < 128) continue; // Skip semi-transparent pixels

        final hsl = HSLColor.fromColor(Color.fromARGB(255, r, g, b));

        // Skip extreme darks and extreme lights
        if (hsl.lightness < 0.12 || hsl.lightness > 0.88) continue;
        // Skip pure grays
        if (hsl.saturation < 0.12) continue;

        // Favor rich saturation and medium lightness (0.3 - 0.5)
        final lightnessScore = 1.0 - (hsl.lightness - 0.38).abs() * 2.2;
        final score = (hsl.saturation * 1.8) + lightnessScore;

        if (score > bestScore) {
          bestScore = score;
          // Clamp lightness to ensure deep, rich gradient backdrop
          final clampedLightness = hsl.lightness.clamp(0.20, 0.40);
          final boostedSaturation = (hsl.saturation * 1.15).clamp(0.0, 1.0);
          bestColor = hsl
              .withLightness(clampedLightness)
              .withSaturation(boostedSaturation)
              .toColor();
        }
      }

      _colorCache[key] = bestColor;
      return bestColor;
    } catch (_) {
      _colorCache[key] = defaultGradientColor;
      return defaultGradientColor;
    }
  }

  static void clearCache() => _colorCache.clear();
}

