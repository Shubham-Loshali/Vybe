import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/constants/version.dart';
import 'package:vybe/services/common_services.dart';
import 'package:vybe/widgets/whats_new_sheet.dart';

import '../support/ui_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final audio = UiTestAudioHandler();
  late Directory directory;
  setUpAll(() async {
    directory = await openUiLibrary(audio);
  });
  tearDownAll(() async {
    await audio.close();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      uiApp(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showWhatsNewIfUpdated(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows once after an update, then never again', (tester) async {
    final previous = userRecentlyPlayed.value;
    addTearDown(() => userRecentlyPlayed.value = previous);
    userRecentlyPlayed.value = [
      {'ytid': 'listened', 'title': 'A song from before the update'},
    ];
    await Hive.box('settings').put('whatsNewSeenVersion', '0.0.1');

    await open(tester);
    expect(find.text("What's new in Vybe"), findsOneWidget);
    expect(
      find.textContaining(whatsNewHighlights.first.$2, findRichText: true),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('Got it'));
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text("What's new in Vybe"), findsNothing);

    await open(tester);
    expect(find.text("What's new in Vybe"), findsNothing);
    expect(Hive.box('settings').get('whatsNewSeenVersion'), appVersion);
  });

  testWidgets('Dismiss closes the announcement', (tester) async {
    final previous = userRecentlyPlayed.value;
    addTearDown(() => userRecentlyPlayed.value = previous);
    userRecentlyPlayed.value = [
      {'ytid': 'listened', 'title': 'A song from before the update'},
    ];
    await Hive.box('settings').put('whatsNewSeenVersion', '0.0.1');

    await open(tester);
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text("What's new in Vybe"), findsNothing);
  });

  testWidgets('a fresh install is only marked as seen', (tester) async {
    final previous = userRecentlyPlayed.value;
    addTearDown(() => userRecentlyPlayed.value = previous);
    userRecentlyPlayed.value = [];
    await Hive.box('settings').delete('whatsNewSeenVersion');

    await open(tester);
    expect(find.text("What's new in Vybe"), findsNothing);
    expect(Hive.box('settings').get('whatsNewSeenVersion'), appVersion);
  });
}
