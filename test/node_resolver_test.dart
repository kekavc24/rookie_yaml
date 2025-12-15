import 'package:checks/checks.dart';
import 'package:rookie_yaml/rookie_yaml.dart';
import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:rookie_yaml/src/parser/delegates/parser_delegate.dart';
import 'package:test/test.dart';

import 'helpers/exception_helpers.dart';

final class _MySetFromMap extends MapToObjectDelegate<Set<String>> {
  _MySetFromMap({
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

final class _MySortedList extends IterableToObjectDelegate<List<int>> {
  _MySortedList({
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

void main() {
  final listResolver = ObjectFromIterable<List<int>>(
    onCustomIterable: (style, indentLevel, indent, start) => _MySortedList(
      collectionStyle: style,
      indentLevel: indentLevel,
      indent: indent,
      start: start,
    ),
  );

  final mapResolver = ObjectFromMap<Set<String>>(
    onCustomMap: (nodeStyle, indentLevel, indent, start) => _MySetFromMap(
      collectionStyle: nodeStyle,
      indentLevel: indentLevel,
      indent: indent,
      start: start,
    ),
  );

  group('Resolvers', () {
    test('Loads a predictable strongly typed set from a map', () {
      // Flow map that has no values
      final source = '$setTag {  break, key, key, key, cycle }';

      check(
        loadDartObject(
          YamlSource.string(source),
          nodeResolvers: {setTag: mapResolver},
        ),
      ).isA<Set<String>>().deepEquals({'break', 'key', 'cycle'});
    });

    test('Loads a predictable strongly typed sorted list', () {
      final source = '$sequenceTag [55, 2, 1000, 60, 89]';

      check(
        loadDartObject(
          YamlSource.string(source),
          nodeResolvers: {sequenceTag: listResolver},
        ),
      ).isA<List<int>>().deepEquals([2, 55, 60, 89, 1000]);
    });
  });

  group('Exceptions', () {
    test('Throws when a block node is inline with the custom properties', () {
      check(
        () => loadDartObject(
          YamlSource.string('$setTag ? key'),
          nodeResolvers: {setTag: mapResolver},
        ),
      ).throwsParserException(
        'A block sequence/map cannot be forced to be implicit or have inline '
        'properties before its indicator',
      );

      check(
        () => loadDartObject(
          YamlSource.string('$sequenceTag - sequence'),
          nodeResolvers: {sequenceTag: listResolver},
        ),
      ).throwsParserException(
        'A block sequence/map cannot be forced to be implicit or have inline '
        'properties before its indicator',
      );
    });
  });
}
