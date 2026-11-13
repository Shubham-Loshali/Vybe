import 'package:flutter_test/flutter_test.dart';
import 'package:vybe/utilities/account_name.dart';

import '../support/test_account_user.dart';

void main() {
  test('uses the current account display name and handles whitespace', () {
    expect(
      accountFirstName(TestAccountUser(displayName: '  Sasha   Verma  ')),
      'Sasha',
    );
    expect(
      accountFirstName(TestAccountUser(displayName: 'María\tGarcía')),
      'María',
    );
    expect(
      accountFirstName(TestAccountUser(displayName: 'दीपक डुमका')),
      'दीपक',
    );
  });

  test('email-only accounts derive a name from their own email address', () {
    expect(
      accountFirstName(TestAccountUser(email: 'sasha.patel+music@example.com')),
      'Sasha',
    );
    expect(
      accountFirstName(
        TestAccountUser(displayName: '  ', email: 'morgan_lee@example.com'),
      ),
      'Morgan',
    );
    expect(accountFirstName(TestAccountUser()), '');
  });

  test('signed-out, anonymous and unverified accounts do not show a name', () {
    expect(accountFirstName(null), '');
    expect(
      accountFirstName(
        TestAccountUser(displayName: 'Old name', isAnonymous: true),
      ),
      '',
    );
    expect(
      accountFirstName(
        TestAccountUser(displayName: 'New account', emailVerified: false),
      ),
      '',
    );
  });
}
