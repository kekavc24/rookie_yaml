import 'package:checks/checks.dart';
import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/loaders/loader.dart';
import 'package:test/test.dart';

void main() {
  group('Generic Dart objects', () {
    group('Scalars', () {
      test('Loads string scalars as primitive Dart String', () {
        const string = 'normal';
        check(
          loadObject(YamlSource.string(string)),
        ).isA<String>().equals(string);
      });

      test('Loads int scalars as primitive Dart int', () {
        const integer = 24;

        check(
          loadObject(YamlSource.string('24')),
        ).isA<int>().equals(integer);
        check(
          loadObject(YamlSource.string('0x18')),
        ).isA<int>().equals(integer);
        check(
          loadObject(YamlSource.string('0o30')),
        ).isA<int>().equals(integer);
      });

      test('Loads float scalars as primitive Dart float', () {
        check(
          loadObject(YamlSource.string('24.0')),
        ).isA<double>().equals(24.0);
      });

      test('Loads boolean scalars as primitive Dart bool', () {
        check(loadObject(YamlSource.string('false'))).isA<bool>().isFalse();
        check(loadObject(YamlSource.string('true'))).isA<bool>().isTrue();
      });

      test('Loads null scalars as primitive Dart null', () {
        check(loadObject(YamlSource.string('null'))).isNull();
        check(loadObject(YamlSource.string('NULL'))).isNull();
        check(loadObject(YamlSource.string('~'))).isNull();
        check(loadObject(YamlSource.string(''))).isNull();
      });
    });

    test('Loads sequence as a dynamic Dart List', () {
      const list = [
        24.0,
        true,
        24,
        'value',
        null,
        {'key': 'value'},
        ['value'],
      ];

      check(
        loadObject(YamlSource.string(list.toString())),
      ).isA<List>().deepEquals(list);
    });

    test('Loads mapping as a dynamic Dart Map', () {
      final map = {
        'key': 'value',
        ['value']: 'list',
        {'map': 'key'}: 'map',
        'last': {
          [true, null, 24]: 'value',
        },
      };

      check(
        DeepCollectionEquality().equals(
          loadObject(YamlSource.string(map.toString())),
          map,
        ),
      ).isTrue();
    });

    group('Aliases', () {
      const yaml = '''
- &list [ flow, &map { key: value } ]
- *list
- *map
''';

      const node = [
        [
          'flow',
          {'key': 'value'},
        ],
        [
          'flow',
          {'key': 'value'},
        ],
        {'key': 'value'},
      ];

      test('Loads node with anchor and aliases', () {
        check(
          loadObject<List>(YamlSource.string(yaml)),
        ).isA<List>().deepEquals(node);
      });

      test('Dereferences list and map aliases', () {
        final sequence = loadObject<List>(
          YamlSource.string(yaml),
          dereferenceAliases: true,
        );

        check(sequence?[0]).not((list) => list.equals(sequence?[1]));
        check(sequence?[0][1]).not((map) => map.equals(sequence?[2]));
      });
    });
  });

  test('Loads multiple documents dynamically', () {
    const documents = [
      24,
      ['value'],
      {'key': 'value'},
    ];

    check(
      loadAllObjects(
        // Separate with document end marker!
        YamlSource.string(
          documents.map((doc) => '$doc\n...').join('\n').toString(),
        ),
      ),
    ).deepEquals(documents);
  });
}
