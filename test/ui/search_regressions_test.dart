import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/screens/search_page.dart';
import 'package:vybe/widgets/custom_search_bar.dart';

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
  setUp(() => searchHistoryNotifier.value = []);

  Widget search({
    Future<List<dynamic>> Function(String)? songs,
    Future<List<String>> Function(String)? suggestions,
  }) => uiApp(
    SearchPage(
      songSearch: songs ?? (_) async => [],
      artistSearch: (_) async => [],
      playlistSearch: (_, __) async => [],
      suggestionSearch: suggestions ?? (_) async => [],
    ),
  );

  testWidgets(
    'an older search cannot restore results or close a newly focused keyboard',
    (tester) async {
      final old = Completer<List<dynamic>>();
      final current = Completer<List<dynamic>>();
      await tester.pumpWidget(
        search(songs: (query) => query == 'old' ? old.future : current.future),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'old');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'new');
      await tester.pump();
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue);
      old.complete([
        {'ytid': 'old', 'title': 'Old result', 'artist': 'Old artist'},
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Old result'), findsNothing);
      expect(field.focusNode!.hasFocus, isTrue);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      current.complete([
        {'ytid': 'new', 'title': 'New result', 'artist': 'New artist'},
      ]);
      await tester.pumpAndSettle();
      expect(find.text('New result'), findsOneWidget);
      expect(find.text('Old result'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'clearing a submitted search invalidates responses still in flight',
    (tester) async {
      final pending = Completer<List<dynamic>>();
      await tester.pumpWidget(search(songs: (_) => pending.future));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'pending');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      pending.complete([
        {'ytid': 'pending', 'title': 'Stale result', 'artist': 'Artist'},
      ]);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      expect(find.text('Stale result'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('only suggestions for the latest typed query appear', (
    tester,
  ) async {
    final old = Completer<List<String>>();
    final current = Completer<List<String>>();
    await tester.pumpWidget(
      search(
        suggestions: (query) => query == 'old' ? old.future : current.future,
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'old');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byType(TextField), 'new');
    await tester.pump(const Duration(milliseconds: 350));
    old.complete(['Old suggestion']);
    await tester.pump();
    expect(find.text('Old suggestion'), findsNothing);
    current.complete(['New suggestion']);
    await tester.pumpAndSettle();
    expect(find.text('New suggestion'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed suggestion requests do not crash the search screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      search(suggestions: (_) async => throw Exception('Unavailable')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'song');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets(
    'a search finishing after disposal never updates a disposed notifier',
    (tester) async {
      final pending = Completer<List<dynamic>>();
      await tester.pumpWidget(search(songs: (_) => pending.future));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'pending');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      pending.complete([]);
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty results show an empty state instead of unrelated search history',
    (tester) async {
      searchHistoryNotifier.value = ['Previous unrelated query'];
      await tester.pumpWidget(search());
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'unknown song');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Previous unrelated query'), findsNothing);
      expect(find.textContaining('No results found'), findsOneWidget);
    },
  );

  testWidgets('programmatic text changes refresh the clear button', (
    tester,
  ) async {
    final controller = TextEditingController();
    final focus = FocusNode();
    await tester.pumpWidget(
      uiApp(
        CustomSearchBar(
          controller: controller,
          focusNode: focus,
          labelText: 'Search',
          onSubmitted: (_) {},
        ),
      ),
    );
    expect(find.byTooltip('Clear search'), findsNothing);
    controller.text = 'A saved search';
    await tester.pump();
    expect(find.byTooltip('Clear search'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(controller.text, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    focus.dispose();
  });
}
