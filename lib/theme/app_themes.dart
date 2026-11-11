import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/services/settings_manager.dart';

ThemeMode themeMode = getThemeMode(themeModeSetting);
Brightness brightness = getBrightnessFromThemeMode(themeMode);

Brightness getBrightnessFromThemeMode(ThemeMode themeMode) {
  final themeBrightnessMapping = {
    ThemeMode.light: Brightness.light,
    ThemeMode.dark: Brightness.dark,
    ThemeMode.system:
        SchedulerBinding.instance.platformDispatcher.platformBrightness,
  };

  return themeBrightnessMapping[themeMode] ?? Brightness.dark;
}

ThemeMode getThemeMode(int themeModeIndex) {
  const themeModes = ThemeMode.values;
  if (themeModeIndex >= 0 && themeModeIndex < themeModes.length) {
    return themeModes[themeModeIndex];
  }
  return ThemeMode.system;
}

ColorScheme getAppColorScheme(
  ColorScheme? lightColorScheme,
  ColorScheme? darkColorScheme,
) {
  final selectedScheme = (brightness == Brightness.light)
      ? lightColorScheme
      : darkColorScheme;

  if (useSystemColor.value && selectedScheme != null) {
    return selectedScheme;
  } else {
    if (brightness == Brightness.dark) {
      return ColorScheme(
        brightness: Brightness.dark,
        primary: primaryColorSetting, // Spotify Green (0xFF1DB954)
        onPrimary: const Color(0xFF000000),
        primaryContainer: primaryColorSetting.withValues(alpha: 0.25),
        onPrimaryContainer: primaryColorSetting,
        secondary: const Color(0xFFFFFFFF),
        onSecondary: const Color(0xFF000000),
        secondaryContainer: const Color(0xFF282828),
        onSecondaryContainer: const Color(0xFFFFFFFF),
        tertiary: const Color(0xFF1ED760),
        onTertiary: const Color(0xFF000000),
        tertiaryContainer: const Color(0xFF1DB954).withValues(alpha: 0.15),
        onTertiaryContainer: const Color(0xFF1ED760),
        error: const Color(0xFFE91429),
        onError: const Color(0xFFFFFFFF),
        surface: const Color(0xFF121212), // Spotify Dark Base
        onSurface: const Color(0xFFFFFFFF), // Pure White High Emphasis
        onSurfaceVariant: const Color(0xFFB3B3B3), // Spotify Subtext Gray
        surfaceContainerLowest: const Color(0xFF000000),
        surfaceContainerLow: const Color(0xFF181818),
        surfaceContainer: const Color(0xFF222222),
        surfaceContainerHigh: const Color(0xFF282828),
        surfaceContainerHighest: const Color(0xFF333333),
        outline: const Color(0xFF404040),
        outlineVariant: const Color(0xFF282828),
        shadow: const Color(0xFF000000),
      );
    }
    return ColorScheme.fromSeed(
      seedColor: primaryColorSetting,
      brightness: brightness,
    );
  }
}

ThemeData getAppTheme(ColorScheme colorScheme) {
  final base = colorScheme.brightness == Brightness.light
      ? ThemeData.light()
      : ThemeData.dark();

  final isLight = colorScheme.brightness == Brightness.light;
  final isPureBlack =
      colorScheme.brightness == Brightness.dark && usePureBlackColor.value;

  // Pure black & Spotify dark theme colors
  const pureBlack = Color(0xFF000000);
  const pureBlackElevated = Color(0xFF0A0A0A);
  const pureBlackContainer = Color(0xFF121212);
  const pureBlackContainerHigh = Color(0xFF1A1A1A);

  const spotifyBlack = Color(0xFF121212);
  const spotifyElevated = Color(0xFF181818);
  const spotifyContainer = Color(0xFF242424);
  const spotifyContainerHigh = Color(0xFF282828);

  final bgColor = isLight
      ? colorScheme.surface
      : (isPureBlack ? pureBlack : spotifyBlack);

  final cardBgColor = isLight
      ? colorScheme.surfaceContainerLow
      : (isPureBlack ? pureBlackElevated : spotifyElevated);

  // modified color scheme for pure black or spotify dark theme
  final effectiveColorScheme = isPureBlack
      ? colorScheme.copyWith(
          surface: pureBlack,
          surfaceContainerLowest: pureBlack,
          surfaceContainerLow: pureBlackElevated,
          surfaceContainer: pureBlackContainer,
          surfaceContainerHigh: pureBlackContainerHigh,
          surfaceContainerHighest: pureBlackContainerHigh,
        )
      : (!isLight
          ? colorScheme.copyWith(
              surface: spotifyBlack,
              surfaceContainerLowest: pureBlack,
              surfaceContainerLow: spotifyElevated,
              surfaceContainer: spotifyContainer,
              surfaceContainerHigh: spotifyContainerHigh,
              surfaceContainerHighest: const Color(0xFF333333),
            )
          : colorScheme);

  return ThemeData(
    scaffoldBackgroundColor: bgColor,
    colorScheme: effectiveColorScheme,
    cardColor: cardBgColor,
    cardTheme: base.cardTheme.copyWith(
      elevation: 0,
      color: cardBgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: bgColor,
      foregroundColor: effectiveColorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: effectiveColorScheme.onSurface,
        letterSpacing: -0.4,
      ),
      toolbarHeight: 60,
      iconTheme: IconThemeData(
        color: effectiveColorScheme.onSurface,
        size: 24,
      ),
      actionsIconTheme: IconThemeData(
        color: effectiveColorScheme.onSurface,
        size: 24,
      ),
    ),
    listTileTheme: base.listTileTheme.copyWith(
      textColor: effectiveColorScheme.onSurface,
      iconColor: effectiveColorScheme.primary,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      year2023: false,
      trackHeight: 4,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      activeTrackColor: effectiveColorScheme.primary,
      inactiveTrackColor: isLight ? Colors.black12 : const Color(0xFF4D4D4D),
      thumbColor: isLight ? effectiveColorScheme.primary : Colors.white,
    ),
    bottomSheetTheme: base.bottomSheetTheme.copyWith(
      backgroundColor: isLight
          ? colorScheme.surfaceContainerLow
          : (isPureBlack ? pureBlackElevated : spotifyContainerHigh),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      isDense: true,
      fillColor: isLight
          ? colorScheme.surfaceContainerHighest
          : (isPureBlack
                ? pureBlackContainerHigh
                : spotifyContainerHigh),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: isLight
          ? colorScheme.surfaceContainerLow
          : (isPureBlack ? pureBlackContainer : spotifyContainer),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    navigationBarTheme: base.navigationBarTheme.copyWith(
      backgroundColor: bgColor,
      elevation: 0,
      height: 64,
      indicatorColor: Colors.transparent,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(
            color: Colors.white,
            size: 24,
          );
        }
        return const IconThemeData(
          color: Color(0xFFB3B3B3),
          size: 24,
        );
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          );
        }
        return const TextStyle(
          color: Color(0xFFB3B3B3),
          fontSize: 11,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.2,
        );
      }),
    ),
    navigationRailTheme: base.navigationRailTheme.copyWith(
      backgroundColor: bgColor,
      elevation: 0,
      indicatorColor: Colors.transparent,
      selectedIconTheme: const IconThemeData(
        color: Colors.white,
        size: 24,
      ),
      unselectedIconTheme: const IconThemeData(
        color: Color(0xFFB3B3B3),
        size: 24,
      ),
      selectedLabelTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
      unselectedLabelTextStyle: const TextStyle(
        color: Color(0xFFB3B3B3),
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    ),
    popupMenuTheme: base.popupMenuTheme.copyWith(
      color: isLight
          ? colorScheme.surfaceContainerLow
          : (isPureBlack ? pureBlackContainer : spotifyContainerHigh),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    dividerTheme: base.dividerTheme.copyWith(
      color: isLight
          ? effectiveColorScheme.outlineVariant
          : const Color(0xFF282828),
      thickness: 1,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: effectiveColorScheme.secondaryContainer,
      closeIconColor: effectiveColorScheme.onSecondaryContainer,
      contentTextStyle: TextStyle(
        color: effectiveColorScheme.onSecondaryContainer,
        fontWeight: FontWeight.w500,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: effectiveColorScheme.outlineVariant,
          width: 0.2,
        ),
      ),
      elevation: 0,
      actionTextColor: effectiveColorScheme.primary,
    ),
    visualDensity: VisualDensity.adaptivePlatformDensity,
    useMaterial3: true,
  );
}
