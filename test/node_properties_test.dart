import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';
import 'package:test/test.dart';

import 'helpers/bootstrap_parser.dart';
import 'helpers/exception_helpers.dart';
import 'helpers/model_helpers.dart';

void main() {
  group('Tag properties', () {
    test('Parses simple tags', () {
      final testTag = TagShorthand.fromTagUri(TagHandle.primary(), 'test-tag');
      final yaml =
          '''
$testTag plain-scalar
---
$testTag "double quoted"
---
$testTag 'single quoted'
---
$testTag {flow: map}
---
$testTag [flow, sequence]
---
$testTag
block: map
---
$testTag
- block sequence
''';

      check(bootstrapDocParser(yaml).parsedNodes())
        ..length.equals(7)
        ..every((n) => n.hasTag(testTag));
    });

    test('Parses tags nested in flow map', () {
      final entryTag = TagShorthand.fromTagUri(
        TagHandle.primary(),
        'simple-kv',
      );
      final mapTag = TagShorthand.fromTagUri(TagHandle.primary(), 'flow-map');

      final yaml =
          '''
$mapTag {
$entryTag key: $entryTag value,
$entryTag key0: $entryTag value
}
''';

      check(
          bootstrapDocParser(yaml).parseNodeSingle(),
        ).isA<Mapping>()
        ..hasTag(mapTag)
        ..has((m) => m.entries, 'Flow Map Entries').every(
          (e) => e
            ..has(
              (e) => e.key,
              'Flow Map Key',
            ).isA<YamlSourceNode>().hasTag(entryTag)
            ..has((e) => e.value, 'Flow Map Value').hasTag(entryTag),
        );
    });

    test('Parses tags in flow sequence', () {
      final seqEntryTag = TagShorthand.fromTagUri(
        TagHandle.primary(),
        'seq-entry',
      );
      final seqTag = TagShorthand.fromTagUri(TagHandle.primary(), 'flow-seq');

      final yaml =
          '''
$seqTag [
$seqEntryTag "double quoted",
$seqEntryTag plain
  multiline, $seqEntryTag 'single quoted',

  $seqEntryTag {flow: map-string},

  $seqEntryTag compact-flow-map: 'tag goes to key'
]
''';

      final parsed = bootstrapDocParser(yaml).parseNodeSingle();

      // First 5 elements have tags.
      check(parsed).isA<Sequence>()
        ..hasTag(seqTag)
        ..has(
          (e) => e.take(4),
          'First 5 entries',
        ).every((e) => e.hasTag(seqEntryTag))
        ..which(
          // The last element's tag is given to the key
          (s) => s.last.isA<Mapping>()
            ..hasTag(yamlGlobalTag, suffix: mappingTag)
            ..has(
              (e) => e.keys.firstOrNull,
              'Single key',
            ).isNotNull().isA<YamlSourceNode>().hasTag(seqEntryTag),
        );
    });

    test('Parses tags in a block map', () {
      final kvTag = TagShorthand.fromTagUri(TagHandle.primary(), 'block-kv');

      final yaml =
          '''
$kvTag key: $kvTag value
$kvTag key0: $kvTag value
? $kvTag >
 key1
: $kvTag value
''';

      check(
          bootstrapDocParser(yaml).parseNodeSingle(),
        ).isA<Mapping>()
        ..hasTag(yamlGlobalTag, suffix: mappingTag)
        ..has((m) => m.entries, 'Block Map Entries').every(
          (e) => e
            ..has(
              (e) => e.key,
              'Block Map Key',
            ).isA<YamlSourceNode>().hasTag(kvTag)
            ..has((e) => e.value, 'Block Map Value').hasTag(kvTag),
        );
    });

    test('Parses tags in block sequence', () {
      final blockSeqTag = TagShorthand.fromTagUri(
        TagHandle.primary(),
        'block-seq',
      );
      final seqTag = TagShorthand.fromTagUri(TagHandle.primary(), 'seq');

      final yaml =
          '''
$seqTag
- $blockSeqTag "double quoted"

- $blockSeqTag plain
  multiline

- $blockSeqTag 'single quoted'

- $blockSeqTag >
  folded

- $blockSeqTag |
  literal

- $blockSeqTag [flow, sequence]
- $blockSeqTag {flow: map}

- compact: map
  not: allowed-properties

- ? compact-key: also
    not: allowed-properties
''';

      final parsed = bootstrapDocParser(
        yaml,
      ).parseNodeSingle();

      check(parsed).isA<Sequence>()
        ..hasTag(seqTag)
        ..has(
          (e) => e.take(7),
          'First 7 entries',
        ).every((e) => e.hasTag(blockSeqTag))
        ..has(
          (s) => s.skip(7),
          'Trailing elements',
        ).every((e) => e.hasTag(yamlGlobalTag, suffix: mappingTag));
    });
  });

  group('Anchors & alias', () {
    test('Parses simple anchor and alias', () {
      const yaml = '''
&a key: &b [ &c value ]

*b : &d { *a : *b }

*c :
  &e
  - ? *a
    : *b
  - *c

*d : *e
''';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        {
          'key': ['value'],

          ['value']: {
            'key': ['value'],
          },

          'value': [
            {
              'key': ['value'],
            },
            'value',
          ],

          {
            'key': ['value'],
          }: [
            {
              'key': ['value'],
            },
            'value',
          ],
        }.toString(),
      );
    });

    test('References flow key before entire entry is parsed', () {
      const yaml = '''
{
  &flow-key key: *flow-key ,

  &seq-key another: [
    *flow-key ,

    &multi-line-entry
    {key: *seq-key} ,

    *multi-line-entry ,

    &for-key key: *for-key
  ],

  *multi-line-entry
}
''';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        {
          'key': 'key',
          'another': [
            'key',
            {'key': 'another'},
            {'key': 'another'},
            {'key': 'key'},
          ],
          {'key': 'another'}: null,
        }.toString(),
      );
    });

    test('References block key before entire entry is parsed', () {
      const yaml = '''
&key key: *key

? &another another
: *another
''';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        {'key': 'key', 'another': 'another'}.toString(),
      );
    });

    test('Parses trailing flow sequence aliases', () {
      const yaml = '''
[
  &anchor value,

  [ *anchor ], # Single trailing
  [ *anchor , *anchor ],
  *anchor
]
''';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        [
          'value',
          ['value'],
          ['value', 'value'],
          'value',
        ].toString(),
      );
    });

    test('Parses compact block map with alias as key in block sequence', () {
      const yaml = '''
- &anchor value
- *anchor
- *anchor : *anchor
''';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(
        [
          'value',
          'value',
          {'value': 'value'},
        ].toString(),
      );
    });
  });

  group(
    'Uses the minimum indent if a node is less indented than '
    'its properties',
    () {
      test('Variant [1]', () {
        check(
          bootstrapDocParser('''
-     !too-indented
  - hello
''').nodeAsSimpleString(),
        ).equals(
          [
            ['hello'],
          ].toString(),
        );
      });

      test('Variant [2]', () {
        check(
          bootstrapDocParser('''
?     !too-indented
  - hello
:             !even-further-indented
  - hello
''').nodeAsSimpleString(),
        ).equals(
          {
            ['hello']: ['hello'],
          }.toString(),
        );
      });

      test('Variant [3]', () {
        check(
          bootstrapDocParser('''
implicit:     !even-in-implicit
  - hello
''').nodeAsSimpleString(),
        ).equals(
          {
            'implicit': ['hello'],
          }.toString(),
        );
      });
    },
  );

  group('Attempts to compose a block map if multiple multiline properties '
      'are seen', () {
    test('Variant [1]', () {
      check(
        bootstrapDocParser('''
&must-be-map
&definitely key: value
''').nodeAsSimpleString(),
      ).equals(
        {'key': 'value'}.toString(),
      );
    });

    test('Variant [2]', () {
      check(
        bootstrapDocParser('''
- &anchor key
- &map
  *anchor : value
''').nodeAsSimpleString(),
      ).equals(
        [
          'key',
          {'key': 'value'},
        ].toString(),
      );
    });

    test('Variant [3]: Throws if impossible', () {
      check(
        () => bootstrapDocParser('''
&throw
&not key
'''),
      ).throwsParserException(
        'Expected an (implied) block map with property "throw"',
      );
    });
  });

  group('Exceptions', () {
    test('Throws when an unknown secondary tag is used', () {
      final tag = '!!unknown-tag';
      final yaml = '$tag ignored :)';

      check(
        () => bootstrapDocParser(yaml).parseNodeSingle(),
      ).throwsParserException(
        'Invalid secondary tag. Expected any of: '
        '$mappingTag, $orderedMappingTag, '
        '$sequenceTag, $setTag, '
        '$stringTag, $nullTag, $booleanTag, $integerTag or $floatTag',
      );
    });

    test('Throws when a named tag has no global tag alias', () {
      final tag = '!unknown-alias!string';
      final yaml = '$tag ignored :)';

      check(
        () => bootstrapDocParser(yaml).parseNodeSingle(),
      ).throwsParserException(
        'Named tags must have a corresponding global tag',
      );
    });

    test('Throws when a named tag has no suffix', () {
      final tag = '!no-suffix!';
      final yaml =
          '''
%TAG $tag !indeed
---
$tag ignored :)
''';

      check(
        () => bootstrapDocParser(yaml).parseNodeSingle(),
      ).throwsParserException('Named tags must have a non-empty suffix');
    });

    test('Throws when a tag is declared for a compact flow node', () {
      final yaml = '''
[
  !compact-tag
  key: value
]
''';

      check(
        () => bootstrapDocParser(yaml).parseNodeSingle(),
      ).throwsParserException('Invalid flow collection state. Expected "]"');
    });

    test(
      'Throws when tags are used before explicit keys in block and flow styles',
      () {
        check(
          () => bootstrapDocParser('&anchor ? explicit-key').parseNodeSingle(),
        ).throwsParserException(
          'An explicit key cannot be forced to be implicit or have inline '
          'properties before its indicator',
        );

        check(
          () => bootstrapDocParser(
            '''
? key
: okay

!error ? never-parsed
''',
          ).parseNodeSingle(),
        ).throwsParserException(
          'An explicit key cannot be forced to be implicit or have inline '
          'properties before its indicator',
        );

        check(
          () => bootstrapDocParser(
            '''
? key
: okay

!error
? even-when-on-a-new-line
''',
          ).parseNodeSingle(),
        ).throwsParserException(
          'Implicit block nodes cannot span multiple lines',
        );

        check(
          () => bootstrapDocParser(
            '''
{
? key
: okay,

!error
? also-applies-to-flow
}
''',
          ).parseNodeSingle(),
        ).throwsParserException(
          'Flow node cannot span multiple lines when implicit',
        );
      },
    );

    test('Throws when tags are multiline in implicit keys', () {
      check(
        () => bootstrapDocParser(
          '''
!tag-okay implicit-1: is-fine

!this-is-not-okay
implicit-2: is-an-error
''',
        ).parseNodeSingle(),
      ).throwsParserException(
        'Implicit block nodes cannot span multiple lines',
      );

      check(
        () => bootstrapDocParser(
          '''
{
!tag-okay implicit-1: is-fine,

!this-is-not-okay
implicit-2: is-an-error}
''',
        ).parseNodeSingle(),
      ).throwsParserException(
        'Flow node cannot span multiple lines when implicit',
      );
    });

    test('Throws when tags are declared before block sequence indicator', () {
      check(
        () => bootstrapDocParser(
          '!!seq - not-okay',
        ).parseNodeSingle(),
      ).throwsParserException(
        'A block sequence cannot be forced to be implicit or have inline '
        'properties before its indicator',
      );

      check(
        () => bootstrapDocParser('''
!experimental-okay-1st
- first

!not-and-unlikely-okay
- second
''').parseNodeSingle(),
      ).throwsParserException('Expected a "- " at the start of the next entry');
    });

    test('Throws when non-existent alias is used', () {
      const alias = 'value';

      check(
        () => bootstrapDocParser('key: *$alias').parseNodeSingle(),
      ).throwsParserException('Alias is not a valid anchor reference');
    });

    test('Throws when an anchor is declared for a compact flow node', () {
      final yaml = '''
[
  !compact-anchor
  key: value
]
''';

      check(
        () => bootstrapDocParser(yaml).parseNodeSingle(),
      ).throwsParserException('Invalid flow collection state. Expected "]"');
    });

    test('Throws when a multiline property is less indented than its '
        'block node', () {
      const message =
          'A block node cannot be indented more that its'
          ' properties';

      for (final parent in const ['?', '-']) {
        check(
          () => bootstrapDocParser('''
$parent 
  &invalid
    - value
'''),
        ).throwsParserException(message);

        check(
          () => bootstrapDocParser('''
$parent
  &invalid
    ? value
'''),
        ).throwsParserException(message);

        check(
          () => bootstrapDocParser('''
$parent
  &invalid
    > 
     value
'''),
        ).throwsParserException(message);

        check(
          () => bootstrapDocParser('''
$parent
  &invalid
    | 
      value
'''),
        ).throwsParserException(message);
      }
    });

    test("Throws when block node has an anchor or tag after an alias", () {
      check(
        () => bootstrapDocParser('''
key:
  *alias
  &anchor
'''),
      ).throwsParserException(
        'Invalid block node state. Duplicate properties implied the'
        ' start of a block map but a block map cannot be composed in the'
        ' current state',
      );
    });
  });
}
