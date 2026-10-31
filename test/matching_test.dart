import 'package:flutter_test/flutter_test.dart';
import 'package:volna/core/text_norm.dart';
import 'package:volna/import/link_importer.dart';
import 'package:volna/import/matcher.dart';
import 'package:volna/models.dart';
import 'package:volna/sources/jamendo.dart';

double? score(String wt, String wa, String ct, String ca) =>
    scoreMatch(buildTrackKey(wt, wa), buildTrackKey(ct, ca));

void main() {
  group('нормализация', () {
    test('апострофы и знаки препинания', () {
      expect(normalizeText("Don't Stop Believin'"), 'dont stop believin');
      expect(normalizeText('Ёлки-палки!'), 'елки палки');
    });

    test('кириллица и латиница сходятся после транслитерации', () {
      expect(toLatin('мумий тролль'), toLatin('mumiy troll'));
      expect(toLatin('лесник'), toLatin('lesnik'));
    });

    test('расстояние Левенштейна', () {
      expect(levenshtein('kitten', 'sitting'), 3);
      expect(levenshtein('', 'abc'), 3);
      expect(levenshtein('abc', 'abc'), 0);
    });
  });

  group('сопоставление треков', () {
    test('один и тот же трек', () {
      expect(score('Группа крови', 'Кино', 'Группа крови', 'Кино'), isNotNull);
      expect(score('Time', 'Pink Floyd', 'Time', 'Pink Floyd'), isNotNull);
    });

    test('игнорирует ремастер, регистр и feat.', () {
      expect(score('Группа крови - 2019 Remaster', 'Кино', 'Группа крови', 'Кино'),
          isNotNull);
      expect(
          score('Smells Like Teen Spirit', 'Nirvana',
              'Smells Like Teen Spirit - Remastered 2011', 'Nirvana'),
          isNotNull);
      expect(
          score('Smoke on the Water', 'Deep Purple',
              'Smoke on the Water (feat. X)', 'Deep Purple'),
          isNotNull);
      expect(score('Звезда по имени Солнце', 'Кино', 'Звезда по имени солнце', 'Кино'),
          isNotNull);
    });

    test('переживает опечатки, артикли и дополнительных исполнителей', () {
      expect(score("Don't Stop Believin'", 'Journey', 'Dont Stop Believing', 'Journey'),
          isNotNull);
      expect(score('Show Must Go On', 'Queen', 'The Show Must Go On', 'Queen'),
          isNotNull);
      expect(score('Numb', 'Linkin Park', 'Numb', 'Linkin Park feat. Jay-Z'),
          isNotNull);
      expect(score('Yesterday', 'The Beatles', 'Yesterday', 'Beatles'), isNotNull);
    });

    test('кириллица ↔ латиница', () {
      expect(score('Владивосток 2000', 'Мумий Тролль', 'Vladivostok 2000', 'Mumiy Troll'),
          isNotNull);
      expect(score('Лесник', 'Король и Шут', 'Lesnik', 'Korol i Shut'), isNotNull);
    });

    test('другая версия — не тот трек', () {
      expect(score('Numb', 'Linkin Park', 'Numb (Live)', 'Linkin Park'), isNull);
      expect(score('Numb', 'Linkin Park', 'Numb - Remix', 'Linkin Park'), isNull);
    });

    test('другое название или другой исполнитель — не тот трек', () {
      expect(score('Love', 'Beatles', 'Lover', 'Beatles'), isNull);
      expect(score('Song 2', 'Blur', 'Song', 'Blur'), isNull);
      expect(score('Hello', 'Adele', 'Hello', 'Lionel Richie'), isNull);
      expect(score('Imagine', 'John Lennon', 'Imagine', 'Imagine Dragons'), isNull);
      expect(score('Я свободен', 'Кипелов', 'Я свободен', 'Ария'), isNull);
      expect(score('Звезда по имени Солнце', 'Кино', 'Кукушка', 'Кино'), isNull);
    });
  });

  group('Matcher', () {
    test('ищет в медиатеке и не находит лишнего', () async {
      const pool = [
        Track(
            id: 'local:1',
            title: 'Группа крови',
            artist: 'Кино',
            source: 'local',
            localFile: 'a.mp3'),
        Track(
            id: 'local:2',
            title: 'Bohemian Rhapsody',
            artist: 'Queen',
            source: 'local',
            localFile: 'b.mp3'),
      ];
      final run = await Matcher.run(
        const [
          ImportedItem('Кино', 'Группа крови (Remastered)'),
          ImportedItem('Queen', 'Bohemian Rhapsody - Live'),
          ImportedItem('Nobody', 'Nothing'),
        ],
        pool: pool,
        jamendo: JamendoSource(''),
      );
      expect(run.results.map((r) => r.found).toList(), [true, false, false]);
      expect(run.results.first.track!.id, 'local:1');
      expect(run.results.first.via, 'Медиатека');
    });
  });
}
