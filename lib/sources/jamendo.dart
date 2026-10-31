import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models.dart';

/// Каталог легальной музыки Jamendo (Creative Commons, без рекламы).
/// Нужен бесплатный client_id: https://devportal.jamendo.com
class JamendoSource {
  JamendoSource(this.clientId);

  final String clientId;

  static const _base = 'https://api.jamendo.com/v3.0';

  bool get ready => clientId.trim().isNotEmpty;

  Future<List<Track>> search(String query, {int limit = 30}) {
    return _tracks({'search': query, 'limit': '$limit'});
  }

  Future<List<Track>> popular({int limit = 30}) {
    return _tracks({'order': 'popularity_week', 'limit': '$limit'});
  }

  Future<List<Track>> _tracks(Map<String, String> query) async {
    if (!ready) {
      throw Exception('Не указан client_id Jamendo (Настройки)');
    }
    final uri = Uri.parse('$_base/tracks/').replace(queryParameters: {
      'client_id': clientId.trim(),
      'format': 'json',
      'imagesize': '300',
      ...query,
    });
    final resp = await http.get(uri).timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) {
      throw Exception('Jamendo: ошибка ${resp.statusCode}');
    }
    final body = jsonDecode(utf8.decode(resp.bodyBytes));
    if (body is! Map) throw Exception('Jamendo: неожиданный ответ');
    final headers = body['headers'];
    if (headers is Map && headers['status'] != 'success') {
      throw Exception('Jamendo: ${headers['error_message'] ?? 'ошибка запроса'}');
    }
    final results = (body['results'] as List?) ?? const [];
    return results
        .whereType<Map>()
        .map((e) => _fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Track _fromJson(Map<String, dynamic> m) {
    var cover = m['image'] as String?;
    if (cover == null || cover.isEmpty) cover = m['album_image'] as String?;
    final allowed = m['audiodownload_allowed'] == true;
    final dl = allowed ? m['audiodownload'] as String? : null;
    return Track(
      id: 'jamendo:${m['id']}',
      title: (m['name'] as String?) ?? '',
      artist: (m['artist_name'] as String?) ?? '',
      album: (m['album_name'] as String?) ?? '',
      source: 'jamendo',
      coverUrl: (cover != null && cover.isNotEmpty) ? cover : null,
      streamUrl: m['audio'] as String?,
      downloadUrl: (dl != null && dl.isNotEmpty) ? dl : null,
      durationSec: int.tryParse('${m['duration']}') ?? 0,
    );
  }
}
