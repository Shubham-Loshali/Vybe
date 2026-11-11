import 'package:flutter/foundation.dart';

bool get isAndroidPlatform =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get isIosPlatform => false;

bool get isMobilePlatform => isAndroidPlatform;

bool get isDesktopPlatform => false;
