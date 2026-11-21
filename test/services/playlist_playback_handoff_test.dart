import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
// The platform interface lets the real handler and just_audio run without Android.
// ignore: depend_on_referenced_packages
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:vybe/services/audio_service.dart';
import 'package:vybe/services/data_manager.dart';
import 'package:vybe/services/settings_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;

  setUpAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          (_) async => null,
        );
    directory = await Directory.systemTemp.createTemp('vybe-handoff-');
    Hive.init(directory.path);
    for (final name in ['settings', 'user', 'userNoBackup', 'cache']) {
      await Hive.openBox(name);
    }
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.ryanheise.audio_session'),
          null,
        );
    await Hive.close();
    await directory.delete(recursive: true);
  });

  for (final downloaded in [false, true]) {
    final kind = downloaded ? 'downloaded' : 'collaborative';
    test(
      '$kind playlist switches source before publishing the new track',
      () async {
        final originalPlatform = JustAudioPlatform.instance;
        final platform = _PlaybackPlatform();
        JustAudioPlatform.instance = platform;
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        final audio = VybeAudioHandler();
        addTearDown(() async {
          await audio.stop();
          await audio.audioPlayer.dispose();
          debugDefaultTargetPlatformOverride = null;
          JustAudioPlatform.instance = originalPlatform;
          offlineMode.value = false;
        });
        offlineMode.value = downloaded;

        final songs = <Map<String, dynamic>>[];
        final sources = <String>[];
        for (final number in [1, 2]) {
          final id = '$kind-track-$number';
          final song = <String, dynamic>{
            'ytid': id,
            'title': 'Track $number',
            'highResImage': 'https://example.com/$id.jpg',
          };
          if (downloaded) {
            final file = await File('${directory.path}/$id.m4a')
                .writeAsBytes([number]);
            song['audioPath'] = file.path;
            sources.add(file.uri.toString());
          } else {
            final url = 'https://example.com/$id.m4a';
            await addOrUpdateData(
              'cache',
              'song_${id}_${audioQualitySetting.value}_url',
              url,
            );
            sources.add(url);
          }
          songs.add(song);
        }
        final playlist = {'list': songs, 'isCollaborative': !downloaded};

        final firstStarted = platform.started.first;
        await audio.playPlaylistSong(playlist: playlist, songIndex: 0);
        expect(await firstStarted, sources.first);
        expect(audio.mediaItem.value?.extras?['ytid'], songs[0]['ytid']);

        final requested = platform.loading.first;
        final secondStarted = platform.started.first;
        platform.failNextPause = downloaded;
        final gate = platform.loadGate = Completer<void>();
        addTearDown(() {
          if (!gate.isCompleted) gate.complete();
        });
        final transition = audio.playPlaylistSong(
          playlist: playlist,
          songIndex: 1,
        );
        expect(await requested, sources.last);
        expect(platform.audibleSource, isNull);
        expect(audio.mediaItem.value?.title, 'Track 1');
        await audio.play();
        expect(platform.audibleSource, isNull);

        gate.complete();
        await transition;
        expect(await secondStarted, sources.last);
        expect(platform.audibleSource, sources.last);
        final item = audio.mediaItem.value!;
        expect(item.extras?['ytid'], songs[1]['ytid']);
        expect(item.title, 'Track 2');
        expect(item.artUri.toString(), songs[1]['highResImage']);
        expect(audio.playbackState.value.queueIndex, 1);
      },
    );
  }
}

class _PlaybackPlatform extends JustAudioPlatform {
  final _loading = StreamController<String>.broadcast();
  final _started = StreamController<String>.broadcast();
  Stream<String> get loading => _loading.stream;
  Stream<String> get started => _started.stream;
  Completer<void>? loadGate;
  bool failNextPause = false;
  String? audibleSource;
  final players = <String, _PlatformPlayer>{};

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async =>
      players[request.id] = _PlatformPlayer(request.id, this);

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async {
    await players.remove(request.id)?.events.close();
    audibleSource = null;
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async => DisposeAllPlayersResponse();
}

class _PlatformPlayer extends AudioPlayerPlatform {
  _PlatformPlayer(super.id, this.platform);

  final _PlaybackPlatform platform;
  final events = StreamController<PlaybackEventMessage>();
  String? _loadedSource;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => events.stream;

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    final playlist =
        request.audioSourceMessage as ConcatenatingAudioSourceMessage;
    final source = (playlist.children.single as UriAudioSourceMessage).uri;
    platform._loading.add(source);
    await platform.loadGate?.future;
    _loadedSource = source;
    const duration = Duration(minutes: 3);
    events.add(
      PlaybackEventMessage(
        processingState: ProcessingStateMessage.ready,
        updateTime: DateTime.now(),
        updatePosition: Duration.zero,
        bufferedPosition: duration,
        duration: duration,
        icyMetadata: null,
        currentIndex: 0,
        androidAudioSessionId: null,
      ),
    );
    return LoadResponse(duration: duration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    platform.audibleSource = _loadedSource;
    platform._started.add(_loadedSource!);
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    if (platform.failNextPause) {
      platform.failNextPause = false;
      throw PlatformException(code: 'pause-failed');
    }
    platform.audibleSource = null;
    return PauseResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async =>
      SetVolumeResponse();

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async =>
      SetSpeedResponse();

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async =>
      SetLoopModeResponse();

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async => SetShuffleModeResponse();
}
