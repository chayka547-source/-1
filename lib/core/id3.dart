import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'encoding.dart';

/// Теги, прочитанные из аудиофайла.
class TagInfo {
  const TagInfo({this.title, this.artist, this.album, this.durationMs});

  final String? title;
  final String? artist;
  final String? album;
  final int? durationMs;

  bool get isEmpty =>
      (title ?? '').isEmpty && (artist ?? '').isEmpty && (album ?? '').isEmpty;
}

/// Не читаем слишком большие теги (обложки внутри файла бывают в мегабайтах).
const int _maxTagBytes = 1024 * 1024;

/// Читает теги ID3v2 / ID3v1 (mp3) и Vorbis-комментарии (flac).
/// Для остальных форматов и при любой ошибке возвращает null —
/// тогда название берётся из имени файла.
Future<TagInfo?> readTags(File file) async {
  RandomAccessFile? raf;
  try {
    raf = await file.open();
    final head = await raf.read(10);
    if (head.length >= 10 &&
        head[0] == 0x49 &&
        head[1] == 0x44 &&
        head[2] == 0x33) {
      // "ID3"
      final size = _syncsafe(head, 6);
      final body = await raf.read(size > _maxTagBytes ? _maxTagBytes : size);
      final info = parseId3v2(head, body);
      if (info != null && !info.isEmpty) return info;
    } else if (head.length >= 4 &&
        head[0] == 0x66 &&
        head[1] == 0x4C &&
        head[2] == 0x61 &&
        head[3] == 0x43) {
      // "fLaC"
      await raf.setPosition(4);
      final info = await _readFlac(raf);
      if (info != null && !info.isEmpty) return info;
    }
    final length = await raf.length();
    if (length > 128) {
      await raf.setPosition(length - 128);
      final tail = await raf.read(128);
      final v1 = parseId3v1(tail);
      if (v1 != null && !v1.isEmpty) return v1;
    }
  } catch (_) {
    // Повреждённый тег — не страшно.
  } finally {
    await raf?.close();
  }
  return null;
}

int _syncsafe(Uint8List b, int o) =>
    ((b[o] & 0x7F) << 21) |
    ((b[o + 1] & 0x7F) << 14) |
    ((b[o + 2] & 0x7F) << 7) |
    (b[o + 3] & 0x7F);

int _be32(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

/// Разбор тела тега ID3v2. [head] — первые 10 байт («ID3», версия, флаги, размер),
/// [body] — байты тега после заголовка.
TagInfo? parseId3v2(Uint8List head, Uint8List body) {
  if (head.length < 10) return null;
  final major = head[3];
  if (major < 2 || major > 4) return null;
  final flags = head[5];

  var pos = 0;
  if (major >= 3 && (flags & 0x40) != 0 && body.length >= 4) {
    // Расширенный заголовок: пропускаем.
    pos = major == 4 ? _syncsafe(body, 0) : _be32(body, 0) + 4;
  }

  String? title;
  String? artist;
  String? albumArtist;
  String? album;
  int? lengthMs;

  final idLen = major == 2 ? 3 : 4;
  final headerLen = major == 2 ? 6 : 10;

  while (pos + headerLen <= body.length) {
    if (body[pos] == 0) break; // дальше только заполнитель
    final id = String.fromCharCodes(body, pos, pos + idLen);
    int size;
    if (major == 2) {
      size = (body[pos + 3] << 16) | (body[pos + 4] << 8) | body[pos + 5];
    } else if (major == 4) {
      size = _syncsafe(body, pos + 4);
    } else {
      size = _be32(body, pos + 4);
    }
    final start = pos + headerLen;
    final end = start + size;
    if (size <= 0 || end > body.length) break;

    switch (id) {
      case 'TIT2':
      case 'TT2':
        title = _decodeText(body, start, end);
        break;
      case 'TPE1':
      case 'TP1':
        artist = _decodeText(body, start, end);
        break;
      case 'TPE2':
      case 'TP2':
        albumArtist = _decodeText(body, start, end);
        break;
      case 'TALB':
      case 'TAL':
        album = _decodeText(body, start, end);
        break;
      case 'TLEN':
      case 'TLE':
        final t = _decodeText(body, start, end);
        lengthMs = t == null ? null : int.tryParse(t.trim());
        break;
      default:
        break;
    }
    pos = end;
  }

  final info = TagInfo(
    title: title,
    artist: (artist != null && artist.isNotEmpty) ? artist : albumArtist,
    album: album,
    durationMs: lengthMs,
  );
  return info.isEmpty ? null : info;
}

/// Текстовый кадр: первый байт — кодировка, дальше текст.
String? _decodeText(Uint8List b, int start, int end) {
  if (end <= start + 1) return null;
  final enc = b[start];
  final data = Uint8List.sublistView(b, start + 1, end);
  String s;
  switch (enc) {
    case 1:
      s = _decodeUtf16(data, null);
      break;
    case 2:
      s = _decodeUtf16(data, true);
      break;
    case 3:
      s = utf8.decode(data, allowMalformed: true);
      break;
    default:
      s = decodeLegacy(data);
  }
  // Несколько значений разделяются нулевым символом — берём первое.
  final z = s.indexOf('\u0000');
  if (z >= 0) s = s.substring(0, z);
  s = s.trim();
  return s.isEmpty ? null : s;
}

/// UTF-16. [bigEndian] == null — порядок байт определяется по BOM.
String _decodeUtf16(Uint8List d, bool? bigEndian) {
  var i = 0;
  var be = bigEndian ?? false;
  if (bigEndian == null && d.length >= 2) {
    if (d[0] == 0xFF && d[1] == 0xFE) {
      be = false;
      i = 2;
    } else if (d[0] == 0xFE && d[1] == 0xFF) {
      be = true;
      i = 2;
    }
  }
  final units = <int>[];
  for (; i + 1 < d.length; i += 2) {
    units.add(be ? (d[i] << 8) | d[i + 1] : (d[i + 1] << 8) | d[i]);
  }
  return String.fromCharCodes(units);
}

/// ID3v1: последние 128 байт файла.
TagInfo? parseId3v1(Uint8List t) {
  if (t.length < 128 || t[0] != 0x54 || t[1] != 0x41 || t[2] != 0x47) {
    return null; // нет "TAG"
  }
  String field(int from, int to) {
    var end = to;
    for (var i = from; i < to; i++) {
      if (t[i] == 0) {
        end = i;
        break;
      }
    }
    return decodeLegacy(Uint8List.sublistView(t, from, end)).trim();
  }

  final title = field(3, 33);
  final artist = field(33, 63);
  final album = field(63, 93);
  final info = TagInfo(
    title: title.isEmpty ? null : title,
    artist: artist.isEmpty ? null : artist,
    album: album.isEmpty ? null : album,
  );
  return info.isEmpty ? null : info;
}

/// FLAC: ищем блок VORBIS_COMMENT среди метаданных.
Future<TagInfo?> _readFlac(RandomAccessFile raf) async {
  for (var i = 0; i < 64; i++) {
    final h = await raf.read(4);
    if (h.length < 4) return null;
    final isLast = (h[0] & 0x80) != 0;
    final type = h[0] & 0x7F;
    final len = (h[1] << 16) | (h[2] << 8) | h[3];
    if (type == 4) {
      if (len > _maxTagBytes) return null;
      return parseVorbisComments(await raf.read(len));
    }
    final pos = await raf.position();
    await raf.setPosition(pos + len);
    if (isLast) break;
  }
  return null;
}

/// Блок комментариев Vorbis: длины — little-endian.
TagInfo? parseVorbisComments(Uint8List d) {
  String? title;
  String? artist;
  String? albumArtist;
  String? album;
  try {
    final bd = ByteData.sublistView(d);
    var o = 0;
    final vendorLen = bd.getUint32(o, Endian.little);
    o += 4 + vendorLen;
    final count = bd.getUint32(o, Endian.little);
    o += 4;
    for (var i = 0; i < count; i++) {
      if (o + 4 > d.length) break;
      final l = bd.getUint32(o, Endian.little);
      o += 4;
      if (o + l > d.length) break;
      final s = utf8.decode(Uint8List.sublistView(d, o, o + l),
          allowMalformed: true);
      o += l;
      final eq = s.indexOf('=');
      if (eq <= 0) continue;
      final key = s.substring(0, eq).toUpperCase();
      final value = s.substring(eq + 1).trim();
      if (value.isEmpty) continue;
      switch (key) {
        case 'TITLE':
          title ??= value;
          break;
        case 'ARTIST':
          artist ??= value;
          break;
        case 'ALBUMARTIST':
          albumArtist ??= value;
          break;
        case 'ALBUM':
          album ??= value;
          break;
        default:
          break;
      }
    }
  } catch (_) {
    // Берём то, что успели прочитать.
  }
  final info = TagInfo(
    title: title,
    artist: artist ?? albumArtist,
    album: album,
  );
  return info.isEmpty ? null : info;
}
