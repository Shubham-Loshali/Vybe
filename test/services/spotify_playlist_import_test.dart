import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vybe/services/spotify_playlist_import.dart';

const id = '3cEYpjA9oz9GiPac4AsH4n';

http.Response embedResponse({String playlistId = id}) {
  final entity = {
    'type': 'playlist',
    'id': playlistId,
    'name': 'रात की Playlist',
    'trackList': [
      {
        'uri': 'spotify:track:one',
        'title': 'Track B',
        'subtitle': 'Artist, Guest',
      },
      {'uri': 'spotify:episode:two', 'title': 'Episode', 'subtitle': 'Host'},
      {'uri': 'spotify:track:three', 'title': 'Track A', 'subtitle': 'Singer'},
    ],
  };
  final data = {
    'props': {
      'pageProps': {
        'state': {
          'data': {'entity': entity},
        },
      },
    },
  };
  return http.Response.bytes(
    utf8.encode(
      '<script id="__NEXT_DATA__" type="application/json">${jsonEncode(data)}</script>',
    ),
    200,
  );
}

http.Response pageResponse({int total = 1}) {
  final entity = {
    'name': 'Public page',
    'content': {
      'totalCount': total,
      'items': [
        {
          'itemV2': {
            'data': {
              'uri': 'spotify:track:one',
              'name': 'Track B',
              'artists': {
                'items': [
                  {
                    'profile': {'name': 'Artist'},
                  },
                ],
              },
            },
          },
        },
      ],
    },
  };
  final state = {
    'entities': {
      'items': {'spotify:playlist:$id': entity},
    },
  };
  final encoded = base64Encode(utf8.encode(jsonEncode(state)));
  return http.Response('<script id="initialState">$encoded</script>', 200);
}

void main() {
  test('validates playlist links and rejects lookalike hosts', () {
    expect(
      spotifyPlaylistId('https://open.spotify.com/intl-de/playlist/$id?si=abc'),
      id,
    );
    expect(spotifyPlaylistId('spotify:playlist:$id'), id);
    expect(spotifyPlaylistId('https://open.spotify.com/track/$id'), isNull);
    expect(
      spotifyPlaylistId('https://open.spotify.com.example.org/playlist/$id'),
      isNull,
    );
    expect(
      spotifyPlaylistId('https://open.spotify.com:444/playlist/$id'),
      isNull,
    );
  });

  test('resolves short links and keeps the public track order', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'spotify.link') {
        return http.Response(
          '',
          302,
          headers: {'location': 'https://open.spotify.com/playlist/$id?si=abc'},
        );
      }
      if (request.url.path == '/playlist/$id') return pageResponse(total: 3);
      expect(
        request.url.toString(),
        'https://open.spotify.com/embed/playlist/$id',
      );
      return embedResponse();
    });
    final playlist = await loadSpotifyPlaylist(
      'https://spotify.link/example',
      client: client,
    );
    expect(playlist.title, 'रात की Playlist');
    expect(playlist.tracks.map((track) => track.title), ['Track B', 'Track A']);
    expect(playlist.tracks.first.artist, 'Artist, Guest');
    expect(playlist.mayBeIncomplete, isFalse);
  });

  test('does not follow a short link to an unrelated site', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'spotify.link');
      return http.Response(
        '',
        302,
        headers: {'location': 'https://example.org/playlist/$id'},
      );
    });
    await expectLater(
      loadSpotifyPlaylist('https://spotify.link/example', client: client),
      throwsFormatException,
    );
  });

  test('uses the public page when the embed is unavailable', () async {
    final client = MockClient(
      (request) async => request.url.path.startsWith('/embed')
          ? http.Response('', 404)
          : pageResponse(),
    );
    final playlist = await loadSpotifyPlaylist(
      'spotify:playlist:$id',
      client: client,
    );
    expect(playlist.tracks.single.artist, 'Artist');
    expect(playlist.totalEntries, 1);
    expect(playlist.mayBeIncomplete, isFalse);
  });

  test('uses Spotify’s total to detect a partial embed', () async {
    final client = MockClient(
      (request) async => request.url.path.startsWith('/embed')
          ? embedResponse()
          : pageResponse(total: 245),
    );
    final playlist = await loadSpotifyPlaylist(
      'spotify:playlist:$id',
      client: client,
    );
    expect(playlist.tracks, hasLength(2));
    expect(playlist.totalEntries, 245);
    expect(playlist.mayBeIncomplete, isTrue);
  });

  test('reports a playlist with no published embed as unavailable', () async {
    final client = MockClient((_) async => http.Response('<html></html>', 200));
    await expectLater(
      loadSpotifyPlaylist('spotify:playlist:$id', client: client),
      throwsA(isA<SpotifyPlaylistUnavailable>()),
    );
  });
}
