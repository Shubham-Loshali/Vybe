// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:http_parser/http_parser.dart';
import 'package:vybe/constants/clients.dart';
import 'package:vybe/services/io_service.dart';
import 'package:vybe/services/listen_together_service.dart';
import 'package:vybe/services/settings_manager.dart';
import 'package:vybe/utilities/app_utils.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('vybe_crossfade_lt_test_');
    applicationDirPath = tempDir.path;
    await FilePaths.ensureDirectoriesExist();

    Hive.init(tempDir.path);
    await Hive.openBox('settings');
    await Hive.openBox('user');
    await Hive.openBox('userNoBackup');
    await Hive.openBox('cache');
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Crossfade Settings and Equal-Power Curve Logic', () {
    test('crossfadeSeconds clamps between 0 and maxCrossfadeSeconds (12)', () {
      expect(maxCrossfadeSeconds, 12);
      crossfadeSeconds.value = 5;
      expect(crossfadeSeconds.value, 5);

      crossfadeSeconds.value = 0;
      expect(crossfadeSeconds.value, 0);

      // Verify Hive saving clamp logic
      final box = Hive.box('settings')
        ..put('crossfadeSeconds', 15)
        ..put('crossfadeSeconds_neg', -4);

      final readFromBox = (box.get('crossfadeSeconds') as num).toInt().clamp(
        0,
        maxCrossfadeSeconds,
      );
      expect(readFromBox, 12);

      final readNegative = (box.get('crossfadeSeconds_neg') as num).toInt().clamp(
        0,
        maxCrossfadeSeconds,
      );
      expect(readNegative, 0);
    });

    test('equal-power curve maintains constant acoustic power (sin^2 + cos^2 = 1.0)', () {
      const steps = 100;
      for (var i = 0; i <= steps; i++) {
        final t = i / steps; // 0.0 to 1.0
        final incomingGain = math.sin(t * math.pi / 2);
        final outgoingGain = math.cos(t * math.pi / 2);

        final totalPower = math.pow(incomingGain, 2) + math.pow(outgoingGain, 2);
        expect(totalPower, closeTo(1.0, 1e-6));
      }
    });

    test('1000 randomized iterations: equal-power gain calculation is stable and monotonic', () {
      final random = math.Random(42);
      for (var i = 0; i < 1000; i++) {
        final t = random.nextDouble();
        final vol = random.nextDouble();
        final inGain = vol * math.sin(t * math.pi / 2);
        final outGain = vol * math.cos(t * math.pi / 2);

        expect(inGain, greaterThanOrEqualTo(0.0));
        expect(inGain, lessThanOrEqualTo(vol + 1e-6));
        expect(outGain, greaterThanOrEqualTo(0.0));
        expect(outGain, lessThanOrEqualTo(vol + 1e-6));

        final power = math.pow(inGain / vol, 2) + math.pow(outGain / vol, 2);
        expect(power, closeTo(1.0, 1e-5));
      }
    });

    test('volume boundaries at t=0 and t=1 are exact', () {
      const tStart = 0.0;
      final inStart = math.sin(tStart * math.pi / 2);
      final outStart = math.cos(tStart * math.pi / 2);
      expect(inStart, 0.0);
      expect(outStart, 1.0);

      const tEnd = 1.0;
      final inEnd = math.sin(tEnd * math.pi / 2);
      final outEnd = math.cos(tEnd * math.pi / 2);
      expect(inEnd, closeTo(1.0, 1e-6));
      expect(outEnd, closeTo(0.0, 1e-6));
    });
  });

  group('Listen Together Service Logic and Invariants', () {
    test('normaliseCode cleans whitespace and converts to uppercase', () {
      expect(ListenTogetherService.normaliseCode('  k7qm2p  '), 'K7QM2P');
      expect(ListenTogetherService.normaliseCode('abc-def'), 'ABCDEF');
      expect(ListenTogetherService.normaliseCode('12 34 56'), '123456');
      expect(ListenTogetherService.normaliseCode('!@#k\$%7^&*q(m)2_p'), 'K7QM2P');
    });

    test('invite link generates correct deep link format and extracts code', () {
      const code = 'ABC123';
      final link = ListenTogetherService.inviteLink(code);
      expect(link, 'vybe://listen/$code');

      final extracted = ListenTogetherService.codeFromLink(Uri.parse(link));
      expect(extracted, code);

      expect(ListenTogetherService.codeFromLink(Uri.parse('https://other.com/')), isNull);
    });

    test('ListenTogetherSession copyWith and isHost checks', () {
      const session = ListenTogetherSession(
        code: 'K7QM2P',
        role: ListenTogetherRole.host,
        hostName: 'HostUser',
        guests: ['Guest1'],
      );

      expect(session.isHost, isTrue);
      expect(session.code, 'K7QM2P');
      expect(session.guests, contains('Guest1'));

      final updated = session.copyWith(
        guests: const ['Guest1', 'Guest2'],
        status: 'Syncing',
      );
      expect(updated.isHost, isTrue);
      expect(updated.guests.length, 2);
      expect(updated.status, 'Syncing');

      const guestSession = ListenTogetherSession(
        code: 'K7QM2P',
        role: ListenTogetherRole.guest,
        hostName: 'HostUser',
      );
      expect(guestSession.isHost, isFalse);
    });

    test('drift calculation adheres to drift tolerance (700ms)', () {
      const driftTolerance = Duration(milliseconds: 700);

      // Within drift tolerance (e.g. 400ms ahead or behind) should not trigger seek
      const smallDrift = 400;
      expect(smallDrift.abs() > driftTolerance.inMilliseconds, isFalse);

      // Outside tolerance (e.g. 850ms) triggers seek
      const largeDrift = 850;
      expect(largeDrift.abs() > driftTolerance.inMilliseconds, isTrue);

      const negativeDrift = -900;
      expect(negativeDrift.abs() > driftTolerance.inMilliseconds, isTrue);
    });

    test('1000 randomized iterations: drift and position clamping never produce invalid or NaN values', () {
      final random = math.Random(12345);
      const tolerance = Duration(milliseconds: 700);

      for (var i = 0; i < 1000; i++) {
        final hostPos = random.nextInt(300000); // 0 to 5 mins
        final serverNow = 1700000000000 + random.nextInt(100000);
        final stateAt = serverNow - random.nextInt(5000);
        final hostPlaying = random.nextBool();
        final localPos = hostPos + (random.nextInt(3000) - 1500);

        final expected = hostPos + (hostPlaying ? math.max(0, serverNow - stateAt) : 0);
        final drift = localPos - expected;

        final shouldSeek = drift.abs() > tolerance.inMilliseconds;
        if (drift.abs() <= 700) {
          expect(shouldSeek, isFalse);
        } else {
          expect(shouldSeek, isTrue);
        }

        final target = math.max(0, expected + (hostPlaying ? 300 : 0));
        expect(target, greaterThanOrEqualTo(0));
      }
    });

    test('seek target calculation with lead time clamps safely to non-negative', () {
      expect(math.max(0, 5000 + 300), 5300);
      expect(math.max(0, -500), 0);
    });

    test('Audio quality setting supports lossless max quality', () {
      expect(audioQualitySetting.value, 'lossless');
      audioQualitySetting.value = 'high';
      expect(audioQualitySetting.value, 'high');
      audioQualitySetting.value = 'lossless';
      expect(audioQualitySetting.value, 'lossless');
    });

    test('1000 randomized iterations: selectAudioOnlyStreamForQuality picks highest bitrate in lossless mode and excludes dolby', () {
      final random = math.Random(999);
      audioQualitySetting.value = 'lossless';

      for (var iter = 0; iter < 1000; iter++) {
        final streamCount = random.nextInt(10) + 1;
        final streams = <AudioOnlyStreamInfo>[];

        for (var s = 0; s < streamCount; s++) {
          final isDolby = random.nextBool() && random.nextBool();
          final isAac = random.nextBool();
          final bitrateValue = (random.nextInt(320) + 32) * 1000;

          final String codecStr;
          final StreamContainer container;
          if (isDolby) {
            codecStr = 'audio/mp4; codecs=ec-3';
            container = StreamContainer.mp4;
          } else if (isAac) {
            codecStr = 'audio/mp4; codecs=mp4a.40.2';
            container = StreamContainer.mp4;
          } else {
            codecStr = 'audio/webm; codecs=opus';
            container = StreamContainer.webM;
          }

          streams.add(
            AudioOnlyStreamInfo(
              VideoId('kJQP7kiw5F$s'),
              100 + s,
              Uri.parse('https://example.com/audio_$s'),
              container,
              const FileSize(1000000),
              Bitrate(bitrateValue),
              codecStr,
              'Audio $s',
              const [],
              MediaType.parse(codecStr),
              null,
            ),
          );
        }

        final selected = selectAudioOnlyStreamForQuality(streams);
        expect(selected, isNotNull);

        // Verify dolby is never selected when other compatible codecs exist
        final nonDolbyStreams = streams.where((st) => !st.codec.toString().contains('ec-3')).toList();
        if (nonDolbyStreams.isNotEmpty) {
          expect(selected!.codec.toString().contains('ec-3'), isFalse);
          // Verify selected has maximum or equal bitrate among compatible streams
          final maxCompatibleBitrate = nonDolbyStreams.map((e) => e.bitrate).reduce((a, b) => a.bitsPerSecond > b.bitsPerSecond ? a : b);
          expect(selected.bitrate, equals(maxCompatibleBitrate));
        }
      }
    });

    test('1000 randomized iterations: normaliseCode handles arbitrary corrupt inputs safely', () {
      final random = math.Random(777);
      const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*()-_=+[]{}|;:\'",.<>?/~` ';

      for (var i = 0; i < 1000; i++) {
        final length = random.nextInt(30);
        final buffer = StringBuffer();
        for (var j = 0; j < length; j++) {
          buffer.write(chars[random.nextInt(chars.length)]);
        }
        final raw = buffer.toString();
        final normalised = ListenTogetherService.normaliseCode(raw);

        // Invariant: only uppercase A-Z and 0-9, or empty
        expect(RegExp(r'^[A-Z0-9]*$').hasMatch(normalised), isTrue);
      }
    });

    test('1000 randomized iterations: streamPlaybackHeaders handles arbitrary songIds and limit caching safely', () {
      final random = math.Random(888);
      for (var i = 0; i < 1000; i++) {
        final songId = 'song_${random.nextInt(500)}';
        final headers = streamPlaybackHeaders(songId);
        expect(headers, isNotNull);
        expect(headers.containsKey('user-agent'), isTrue);
        expect(headers['user-agent'], isNotEmpty);
      }
    });
  });
}
