import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/yaml_document.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';
import 'package:test/test.dart';

import 'helpers/bootstrap_parser.dart';
import 'helpers/document_helper.dart';
import 'helpers/exception_helpers.dart';
import 'helpers/model_helpers.dart';

void main() {
  group('YamlDocument', () {
    test('Parses bare documents', () {
      final docs = bootstrapDocParser(docStringAs(YamlDocType.bare)).toList();

      check(docs).every(
        (d) => d
          ..hasVersionDirective(parserVersion)
          ..hasGlobalTags({})
          ..isDocOfType(YamlDocType.bare)
          ..isDocStartExplicit().isFalse()
          ..isDocEndExplicit().isTrue(),
      );

      check(docs.nodesAsSimpleString()).unorderedEquals(parsed);
    });

    test('Parses explicit document', () {
      final docs = bootstrapDocParser(
        docStringAs(YamlDocType.explicit),
      ).toList();

      check(docs).every(
        (d) => d
          ..hasVersionDirective(parserVersion)
          ..hasGlobalTags({})
          ..isDocOfType(YamlDocType.explicit)
          ..isDocStartExplicit().isTrue()
          ..isDocEndExplicit().isTrue(),
      );

      check(docs.nodesAsSimpleString()).unorderedEquals(parsed);
    });

    test('Parses directive doc', () {
      final globalWithLocal = GlobalTag.fromTagShorthand(
        TagHandle.named('with-tag'),
        TagShorthand.fromTagUri(TagHandle.primary(), 'tag'),
      );

      final globalWithUri = GlobalTag.fromTagUri(
        TagHandle.named('with-uri'),
        'fake-uri://uri',
      );

      const reserved = '%RESERVED directive is restricted';

      final yamlDirective = YamlDirective.ofVersion(1, 0);

      const node = 'simple node';

      final yaml =
          '''
$yamlDirective
$globalWithLocal
$globalWithUri
$reserved
---
$node
...
''';

      final doc = bootstrapDocParser(yaml).firstOrNull;

      check(doc).isNotNull()
        ..hasVersionDirective(yamlDirective)
        ..hasGlobalTags({globalWithUri, globalWithLocal})
        ..isDocOfType(YamlDocType.directiveDoc)
        ..isDocStartExplicit().isTrue()
        ..isDocEndExplicit().isTrue()
        ..which(
          (d) => d.hasNode()
            ..hasTag(yamlGlobalTag, suffix: stringTag)
            ..asSimpleString(node),
        );
    });

    test('Parses doc when on same line as directive end markers', () {
      const yaml = '''
--- simple
plain scalar

--- "double
quoted"

--- 'single
quoted'

--- |
literal

--- >
folded

--- ['sequence']

--- {key: value}
''';

      check(bootstrapDocParser(yaml)).every(
        (d) => d
          ..isDocStartExplicit().isTrue()
          ..isDocEndExplicit().isFalse()
          ..hasNode().withTag().isNotNull(),
      );
    });

    test('Parses empty-ish documents', () {
      const yaml = '''
# Just comments
...
...
!just-a-tag # Treated as a string
...
''';

      check(bootstrapDocParser(yaml))
        ..length.equals(3)
        ..every((d) => d.isDocEndExplicit().isTrue())
        ..has((d) => d.take(2).map((e) => e.root), 'Leading elements').every(
          (e) => e.isA<Scalar>().has((s) => s.value, 'Value').isNull(),
        )
        ..has((d) => d.last.root, 'Trailing element').isA<Scalar>().which(
          (s) => s.has((s) => s.value, 'Value').isA<String>().isEmpty(),
        );
    });

    test('Defaults to plain scalar if not directive end marker', () {
      const yaml = '-- just a plain scalar';

      check(
        bootstrapDocParser(yaml).nodeAsSimpleString(),
      ).equals(yaml);
    });
  });

  group('Tags', () {
    test('Assigns shorthand as is if not resolved', () {
      final tag = TagShorthand.fromTagUri(TagHandle.primary(), 'not-resolved');

      final yaml =
          '''
$tag yaml
''';

      check(
        bootstrapDocParser(yaml).parseNodeSingle(),
      ).hasTag(tag);
    });

    test('Resolves shorthands with primary tag handles', () {
      final globalTag = GlobalTag.fromTagShorthand(
        TagHandle.primary(),
        TagShorthand.fromTagUri(TagHandle.primary(), 'test-tag-for-'),
      );

      final suffix = TagShorthand.fromTagUri(
        TagHandle.primary(),
        'primary-handles',
      );

      final yaml =
          '''
$globalTag
---
$suffix node
''';

      check(
        bootstrapDocParser(yaml).parseNodeSingle(),
      ).hasTag(globalTag, suffix: suffix);
    });

    test(
      'Resolves shorthands with secondary handle to the YAML global tag',
      () {
        final yaml = '$stringTag node';

        check(
          bootstrapDocParser(yaml).parseNodeSingle(),
        ).hasTag(yamlGlobalTag, suffix: stringTag);
      },
    );

    test('Redeclares secondary handle to use custom global tag', () {
      final globalTag = GlobalTag.fromTagShorthand(
        TagHandle.secondary(),
        TagShorthand.fromTagUri(
          TagHandle.primary(),
          'redeclared-for-secondary-handles',
        ),
      );

      final yaml =
          '''
$globalTag
---
$stringTag node
''';

      check(
        bootstrapDocParser(yaml).parseNodeSingle(),
      ).hasTag(globalTag, suffix: stringTag);
    });

    test('Resolves named shorthands to custom declaration', () {
      final handle = TagHandle.named('named');

      final globalTag = GlobalTag.fromTagShorthand(
        handle,
        TagShorthand.fromTagUri(TagHandle.primary(), 'tag'),
      );

      final suffix = TagShorthand.fromTagUri(handle, 'suffix');

      final yaml =
          '''
$globalTag
---
$suffix
''';

      check(
        bootstrapDocParser(yaml).parseNodeSingle(),
      ).hasTag(globalTag, suffix: suffix);
    });

    test(
      'Resolves a handle based on the global tag declaration for each document',
      () {
        final telescope = TagHandle.primary();

        final firstGlobal = GlobalTag.fromTagShorthand(
          telescope,
          TagShorthand.fromTagUri(TagHandle.primary(), 'primary-galaxy'),
        );

        final secondGlobal = GlobalTag.fromTagUri(
          telescope,
          'secondary://galaxy',
        );

        final star = TagShorthand.fromTagUri(
          telescope,
          'same-star-different-galaxy',
        );

        final yaml =
            '''
$firstGlobal
---
$star
...
$secondGlobal
---
$star
---
$star
''';

        final docs = bootstrapDocParser(
          yaml,
        ).parsedNodes().toList();

        check(docs).length.equals(3);

        check(docs[0]).hasTag(firstGlobal, suffix: star);
        check(docs[1]).hasTag(secondGlobal, suffix: star);

        // Not resolved to any global tag
        check(docs[2]).hasTag(star);
      },
    );

    test('Resolves non-specific tags based on kind', () {
      check(
          bootstrapDocParser('! { ! [], ! scalar }').parseNodeSingle(),
        ).isNotNull().isA<Mapping>()
        ..hasTag(yamlGlobalTag, suffix: mappingTag)
        ..has((map) => map.keys, 'Keys').which(
          (keys) => keys
            ..has((k) => k.firstOrNull, 'First element').which(
              (e) => e.isA<Sequence>().hasTag(
                yamlGlobalTag,
                suffix: sequenceTag,
              ),
            )
            ..has((k) => k.lastOrNull, 'Last element').which(
              (e) => e.isA<Scalar>().hasTag(yamlGlobalTag, suffix: stringTag),
            ),
        );
    });
  });

  group('Exceptions', () {
    test('Throws exception when a named tag is used as global tag prefix', () {
      final global = GlobalTag.fromTagShorthand(
        TagHandle.named('okay'),
        TagShorthand.fromTagUri(TagHandle.named('not-okay'), 'tag'),
      );

      final yaml =
          '''
$global
---
never parsed
''';

      /// Once leading "!" is seen, the rest are treated as normal tag uri
      /// where "!" must be escaped
      check(
        () => bootstrapDocParser(yaml),
      ).throwsParserException(
        'Tag indicator must escaped when used as a URI character',
      );
    });

    test('Throws exception if directive end marker is not used', () {
      const yaml = '''
%YAML 1.1
''';

      check(
        () => bootstrapDocParser(yaml),
      ).throwsParserException(
        'Expected a directives end marker after the last directive',
      );
    });

    test(
      'Throws an excpetion if a directive indicator is used in the first '
      'non-empty content line',
      () {
        const yaml = '''
First document
---
%this is a scalar
''';

        check(
          () => bootstrapDocParser(yaml).toList(),
        ).throwsParserException(
          '"%" cannot be used as the first non-whitespace character in a '
          'non-empty content line',
        );
      },
    );

    test(
      'Throws when block collections are declared on the directive end marker'
      ' line',
      () {
        const directiveEnd = '--- ';
        final block = ['? key', '- sequence', ': value'];

        for (final collection in block) {
          check(
            () => bootstrapDocParser('$directiveEnd$collection'),
          ).throwsParserException(
            'A block collection cannot be declared on the same line as a'
            ' directive end marker',
          );
        }

        // Throws only after the block map has exited and cannot be composed
        check(
          () => bootstrapDocParser('$directiveEnd key: value'),
        ).throwsParserException(
          'Invalid node state. Expected to find document end "..." or directive'
          ' end chars "---" ',
        );
      },
    );
  });

  group('Utility methods', () {
    test('Skips to the next parsable char', () {
      const yaml = '''


My node starts here
''';

      final scanner = UnicodeIterator.ofString(yaml);

      check(skipToParsableChar(scanner, onParseComment: (_) {})).equals(0);
      check(scanner.current.asString()).equals('M');
    });

    test('Skips leading whitespace as', () {
      const yaml = ' My node starts here';

      final scanner = UnicodeIterator.ofString(yaml);

      check(skipToParsableChar(scanner, onParseComment: (_) {})).isNull();
      check(scanner.current.asString()).equals('M');
    });

    test('Skips to the next parsable char even with comments', () {
      const yaml = '''
# This is a comment
# This is another

My node starts here
''';

      final comments = <YamlComment>[];

      final scanner = UnicodeIterator.ofString(yaml);

      check(skipToParsableChar(scanner, comments: comments)).equals(0);
      check(scanner.current.asString()).equals('M');
      check(comments.map((e) => e.comment)).deepEquals([
        'This is a comment',
        'This is another',
      ]);
    });
  });
}
