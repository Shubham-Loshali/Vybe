import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vybe/constants/version.dart';
import 'package:vybe/services/update_manager.dart';

void main() {
  test(
    'rollout blocks older versions without disabling 10.6.8 or future builds',
    () {
      final policy = jsonDecode(
        File('workers/update-policy/check.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final fallbackPolicy = jsonDecode(File('check.json').readAsStringSync());
      expect(fallbackPolicy, policy);
      final target = policy['version'] as String;
      // A local QA build can be newer than the last published update.
      expect(isLatestVersionHigher(appVersion, target), isFalse);
      expect(policy['force_shutdown'], isFalse);
      expect(isLatestVersionHigher('10.6.2', target), isTrue);
      expect(isLatestVersionHigher('10.6.3', target), isTrue);
      expect(isLatestVersionHigher('v10.6.3+206', target), isTrue);
      expect(isLatestVersionHigher('10.6.4', target), isTrue);
      expect(isLatestVersionHigher('v10.6.4+207', target), isTrue);
      expect(isLatestVersionHigher('10.6.5', target), isTrue);
      expect(isLatestVersionHigher('v10.6.5+208', target), isTrue);
      expect(isLatestVersionHigher('10.6.6', target), isTrue);
      expect(isLatestVersionHigher('v10.6.6+217', target), isTrue);
      expect(isLatestVersionHigher('10.6.7', target), isTrue);
      expect(isLatestVersionHigher('v10.6.7+214', target), isTrue);
      expect(isLatestVersionHigher('10.6.8', target), isFalse);
      expect(isLatestVersionHigher('v10.6.8+218', target), isFalse);
      expect(isLatestVersionHigher('10.6.9', target), isFalse);
      expect(policy['minimum_version'], target);
      expect(
        policy['blocked_versions'],
        containsAll(['10.6.0', '10.6.1', '10.6.2', '10.6.3', '10.6.4', '10.6.5', '10.6.6', '10.6.7']),
      );
      expect(policy['blocked_versions'], isNot(contains(target)));
      for (final name in ['url', 'arm64url', 'companion_url']) {
        expect(Uri.parse(policy[name] as String).scheme, 'https');
        expect(policy[name], contains('/v10.6.8/'));
      }
      expect(policy['url'], endsWith('/Vybe.apk'));
      expect(policy['arm64url'], policy['url']);
      expect(policy['companion_url'], endsWith('/companion/Vybe.apk'));
      expect(Uri.parse(policy['companion_url'] as String).host,
          'vybe.shubham-loshali18.workers.dev');
    },
  );
}
