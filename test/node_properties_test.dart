import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/directives/directives.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';
import 'package:test/test.dart';

import 'helpers/bootstrap_parser.dart';
import 'helpers/exception_helpers.dart';
import 'helpers/model_helpers.dart';

void main() {
  group('Parses non-specific local tags', () {
    test('Parses simple tags', () {
      final tag = LocalTag.fromTagUri(TagHandle.primary(), 'test-tag');
      print(tag);

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
      final yaml = '''
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
