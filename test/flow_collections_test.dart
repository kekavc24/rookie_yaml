import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'helpers/bootstrap_parser.dart';
import 'helpers/exception_helpers.dart';

void main() {
  group('Flow Maps', () {
    test('Parses simple flow map', () {
      const yaml =
          '{'
          'one: "double-quoted", '
          "two: 'single-quoted', "
          'three: plain value, '
          'four: [sequence], '
          'five: {flow: map}'
          '}';

      check(
        bootstrapDocParser(yaml).parseDocs().nodeAsSimpleString(),
      ).equals(
        {
          'one': 'double-quoted',
          'two': 'single-quoted',
          'three': 'plain value',
          'four': ['sequence'],
          'five': {'flow': 'map'},
        }.toString(),
      );
    });

    test('Parses implicit and explicit keys', () {
      const yaml =
          '{ implicit key: value,'
          '? explicit key: value }';

      check(
        bootstrapDocParser(yaml).parseDocs().nodeAsSimpleString(),
      ).equals({'implicit key': 'value', 'explicit key': 'value'}.toString());
    });

    test('Parses empty entry node declared explicitly', () {
      const yaml = '{ ? }';

      check(
        bootstrapDocParser(yaml).parseDocs().nodeAsSimpleString(),
      ).equals({null: null}.toString());
    });

    test('Parses implicit entry with missing keys/values', () {
      const yaml =
          '{'
          'implicit: with value ,'
          'implicit-with-no-value: ,'
          'implicit-with-no-colon ,'
          ': value-with-no-key'
          '}';

      check(
        bootstrapDocParser(yaml).parseDocs().nodeAsSimpleString(),
      ).equals(
        {
          'implicit': 'with value',
          'implicit-with-no-value': null,
          'implicit-with-no-colon': null,
          null: 'value-with-no-key',
        }.toString(),
      );
    });

    test('Parses json-like keys without restrictions', () {
      // JSON-like keys need not have space after ":"
      const yaml =
          '{'
          '{ JSON-like-map: as-key }:"value" ,'
          '[JSON, like, sequence, as-key]:"value" ,'
          '"JSON-like-double-quoted":"value" ,'
          "'JSON-like-single-quoted':'value'"
          '}';

      check(
        bootstrapDocParser(yaml).parseDocs().nodeAsSimpleString(),
      ).equals(
        {
          {'JSON-like-map': 'as-key'}: 'value',
          ['JSON', 'like', 'sequence', 'as-key']: 'value',
          'JSON-like-double-quoted': 'value',
          'JSON-like-single-quoted': 'value',
        }.toString(),
      );
    });

    test("Throws if flow map doesn't start/end with map delimiters", () {
      check(
        () => bootstrapDocParser('}').parseDocs().nodeAsSimpleString(),
      ).throwsAFormatException(
        'Leading "," "}" or "]" flow indicators found with no opening "["'
        ' "{"',
      );

      check(
        () => bootstrapDocParser('{').parseDocs().nodeAsSimpleString(),
      ).throwsAFormatException(
        'Expected the flow delimiter: "}" but found: "nothing"',
      );
    });

    test('Throws if duplicate keys are found', () {
      const yaml = '{key: value, key: value}';

      check(
        () => bootstrapDocParser(yaml).parseDocs().nodeAsSimpleString(),
      ).throwsAFormatException(
        'Flow map cannot contain duplicate entries by the same key',
      );
    });

    test('Throws if "," is declared before key', () {
      check(
        () => bootstrapDocParser('{,}').parseDocs().nodeAsSimpleString(),
      ).throwsAFormatException(
        'Expected at least a key in the flow map entry but found ","',
      );

      check(
        () => bootstrapDocParser('{key,,}').parseDocs().nodeAsSimpleString(),
      ).throwsAFormatException(
        'Expected at least a key in the flow map entry but found ","',
      );
    });

    test("Throws if implicit key spans multiple lines", () {
      check(
        () => bootstrapDocParser(
          '{'
          'implicit-key-not-inline'
          '\n splits-here'
          ': value'
          '}',
        ).parseDocs().nodeAsSimpleString(),
      ).throwsAFormatException(
        'Expected a next flow entry indicator "," or a map value indicator ":" '
        'or a terminating delimiter "}"',
      );
    });
  });

  group('Flow Sequences', () {
    test('Parses simple flow sequence', () {
      const yaml = '[one, two, three, four]';

      check(
        bootstrapDocParser(yaml).parseDocs().nodeAsSimpleString(),
      ).equals(['one', 'two', 'three', 'four'].toString());
    });

    test('Parses flow sequence with various flow node types', () {
      const yaml = '''
[
"double
 quoted", 'single
           quoted',
plain
 text, [ nested ],
implicit: pair,
? explicit
  key: pair
]
''';

      check(
        bootstrapDocParser(yaml).parseDocs().nodeAsSimpleString(),
      ).equals(
        [
          'double quoted',
          'single quoted',
          'plain text',
          ['nested'],
          {'implicit': 'pair'},
          {'explicit key': 'pair'},
        ].toString(),
      );
    });

    test(
      "Throws if flow sequence doesn't start/end with sequence delimiters",
      () {
        check(
          () => bootstrapDocParser(']').parseDocs().nodeAsSimpleString(),
        ).throwsAFormatException(
          'Leading "," "}" or "]" flow indicators found with no opening "["'
          ' "{"',
        );

        check(
          () => bootstrapDocParser('[').parseDocs().nodeAsSimpleString(),
        ).throwsAFormatException(
          'Expected the flow delimiter: "]" but found: "nothing"',
        );
      },
    );

    test('Throws if "," is declared before entry', () {
      check(
        () => bootstrapDocParser('[,]').parseDocs().nodeAsSimpleString(),
      ).throwsAFormatException(
        'Expected to find the first value but found ","',
      );

      check(
        () => bootstrapDocParser('[value,,]').parseDocs().nodeAsSimpleString(),
      ).throwsAFormatException(
        'Found a duplicate "," before finding a flow sequence entry',
      );
    });
  });
}
