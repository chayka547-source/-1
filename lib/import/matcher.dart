import 'dart:math';

import '../core/text_norm.dart';
import '../models.dart';
import '../sources/jamendo.dart';
import 'link_importer.dart';

class MatchResult {
  const MatchResult(this.item, [this.track, this.via]);
  final ImportedItem item;
  final Track? track;

  /// Где нашли: «Медиатека» или «Jamendo».
  final String? via;
  bool get found => track != null;
}

class MatchRun {
  const MatchRun(this.results, this.error);
  final List<MatchResult> results;

  /// Первая ошибка поиска в каталоге (например, неверный client_id).
  final String? error;
}

/// Индекс уже известных треков (медиатека, сохранённое, загрузки):
/// отпечатки считаются один раз, кандидаты отбираются по общим словам.
class TrackPool {
  TrackPool(Iterable<Track> tracks) {
    for (final t in tracks) {
      final key = buildTrackKey(t.title, t.artist);
      final i = _tracks.length;
      _tracks.add(t);
      _keys.add(key);
      for (final token in key.indexTokens) {
        (_postings[token] ??= <int>[]).add(i);
      }
    }
  }

  final List<Track> _tracks = <Track>[];
  final List<TrackKey> _keys = <TrackKey>[];
  final Map<String, List<int>> _postings = <String, List<int>>{};

  Track? best(TrackKey wanted) {
    final candidates = <int>{};
    for (final token in wanted.indexTokens) {
      final list = _postings[token];
      if (list != null) candidates.addAll(list);
    }
    Track? best;
    var bestScore = 0.0;
    for (final i in candidates) {
      final s = scoreMatch(wanted, _keys[i]);
      if (s != null && s > bestScore) {
        bestScore = s;
        best = _tracks[i];
      }
    }
    return best;
  }
}

/// Ищет для каждого трека из чужого списка такой же трек у нас:
/// сначала среди своих файлов и сохранённого, потом в каталоге Jamendo.
class Matcher {
  static Track? _bestOf(TrackKey wanted, Iterable<Track> candidates) {
    Track? best;
    var bestScore = 0.0;
    for (final t in candidates) {
      final s = scoreMatch(wanted, buildTrackKey(t.title, t.artist));
      if (s != null && s > bestScore) {
        bestScore = s;
        best = t;
      }
    }
    return best;
  }

  static Future<MatchRun> run(
    List<ImportedItem> items, {
    required List<Track> pool,
    required JamendoSource jamendo,
    void Function(int done, int total)? onProgress,
  }) async {
    final index = TrackPool(pool);
    final results = List<MatchResult?>.filled(items.length, null);
    String? firstError;
    var done = 0;

    Future<void> one(int i) async {
      final it = items[i];
      final wanted = buildTrackKey(it.title, it.artist);
      final local = index.best(wanted);
      if (local != null) {
        results[i] = MatchResult(it, local, 'Медиатека');
      } else if (jamendo.ready) {
        try {
          final q = it.artist.isEmpty ? it.title : '${it.artist} ${it.title}';
          var found = await jamendo.search(q, limit: 15);
          var best = _bestOf(wanted, found);
          if (best == null && it.artist.isNotEmpty) {
            found = await jamendo.search(it.title, limit: 25);
            best = _bestOf(wanted, found);
          }
          if (best != null) results[i] = MatchResult(it, best, 'Jamendo');
        } catch (e) {
          firstError ??= e.toString().replaceFirst('Exception: ', '');
        }
      }
      results[i] ??= MatchResult(it);
      done++;
      onProgress?.call(done, items.length);
    }

    for (var s = 0; s < items.length; s += 4) {
      final end = min(s + 4, items.length);
      await Future.wait([for (var i = s; i < end; i++) one(i)]);
    }
    return MatchRun(results.whereType<MatchResult>().toList(), firstError);
  }
}
