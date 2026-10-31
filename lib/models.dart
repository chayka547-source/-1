/// Один трек. Может быть из каталога (Jamendo) или файлом с телефона.
class Track {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.source,
    this.album = '',
    this.coverUrl,
    this.streamUrl,
    this.downloadUrl,
    this.localFile,
    this.durationSec = 0,
  });

  /// Уникальный id: `jamendo:123` или `local:...`.
  final String id;
  final String title;
  final String artist;
  final String album;

  /// `jamendo` или `local`.
  final String source;
  final String? coverUrl;
  final String? streamUrl;
  final String? downloadUrl;

  /// Для файлов с телефона — имя файла внутри папки приложения.
  final String? localFile;
  final int durationSec;

  bool get isLocal => source == 'local';

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'source': source,
        'coverUrl': coverUrl,
        'streamUrl': streamUrl,
        'downloadUrl': downloadUrl,
        'localFile': localFile,
        'durationSec': durationSec,
      };

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        title: (j['title'] as String?) ?? '',
        artist: (j['artist'] as String?) ?? '',
        album: (j['album'] as String?) ?? '',
        source: (j['source'] as String?) ?? 'jamendo',
        coverUrl: j['coverUrl'] as String?,
        streamUrl: j['streamUrl'] as String?,
        downloadUrl: j['downloadUrl'] as String?,
        localFile: j['localFile'] as String?,
        durationSec: (j['durationSec'] as num?)?.toInt() ?? 0,
      );
}

/// Плейлист пользователя: просто имя и список id треков.
class UserPlaylist {
  UserPlaylist({required this.id, required this.name, List<String>? trackIds})
      : trackIds = trackIds ?? <String>[];

  final String id;
  String name;
  final List<String> trackIds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'trackIds': trackIds,
      };

  factory UserPlaylist.fromJson(Map<String, dynamic> j) => UserPlaylist(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'Плейлист',
        trackIds: List<String>.from((j['trackIds'] as List?) ?? const []),
      );
}
