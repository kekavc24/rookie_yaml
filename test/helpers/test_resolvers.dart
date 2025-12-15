import 'package:rookie_yaml/src/parser/delegates/parser_delegate.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';

final class SimpleUtfBuffer extends BytesToScalar<List<int>> {
  SimpleUtfBuffer({
    required super.scalarStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
  });

  final buffer = <int>[];

  @override
  void Function() get onComplete =>
      () => buffer.add(-1); // Spike on complete

  @override
  CharWriter get onWriteRequest => buffer.add;

  @override
  List<int> parsed() => buffer;
}

final class MySetFromMap extends MapToObjectDelegate<Set<String>> {
  MySetFromMap({
    required super.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
  });

  final _mySet = <String>{};

  @override
  bool accept(Object? key, Object? _) {
    _mySet.add(key as String);
    return true;
  }

  @override
  Set<String> parsed() => _mySet;
}

final class MySortedList extends IterableToObjectDelegate<List<int>> {
  MySortedList({
    required super.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
  });

  final list = <int>[];

  @override
  void accept(Object? input) {
    if (input == null) return;
    list.add(input as int);
  }

  @override
  List<int> parsed() {
    list.sort();
    return list;
  }
}
