import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:volna/core/id3.dart';

/// Кадр ID3v2.3: id, размер (4 байта), флаги (2 байта), данные.
List<int> frame(String id, List<int> data) => [
      ...ascii.encode(id),
      (data.length >> 24) & 0xFF,
      (data.length >> 16) & 0xFF,
      (data.length >> 8) & 0xFF,
      data.length & 0xFF,
      0,
      0,
      ...data,
    ];

/// Возвращает [заголовок из 10 байт, тело тега].
List<Uint8List> tag(List<List<int>> frames) {
  final body = <int>[for (final f in frames) ...f];
  final n = body.length;
  final head = Uint8List.fromList([
    0x49, 0x44, 0x33, 3, 0, 0, // "ID3", версия 2.3, флаги
    (n >> 21) & 0x7F, (n >> 14) & 0x7F, (n >> 7) & 0x7F, n & 0x7F,
  ]);
  return [head, Uint8List.fromList(body)];
}

void main() {
  test('ID3v2.3: Latin-1', () {
    final t = tag([
      frame('TIT2', [0, ...ascii.encode('Song')]),
      frame('TPE1', [0, ...ascii.encode('Artist')]),
      frame('TALB', [0, ...ascii.encode('Album')]),
      frame('TLEN', [0, ...ascii.encode('215000')]),
    ]);
    final info = parseId3v2(t[0], t[1])!;
    expect(info.title, 'Song');
    expect(info.artist, 'Artist');
    expect(info.album, 'Album');
    expect(info.durationMs, 215000);
  });

  test('ID3v2.3: UTF-8 (кодировка 3)', () {
    final t = tag([
      frame('TIT2', [3, ...utf8.encode('Группа крови')]),
      frame('TPE1', [3, ...utf8.encode('Кино')]),
    ]);
    final info = parseId3v2(t[0], t[1])!;
    expect(info.title, 'Группа крови');
    expect(info.artist, 'Кино');
  });

  test('ID3v2.3: русский текст в windows-1251, помеченный как Latin-1', () {
    final t = tag([
      frame('TIT2', [0, 0xCA, 0xE8, 0xED, 0xEE]), // «Кино»
    ]);
    expect(parseId3v2(t[0], t[1])!.title, 'Кино');
  });

  test('ID3v2.3: UTF-16 с BOM', () {
    final units = 'Привет'.codeUnits;
    final bytes = <int>[0xFF, 0xFE, for (final u in units) ...[u & 0xFF, u >> 8]];
    final t = tag([
      frame('TIT2', [1, ...bytes]),
    ]);
    expect(parseId3v2(t[0], t[1])!.title, 'Привет');
  });

  test('ID3v2: исполнитель альбома, если нет исполнителя трека', () {
    final t = tag([
      frame('TIT2', [0, ...ascii.encode('Song')]),
      frame('TPE2', [0, ...ascii.encode('Band')]),
    ]);
    expect(parseId3v2(t[0], t[1])!.artist, 'Band');
  });

  test('ID3v2: обрезанный тег не падает', () {
    final t = tag([
      frame('TIT2', [0, ...ascii.encode('Song')]),
    ]);
    final cut = Uint8List.sublistView(t[1], 0, t[1].length - 2);
    expect(() => parseId3v2(t[0], cut), returnsNormally);
  });

  test('ID3v1', () {
    final b = Uint8List(128);
    b.setRange(0, 3, ascii.encode('TAG'));
    b.setRange(3, 3 + 4, ascii.encode('Song'));
    b.setRange(33, 33 + 6, ascii.encode('Artist'));
    final info = parseId3v1(b)!;
    expect(info.title, 'Song');
    expect(info.artist, 'Artist');
  });

  test('Vorbis-комментарии (FLAC)', () {
    final out = <int>[];
    void le32(int v) =>
        out.addAll([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
    final vendor = ascii.encode('test');
    le32(vendor.length);
    out.addAll(vendor);
    final comments = ['TITLE=Группа крови', 'ARTIST=Кино', 'ALBUM=Группа крови'];
    le32(comments.length);
    for (final c in comments) {
      final e = utf8.encode(c);
      le32(e.length);
      out.addAll(e);
    }
    final info = parseVorbisComments(Uint8List.fromList(out))!;
    expect(info.title, 'Группа крови');
    expect(info.artist, 'Кино');
    expect(info.album, 'Группа крови');
  });
}
