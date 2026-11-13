import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vybe/constants/version.dart';
import 'package:vybe/services/update_manager.dart';

void main() {
  test(
    'rollout blocks older versions without disabling 10.6.5 or future builds',
    () {
      final policy = jsonDecode(
        File('workers/update-policy/check.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final fallbackPolicy = jsonDecode(File('check.json').readAsStringSync());
      expect(fallbackPolicy, policy);
      final target = policy['version'] as String;
      expect(target, appVersion);
      expect(policy['force_shutdown'], isFalse);
      expect(isLatestVersionHigher('10.6.2', target), isTrue);
      expect(isLatestVersionHigher('10.6.3', target), isTrue);
      expect(isLatestVersionHigher('v10.6.3+206', target), isTrue);
      expect(isLatestVersionHigher('10.6.4', target), isTrue);
      expect(isLatestVersionHigher('v10.6.4+207', target), isTrue);
      expect(isLatestVersionHigher('10.6.5', target), isFalse);
      expect(isLatestVersionHigher('v10.6.5+208', target), isFalse);
      expect(isLatestVersionHigher('10.6.6', target), isFalse);
      expect(policy['minimum_version'], target);
      expect(
        policy['blocked_versions'],
        containsAll(['10.6.0', '10.6.1', '10.6.2', '10.6.3', '10.6.4']),
      );
      expect(policy['blocked_versions'], isNot(contains(target)));
      for (final name in ['url', 'arm64url', 'companion_url']) {
        expect(Uri.parse(policy[name] as String).scheme, 'https');
        expect(policy[name], contains('/v10.6.5/'));
      }
    },
  );
}
