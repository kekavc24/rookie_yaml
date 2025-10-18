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
      final tag = TagShorthand.fromTagUri(TagHandle.primary(), 'test-tag');
      final yaml =
          '''
$tag plain-scalar
---
$tag "double quoted"
---
$tag 'single quoted'
---
$tag {flow: map}
---
$tag [flow, sequence]
---
$tag
block: map
---
$tag
- block sequence
''';

      check(bootstrapDocParser(yaml).parseDocuments().parsedNodes())
        ..length.equals(7)
        ..every((n) => n.hasTag(tag));
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
          bootstrapDocParser(yaml).parseDocuments().parseNodeSingle(),
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

      final parsed = bootstrapDocParser(
        yaml,
      ).parseDocuments().parseNodeSingle();

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
          bootstrapDocParser(yaml).parseDocuments().parseNodeSingle(),
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
      ).parseDocuments().parseNodeSingle();

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

    test('Throws when an unknown secondary tag is used', () {
      final tag = '!!unknown-tag';
      final yaml = '$tag ignored :)';

      check(
        () => bootstrapDocParser(yaml).parseDocuments().parseNodeSingle(),
      ).throwsParserException(
        'Invalid secondary tag. Expected any of: $mappingTag, $sequenceTag, '
        '${scalarTags.join(', ')}',
      );
    });

    test('Throws when a named tag has no global tag alias', () {
      final tag = '!unknown-alias!string';
      final yaml = '$tag ignored :)';

      check(
        () => bootstrapDocParser(yaml).parseDocuments().parseNodeSingle(),
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
        () => bootstrapDocParser(yaml).parseDocuments().parseNodeSingle(),
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
        () => bootstrapDocParser(yaml).parseDocuments().parseNodeSingle(),
      ).throwsParserException(
        'Compact implicit map entries cannot have properties',
      );
    });

    test(
      'Throws when tags are used before explicit keys in block and flow styles',
      () {
        check(
          () => bootstrapDocParser(
            '!!str ? explicit-key',
          ).parseDocuments().parseNodeSingle(),
        ).throwsParserException(
          'Inline node properties cannot be declared before the first "? "'
          ' indicator',
        );

        check(
          () => bootstrapDocParser(
            '''
? key
: okay

!error ? never-parsed
''',
          ).parseDocuments().parseNodeSingle(),
        ).throwsParserException(
          'Explicit keys cannot have any node properties before the "?" '
          'indicator',
        );

        check(
          () => bootstrapDocParser(
            '''
? key
: okay

!error
? even-when-on-a-new-line
''',
          ).parseDocuments().parseNodeSingle(),
        ).throwsParserException(
          'Explicit keys cannot have any node properties before the "?" '
          'indicator',
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
          ).parseDocuments().parseNodeSingle(),
        ).throwsParserException(
          'Explicit keys cannot have any node properties before the "?" '
          'indicator',
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
        ).parseDocuments().parseNodeSingle(),
      ).throwsParserException(
        'Node properties for an implicit block key cannot span multiple lines',
      );

      check(
        () => bootstrapDocParser(
          '''
{
!tag-okay implicit-1: is-fine,

!this-is-not-okay
implicit-2: is-an-error}
''',
        ).parseDocuments().parseNodeSingle(),
      ).throwsParserException(
        'Node properties for an implicit flow key cannot span multiple lines',
      );
    });

    test('Throws when tags are declared before block sequence indicator', () {
      check(
        () => bootstrapDocParser(
          '!!str - not-okay',
        ).parseDocuments().parseNodeSingle(),
      ).throwsParserException(
        'Inline node properties cannot be declared before the first "- "'
        ' indicator',
      );

      const yaml = '''
!experimental-okay-1st
- first

!not-and-unlikely-okay
- second
''';

      check(
        () => bootstrapDocParser(yaml).parseDocuments().parseNodeSingle(),
      ).throwsParserException(
        'Dangling node properties are not allowed here',
      );
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
        bootstrapDocParser(yaml).parseDocuments().nodeAsSimpleString(),
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
        bootstrapDocParser(yaml).parseDocuments().nodeAsSimpleString(),
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
        bootstrapDocParser(yaml).parseDocuments().nodeAsSimpleString(),
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
        bootstrapDocParser(yaml).parseDocuments().nodeAsSimpleString(),
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
        bootstrapDocParser(yaml).parseDocuments().nodeAsSimpleString(),
      ).equals(
        [
          'value',
          'value',
          {'value': 'value'},
        ].toString(),
      );
    });

    test('Throws when non-existent alias is used', () {
      const alias = 'value';

      check(
        () => bootstrapDocParser(
          'key: *$alias',
        ).parseDocuments().parseNodeSingle(),
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
        () => bootstrapDocParser(yaml).parseDocuments().parseNodeSingle(),
      ).throwsParserException(
        'Compact implicit map entries cannot have properties',
      );
    });
  });
}
