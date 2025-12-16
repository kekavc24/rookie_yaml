import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';

final class SimpleUtfBuffer extends BytesToScalar<List<int>> {
  final buffer = <int>[];

  @override
  CharWriter get onWriteRequest => buffer.add;

  @override
  void onComplete() => buffer.add(-1);

  @override
  List<int> parsed() => buffer;
}

final class MySetFromMap extends MappingToObject<Set<String>> {
  final _mySet = <String>{};

  @override
  bool accept(Object? key, Object? _) {
    _mySet.add(key as String);
    return true;
  }

  @override
  Set<String> parsed() => _mySet;
}

final class MySortedList extends SequenceToObject<List<int>> {
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
