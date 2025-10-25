import 'package:checks/checks.dart';
import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/parser/yaml_parser.dart';
import 'package:test/test.dart';

void main() {
  group('Generic Dart objects', () {
    group('Scalars', () {
      test('Loads string scalars as primitive Dart String', () {
        const string = 'normal';
        check(loadDartObject(source: string)).isA<String>().equals(string);
      });

      test('Loads int scalars as primitive Dart int', () {
        const integer = 24;

        check(loadDartObject(source: '24')).isA<int>().equals(integer);
        check(loadDartObject(source: '0x18')).isA<int>().equals(integer);
        check(loadDartObject(source: '0o30')).isA<int>().equals(integer);
      });

      test('Loads float scalars as primitive Dart float', () {
        check(loadDartObject(source: '24.0')).isA<double>().equals(24.0);
      });

      test('Loads boolean scalars as primitive Dart bool', () {
        check(loadDartObject(source: 'false')).isA<bool>().isFalse();
        check(loadDartObject(source: 'true')).isA<bool>().isTrue();
      });

      test('Loads null scalars as primitive Dart null', () {
        check(loadDartObject(source: 'null')).isNull();
        check(loadDartObject(source: 'NULL')).isNull();
        check(loadDartObject(source: '~')).isNull();
        check(loadDartObject(source: '')).isNull();
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
        loadDartObject(source: list.toString()),
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
          loadDartObject(source: map.toString()),
          map,
        ),
      ).isTrue();
    });
  });

  test('Loads multiple documents dynamically', () {
    const documents = [
      24,
      ['value'],
      {'key': 'value'},
    ];

    check(
      loadAsDartObjects(
        // Separate with document end marker!
        source: documents.map((doc) => '$doc\n...').join('\n').toString(),
      ),
    ).deepEquals(documents);
  });
}
