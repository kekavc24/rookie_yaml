import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/directives/directives.dart';
import 'package:rookie_yaml/src/schema/nodes/node.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';
import 'package:test/test.dart';

import 'helpers/bootstrap_parser.dart';
import 'helpers/exception_helpers.dart';
import 'helpers/model_helpers.dart';

void main() {
  group('Tag properties', () {
    test('Parses simple tags', () {
      final tag = LocalTag.fromTagUri(TagHandle.primary(), 'test-tag');
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

      check(bootstrapDocParser(yaml).parsedNodes().toList())
        ..length.equals(7)
        ..every((n) => n.hasTag(tag));
    });

    test('Parses tags nested in flow map', () {
      final entryTag = LocalTag.fromTagUri(TagHandle.primary(), 'simple-kv');
      final mapTag = LocalTag.fromTagUri(TagHandle.primary(), 'flow-map');

      final yaml =
          '''
$mapTag {
$entryTag key: $entryTag value,
$entryTag key0: $entryTag value
}
''';

      check(bootstrapDocParser(yaml).parseNodeSingle()).isA<Mapping>()
        ..hasTag(mapTag)
        ..has((m) => m.entries, 'Flow Map Entries').every(
          (e) => e
            ..has((e) => e.key, 'Flow Map Key').hasTag(entryTag)
            ..has((e) => e.value, 'Flow Map Value').hasTag(entryTag),
        );
    });

    test('Parses tags in flow sequence', () {
      final seqEntryTag = LocalTag.fromTagUri(TagHandle.primary(), 'seq-entry');
      final seqTag = LocalTag.fromTagUri(TagHandle.primary(), 'flow-seq');

      final yaml =
          '''
$seqTag [
$seqEntryTag "double quoted",
$seqEntryTag plain
  multiline, $seqEntryTag 'single quoted',

  $seqEntryTag {flow: map-string},

  $seqEntryTag
  compact-flow-map: 'entire tag goes to compact map',

  $seqEntryTag compact-flow-map: 'tag goes to key'
]
''';

      final parsed = bootstrapDocParser(yaml).parseNodeSingle();

      // First 5 elements have tags.
      check(parsed).isA<Sequence>()
        ..hasTag(seqTag)
        ..has(
          (e) => e.take(5),
          'First 5 entries',
        ).every((e) => e.hasTag(seqEntryTag));

      // The last element's tag is given to the key
      check((parsed as Sequence).last).isA<Mapping>()
        ..hasNoTag()
        ..has(
          (e) => e.keys.firstOrNull,
          'Single key',
        ).isNotNull().hasTag(seqEntryTag);
    });

    test('Parses tags in a block map', () {
      final kvTag = LocalTag.fromTagUri(TagHandle.primary(), 'block-kv');

      final yaml =
          '''
$kvTag key: $kvTag value
$kvTag key0: $kvTag value
? $kvTag >
 key1
: $kvTag value
''';

      check(bootstrapDocParser(yaml).parseNodeSingle()).isA<Mapping>()
        ..hasNoTag()
        ..has((m) => m.entries, 'Block Map Entries').every(
          (e) => e
            ..has((e) => e.key, 'Block Map Key').hasTag(kvTag)
            ..has((e) => e.value, 'Block Map Value').hasTag(kvTag),
        );
    });

    test('Parses tags in block sequence', () {
      final blockSeqTag = LocalTag.fromTagUri(TagHandle.primary(), 'block-seq');
      final seqTag = LocalTag.fromTagUri(TagHandle.primary(), 'seq');

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

      final parsed = bootstrapDocParser(yaml).parseNodeSingle();

      check(parsed).isA<Sequence>()
        ..hasTag(seqTag)
        ..has(
          (e) => e.take(7),
          'First 7 entries',
        ).every((e) => e.hasTag(blockSeqTag));

      check((parsed as Sequence).skip(7))
        ..length.equals(2)
        ..every((e) => e.hasNoTag());
    });

    test('Throws when an unknown secondary tag is used', () {
      final tag = '!!unknown-tag';
      final yaml = '$tag ignored :)';

      check(
        () => bootstrapDocParser(yaml).parseNodeSingle(),
      ).throwsAFormatException(
        'Unrecognized secondary tag "$tag". Expected any of: $yamlTags',
      );
    });

    test('Throws when a named tag has no global tag alias', () {
      final tag = '!unknown-alias!string';
      final yaml = '$tag ignored :)';

      check(
        () => bootstrapDocParser(yaml).parseNodeSingle(),
      ).throwsAFormatException(
        'Named tag "$tag" has no corresponding global tag',
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
      ).throwsAFormatException(
        'Named tag "$tag" has no suffix',
      );
    });
  });
}
