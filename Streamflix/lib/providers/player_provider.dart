import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/storage.dart';
import '../models/media.dart';

class PlayerSession {
  final String streamId;
  final String streamUrl;
  final MediaItem media;
  final String? magnetURI;
  final int? fileIdx;
  final int? season;
  final int? episode;

  const PlayerSession({
    required this.streamId,
    required this.streamUrl,
    required this.media,
    this.magnetURI,
    this.fileIdx,
    this.season,
    this.episode,
  });
}

class PlayerNotifier extends Notifier<PlayerSession?> {
  @override
  PlayerSession? build() => null;

  void setStream(
    String streamId,
    String streamUrl,
    MediaItem media, {
    String? magnetURI,
    int? fileIdx,
    int? season,
    int? episode,
  }) {
    state = PlayerSession(
      streamId: streamId,
      streamUrl: streamUrl,
      media: media,
      magnetURI: magnetURI,
      fileIdx: fileIdx,
      season: season,
      episode: episode,
    );
    // Persist a lightweight session for resume.
    AppStorage.instance.playerSession = {
      'streamId': streamId,
      'streamUrl': streamUrl,
      'mediaId': media.id,
      'mediaType': media.mediaType,
      'title': media.title,
      'imdbId': media.imdbId,
    };
  }

  void clear() {
    state = null;
    AppStorage.instance.playerSession = null;
  }
}

final playerProvider = NotifierProvider<PlayerNotifier, PlayerSession?>(PlayerNotifier.new);
