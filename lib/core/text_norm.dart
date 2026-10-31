import 'dart:math' as math;

/// Сравнение названий треков и исполнителей «по смыслу»:
/// игнорирует регистр, знаки препинания, «feat.», «(Remastered)», путает «ё/е»,
/// переживает опечатки и сопоставляет кириллицу с латиницей («Кино» ≈ «Kino»).
/// Версии «live / remix / acoustic…» должны совпадать: студийный трек не
/// подменяется концертным.

final RegExp _apostrophes = RegExp("['’‘`´]");
final RegExp _nonWord = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
final RegExp _spaces = RegExp(r'\s+');
final RegExp _bracketRe = RegExp(r'[\(\[\{]([^\)\]\}]*)[\)\]\}]');
final RegExp _featRe =
    RegExp(r'\s(?:feat\.?|ft\.?|featuring|при уч\.?|при участии)\s.*$');
final RegExp _dashSuffixRe = RegExp(r'\s[-–—]\s(.*)$');
final RegExp _versionWordRe = RegExp(
    r'remaster|live|version|mix|edit|remix|mono|stereo|acoustic|instrumental|'
    r'single|radio|demo|deluxe|bonus|reprise|ремастер|верси|концерт|ремикс|'
    r'акустик|инструментал');
final RegExp _remixRe = RegExp(r'remix|ремикс|rmx');
final RegExp _doubleChars = RegExp(r'(.)\1');

final Map<String, RegExp> _tagPatterns = <String, RegExp>{
  'remix': _remixRe,
  'live': RegExp(r'\blive\b|концерт|вживую'),
  'acoustic': RegExp(r'acoustic|акустик|акустич'),
  'instrumental': RegExp(r'instrumental|инструментал|karaoke|караоке'),
  'cover': RegExp(r'\bcover\b|кавер'),
  'slowed': RegExp(r'slowed|sped up|speed up|nightcore'),
};

const Set<String> _unknownArtists = <String>{
  'unknown',
  'unknown artist',
  'неизвестный исполнитель',
  'неизвестен',
  'various artists',
  'various',
  'разные исполнители',
  'va',
  'без исполнителя',
};

const Set<String> _artistStop = <String>{
  'feat',
  'ft',
  'featuring',
  'and',
  'и',
  'vs',
  'with',
};

const Map<String, String> _translit = <String, String>{
  'а': 'a',
  'б': 'b',
  'в': 'v',
  'г': 'g',
  'д': 'd',
  'е': 'e',
  'ж': 'zh',
  'з': 'z',
  'и': 'i',
  'й': 'i',
  'к': 'k',
  'л': 'l',
  'м': 'm',
  'н': 'n',
  'о': 'o',
  'п': 'p',
  'р': 'r',
  'с': 's',
  'т': 't',
  'у': 'u',
  'ф': 'f',
  'х': 'h',
  'ц': 'c',
  'ч': 'ch',
  'ш': 'sh',
  'щ': 'sh',
  'ъ': '',
  'ы': 'i',
  'ь': '',
  'э': 'e',
  'ю': 'u',
  'я': 'a',
};

// Упрощения латиницы, чтобы «Mumiy» и «Mumii», «Yuri» и «Юрий» совпадали.
const List<String> _foldFrom = <String>[
  'kh',
  'ts',
  'ph',
  'ck',
  'yu',
  'ya',
  'yo',
  'ye',
  'y',
  'x',
  'w',
];
const List<String> _foldTo = <String>[
  'h',
  'c',
  'f',
  'k',
  'u',
  'a',
  'o',
  'e',
  'i',
  'ks',
  'v',
];

/// Нижний регистр, «ё»→«е», без апострофов и знаков препинания, пробелы по одному.
String normalizeText(String input) {
  var t = input.toLowerCase().replaceAll('ё', 'е');
  t = t.replaceAll(_apostrophes, '');
  t = t.replaceAll('&', ' and ');
  t = t.replaceAll(_nonWord, ' ');
  return t.replaceAll(_spaces, ' ').trim();
}

/// Кириллица → латиница + упрощение; вход — уже нормализованная строка.
String toLatin(String normalized) {
  final sb = StringBuffer();
  for (final rune in normalized.runes) {
    final ch = String.fromCharCode(rune);
    sb.write(_translit[ch] ?? ch);
  }
  var t = sb.toString();
  for (var i = 0; i < _foldFrom.length; i++) {
    t = t.replaceAll(_foldFrom[i], _foldTo[i]);
  }
  return t.replaceAllMapped(_doubleChars, (m) => m[1]!);
}

/// Расстояние Левенштейна.
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var curr = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    final ca = a.codeUnitAt(i - 1);
    for (var j = 1; j <= b.length; j++) {
      final cost = ca == b.codeUnitAt(j - 1) ? 0 : 1;
      curr[j] = math.min(
        math.min(curr[j - 1] + 1, prev[j] + 1),
        prev[j - 1] + cost,
      );
    }
    final tmp = prev;
    prev = curr;
    curr = tmp;
  }
  return prev[b.length];
}

/// «Отпечаток» трека для сравнения.
class TrackKey {
  TrackKey._({
    required this.core,
    required this.coreLatin,
    required this.artistNorm,
    required this.artistTokens,
    required this.artistLatinTokens,
    required this.tags,
  });

  /// Название без скобок, «feat.» и пометок о ремастере — нормализованное.
  final String core;
  final String coreLatin;
  final String artistNorm;
  final Set<String> artistTokens;
  final Set<String> artistLatinTokens;

  /// Версия трека: remix, live, acoustic, instrumental, cover, slowed.
  final Set<String> tags;

  bool get artistKnown => artistTokens.isNotEmpty;

  /// Слова для быстрого поиска кандидатов в большой медиатеке.
  Set<String> get indexTokens {
    final out = <String>{};
    for (final s in <String>[core, coreLatin]) {
      for (final t in s.split(' ')) {
        if (t.isNotEmpty) out.add(t);
      }
    }
    return out;
  }
}

/// «The Show Must Go On» ≈ «Show Must Go On».
String _stripArticle(String s) {
  for (final a in const <String>['the ', 'a ', 'an ']) {
    if (s.startsWith(a) && s.length > a.length + 2) {
      return s.substring(a.length);
    }
  }
  return s;
}

/// Строит отпечаток по названию и исполнителю.
TrackKey buildTrackKey(String title, String artist) {
  final lowerTitle = title.toLowerCase();
  var raw = lowerTitle;
  final qualifiers = StringBuffer();

  raw = raw.replaceAllMapped(_bracketRe, (m) {
    qualifiers.write(' ${m[1]} ');
    return ' ';
  });
  final dash = _dashSuffixRe.firstMatch(raw);
  if (dash != null && _versionWordRe.hasMatch(dash.group(1)!)) {
    qualifiers.write(' ${dash.group(1)} ');
    raw = raw.substring(0, dash.start);
  }
  raw = raw.replaceFirst(_featRe, '');

  final q = qualifiers.toString();
  final tags = <String>{};
  _tagPatterns.forEach((tag, re) {
    if (re.hasMatch(q)) tags.add(tag);
  });
  if (_remixRe.hasMatch(lowerTitle)) tags.add('remix');

  var core = normalizeText(raw);
  if (core.isEmpty) core = normalizeText(title);
  core = _stripArticle(core);

  final artistNorm = normalizeText(artist);
  final tokens = artistNorm
      .split(' ')
      .where((t) => t.isNotEmpty && !_artistStop.contains(t))
      .toSet();
  final known = tokens.isNotEmpty && !_unknownArtists.contains(artistNorm);

  return TrackKey._(
    core: core,
    coreLatin: toLatin(core),
    artistNorm: artistNorm,
    artistTokens: known ? tokens : <String>{},
    artistLatinTokens: known ? tokens.map(toLatin).toSet() : <String>{},
    tags: tags,
  );
}

double _jaccard(List<String> a, List<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final sa = a.toSet();
  final sb = b.toSet();
  final inter = sa.intersection(sb).length;
  return inter / (sa.length + sb.length - inter);
}

double _stringSimilarity(String x, String y) {
  if (x.isEmpty || y.isEmpty) return 0;
  if (x == y) return 1;
  final tx = x.split(' ');
  final ty = y.split(' ');
  // Короткие однословные названия («Love», «Hurt») — только точное совпадение.
  if (tx.length == 1 && ty.length == 1 && math.min(x.length, y.length) < 7) {
    return 0;
  }
  final jac = _jaccard(tx, ty);
  final longer = math.max(x.length, y.length);
  final shorter = math.min(x.length, y.length);
  if (shorter / longer < 0.6) return jac;
  final lev = 1 - levenshtein(x, y) / longer;
  return math.max(lev, jac);
}

bool _tokenEquals(String x, String y) {
  if (x == y) return true;
  if (x.length < 4 || y.length < 4) return false;
  if ((x.length - y.length).abs() > 2) return false;
  return 1 - levenshtein(x, y) / math.max(x.length, y.length) >= 0.8;
}

/// Доля слов меньшего набора, нашедших пару в большем.
double _containment(Set<String> a, Set<String> b) {
  if (a.isEmpty || b.isEmpty) return 0;
  final small = a.length <= b.length ? a : b;
  final large = a.length <= b.length ? b : a;
  var hit = 0;
  for (final t in small) {
    if (large.any((u) => _tokenEquals(t, u))) hit++;
  }
  return hit / small.length;
}

/// Насколько совпадают названия: 0..1.
double titleSimilarity(TrackKey a, TrackKey b) =>
    math.max(_stringSimilarity(a.core, b.core),
        _stringSimilarity(a.coreLatin, b.coreLatin));

/// Насколько совпадают исполнители: 0..1 (оба должны быть известны).
double artistSimilarity(TrackKey a, TrackKey b) {
  final byWords = _containment(a.artistTokens, b.artistTokens);
  final byLatin = _containment(a.artistLatinTokens, b.artistLatinTokens);
  return math.max(byWords, byLatin);
}

/// Оценка совпадения искомого трека [wanted] с кандидатом [cand].
/// Возвращает null, если это не тот трек; иначе число от 0 до 1 (больше — лучше).
double? scoreMatch(TrackKey wanted, TrackKey cand) {
  if (wanted.tags.length != cand.tags.length ||
      !wanted.tags.containsAll(cand.tags)) {
    return null; // разные версии
  }
  final ts = titleSimilarity(wanted, cand);
  if (ts < 0.82) return null;
  double artistScore;
  if (wanted.artistKnown && cand.artistKnown) {
    artistScore = artistSimilarity(wanted, cand);
    if (artistScore < 0.6) return null;
  } else {
    // Исполнитель неизвестен хотя бы с одной стороны — нужно почти точное название.
    if (ts < 0.97) return null;
    artistScore = 0.5;
  }
  return ts * 0.7 + artistScore * 0.3;
}
