import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';

extension ThrowableHelper<T> on Subject<T Function()> {
  void throwsWithMessage<E>(
    String message,
    String Function(E exception) onException,
  ) => throws<E>().has(onException, '$E').equals(message);

  void throwsAFormatException(String message) =>
      throwsWithMessage<FormatException>(message, (e) => e.message);

  void throwsParserException(String message) =>
      throwsWithMessage<YamlParseException>(message, (e) => e.message);

  void throwsAnException(String message) =>
      throwsWithMessage<Exception>('Exception: $message', (e) => e.toString());
}
