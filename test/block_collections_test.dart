import 'package:checks/checks.dart';
import 'package:test/test.dart';

import 'helpers/bootstrap_parser.dart';
import 'helpers/exception_helpers.dart';

void main() {
  group('Block maps', () {
    test('Parses simple block map', () {
      const yaml =
          'one: "double-quoted"\n'
          "two: 'single-quoted'\n"
          'three: plain value\n'
          'four: [flow sequence]\n'
          'five: {flow: map}\n'
          'six:\n'
          ' - block sequence';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        {
          'one': 'double-quoted',
          'two': 'single-quoted',
          'three': 'plain value',
          'four': ['flow sequence'],
          'five': {'flow': 'map'},
          'six': ['block sequence'],
        }.toString(),
      );
    });

    test('Parses explicit keys', () {
      const yaml = '''
? # Empty node

? plain-key-with-empty-value # No value

? |
  block-key
: - value
  - value

? >
  folded
  key
: [value, value]

? - block
  - sequence
  - key
: {flow: value}

? {flow:
  map, ? as: key}
: "double quoted value"

? block: map
  as: key
: 'single quoted value'

? ? nested explicit key
  : nested value
: value

''';

      check(bootstrapDocParser(yaml).nodeAsSimpleString()).equals(
        {
          null: null,
          'plain-key-with-empty-value': null,
          'block-key\n': ['value', 'value'],
          'folded key\n': ['value', 'value'],
          ['block', 'sequence', 'key']: {'flow': 'value'},
          {'flow': 'map', 'as': 'key'}: 'double quoted value',
          {'block': 'map', 'as': 'key'}: 'single quoted value',
          {'nested explicit key': 'nested value'}: 'value',
        }.toString(),
      );
    });

    test('Parses implicit keys', () {
      const yaml = '''
: # Empty node

'key': # Key with no value

"key0": value # Key with inline value

key1:
  nested: block map

key2:
  - block sequence

key3:
- block indicator as indent
''';

      check(bootstrapDocParser(yaml).nodeAsSimpleString()).equals(
        {
          null: null,
          'key': null,
          'key0': 'value',
          'key1': {'nested': 'block map'},
          'key2': ['block sequence'],
          'key3': ['block indicator as indent'],
        }.toString(),
      );
    });

    test('Throws if dangling ":" is not inline with "?"', () {
      const yaml = '''
?   - extremely indented block list
  : dangling value
''';

      check(
        () => bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).throwsAFormatException(
        'Expected ":" on a new line with an indent of 0 space(s) and'
        ' not 2 space(s)',
      );
    });

    test('Throws if block sequence is used as an implicit key', () {
      const yaml = '''
implicit: map

- rogue block key:
    value
''';

      check(
        () => bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).throwsAFormatException(
        'Implicit keys are restricted to a single line. Consider using an'
        ' explicit key for the entry',
      );
    });

    test('Throws if implicit key spans multiple lines', () {
      const yaml = '''
implicit: map

rogue
 implicit key: value
''';

      check(
        () => bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).throwsAFormatException('Expected a ":" (after the key) but found "i"');
    });

    test('Throws if a block sequence is inline with block implicit key', () {
      const yaml =
          'implicit:'
          ' - block sequence value # Block lists start on new line';

      check(
        () => bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).throwsAFormatException(
        'The block collections must start on a new line'
        ' when used as values of an implicit key',
      );
    });

    test('Throws if dangling map entry', () {
      const yaml = '''
implicit:
    nested: map
  dangling: map
''';

      check(
        () => bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).throwsAFormatException(
        'Dangling node/node properties found with indent of 2 space(s) while parsing',
      );
    });
  });

  group('Block Sequences', () {
    test('Parses block sequence', () {
      const yaml = '''
- "double quoted"
- 'single quoted'
- plain
- |
 literal
- >
 folded
- [flow, sequence]
- {flow: map}
- block: map
  nested: well
- - nested
  - sequence''';

      check(bootstrapDocParser(yaml).nodeAsSimpleString()).equals(
        [
          'double quoted',
          'single quoted',
          'plain',
          'literal\n',
          'folded\n',
          ['flow', 'sequence'],
          {'flow': 'map'},
          {'block': 'map', 'nested': 'well'},
          ['nested', 'sequence'],
        ].toString(),
      );
    });

    test('Parses block sequence with compact block nodes', () {
      const yaml = '''
- ? compact: explicit
  : - nested
    - sequence
  implicit: compact
- - compact
  - sequence:
     ? nested: block
     : as value
''';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        [
          {
            {'compact': 'explicit'}: ['nested', 'sequence'],
            'implicit': 'compact',
          },
          [
            'compact',
            {
              'sequence': {
                {'nested': 'block'}: 'as value',
              },
            },
          ],
        ].toString(),
      );
    });

    test('Exits gracefully if doc markers are declared within sequence', () {
      const markers = ['---\n', '...\n'];

      const plain = 'block with doc markers';
      final sequenceStr = [plain].toString();

      const yaml = '- $plain\n';
      const trailing = '- ignored';

      for (final marker in markers) {
        check(
          bootstrapDocParser('$yaml$marker$trailing').nodeAsSimpleString(),
        ).equals(sequenceStr);
      }
    });

    test('Throws if a node has missing "- "', () {
      const yaml =
          '- value\n'
          '-error';

      check(
        () => bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).throwsAFormatException(
        'Expected a "- " while parsing sequence but found "-e"',
      );
    });

    test('Throws if dangling nested block entry is encountered', () {
      const yaml = '''
- first
-  - nested second
  - dangling third
''';

      check(
        () => bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).throwsAFormatException(
        'Dangling node/node properties found with indent of 2 space(s) while'
        ' parsing',
      );
    });
  });
}
