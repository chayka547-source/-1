import 'package:flutter_test/flutter_test.dart';
import 'package:volna/core/encoding.dart';
import 'package:volna/import/link_importer.dart';

void main() {
  group('extractLink', () {
    test('одна ссылка', () {
      expect(LinkImporter.extractLink('https://music.yandex.ru/album/123?utm=1'),
          'https://music.yandex.ru/album/123?utm=1');
    });

    test('ссылка внутри текста «Поделиться»', () {
      expect(
          LinkImporter.extractLink('Слушайте альбом\nhttps://music.yandex.ru/album/1'),
          'https://music.yandex.ru/album/1');
    });

    test('точка после ссылки отбрасывается', () {
      expect(LinkImporter.extractLink('Вот: https://open.spotify.com/album/abc.'),
          'https://open.spotify.com/album/abc');
    });

    test('список песен — это не ссылка', () {
      expect(LinkImporter.extractLink('Кино - Группа крови\nQueen - Show Must Go On'),
          isNull);
      expect(LinkImporter.extractLink('Список\nhttps://example.com/x\nещё'), isNull);
    });
  });

  group('текстовый список', () {
    test('исполнитель - название, нумерация, строка без исполнителя', () {
      final list = LinkImporter.fromText(
          '1. Кино — Группа крови\nQueen - Bohemian Rhapsody\n\nПросто название');
      expect(list.items.length, 3);
      expect(list.items[0].artist, 'Кино');
      expect(list.items[0].title, 'Группа крови');
      expect(list.items[1].artist, 'Queen');
      expect(list.items[2].artist, '');
      expect(list.items[2].title, 'Просто название');
    });
  });

  group('разбор ответов сервисов', () {
    test('Яндекс Музыка: альбом', () {
      final list = LinkImporter.parseYandexAlbum({
        'result': {
          'title': 'Группа крови',
          'artists': [
            {'name': 'Кино'}
          ],
          'volumes': [
            [
              {
                'title': 'Группа крови',
                'artists': [
                  {'name': 'Кино'}
                ]
              },
              {
                'title': 'Закрой за мной дверь',
                'artists': <Object>[],
                'version': 'Remastered'
              },
            ]
          ],
        }
      });
      expect(list.name, 'Группа крови');
      expect(list.service, 'Яндекс Музыка');
      expect(list.items.length, 2);
      expect(list.items[0].artist, 'Кино');
      expect(list.items[1].artist, 'Кино'); // исполнитель альбома
      expect(list.items[1].title, 'Закрой за мной дверь (Remastered)');
    });

    test('Spotify: страница embed', () {
      const html = '<html><script id="__NEXT_DATA__" type="application/json">'
          '{"props":{"pageProps":{"state":{"data":{"entity":{"name":"My List",'
          '"trackList":[{"title":"Numb","subtitle":"Linkin Park"},'
          '{"title":"Hello","subtitle":"Adele"}]}}}}}}</script></html>';
      final list = LinkImporter.parseSpotifyHtml(html);
      expect(list.name, 'My List');
      expect(list.items.length, 2);
      expect(list.items[0].title, 'Numb');
      expect(list.items[1].artist, 'Adele');
    });

    test('VK: атрибуты data-audio', () {
      const html = '<div class="audio_row" '
          'data-audio="[123,456,&quot;&quot;,&quot;Группа крови&quot;,&quot;Кино&quot;,280]"></div>';
      final items = LinkImporter.parseVkHtml(html);
      expect(items.length, 1);
      expect(items.first.artist, 'Кино');
      expect(items.first.title, 'Группа крови');
    });

    test('VK: страница без треков (нужен вход) даёт пустой список', () {
      expect(LinkImporter.parseVkHtml('<html>войдите</html>'), isEmpty);
    });
  });

  group('кодировки', () {
    test('windows-1251', () {
      expect(decodeCp1251([0xCF, 0xF0, 0xE8, 0xE2, 0xE5, 0xF2]), 'Привет');
      expect(looksLikeCp1251([0xCA, 0xE8, 0xED, 0xEE]), isTrue);
      expect(looksLikeCp1251('Beyonc'.codeUnits + [0xE9]), isFalse);
    });

    test('HTML-сущности', () {
      expect(unescapeHtml('&quot;A&quot; &amp; B &#39;C&#39; &#x41;'), '"A" & B \'C\' A');
    });
  });
}
