import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vybe/services/lyrics/lyrics_models.dart';
import 'package:vybe/widgets/now_playing/synced_lyrics_view.dart';

String lineText(int i) => i % 3 == 0
    ? 'Line $i · लम्बी पंक्ति जो छोटे पर्दे पर कई पंक्तियों में दिखाई देती है'
    : 'Line $i';

Lyrics makeLyrics({int count = 45}) => Lyrics(
  source: 'test',
  synced: List.generate(
    count,
    (i) => LyricLine(Duration(seconds: i * 3), lineText(i)),
  ),
);

void main() {
  late StreamController<Duration> positions;
  late List<Duration> seeks;
  setUp(() {
    positions = StreamController<Duration>.broadcast();
    seeks = [];
  });
  tearDown(() async {
    await positions.close();
  });

  Widget view(
    Lyrics lyrics, {
    Duration initial = Duration.zero,
    double scale = 1,
  }) => MaterialApp(
    theme: ThemeData.dark(),
    home: MediaQuery(
      data: MediaQueryData(
        size: const Size(390, 700),
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(
        body: SyncedLyricsView(
          lyrics: lyrics,
          positionStream: positions.stream,
          initialPosition: initial,
          onSeek: seeks.add,
        ),
      ),
    ),
  );

  Color? lineColor(WidgetTester tester, int i) => tester
      .widget<AnimatedDefaultTextStyle>(
        find
            .ancestor(
              of: find.text(lineText(i)),
              matching: find.byType(AnimatedDefaultTextStyle),
            )
            .first,
      )
      .style
      .color;

  testWidgets('moves the glow between words before advancing the line', (
    tester,
  ) async {
    const lyrics = Lyrics(
      source: 'fixture',
      synced: [
        LyricLine(
          Duration.zero,
          'First second third',
          wordCues: [
            (wordIndex: 0, start: Duration.zero),
            (wordIndex: 1, start: Duration(milliseconds: 350)),
            (wordIndex: 2, start: Duration(milliseconds: 900)),
          ],
        ),
        LyricLine(Duration(seconds: 4), 'Next line'),
      ],
    );
    await tester.pumpWidget(view(lyrics));
    await tester.pumpAndSettle();
    double brightness(String word) {
      final text = tester.widget<Text>(find.text('First second third'));
      return (text.textSpan as TextSpan).children!
          .whereType<TextSpan>()
          .singleWhere((span) => span.text == word)
          .style!
          .color!
          .a;
    }

    final initial = brightness('First');
    positions.add(const Duration(milliseconds: 240));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 45));
    final midway = brightness('First');
    expect(midway, greaterThan(initial));
    await tester.pumpAndSettle();
    expect(brightness('First'), greaterThan(midway));
    expect(brightness('second'), closeTo(initial, 0.001));
    positions.add(const Duration(milliseconds: 580));
    await tester.pumpAndSettle();
    expect(brightness('second'), greaterThan(initial));
    expect(brightness('third'), closeTo(initial, 0.001));
    positions.add(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(brightness('second'), closeTo(initial, 0.001));
  });

  testWidgets('opens at the current line even when playback is paused', (
    tester,
  ) async {
    await tester.pumpWidget(
      view(makeLyrics(), initial: const Duration(seconds: 60)),
    );
    await tester.pumpAndSettle();
    expect(lineColor(tester, 20), Colors.white);
    final bounds = tester.getRect(find.text(lineText(20)));
    expect(bounds.top, greaterThanOrEqualTo(0));
    expect(bounds.bottom, lessThan(600));
  });

  testWidgets(
    'follows long wrapped lines and both forward and backward seeks',
    (tester) async {
      await tester.pumpWidget(view(makeLyrics()));
      await tester.pumpAndSettle();
      for (final index in [30, 6, 44]) {
        positions.add(Duration(seconds: index * 3));
        await tester.pumpAndSettle();
        expect(lineColor(tester, index), Colors.white);
        final bounds = tester.getRect(find.text(lineText(index)));
        expect(bounds.top, greaterThanOrEqualTo(0));
        expect(bounds.bottom, lessThan(600));
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'manual scrolling resumes following without a new playback event',
    (tester) async {
      await tester.pumpWidget(
        view(makeLyrics(), initial: const Duration(seconds: 30)),
      );
      await tester.pumpAndSettle();
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -180),
      );
      await tester.pumpAndSettle();
      expect(find.text('Follow song'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(find.text('Follow song'), findsNothing);
      expect(
        tester.getRect(find.text(lineText(10))).top,
        greaterThanOrEqualTo(0),
      );
    },
  );

  testWidgets(
    'line taps seek using the adjusted timing and reset for a new song',
    (tester) async {
      await tester.pumpWidget(
        view(makeLyrics(), initial: const Duration(seconds: 12)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Show lyrics earlier'));
      await tester.pumpAndSettle();
      expect(find.text('Timing +0.5s'), findsOneWidget);
      await tester.tap(find.text(lineText(4)));
      expect(seeks.single, const Duration(milliseconds: 11500));
      await tester.pumpWidget(view(makeLyrics(count: 3)));
      await tester.pumpAndSettle();
      expect(find.text('Timing 0.0s'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('small screens and large text wrap without layout overflows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(view(makeLyrics(count: 3), scale: 1.7));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
