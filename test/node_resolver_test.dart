import 'package:checks/checks.dart';
import 'package:rookie_yaml/rookie_yaml.dart';
import 'package:rookie_yaml/src/parser/custom_resolvers.dart';
import 'package:test/test.dart';

import 'helpers/exception_helpers.dart';
import 'helpers/test_resolvers.dart';

void main() {
  final listResolver = ObjectFromIterable<List<int>>(
    onCustomIterable: (style, indentLevel, indent, start) => MySortedList(
      collectionStyle: style,
      indentLevel: indentLevel,
      indent: indent,
      start: start,
    ),
  );

  final mapResolver = ObjectFromMap<Set<String>>(
    onCustomMap: (nodeStyle, indentLevel, indent, start) => MySetFromMap(
      collectionStyle: nodeStyle,
      indentLevel: indentLevel,
      indent: indent,
      start: start,
    ),
  );

  final scalarResolver = ObjectFromScalarBytes<List<int>>(
    onCustomScalar: (style, indentLevel, indent, start) => SimpleUtfBuffer(
      scalarStyle: style,
      indentLevel: indentLevel,
      indent: indent,
      start: start,
    ),
  );

  group('Resolvers', () {
    test('Loads a predictable strongly typed set from a map', () {
      // Flow map that has no values
      final sources = [
        '$setTag {  break, key, key, key, cycle }',
        '''
$setTag
? break
? key
key:
cycle:
''',
      ];

      const expected = {'break', 'key', 'cycle'};

      for (final source in sources) {
        check(
          loadDartObject(
            YamlSource.string(source),
            nodeResolvers: {setTag: mapResolver},
          ),
        ).isA<Set<String>>().deepEquals(expected);
      }
    });

    test('Loads a predictable strongly typed sorted list', () {
      final sources = [
        '$sequenceTag [55, 2, 1000, 60, 89]',
        '''
$sequenceTag
- 55
- 2
- 1000
- 60
- 89
''',
      ];

      const expected = [2, 55, 60, 89, 1000];

      for (final source in sources) {
        check(
          loadDartObject(
            YamlSource.string(source),
            nodeResolvers: {sequenceTag: listResolver},
          ),
        ).isA<List<int>>().deepEquals(expected);
      }
    });

    test('Loads a strongly typed sorted list with special block sequences', () {
      check(
        loadDartObject(
          YamlSource.string('''
key: $sequenceTag
- 25
- 2
- 0
- 18
'''),
          nodeResolvers: {sequenceTag: listResolver},
        ),
      ).isA<Map>().which(
        (m) => m.values.first.isA<List<int>>().deepEquals([0, 2, 18, 25]),
      );
    });

    test(
      'Loads a strongly typed set from a block map when leading key has'
      ' properties',
      () {
        check(
          loadDartObject(
            YamlSource.string('''
$setTag 
!!str key:
'''),
            nodeResolvers: {setTag: mapResolver},
          ),
        ).isA<Set<String>>().deepEquals({'key'});
      },
    );
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

    test('Throws when a map can be constructed in the current state', () {
      check(
        () => loadDartObject(
          YamlSource.string('''
$stringTag
!!int key: value
'''),
          nodeResolvers: {stringTag: scalarResolver},
        ),
      ).throwsParserException(
        'Expected the implied start of a custom block map',
      );
    });

    test('Throws when a custom map cannot be parsed', () {
      check(
        () => loadDartObject(
          YamlSource.string('$setTag [flow, sequence]'),
          nodeResolvers: {setTag: mapResolver},
        ),
      ).throwsParserException('Expected a custom map');
    });

    test('Throws when a custom scalar cannot be parsed', () {
      check(
        () => loadDartObject(
          YamlSource.string('$stringTag {key: value}'),
          nodeResolvers: {stringTag: scalarResolver},
        ),
      ).throwsParserException(
        'Expected a scalar that can be parsed as a custom node',
      );
    });
  });
}
