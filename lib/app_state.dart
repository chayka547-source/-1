import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';

import 'core/id3.dart';
import 'models.dart';
import 'sources/jamendo.dart';

/// Нужен, чтобы показывать сообщения из любого места приложения.
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// Всё состояние приложения: медиатека, плейлисты, загрузки, плеер.
class AppState extends ChangeNotifier {
  AppState();

  final AudioPlayer player = AudioPlayer();

  late final Directory _docs;
  late final Directory musicDir;
  late final File _dbFile;

  /// Все треки, на которые что-то ссылается (медиатека, плейлисты, загрузки).
  final Map<String, Track> tracks = {};

  /// Id треков в медиатеке, новые сверху.
  final List<String> favorites = [];
  final List<UserPlaylist> playlists = [];

  /// id трека -> имя скачанного файла.
  final Map<String, String> downloads = {};
  final Map<String, double> downloadProgress = {};

  String jamendoClientId = '';

  List<Track> queue = [];
  int currentIndex = -1;

  JamendoSource get jamendo => JamendoSource(jamendoClientId);

  Track? get current =>
      (currentIndex >= 0 && currentIndex < queue.length)
          ? queue[currentIndex]
          : null;

  // ---------------------------------------------------------------- init ---

  Future<void> init() async {
    _docs = await getApplicationDocumentsDirectory();
    musicDir = Directory('${_docs.path}/music');
    if (!musicDir.existsSync()) musicDir.createSync(recursive: true);
    _dbFile = File('${_docs.path}/volna.json');
    await _load();
    _pruneMissingFiles();

    player.currentIndexStream.listen((i) {
      if (i != null && i != currentIndex) {
        currentIndex = i;
        notifyListeners();
      }
    });
    player.playerStateStream.listen((_) => notifyListeners());
  }

  Future<void> _load() async {
    try {
      if (!_dbFile.existsSync()) return;
      final j = jsonDecode(await _dbFile.readAsString());
      if (j is! Map) return;
      jamendoClientId = (j['jamendoClientId'] as String?) ?? '';
      for (final t in (j['tracks'] as List?) ?? const []) {
        final tr = Track.fromJson(Map<String, dynamic>.from(t as Map));
        tracks[tr.id] = tr;
      }
      favorites
        ..clear()
        ..addAll(List<String>.from((j['favorites'] as List?) ?? const []));
      playlists
        ..clear()
        ..addAll(((j['playlists'] as List?) ?? const []).map(
            (p) => UserPlaylist.fromJson(Map<String, dynamic>.from(p as Map))));
      downloads
        ..clear()
        ..addAll(Map<String, String>.from((j['downloads'] as Map?) ?? const {}));
    } catch (e) {
      debugPrint('load error: $e');
    }
  }

  /// Забывает треки, чьи файлы пропали (например, их удалили через файловый менеджер).
  void _pruneMissingFiles() {
    downloads.removeWhere(
        (id, name) => !File('${musicDir.path}/$name').existsSync());
    final lost = tracks.values
        .where((t) =>
            t.isLocal &&
            (t.localFile == null ||
                !File('${musicDir.path}/${t.localFile}').existsSync()))
        .map((t) => t.id)
        .toList();
    for (final id in lost) {
      tracks.remove(id);
      favorites.remove(id);
      for (final p in playlists) {
        p.trackIds.remove(id);
      }
    }
  }

  Future<void> _save() async {
    final used = <String>{...favorites, ...downloads.keys};
    for (final p in playlists) {
      used.addAll(p.trackIds);
    }
    tracks.removeWhere((id, t) => !t.isLocal && !used.contains(id));
    final data = {
      'jamendoClientId': jamendoClientId,
      'tracks': tracks.values.map((t) => t.toJson()).toList(),
      'favorites': favorites,
      'playlists': playlists.map((p) => p.toJson()).toList(),
      'downloads': downloads,
    };
    try {
      await _dbFile.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint('save error: $e');
    }
  }

  void _commit() {
    notifyListeners();
    unawaited(_save());
  }

  void say(String message) {
    final m = messengerKey.currentState;
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(content: Text(message)));
  }

  static String shortError(Object e) {
    var s = e.toString();
    s = s.replaceFirst('Exception: ', '');
    return s.length > 120 ? '${s.substring(0, 120)}…' : s;
  }

  // ------------------------------------------------------------ settings ---

  void setClientId(String id) {
    jamendoClientId = id.trim();
    _commit();
  }

  // ------------------------------------------------------------- library ---

  List<Track> get libraryTracks =>
      favorites.map((id) => tracks[id]).whereType<Track>().toList();

  List<Track> get offlineTracks =>
      tracks.values.where(isDownloaded).toList()
        ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  bool isFavorite(String id) => favorites.contains(id);

  void toggleFavorite(Track t) {
    if (t.isLocal) return;
    if (!favorites.remove(t.id)) {
      tracks[t.id] = t;
      favorites.insert(0, t.id);
    }
    _commit();
  }

  /// Полностью убрать трек (для файлов с телефона — удалить файл).
  Future<void> removeTrack(Track t) async {
    favorites.remove(t.id);
    for (final p in playlists) {
      p.trackIds.remove(t.id);
    }
    final path = localPath(t);
    if (path != null) {
      try {
        File(path).deleteSync();
      } catch (_) {}
    }
    downloads.remove(t.id);
    if (t.isLocal) tracks.remove(t.id);
    _commit();
  }

  // ----------------------------------------------------------- playlists ---

  UserPlaylist createPlaylist(String name, [Iterable<Track> initial = const []]) {
    final trimmed = name.trim();
    final pl = UserPlaylist(
      id: 'pl_${DateTime.now().microsecondsSinceEpoch}',
      name: trimmed.isEmpty ? 'Новый плейлист' : trimmed,
    );
    for (final t in initial) {
      tracks[t.id] = t;
      if (!pl.trackIds.contains(t.id)) pl.trackIds.add(t.id);
    }
    playlists.insert(0, pl);
    _commit();
    return pl;
  }

  void addToPlaylist(UserPlaylist pl, Track t) {
    if (pl.trackIds.contains(t.id)) {
      say('Этот трек уже в плейлисте «${pl.name}»');
      return;
    }
    tracks[t.id] = t;
    pl.trackIds.add(t.id);
    _commit();
    say('Добавлено в «${pl.name}»');
  }

  void removeFromPlaylist(UserPlaylist pl, Track t) {
    pl.trackIds.remove(t.id);
    _commit();
  }

  void renamePlaylist(UserPlaylist pl, String name) {
    if (name.trim().isEmpty) return;
    pl.name = name.trim();
    _commit();
  }

  void deletePlaylist(UserPlaylist pl) {
    playlists.remove(pl);
    _commit();
  }

  List<Track> playlistTracks(UserPlaylist pl) =>
      pl.trackIds.map((id) => tracks[id]).whereType<Track>().toList();

  // --------------------------------------------------------------- files ---

  /// Путь к файлу, если трек можно проиграть без интернета.
  String? localPath(Track t) {
    final name = t.isLocal ? t.localFile : downloads[t.id];
    if (name == null) return null;
    // Наличие файлов проверяется один раз при запуске (_pruneMissingFiles):
    // здесь вызов идёт из build() для каждой строки списка.
    return '${musicDir.path}/$name';
  }

  bool isDownloaded(Track t) => localPath(t) != null;

  bool canPlay(Track t) =>
      localPath(t) != null || (t.streamUrl != null && t.streamUrl!.isNotEmpty);

  static String _safe(String s) => s.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  static String _ext(String name) {
    final i = name.lastIndexOf('.');
    if (i > 0 && name.length - i <= 6) return name.substring(i).toLowerCase();
    return '.mp3';
  }

  /// "01. Artist - Title.mp3" -> ["Artist", "Title"]
  static List<String> _splitName(String fileName) {
    var base = fileName;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    base = base
        .replaceFirst(RegExp(r'^\s*\d{1,3}\s*(?:[\.\)]\s*|\s-\s)'), '')
        .replaceAll('_', ' ')
        .trim();
    final m = RegExp(r'\s[-–—]\s').firstMatch(base);
    if (m != null) {
      return [base.substring(0, m.start).trim(), base.substring(m.end).trim()];
    }
    return ['', base];
  }

  /// Добавить музыкальные файлы с телефона. Возвращает, сколько добавлено.
  Future<int> addLocalFiles() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.audio, allowMultiple: true);
    if (res == null) return 0;
    var added = 0;
    final stamp = DateTime.now().microsecondsSinceEpoch;
    for (final f in res.files) {
      final p = f.path;
      if (p == null) continue;
      try {
        final id = 'local:${stamp}_$added';
        final fileName = '${_safe(id)}${_ext(f.name)}';
        await File(p).copy('${musicDir.path}/$fileName');
        // Сначала теги внутри файла, если их нет — имя файла.
        final tags = await readTags(File(p));
        final parts = _splitName(f.name);
        var title = (tags?.title ?? '').trim();
        var artist = (tags?.artist ?? '').trim();
        if (title.isEmpty) title = parts[1].isEmpty ? f.name : parts[1];
        if (artist.isEmpty) artist = parts[0];
        if (artist.isEmpty) artist = 'Неизвестный исполнитель';
        final t = Track(
          id: id,
          title: title,
          artist: artist,
          album: (tags?.album ?? '').trim(),
          source: 'local',
          localFile: fileName,
          durationSec: (tags?.durationMs ?? 0) ~/ 1000,
        );
        tracks[id] = t;
        favorites.insert(0, id);
        added++;
        if (p.contains('/cache/')) {
          try {
            File(p).deleteSync();
          } catch (_) {}
        }
      } catch (e) {
        say('Не удалось добавить «${f.name}»: ${shortError(e)}');
      }
    }
    if (added > 0) _commit();
    return added;
  }

  // ------------------------------------------------------------ download ---

  Future<void> download(Track t) async {
    if (t.isLocal || isDownloaded(t) || downloadProgress.containsKey(t.id)) {
      return;
    }
    final urls = <String>[
      if (t.downloadUrl != null && t.downloadUrl!.isNotEmpty) t.downloadUrl!,
      if (t.streamUrl != null && t.streamUrl!.isNotEmpty) t.streamUrl!,
    ];
    if (urls.isEmpty) {
      say('У трека нет ссылки для загрузки');
      return;
    }
    tracks[t.id] = t;
    downloadProgress[t.id] = 0;
    notifyListeners();

    final fileName = '${_safe(t.id)}.mp3';
    final file = File('${musicDir.path}/$fileName');
    Object? lastError;
    var ok = false;
    for (final url in urls) {
      final client = http.Client();
      try {
        final resp = await client.send(http.Request('GET', Uri.parse(url)));
        if (resp.statusCode != 200) {
          throw Exception('ошибка ${resp.statusCode}');
        }
        final total = resp.contentLength ?? 0;
        var got = 0;
        final sink = file.openWrite();
        try {
          await for (final chunk in resp.stream) {
            sink.add(chunk);
            got += chunk.length;
            if (total > 0) {
              final p = got / total;
              if (p - (downloadProgress[t.id] ?? 0) > 0.02) {
                downloadProgress[t.id] = p;
                notifyListeners();
              }
            }
          }
        } finally {
          await sink.close();
        }
        ok = true;
        break;
      } catch (e) {
        lastError = e;
        if (file.existsSync()) file.deleteSync();
      } finally {
        client.close();
      }
    }
    downloadProgress.remove(t.id);
    if (ok) {
      downloads[t.id] = fileName;
      _commit();
    } else {
      notifyListeners();
      say('Не удалось скачать «${t.title}»: ${shortError(lastError ?? 'неизвестная ошибка')}');
    }
  }

  Future<void> downloadMany(List<Track> list) async {
    for (final t in list) {
      await download(t);
    }
    say('Загрузка завершена');
  }

  void removeDownload(Track t) {
    final name = downloads.remove(t.id);
    if (name != null) {
      try {
        File('${musicDir.path}/$name').deleteSync();
      } catch (_) {}
    }
    _commit();
  }

  Future<void> clearDownloads() async {
    for (final name in downloads.values) {
      try {
        File('${musicDir.path}/$name').deleteSync();
      } catch (_) {}
    }
    downloads.clear();
    _commit();
  }

  Future<int> storageBytes() async {
    var sum = 0;
    try {
      await for (final e in musicDir.list()) {
        if (e is File) sum += await e.length();
      }
    } catch (_) {}
    return sum;
  }

  // ------------------------------------------------------------ playback ---

  AudioSource _toSource(Track t) {
    final item = MediaItem(
      id: t.id,
      title: t.title,
      artist: t.artist,
      album: t.album.isEmpty ? null : t.album,
      artUri: t.coverUrl == null ? null : Uri.tryParse(t.coverUrl!),
      duration: t.durationSec > 0 ? Duration(seconds: t.durationSec) : null,
    );
    final path = localPath(t);
    if (path != null) return AudioSource.uri(Uri.file(path), tag: item);
    return AudioSource.uri(Uri.parse(t.streamUrl!), tag: item);
  }

  Future<void> playQueue(List<Track> list, int index) async {
    if (list.isEmpty || index < 0 || index >= list.length) return;
    final start = list[index];
    final playable = list.where(canPlay).toList();
    final startIndex = playable.indexWhere((t) => t.id == start.id);
    if (startIndex < 0) {
      say('Этот трек сейчас недоступен');
      return;
    }
    queue = playable;
    currentIndex = startIndex;
    notifyListeners();
    try {
      await player.setAudioSource(
        ConcatenatingAudioSource(children: playable.map(_toSource).toList()),
        initialIndex: startIndex,
        initialPosition: Duration.zero,
      );
      unawaited(player.play());
    } catch (e) {
      say('Не удалось воспроизвести: ${shortError(e)}. Проверьте интернет или скачайте трек.');
    }
  }

  Future<void> playShuffled(List<Track> list) async {
    if (list.isEmpty) return;
    await playQueue(list, Random().nextInt(list.length));
    await player.setShuffleModeEnabled(true);
    await player.shuffle();
  }

  void togglePlay() {
    if (player.playing) {
      unawaited(player.pause());
    } else {
      unawaited(player.play());
    }
  }

  void next() {
    unawaited(player.seekToNext());
  }

  void previous() {
    if (player.position > const Duration(seconds: 3) || !player.hasPrevious) {
      unawaited(player.seek(Duration.zero));
    } else {
      unawaited(player.seekToPrevious());
    }
  }

  Future<void> toggleShuffle() async {
    final enable = !player.shuffleModeEnabled;
    await player.setShuffleModeEnabled(enable);
    if (enable) await player.shuffle();
  }

  void cycleRepeat() {
    final mode = switch (player.loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    unawaited(player.setLoopMode(mode));
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }
}
