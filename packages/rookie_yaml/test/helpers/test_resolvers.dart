import 'package:rookie_yaml/src/loaders/loader.dart';
import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/state/custom_triggers.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';

T? loadResolvedDartObject<T>(
  String yaml, {
  List<ScalarResolver<Object?>>? resolvers,
  Map<TagShorthand, CustomResolver<Object, Object?>>? nodeResolvers,
  OnCustomList<Object?, Object?>? customList,
  OnCustomMap<Object?, Object?, Object?>? customMap,
  OnCustomScalar<Object?>? customScalar,
  void Function(int index)? onDoctStart,
  void Function(Object? key)? onKeySeen,
  void Function(bool, String)? logger,
}) => loadObject(
  YamlSource.string(yaml),
  triggers: TestTrigger(
    resolvers: resolvers,
    advancedResolvers: nodeResolvers,
    onDoctStart: onDoctStart,
    onKeySeen: onKeySeen,
    customList: customList,
    customMap: customMap,
    customScalar: customScalar,
  ),
  logger: logger,
);

final class TestTrigger extends CustomTriggers {
  TestTrigger({
    super.resolvers,
    super.advancedResolvers,
    void Function(int index)? onDoctStart,
    void Function(Object? key)? onKeySeen,
    OnCustomList<Object?, Object?>? customList,
    OnCustomMap<Object?, Object?, Object?>? customMap,
    OnCustomScalar<Object?>? customScalar,
  }) : _onDocStart = onDoctStart ?? ((_) {}),
       _onKeySeen = onKeySeen ?? ((_) {}),
       _defaultList = customList != null
           ? ObjectFromIterable(onCustomIterable: customList)
           : null,
       _defaultMap = customMap != null
           ? ObjectFromMap(onCustomMap: customMap)
           : null,
       _defaultScalar = customScalar != null
           ? ObjectFromScalarBytes(onCustomScalar: customScalar)
           : null;

  final void Function(int index) _onDocStart;

  final void Function(Object? key) _onKeySeen;

  final ObjectFromIterable<Object?, Object?>? _defaultList;

  final ObjectFromMap<Object?, Object?, Object?>? _defaultMap;

  final ObjectFromScalarBytes<Object?>? _defaultScalar;

  @override
  void onDocumentStart(int index) => _onDocStart(index);

  @override
  void onParsedKey(Object? key) => _onKeySeen(key);

  @override
  ObjectFromMap<K, V, M>? onDefaultMapping<K, V, M>() =>
      _defaultMap as ObjectFromMap<K, V, M>?;

  @override
  ObjectFromIterable<E, L>? onDefaultSequence<E, L>() =>
      _defaultList as ObjectFromIterable<E, L>?;

  @override
  ObjectFromScalarBytes<S>? onDefaultScalar<S>() =>
      _defaultScalar as ObjectFromScalarBytes<S>?;
}

final class SimpleUtfBuffer extends BytesToScalar<List<int>> {
  final buffer = <int>[];

  @override
  CharWriter get onWriteRequest => buffer.add;

  @override
  void onComplete() => buffer.add(-1);

  @override
  List<int> parsed() => buffer;
}

final class MySetFromMap extends MappingToObject<String, String?, Set<String>> {
  final _mySet = <String>{};

  @override
  bool accept(Object? key, Object? _) {
    _mySet.add(key as String);
    return true;
  }

  @override
  Set<String> parsed() => _mySet;
}

final class MySortedList extends SequenceToObject<int, List<int>> {
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
