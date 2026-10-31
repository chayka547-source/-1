// Настраивает Android-проект, созданный командой `flutter create`,
// для фонового воспроизведения музыки (just_audio_background) и ставит иконку.
//
// Запуск из корня проекта:  dart run tool/patch_android.dart
// (Dart входит в состав Flutter — отдельно ничего ставить не нужно.)
import 'dart:io';

const String _permissions = '''
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
''';

const String _components = '''
        <service
            android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true"
            tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>
        <receiver
            android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true"
            tools:ignore="Instantiatable">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
    </application>''';

void main(List<String> args) {
  final root = args.isNotEmpty ? args.first : '.';
  final manifest = File('$root/android/app/src/main/AndroidManifest.xml');
  if (!manifest.existsSync()) {
    stderr.writeln('Не найден ${manifest.path}. Сначала выполните: '
        'flutter create --org com.volna --project-name volna --platforms=android .');
    exit(1);
  }

  var text = manifest.readAsStringSync();
  if (text.contains('com.ryanheise.audioservice.AudioService')) {
    print('AndroidManifest.xml уже настроен — пропускаю');
  } else {
    if (!text.contains('xmlns:tools')) {
      text = text.replaceFirst(
          '<manifest', '<manifest xmlns:tools="http://schemas.android.com/tools"');
    }
    if (!text.contains('<application') || !text.contains('</application>')) {
      stderr.writeln('В AndroidManifest.xml нет тега application — формат неожиданный');
      exit(1);
    }
    text = text.replaceFirst('<application', '$_permissions    <application');
    text = text.replaceFirst(
        RegExp(r'android:label="[^"]*"'), 'android:label="Волна"');
    text = text.replaceFirst('</application>', _components);
    manifest.writeAsStringSync(text);
    print('AndroidManifest.xml обновлён');
  }

  // MainActivity должна наследоваться от AudioServiceActivity.
  final kotlinDir = Directory('$root/android/app/src/main/kotlin');
  final javaDir = Directory('$root/android/app/src/main/java');
  var patched = false;
  if (kotlinDir.existsSync()) {
    for (final f in kotlinDir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('MainActivity.kt')) continue;
      final m = RegExp(r'^package\s+([\w.]+)', multiLine: true)
          .firstMatch(f.readAsStringSync());
      if (m == null) {
        stderr.writeln('В ${f.path} нет строки package');
        exit(1);
      }
      f.writeAsStringSync('package ${m.group(1)}\n\n'
          'import com.ryanheise.audioservice.AudioServiceActivity\n\n'
          'class MainActivity : AudioServiceActivity()\n');
      print('${f.path} обновлён');
      patched = true;
    }
  }
  if (!patched && javaDir.existsSync()) {
    for (final f in javaDir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('MainActivity.java')) continue;
      final m = RegExp(r'^package\s+([\w.]+);', multiLine: true)
          .firstMatch(f.readAsStringSync());
      if (m == null) continue;
      f.writeAsStringSync('package ${m.group(1)};\n\n'
          'import com.ryanheise.audioservice.AudioServiceActivity;\n\n'
          'public class MainActivity extends AudioServiceActivity {}\n');
      print('${f.path} обновлён');
      patched = true;
    }
  }
  if (!patched) {
    stderr.writeln('Не найден MainActivity.kt / MainActivity.java');
    exit(1);
  }

  // Иконка приложения (необязательно): assets/icon/android/mipmap-*/ic_launcher.png
  final iconRoot = Directory('$root/assets/icon/android');
  if (iconRoot.existsSync()) {
    for (final dir in iconRoot.listSync().whereType<Directory>()) {
      final name = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final src = File('${dir.path}/ic_launcher.png');
      final dst = Directory('$root/android/app/src/main/res/$name');
      if (src.existsSync() && dst.existsSync()) {
        src.copySync('${dst.path}/ic_launcher.png');
        print('Иконка: $name');
      }
    }
  }
}
