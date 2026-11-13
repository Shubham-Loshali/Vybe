import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:fluentui_system_icons/fluentui_system_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:vybe/constants/version.dart';
import 'package:vybe/extensions/l10n.dart';
import 'package:vybe/main.dart';
import 'package:vybe/services/data_manager.dart';
import 'package:vybe/services/router_service.dart';
import 'package:vybe/services/settings_manager.dart';
import 'package:vybe/utilities/platform_utils.dart';
import 'package:vybe/utilities/url_launcher.dart';
import 'package:vybe/widgets/auto_format_text.dart';

/// Primary private Cloudflare Worker update endpoint.
/// Set your worker URL here once created (e.g. https://vybe-api.workers.dev/check).
const String cloudflareWorkerUrl =
    'https://vybe.shubham-loshali18.workers.dev/check';
const String fallbackCheckUrl =
    'https://raw.githubusercontent.com/Shubham-Loshali/Vybe/update/check.json';
const String checkUrl = fallbackCheckUrl;
const String releasesUrl =
    'https://api.github.com/repos/Shubham-Loshali/Vybe/releases/latest';
const String downloadUrlKey = 'url';
const String downloadUrlArm64Key = 'arm64url';
const String downloadFilename = 'Vybe.apk';

const _isCompanionBuild =
    String.fromEnvironment('FLUTTER_APP_FLAVOR') == 'companion';
Future<void>? _pendingUpdateCheck;
final ValueNotifier<bool> isAppBlockedByUpdate = ValueNotifier<bool>(false);

Future<Map<String, dynamic>?> _fetchUpdateConfig() async {
  // 1. Try private Cloudflare Worker first (instant, real-time, zero caching)
  if (cloudflareWorkerUrl.isNotEmpty) {
    try {
      final response = await http
          .get(Uri.parse(cloudflareWorkerUrl))
          .timeout(const Duration(seconds: 4));
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {
      // Worker not reached or not deployed yet, fall back cleanly
    }
  }

  // 2. Fall back to GitHub raw check.json
  try {
    final response = await http
        .get(Uri.parse(fallbackCheckUrl))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode == 200) {
      return json.decode(response.body) as Map<String, dynamic>;
    }
  } catch (e, stackTrace) {
    logger.log(
      'Failed to fetch update config from all endpoints',
      error: e,
      stackTrace: stackTrace,
    );
  }

  return null;
}

Future<void> checkAppUpdates() {
  return _pendingUpdateCheck ??= _checkAppUpdates().whenComplete(() {
    _pendingUpdateCheck = null;
  });
}

Future<void> _checkAppUpdates() async {
  // Update distribution targets Android APK builds only.
  if (!isMobilePlatform) return;
  try {
    final map = await _fetchUpdateConfig();
    if (map == null) return;
    final latestVersion = map['version']?.toString() ?? '';
    final forceShutdown = map['force_shutdown'] == true;

    final isHigher = isLatestVersionHigher(appVersion, latestVersion);
    final isForced = isHigher || forceShutdown;

    if (!isHigher && !forceShutdown) {
      return;
    }

    if (isForced) {
      isAppBlockedByUpdate.value = true;
    }

    final releasesRequest = await http
        .get(Uri.parse(releasesUrl))
        .timeout(const Duration(seconds: 5));
    final releasesResponse = releasesRequest.statusCode == 200
        ? json.decode(releasesRequest.body) as Map<String, dynamic>
        : <String, dynamic>{};

    await showDialog(
      context: NavigationManager().context,
      barrierDismissible: !isForced,
      builder: (BuildContext context) {
        final colorScheme = Theme.of(context).colorScheme;

        return PopScope(
          canPop: !isForced,
          child: AlertDialog(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isForced
                        ? colorScheme.errorContainer
                        : colorScheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isForced
                        ? FluentIcons.warning_24_filled
                        : FluentIcons.arrow_download_24_regular,
                    color: isForced
                        ? colorScheme.onErrorContainer
                        : colorScheme.onPrimaryContainer,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  isForced
                      ? 'Update Required'
                      : context.l10n!.appUpdateIsAvailable,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'V$latestVersion',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height / 2.5,
                  ),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: SingleChildScrollView(
                    child: AutoFormatText(
                      text: isForced
                          ? 'This older version of Vybe has been shut down.\n\nYou must update to version $latestVersion to continue using the app.'
                          : (releasesResponse['body']?.toString() ?? ''),
                    ),
                  ),
                ),
              ],
            ),
            actionsAlignment: MainAxisAlignment.center,
            actions: <Widget>[
              if (isForced)
                OutlinedButton(
                  onPressed: SystemNavigator.pop,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colorScheme.outline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Exit App'),
                )
              else
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: colorScheme.outline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(context.l10n!.cancel),
                ),
              FilledButton.icon(
                onPressed: () {
                  getDownloadUrl(map).then((url) {
                    launchURL(Uri.parse(url));
                    if (!isForced) {
                      Navigator.pop(context);
                    }
                  });
                },
                icon: const Icon(FluentIcons.arrow_download_20_regular),
                label: Text(isForced ? 'Update Now' : context.l10n!.download),
              ),
            ],
          ),
        );
      },
    );
  } catch (e, stackTrace) {
    logger.log('Error in checkAppUpdates', error: e, stackTrace: stackTrace);
  }
}

void showUpdateCheckDialog(BuildContext context) {
  final colorScheme = Theme.of(context).colorScheme;

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        icon: Icon(
          FluentIcons.arrow_sync_circle_24_regular,
          color: colorScheme.primary,
          size: 40,
        ),
        title: Text(
          context.l10n!.checkForUpdates,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
          textAlign: TextAlign.center,
        ),
        content: Text(
          context.l10n!.enableUpdateChecksDescription,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton(
            onPressed: () {
              shouldWeCheckUpdates.value = false;
              addOrUpdateData<bool>('settings', 'shouldWeCheckUpdates', false);
              Navigator.of(context).pop();
            },
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: colorScheme.outline),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(context.l10n!.no),
          ),
          FilledButton(
            onPressed: () {
              shouldWeCheckUpdates.value = true;
              addOrUpdateData<bool>('settings', 'shouldWeCheckUpdates', true);
              if (!isFdroidBuild && kReleaseMode && !offlineMode.value) {
                checkAppUpdates();
                isUpdateChecked = true;
              }
              Navigator.of(context).pop();
            },
            child: Text(context.l10n!.yes),
          ),
        ],
      );
    },
  );
}

bool isLatestVersionHigher(String appVersion, String latestVersion) {
  final cleanApp = appVersion
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('^v'), '')
      .split('+')[0]
      .trim();
  final cleanLatest = latestVersion
      .trim()
      .toLowerCase()
      .replaceAll(RegExp('^v'), '')
      .split('+')[0]
      .trim();

  // If both versions are strictly identical, remote is NOT higher
  if (cleanApp == cleanLatest) {
    return false;
  }

  final parsedAppVersion = cleanApp.split('.');
  final parsedAppLatestVersion = cleanLatest.split('.');
  final length = parsedAppVersion.length > parsedAppLatestVersion.length
      ? parsedAppVersion.length
      : parsedAppLatestVersion.length;

  for (var i = 0; i < length; i++) {
    final segment1 = i < parsedAppVersion.length ? parsedAppVersion[i] : '0';
    final segment2 = i < parsedAppLatestVersion.length
        ? parsedAppLatestVersion[i]
        : '0';

    final value1 = int.tryParse(segment1) ?? 0;
    final value2 = int.tryParse(segment2) ?? 0;

    if (value2 > value1) {
      return true;
    } else if (value2 < value1) {
      return false;
    }
  }

  return false;
}

Future<String> getCPUArchitecture() async {
  final info = await Process.run('uname', ['-m']);
  final cpu = info.stdout.toString().replaceAll('\n', '');

  return cpu;
}

Future<String> getDownloadUrl(Map<String, dynamic> map) async {
  if (_isCompanionBuild) {
    final companion = map['companion_url'];
    if (companion is String && Uri.tryParse(companion)?.scheme == 'https') {
      return companion;
    }
    return 'https://github.com/Shubham-Loshali/Vybe/releases/latest';
  }
  final cpuArchitecture = await getCPUArchitecture();
  final url = cpuArchitecture == 'aarch64'
      ? map[downloadUrlArm64Key].toString()
      : map[downloadUrlKey].toString();

  return Uri.tryParse(url)?.scheme == 'https'
      ? url
      : 'https://github.com/Shubham-Loshali/Vybe/releases/latest';
}

/// Check for forced updates or updates safe to call for F‑Droid
/// builds where direct update download prompts are not allowed.
Future<void> fetchAnnouncementOnly() async {
  try {
    final map = await _fetchUpdateConfig();
    if (map == null) return;

    final latestVersion = map['version']?.toString();
    final forceShutdown = map['force_shutdown'] == true;
    if (forceShutdown ||
        (latestVersion != null &&
            isLatestVersionHigher(appVersion, latestVersion))) {
      isAppBlockedByUpdate.value = true;
      unawaited(checkAppUpdates());
    }
  } catch (e, stackTrace) {
    logger.log(
      'Error in fetchAnnouncementOnly',
      error: e,
      stackTrace: stackTrace,
    );
  }
}
