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
        bootstrapDocParser(yaml).nodeAsSimpleString(),
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
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals({'implicit key': 'value', 'explicit key': 'value'}.toString());
    });

    test('Parses empty entry node declared explicitly', () {
      const yaml = '{ ? }';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
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
        bootstrapDocParser(yaml).nodeAsSimpleString(),
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
        bootstrapDocParser(yaml).nodeAsSimpleString(),
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
        () => bootstrapDocParser('}').nodeAsSimpleString(),
      ).throwsAFormatException(
        'Leading closing "}" or "]" flow indicators found with no opening "["'
        ' "{"',
      );

      check(
        () => bootstrapDocParser('{').nodeAsSimpleString(),
      ).throwsAFormatException(
        'Expected the flow delimiter: Indicator.mappingEnd "}" but found: '
        '"nothing"',
      );
    });

    test('Throws if duplicate keys are found', () {
      const yaml = '{key: value, key: value}';

      check(
        () => bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).throwsAFormatException(
        'Flow map cannot contain duplicate entries by the same key',
      );
    });

    test('Throws if "," is declared before key', () {
      check(
        () => bootstrapDocParser('{,}').nodeAsSimpleString(),
      ).throwsAFormatException(
        'Expected at least a key in the flow map entry but found ","',
      );

      check(
        () => bootstrapDocParser('{key,,}').nodeAsSimpleString(),
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
        ).nodeAsSimpleString(),
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
        bootstrapDocParser(yaml).nodeAsSimpleString(),
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
        bootstrapDocParser(yaml).nodeAsSimpleString(),
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
          () => bootstrapDocParser(']').nodeAsSimpleString(),
        ).throwsAFormatException(
          'Leading closing "}" or "]" flow indicators found with no opening "["'
          ' "{"',
        );

        check(
          () => bootstrapDocParser('[').nodeAsSimpleString(),
        ).throwsAFormatException(
          'Expected the flow delimiter: Indicator.flowSequenceEnd "]" but '
          'found: "nothing"',
        );
      },
    );

    test('Throws if "," is declared before entry', () {
      check(
        () => bootstrapDocParser('[,]').nodeAsSimpleString(),
      ).throwsAFormatException(
        'Expected to find the first value but found ","',
      );

      check(
        () => bootstrapDocParser('[value,,]').nodeAsSimpleString(),
      ).throwsAFormatException(
        'Found a duplicate "," before finding a flow sequence entry',
      );
    });
  });
}
