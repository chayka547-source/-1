import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/encoding.dart';

/// Один трек из чужого списка: только название и исполнитель.
class ImportedItem {
  const ImportedItem(this.artist, this.title);
  final String artist;
  final String title;
}

class ImportedList {
  const ImportedList({
    required this.name,
    required this.service,
    required this.items,
  });
  final String name;
  final String service;
  final List<ImportedItem> items;
}

class ImportException implements Exception {
  ImportException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Читает список треков (названия и исполнителей) из публичной ссылки
/// на альбом/плейлист. Сами аудиофайлы не скачиваются.
class LinkImporter {
  static const _ua =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  static const _desktopUa =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36';

  static const _vkMessage =
      'VK Музыка не отдаёт список треков без входа в аккаунт, поэтому по ссылке '
      'его прочитать не получилось. Скопируйте список песен текстом '
      '(«Исполнитель - Название», по одной на строке) и вставьте сюда.';

  static const _knownHosts = [
    'yandex',
    'spotify',
    'youtube',
    'youtu.be',
    'vk.com',
    'vk.ru',
    'boom.ru',
  ];

  /// Ссылка во вводе: либо весь ввод — одна строка (в том числе «Слушайте…
  /// https://…» из кнопки «Поделиться»), либо в многострочном тексте есть
  /// ссылка на известный сервис. Иначе null — это список песен текстом.
  static String? extractLink(String input) {
    final m = RegExp(r'https?://[^\s<>"]+').firstMatch(input);
    if (m == null) return null;
    final link = m.group(0)!.replaceFirst(RegExp(r'[.,;:!?)\]]+$'), '');
    final lines =
        input.split(RegExp(r'[\r\n]+')).where((l) => l.trim().isNotEmpty);
    if (lines.length == 1) return link;
    final host = (Uri.tryParse(link)?.host ?? '').toLowerCase();
    return _knownHosts.any(host.contains) ? link : null;
  }

  /// Ссылка на поддерживаемый сервис (Яндекс, YouTube, Spotify, VK) — для подсказки
  /// «в буфере обмена ссылка на музыку». Для остальных адресов возвращает null.
  static String? recognizedLink(String text) {
    final link = extractLink(text);
    if (link == null) return null;
    final host = (Uri.tryParse(link)?.host ?? '').toLowerCase();
    return _knownHosts.any(host.contains) ? link : null;
  }

  // ----------------------------------------------------------------- text ---

  static ImportedList fromText(String text, {String name = 'Импортированный плейлист'}) {
    final items = <ImportedItem>[];
    for (var line in text.split(RegExp(r'[\r\n]+'))) {
      line = line.trim().replaceFirst(RegExp(r'^\d{1,3}\s*[\.\)]\s+'), '');
      if (line.isEmpty) continue;
      final m = RegExp(r'\s[-–—]\s').firstMatch(line);
      if (m != null) {
        final artist = line.substring(0, m.start).trim();
        final title = line.substring(m.end).trim();
        if (title.isNotEmpty) items.add(ImportedItem(artist, title));
      } else {
        items.add(ImportedItem('', line));
      }
    }
    return ImportedList(name: name, service: 'Текст', items: items);
  }

  // ----------------------------------------------------------------- link ---

  static Future<ImportedList> fromLink(String link) async {
    final uri = Uri.tryParse(link);
    if (uri == null || uri.host.isEmpty) {
      throw ImportException('Не похоже на ссылку');
    }
    final host = uri.host.toLowerCase();
    try {
      if (host.contains('yandex')) return await _yandex(uri);
      if (host.contains('spotify')) return await _spotify(uri);
      if (host.contains('youtube') || host == 'youtu.be') {
        return await _youtube(uri);
      }
      if (host.contains('vk.com') ||
          host.contains('vk.ru') ||
          host.contains('boom.ru')) {
        return await _vk(uri);
      }
      return await _generic(uri);
    } on ImportException {
      rethrow;
    } on TimeoutException {
      throw ImportException(
          'Сервис не отвечает. Проверьте интернет (некоторые сервисы могут быть недоступны без VPN).');
    } on SocketException {
      throw ImportException(
          'Не удалось подключиться к сервису. Проверьте интернет (некоторые сервисы могут быть недоступны без VPN).');
    } on http.ClientException {
      throw ImportException(
          'Не удалось подключиться к сервису. Проверьте интернет.');
    } on FormatException {
      throw ImportException(
          'Не удалось разобрать ответ сервиса — возможно, он изменил формат страницы. Попробуйте вставить список текстом.');
    }
  }

  // --------------------------------------------------------------- helpers ---

  static Future<String> _get(String url, {Map<String, String>? headers}) async {
    final r = await http.get(Uri.parse(url), headers: {
      'User-Agent': _ua,
      'Accept-Language': 'ru,en;q=0.8',
      ...?headers,
    }).timeout(const Duration(seconds: 25));
    if (r.statusCode != 200) {
      throw ImportException('Сервис ответил ошибкой ${r.statusCode}');
    }
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }

  /// Возвращает первую карту, в которой есть ключ [key].
  static Map? _findKey(dynamic node, String key) {
    if (node is Map) {
      if (node.containsKey(key)) return node;
      for (final v in node.values) {
        final r = _findKey(v, key);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _findKey(v, key);
        if (r != null) return r;
      }
    }
    return null;
  }

  static void _collectKey(dynamic node, String key, List<Map> out) {
    if (node is Map) {
      for (final e in node.entries) {
        if (e.key == key && e.value is Map) {
          out.add(e.value as Map);
        } else {
          _collectKey(e.value, key, out);
        }
      }
    } else if (node is List) {
      for (final v in node) {
        _collectKey(v, key, out);
      }
    }
  }

  // ---------------------------------------------------------------- yandex ---

  static const _ymBase = 'https://api.music.yandex.net';
  static const _ymHeaders = {
    'X-Yandex-Music-Client': 'YandexMusicAndroid/24023621',
    'User-Agent': 'Yandex-Music-API',
    'Accept': 'application/json',
  };

  static Future<dynamic> _ymJson(String path, {Map<String, String>? form}) async {
    final uri = Uri.parse('$_ymBase$path');
    final http.Response r;
    if (form == null) {
      r = await http.get(uri, headers: _ymHeaders).timeout(const Duration(seconds: 25));
    } else {
      r = await http
          .post(uri, headers: _ymHeaders, body: form)
          .timeout(const Duration(seconds: 25));
    }
    if (r.statusCode == 404 || r.statusCode == 403 || r.statusCode == 401) {
      throw ImportException(
          'Яндекс Музыка не отдала список. Проверьте ссылку и что плейлист открыт для всех.');
    }
    if (r.statusCode != 200) {
      throw ImportException('Яндекс Музыка ответила ошибкой ${r.statusCode}');
    }
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  /// Все исполнители через запятую: «Artist A, Artist B».
  static String _ymArtist(dynamic artists) {
    if (artists is! List) return '';
    return artists
        .whereType<Map>()
        .map((a) => '${a['name'] ?? ''}'.trim())
        .where((s) => s.isNotEmpty)
        .join(', ');
  }

  static ImportedItem _ymTrack(dynamic t, String fallbackArtist) {
    final m = Map<String, dynamic>.from(t as Map);
    final artist = _ymArtist(m['artists']);
    var title = '${m['title'] ?? ''}'.trim();
    // «Radio Edit», «Remix» и т. п. — чтобы не путать с оригиналом.
    final version = '${m['version'] ?? ''}'.trim();
    if (version.isNotEmpty && title.isNotEmpty) title = '$title ($version)';
    return ImportedItem(artist.isEmpty ? fallbackArtist : artist, title);
  }

  static Future<List<ImportedItem>> _ymFullTracks(List<String> ids) async {
    final out = <ImportedItem>[];
    for (var i = 0; i < ids.length; i += 100) {
      final chunk = ids.sublist(i, i + 100 > ids.length ? ids.length : i + 100);
      final j = await _ymJson('/tracks', form: {'track-ids': chunk.join(',')});
      final res = (j is Map ? j['result'] : null) as List? ?? const [];
      for (final t in res) {
        out.add(_ymTrack(t, ''));
      }
    }
    return out;
  }

  /// Ответ `GET /albums/{id}/with-tracks` → список треков альбома.
  static ImportedList parseYandexAlbum(dynamic response) {
    final res = (response is Map ? response['result'] : null);
    if (res is! Map) throw ImportException('Альбом не найден');
    final albumArtist = _ymArtist(res['artists']);
    final items = <ImportedItem>[];
    for (final vol in (res['volumes'] as List?) ?? const []) {
      for (final t in (vol as List)) {
        items.add(_ymTrack(t, albumArtist));
      }
    }
    return ImportedList(
        name: '${res['title'] ?? 'Альбом'}',
        service: 'Яндекс Музыка',
        items: items);
  }

  static Future<ImportedList> _yandex(Uri uri) async {
    final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    String? after(String key) {
      final i = seg.indexOf(key);
      return (i >= 0 && i + 1 < seg.length) ? seg[i + 1] : null;
    }

    const service = 'Яндекс Музыка';

    // Альбом: /album/123 (возможно /album/123/track/456)
    final albumId = after('album');
    final playlistsSeg = seg.contains('playlists');
    if (albumId != null && !playlistsSeg) {
      final j = await _ymJson('/albums/$albumId/with-tracks');
      return parseYandexAlbum(j);
    }

    // Плейлист пользователя: /users/login/playlists/1000
    // Плейлист по uuid: /playlists/xxxxxxxx-xxxx-...
    String path;
    final login = after('users');
    final kind = after('playlists');
    if (login != null && kind != null) {
      path = '/users/$login/playlists/$kind';
    } else if (kind != null) {
      path = '/playlist/$kind';
    } else if (after('track') != null) {
      final items = await _ymFullTracks([after('track')!]);
      return ImportedList(name: 'Трек', service: service, items: items);
    } else {
      throw ImportException(
          'Нужна ссылка на альбом или плейлист Яндекс Музыки (открыть → «Поделиться»).');
    }

    final j = await _ymJson(path);
    final res = (j is Map ? j['result'] : null);
    if (res is! Map) throw ImportException('Плейлист не найден');
    final items = <ImportedItem>[];
    final missing = <String>[];
    for (final e in (res['tracks'] as List?) ?? const []) {
      if (e is! Map) continue;
      final track = e['track'];
      if (track is Map) {
        items.add(_ymTrack(track, ''));
      } else if (e['id'] != null) {
        final album = e['albumId'];
        missing.add(album != null ? '${e['id']}:$album' : '${e['id']}');
      }
    }
    if (missing.isNotEmpty) items.addAll(await _ymFullTracks(missing));
    return ImportedList(
        name: '${res['title'] ?? 'Плейлист'}', service: service, items: items);
  }

  // --------------------------------------------------------------- spotify ---

  static Future<ImportedList> _spotify(Uri uri) async {
    final seg = uri.pathSegments
        .where((s) => s.isNotEmpty && !s.startsWith('intl-'))
        .toList();
    final i = seg.indexWhere((s) => s == 'album' || s == 'playlist' || s == 'track');
    if (i < 0 || i + 1 >= seg.length) {
      throw ImportException(
          'Нужна полная ссылка на альбом или плейлист Spotify (open.spotify.com/…).');
    }
    final html = await _get('https://open.spotify.com/embed/${seg[i]}/${seg[i + 1]}');
    return parseSpotifyHtml(html);
  }

  /// Страница `open.spotify.com/embed/...` → список треков.
  static ImportedList parseSpotifyHtml(String html) {
    final m = RegExp(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', dotAll: true)
        .firstMatch(html);
    if (m == null) {
      throw ImportException(
          'Не удалось прочитать страницу Spotify. Попробуйте вставить список текстом.');
    }
    final data = jsonDecode(m.group(1)!);

    String clean(Object? s) => '$s'.replaceAll(' ', ' ').trim();

    final holder = _findKey(data, 'trackList');
    if (holder != null) {
      final items = <ImportedItem>[];
      for (final t in (holder['trackList'] as List)) {
        if (t is! Map) continue;
        final title = clean(t['title']);
        final artist = clean(t['subtitle']).split(',').first.trim();
        if (title.isNotEmpty) items.add(ImportedItem(artist, title));
      }
      final name = clean(holder['name'] ?? holder['title'] ?? 'Плейлист Spotify');
      return ImportedList(name: name, service: 'Spotify', items: items);
    }
    final single = _findKey(data, 'artists');
    if (single != null && single['name'] != null) {
      final artist = _ymArtist(single['artists']);
      return ImportedList(
          name: clean(single['name']),
          service: 'Spotify',
          items: [ImportedItem(artist, clean(single['name']))]);
    }
    throw ImportException(
        'Spotify изменил формат страницы. Попробуйте вставить список текстом.');
  }

  // --------------------------------------------------------------- youtube ---

  static Future<ImportedList> _youtube(Uri uri) async {
    final id = uri.queryParameters['list'];
    if (id == null || id.isEmpty) {
      throw ImportException(
          'Нужна ссылка на плейлист или альбом (в ней есть «list=…»). '
          'В YouTube Music: альбом → «Поделиться».');
    }
    final html = await _get(
      'https://www.youtube.com/playlist?list=$id&hl=ru',
      headers: {'Cookie': 'SOCS=CAI; CONSENT=YES+1'},
    );
    final m = RegExp(r'ytInitialData\s*=\s*(\{.+?\})\s*;\s*</script>', dotAll: true)
        .firstMatch(html);
    if (m == null) {
      throw ImportException(
          'Не удалось прочитать плейлист. Он должен быть открыт по ссылке.');
    }
    final data = jsonDecode(m.group(1)!);

    String? text(dynamic node) {
      if (node is Map) {
        if (node['simpleText'] != null) return '${node['simpleText']}';
        final runs = node['runs'];
        if (runs is List && runs.isNotEmpty && runs.first is Map) {
          return '${(runs.first as Map)['text']}';
        }
      }
      return null;
    }

    final items = <ImportedItem>[];
    void addRenderers(dynamic source) {
      final renderers = <Map>[];
      _collectKey(source, 'playlistVideoRenderer', renderers);
      for (final r in renderers) {
        var title = (text(r['title']) ?? '').trim();
        var artist = (text(r['shortBylineText']) ?? '').trim();
        if (title.isEmpty) continue;
        if (artist.endsWith(' - Topic')) {
          artist = artist.substring(0, artist.length - ' - Topic'.length).trim();
        } else {
          final dash = RegExp(r'\s[-–—]\s').firstMatch(title);
          if (dash != null) {
            artist = title.substring(0, dash.start).trim();
            title = title.substring(dash.end).trim();
          }
        }
        items.add(ImportedItem(artist, title));
      }
    }

    addRenderers(data);

    // На странице первые 100 треков, остальные подгружаются порциями.
    final apiKey = RegExp(r'"INNERTUBE_API_KEY"\s*:\s*"([^"]+)"')
        .firstMatch(html)
        ?.group(1);
    final clientVersion = RegExp(r'"INNERTUBE_CLIENT_VERSION"\s*:\s*"([^"]+)"')
            .firstMatch(html)
            ?.group(1) ??
        '2.20250101.00.00';
    var token = _ytToken(data);
    var pages = 0;
    while (apiKey != null && token != null && pages < 30) {
      pages++;
      try {
        final r = await http
            .post(
              Uri.parse(
                  'https://www.youtube.com/youtubei/v1/browse?key=$apiKey&prettyPrint=false'),
              headers: {
                'Content-Type': 'application/json',
                'User-Agent': _ua,
                'Origin': 'https://www.youtube.com',
                'Cookie': 'SOCS=CAI; CONSENT=YES+1',
              },
              body: jsonEncode({
                'context': {
                  'client': {
                    'clientName': 'WEB',
                    'clientVersion': clientVersion,
                    'hl': 'ru',
                    'gl': 'RU',
                  },
                },
                'continuation': token,
              }),
            )
            .timeout(const Duration(seconds: 25));
        if (r.statusCode != 200) break;
        final next = jsonDecode(utf8.decode(r.bodyBytes));
        final before = items.length;
        addRenderers(next);
        token = _ytToken(next);
        if (items.length == before) break;
      } catch (_) {
        break; // оставляем то, что уже прочитано
      }
    }

    final meta = _findKey(data, 'playlistMetadataRenderer');
    final name = (meta != null ? meta['playlistMetadataRenderer']['title'] : null) ??
        'Плейлист YouTube';
    return ImportedList(name: '$name', service: 'YouTube', items: items);
  }

  static String? _ytToken(dynamic data) {
    final holder = _findKey(data, 'continuationCommand');
    final cmd = holder?['continuationCommand'];
    if (cmd is Map && cmd['token'] is String) return cmd['token'] as String;
    return null;
  }

  // -------------------------------------------------------------------- vk ---

  static Future<ImportedList> _vk(Uri uri) async {
    final r = await http.get(uri, headers: {
      'User-Agent': _desktopUa,
      'Accept-Language': 'ru,en;q=0.8',
    }).timeout(const Duration(seconds: 25));
    final type = (r.headers['content-type'] ?? '').toLowerCase();
    // Страницы VK отдаются в windows-1251.
    final html = type.contains('1251')
        ? decodeCp1251(r.bodyBytes)
        : utf8.decode(r.bodyBytes, allowMalformed: true);
    final items = parseVkHtml(html);
    if (items.isEmpty) throw ImportException(_vkMessage);
    final t = RegExp(r'<title>(.*?)</title>', dotAll: true)
        .firstMatch(html)
        ?.group(1);
    final name = t == null
        ? ''
        : unescapeHtml(t).replaceAll(RegExp(r'\s*\|\s*VK.*$'), '').trim();
    return ImportedList(
        name: name.isEmpty ? 'Плейлист VK' : name,
        service: 'VK Музыка',
        items: items);
  }

  /// Строки аудио VK кладёт в атрибуты `data-audio` — но только если страница
  /// открыта с входом в аккаунт. Формат: [id, владелец, ссылка, название, исполнитель, …].
  static List<ImportedItem> parseVkHtml(String html) {
    final out = <ImportedItem>[];
    for (final m in RegExp(r'data-audio="([^"]+)"').allMatches(html)) {
      try {
        final arr = jsonDecode(unescapeHtml(m.group(1)!));
        if (arr is List && arr.length > 4) {
          final title = unescapeHtml('${arr[3]}').trim();
          final artist = unescapeHtml('${arr[4]}').trim();
          if (title.isNotEmpty) out.add(ImportedItem(artist, title));
        }
      } catch (_) {
        // пропускаем непонятную строку
      }
    }
    return out;
  }

  // --------------------------------------------------------------- generic ---

  static String _ldArtist(dynamic v) {
    if (v is String) return v;
    if (v is Map) return '${v['name'] ?? ''}';
    if (v is List && v.isNotEmpty) return _ldArtist(v.first);
    return '';
  }

  static bool _ldIsMusic(dynamic type) {
    const wanted = {'MusicAlbum', 'MusicPlaylist'};
    if (type is String) return wanted.contains(type);
    if (type is List) return type.any((t) => wanted.contains(t));
    return false;
  }

  static ImportedList? _ldFind(dynamic node, String host) {
    if (node is List) {
      for (final v in node) {
        final r = _ldFind(v, host);
        if (r != null) return r;
      }
      return null;
    }
    if (node is! Map) return null;
    if (_ldIsMusic(node['@type']) && node['track'] != null) {
      final tr = node['track'];
      List elems = const [];
      if (tr is List) {
        elems = tr;
      } else if (tr is Map && tr['itemListElement'] is List) {
        elems = tr['itemListElement'] as List;
      }
      final albumArtist = _ldArtist(node['byArtist']);
      final items = <ImportedItem>[];
      for (var e in elems) {
        if (e is Map && e['item'] is Map) e = e['item'];
        if (e is! Map) continue;
        final title = '${e['name'] ?? ''}'.trim();
        if (title.isEmpty) continue;
        final artist = _ldArtist(e['byArtist']);
        items.add(ImportedItem(artist.isEmpty ? albumArtist : artist, title));
      }
      if (items.isNotEmpty) {
        return ImportedList(
            name: '${node['name'] ?? 'Плейлист'}', service: host, items: items);
      }
    }
    final graph = node['@graph'];
    if (graph != null) return _ldFind(graph, host);
    return null;
  }

  static Future<ImportedList> _generic(Uri uri) async {
    final html = await _get(uri.toString());
    final re = RegExp(
        r'<script[^>]+type="application/ld\+json"[^>]*>(.*?)</script>',
        dotAll: true,
        caseSensitive: false);
    for (final m in re.allMatches(html)) {
      dynamic data;
      try {
        data = jsonDecode(m.group(1)!.trim());
      } catch (_) {
        continue;
      }
      final found = _ldFind(data, uri.host);
      if (found != null) return found;
    }
    throw ImportException(
        'По этой ссылке не нашлось списка треков. Поддерживаются Яндекс Музыка, '
        'YouTube/YouTube Music и Spotify; для остальных сервисов вставьте список текстом.');
  }
}
