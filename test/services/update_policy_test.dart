import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vybe/constants/version.dart';
import 'package:vybe/services/update_manager.dart';

void main() {
  test(
    'rollout blocks 10.6.2 without disabling the replacement or future builds',
    () {
      final policy = jsonDecode(
        File('workers/update-policy/check.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final target = policy['version'] as String;
      expect(target, appVersion);
      expect(policy['force_shutdown'], isFalse);
      expect(isLatestVersionHigher('10.6.2', target), isTrue);
      expect(isLatestVersionHigher('10.6.3', target), isFalse);
      expect(isLatestVersionHigher('v10.6.3+206', target), isFalse);
      expect(isLatestVersionHigher('10.6.4', target), isFalse);
      for (final name in ['url', 'arm64url', 'companion_url']) {
        expect(Uri.parse(policy[name] as String).scheme, 'https');
        expect(policy[name], contains('/v10.6.3/'));
      }
    },
  );
}
