import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/state/custom_triggers.dart';
import 'package:rookie_yaml/src/parser/loaders/loader.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';

T? loadResolvedDartObject<T>(
  String yaml, {
  List<ScalarResolver<Object?>>? resolvers,
  Map<TagShorthand, CustomResolver>? nodeResolvers,
  OnCustomList<Object>? customList,
  OnCustomMap<Object>? customMap,
  OnCustomScalar<Object>? customScalar,
  void Function(int index)? onDoctStart,
  void Function(Object? key)? onKeySeen,
  void Function(bool, String)? logger,
}) => loadDartObject(
  YamlSource.string(yaml),
  triggers: TestTrigger(
    resolvers: resolvers,
    customResolvers: nodeResolvers,
    onDoctStart: onDoctStart,
    onKeySeen: onKeySeen,
    customList: customList,
    customMap: customMap,
    customScalar: customScalar,
  ),
  logger: logger,
);

final class TestTrigger extends CustomTriggers {
  TestTrigger._({
    super.resolvers,
    super.advancedResolvers,
    void Function(int index)? onDoctStart,
    void Function(Object? key)? onKeySeen,
    OnCustomList<Object>? customList,
    OnCustomMap<Object>? customMap,
    OnCustomScalar<Object>? customScalar,
  }) : _onDocStart = onDoctStart ?? ((_) {}),
       _onKeySeen = onKeySeen ?? ((_) {}),
       _defaultList = customList,
       _defaultMap = customMap,
       _defaultScalar = customScalar;

  final void Function(int index) _onDocStart;

  final void Function(Object? key) _onKeySeen;

  final OnCustomList<Object>? _defaultList;

  final OnCustomMap<Object>? _defaultMap;

  final OnCustomScalar<Object>? _defaultScalar;

  factory TestTrigger({
    List<ScalarResolver<Object?>>? resolvers,
    Map<TagShorthand, CustomResolver>? customResolvers,
    void Function(int index)? onDoctStart,
    void Function(Object? key)? onKeySeen,
    OnCustomList<Object>? customList,
    OnCustomMap<Object>? customMap,
    OnCustomScalar<Object>? customScalar,
  }) {
    final creators = (resolvers ?? []).fold(
      <TagShorthand, ResolverCreator<Object?>>{},
      (p, c) {
        final ScalarResolver(:target, :onTarget) = c;
        p[target] = onTarget;
        return p;
      },
    );

    return TestTrigger._(
      resolvers: creators,
      advancedResolvers: customResolvers,
      onDoctStart: onDoctStart,
      onKeySeen: onKeySeen,
      customList: customList,
      customMap: customMap,
      customScalar: customScalar,
    );
  }

  @override
  void onDocumentStart(int index) => _onDocStart(index);

  @override
  void onParsedKey(Object? key) => _onKeySeen(key);

  @override
  OnCustomMap<M>? onDefaultMapping<M>() => _defaultMap as OnCustomMap<M>?;

  @override
  OnCustomList<L>? onDefaultSequence<L>() => _defaultList as OnCustomList<L>?;

  @override
  OnCustomScalar<S>? onDefaultScalar<S>() =>
      _defaultScalar as OnCustomScalar<S>?;
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
