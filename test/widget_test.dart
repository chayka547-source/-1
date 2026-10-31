// Файл нужен, чтобы `flutter create` не подставил свой шаблонный тест,
// который ссылается на несуществующий класс MyApp.
import 'package:flutter_test/flutter_test.dart';
import 'package:volna/ui/widgets.dart';

void main() {
  test('форматирование времени и размера', () {
    expect(fmtDuration(const Duration(minutes: 3, seconds: 5)), '3:05');
    expect(fmtBytes(5 * 1024 * 1024), '5.0 МБ');
  });
}
