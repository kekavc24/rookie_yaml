import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/yaml_document.dart';
import 'package:rookie_yaml/src/schema/nodes/node.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';
import 'package:test/test.dart';

import 'helpers/bootstrap_parser.dart';
import 'helpers/document_helper.dart';
import 'helpers/exception_helpers.dart';
import 'helpers/model_helpers.dart';

void main() {
  group('YamlDocument', () {
    test('Parses bare documents', () {
      final docs = bootstrapDocParser(
        docStringAs(YamlDocType.bare),
      ).parseDocs().toList();

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
      ).parseDocs().toList();

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
      final globalWithLocal = GlobalTag.fromLocalTag(
        TagHandle.named('with-tag'),
        LocalTag.fromTagUri(TagHandle.primary(), 'tag'),
      );

      final globalWithUri = GlobalTag.fromTagUri(
        TagHandle.named('with-uri'),
        'fake-uri://uri',
      );

      const reserved = '%RESERVED directive is restricted';

      final yamlDirective = YamlDirective.ofVersion('1.0');

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

      final doc = bootstrapDocParser(yaml).parseDocs().firstOrNull;

      check(doc).isNotNull()
        ..hasVersionDirective(yamlDirective)
        ..hasGlobalTags({globalWithUri, globalWithLocal})
        ..isDocOfType(YamlDocType.directiveDoc)
        ..isDocStartExplicit().isTrue()
        ..isDocEndExplicit().isTrue()
        ..which(
          (d) => d.hasNode()
            ..hasNoTag()
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

--- ?
 key
: value

--- - block
- sequence
''';

      check(bootstrapDocParser(yaml).parseDocs()).every(
        (d) => d
          ..isDocStartExplicit().isTrue()
          ..isDocEndExplicit().isFalse()
          ..hasNode().which((n) => n.hasNoTag()),
      );
    });

    test('Parses empty-ish documents', () {
      const yaml = '''
# Just comments
...
...
!just-a-tag
...
''';

      check(
          bootstrapDocParser(yaml).parseDocs(),
        )
        ..length.equals(3)
        ..every(
          (d) => d
            ..isDocEndExplicit().isTrue()
            ..hasNode().which(
              (n) => n
                ..isA<Scalar>().which(
                  (s) => s.has((s) => s.value, 'Value').isNull(),
                ),
            ),
        );
    });

    test('Defaults to plain scalar if not directive end marker', () {
      const yaml = '-- just a plain scalar';

      check(
        bootstrapDocParser(yaml).parseDocs().nodeAsSimpleString(),
      ).equals(yaml);
    });
  });

  group('Tags', () {
    test('Assigns shorthand as is if not resolved', () {
      final tag = LocalTag.fromTagUri(TagHandle.primary(), 'not-resolved');

      final yaml =
          '''
$tag yaml
''';

      check(bootstrapDocParser(yaml).parseDocs().parseNodeSingle()).hasTag(tag);
    });

    test('Resolves shorthands with primary tag handles', () {
      final globalTag = GlobalTag.fromLocalTag(
        TagHandle.primary(),
        LocalTag.fromTagUri(TagHandle.primary(), 'test-tag-for-'),
      );

      final suffix = LocalTag.fromTagUri(
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
        bootstrapDocParser(yaml).parseDocs().parseNodeSingle(),
      ).hasTag(globalTag, suffix: suffix);
    });

    test(
      'Resolves shorthands with secondary handle to the YAML global tag',
      () {
        final yaml = '$stringTag node';

        check(
          bootstrapDocParser(yaml).parseDocs().parseNodeSingle(),
        ).hasTag(yamlGlobalTag, suffix: stringTag);
      },
    );

    test('Redeclares secondary handle to use custom global tag', () {
      final globalTag = GlobalTag.fromLocalTag(
        TagHandle.secondary(),
        LocalTag.fromTagUri(
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
        bootstrapDocParser(yaml).parseDocs().parseNodeSingle(),
      ).hasTag(globalTag, suffix: stringTag);
    });

    test('Resolves named shorthands to custom declaration', () {
      final handle = TagHandle.named('named');

      final globalTag = GlobalTag.fromLocalTag(
        handle,
        LocalTag.fromTagUri(TagHandle.primary(), 'tag'),
      );

      final suffix = LocalTag.fromTagUri(handle, 'suffix');

      final yaml =
          '''
$globalTag
---
$suffix
''';

      check(
        bootstrapDocParser(yaml).parseDocs().parseNodeSingle(),
      ).hasTag(globalTag, suffix: suffix);
    });

    test(
      'Resolves a handle based on the global tag declaration for each document',
      () {
        final telescope = TagHandle.primary();

        final firstGlobal = GlobalTag.fromLocalTag(
          telescope,
          LocalTag.fromTagUri(TagHandle.primary(), 'primary-galaxy'),
        );

        final secondGlobal = GlobalTag.fromTagUri(
          telescope,
          'secondary://galaxy',
        );

        final star = LocalTag.fromTagUri(
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
        ).parseDocs().parsedNodes().toList();

        check(docs).length.equals(3);

        check(docs[0]).hasTag(firstGlobal, suffix: star);
        check(docs[1]).hasTag(secondGlobal, suffix: star);

        // Not resolved to any global tag
        check(docs[2]).hasTag(star);
      },
    );
  });

  group('Exceptions', () {
    test('Throws exception when a named tag is used as global tag prefix', () {
      final global = GlobalTag.fromLocalTag(
        TagHandle.named('okay'),
        LocalTag.fromTagUri(TagHandle.named('not-okay'), 'tag'),
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
        () => bootstrapDocParser(yaml).parseDocs(),
      ).throwsAFormatException(
        'Expected "!" to be escaped. The "!" character must be escaped.',
      );
    });

    test('Throws exception if directive end marker is not used', () {
      const yaml = '''
%YAML 1.1
''';

      check(
        () => bootstrapDocParser(yaml).parseDocs(),
      ).throwsAFormatException(
        'Expected a directive end marker but found "nullnull.." as the first '
        'two characters',
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
          () => bootstrapDocParser(yaml).parseDocs().toList(),
        ).throwsAFormatException(
          '"%" cannot be used as the first non-whitespace character in a '
          'non-empty content line',
        );
      },
    );
  });
}
