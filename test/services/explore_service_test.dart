import 'package:flutter_test/flutter_test.dart';
import 'package:vybe/services/explore_service.dart';
import 'package:vybe/services/playlists_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExploreService', () {
    test('fallback chart playlists include regional and global hits', () {
      const playlists = ExploreService.fallbackChartPlaylists;
      expect(playlists, isNotEmpty);
      expect(
        playlists.any((p) => p['title'].toString().contains('India')),
        isTrue,
      );
      expect(
        playlists.any((p) => p['title'].toString().contains('Global') || p['title'].toString().contains('Hollywood')),
        isTrue,
      );
      for (final p in playlists) {
        expect(p['ytid'], isNotNull);
        expect((p['ytid'] as String).startsWith('VL'), isFalse);
      }
    });

    test('fallback artists include popular Bollywood and international singers', () {
      const artists = ExploreService.fallbackArtists;
      expect(artists, isNotEmpty);
      expect(artists.any((a) => a['title'] == 'Arijit Singh'), isTrue);
      expect(artists.any((a) => a['title'] == 'Shreya Ghoshal'), isTrue);
      for (final a in artists) {
        expect(a['isArtist'], isTrue);
        expect((a['ytid'] as String).startsWith('UC'), isTrue);
      }
    });

    test('isArtistPlaylist identifies artists from ExploreService', () {
      final artist = ExploreService.fallbackArtists.first;
      expect(isArtistPlaylist(artist), isTrue);

      final playlist = ExploreService.fallbackChartPlaylists.first;
      expect(isArtistPlaylist(playlist), isFalse);
    });
  });
}
