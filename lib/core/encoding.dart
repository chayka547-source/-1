/// Работа с кодировками и HTML-экранированием (без внешних пакетов).

int _cp1251ToUnicode(int b) {
  if (b < 0x80) return b;
  if (b >= 0xC0) return 0x0410 + (b - 0xC0); // А..я
  switch (b) {
    case 0xA8:
      return 0x0401; // Ё
    case 0xB8:
      return 0x0451; // ё
    case 0x85:
      return 0x2026; // …
    case 0x91:
      return 0x2018;
    case 0x92:
      return 0x2019;
    case 0x93:
      return 0x201C;
    case 0x94:
      return 0x201D;
    case 0x96:
      return 0x2013; // –
    case 0x97:
      return 0x2014; // —
    case 0xAB:
      return 0x00AB; // «
    case 0xBB:
      return 0x00BB; // »
    case 0xB9:
      return 0x2116; // №
    default:
      return b;
  }
}

/// Строка из байтов Windows-1251.
String decodeCp1251(List<int> bytes) {
  final buf = StringBuffer();
  for (final b in bytes) {
    buf.writeCharCode(_cp1251ToUnicode(b));
  }
  return buf.toString();
}

/// Старые теги (ID3v1 и ID3v2 с кодировкой «Latin-1») на русских файлах часто
/// на самом деле записаны в Windows-1251. Угадываем: если все «нелатинские»
/// байты попадают в диапазон русских букв и их много — это cp1251.
bool looksLikeCp1251(List<int> bytes) {
  var high = 0; // байты >= 0x80
  var cyr = 0; // из них — русские буквы в cp1251
  var letters = 0; // все буквы (латиница + высокие байты)
  for (final b in bytes) {
    if (b >= 0x80) {
      high++;
      letters++;
      if (b >= 0xC0 || b == 0xA8 || b == 0xB8) cyr++;
    } else if ((b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)) {
      letters++;
    }
  }
  if (high == 0 || cyr != high) return false;
  if (cyr * 2 < letters) return false;
  return cyr >= 2 || letters == high;
}

/// Latin-1 или cp1251 — смотря на что похоже.
String decodeLegacy(List<int> bytes) =>
    looksLikeCp1251(bytes) ? decodeCp1251(bytes) : String.fromCharCodes(bytes);

String _charFromCode(int? code, String fallback) {
  if (code == null || code < 0 || code > 0x10FFFF) return fallback;
  return String.fromCharCode(code);
}

/// Превращает `&quot;`, `&amp;`, `&#39;` и т. п. обратно в символы.
String unescapeHtml(String s) {
  return s
      .replaceAllMapped(RegExp(r'&#(\d+);'),
          (m) => _charFromCode(int.tryParse(m[1]!), m[0]!))
      .replaceAllMapped(RegExp(r'&#[xX]([0-9a-fA-F]+);'),
          (m) => _charFromCode(int.tryParse(m[1]!, radix: 16), m[0]!))
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&');
}
