import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/scanner/chunk_scanner.dart';
import 'package:test/test.dart';

import 'helpers/exception_helpers.dart';
import 'helpers/model_helpers.dart';

void main() {
  group('Tag Handles', () {
    test('Parses primary tag handle', () {
      check(
        parseTagHandle(GraphemeScanner.of('!')),
      ).equals(TagHandle.primary());
    });

    test('Parses secondary tag handle, ignore chars ahead', () {
      final scanner = GraphemeScanner.of('!!ignored');

      check(parseTagHandle(scanner)).equals(TagHandle.secondary());
      check(scanner.canChunkMore).isTrue();
    });

    test('Parses named tag handle', () {
      const named = 'named';

      check(
        parseTagHandle(GraphemeScanner.of('!$named!')),
      ).equals(TagHandle.named(named));
    });

    test('Throws if leading char is not a tag indicator', () {
      check(
        () => parseTagHandle(GraphemeScanner.of('fake')),
      ).throwsAFormatException('Expected a "!" but found "f"');
    });

    test('Throws if primary tag has trailing chars and is not named', () {
      check(
        () => parseTagHandle(GraphemeScanner.of('!fake')),
      ).throwsAFormatException(
        'Invalid/incomplete named tag handle. Expected a tag with alphanumeric'
        ' characters but found !fake<null>',
      );
    });
  });

  group('Global Tag directive', () {
    test('Parses global tag uri with primary tag handle and uri prefix', () {
      final tagDefinition = '%TAG ! ';
      final uriPrefix = 'tag:example.com,2000:app/';

      final yaml =
          '$tagDefinition$uriPrefix'
          '\n---';

      final handle = TagHandle.primary();

      check(vanillaDirectives(yaml))
          .has((d) => d.globalTags, 'Global Tag from tag uri')
          .deepEquals({handle: GlobalTag.fromTagUri(handle, uriPrefix)});
    });

    test('Parses global tag uri with secondary tag handle and uri prefix', () {
      final tagDefinition = '%TAG !! ';
      final uriPrefix = 'tag:example.com,2000:app/';

      final yaml =
          '$tagDefinition$uriPrefix'
          '\n---';

      final handle = TagHandle.secondary();

      check(vanillaDirectives(yaml))
          .has((d) => d.globalTags, 'Global Tag from tag uri')
          .deepEquals({handle: GlobalTag.fromTagUri(handle, uriPrefix)});
    });

    test('Parses global tag uri with named tag handle and uri prefix', () {
      final named = 'named';
      final tagDefinition = '%TAG !$named! ';
      final uriPrefix =
          'tag:example.com,2000:app/'
          '\n---';

      final yaml = '$tagDefinition$uriPrefix';

      final handle = TagHandle.named(named);

      check(vanillaDirectives(yaml))
          .has((d) => d.globalTags, 'Global Tag from tag uri')
          .deepEquals({handle: GlobalTag.fromTagUri(handle, uriPrefix)});
    });

    test('Parses global tag uri with a local tag prefix', () {
      final name = 'testing';
      final tagDefinition = '%TAG !$name! ';
      final localTag = 'testing';

      final yaml =
          '$tagDefinition !$localTag'
          '\n---';

      final handle = TagHandle.named(name);

      check(
        vanillaDirectives(yaml),
      ).has((d) => d.globalTags, 'Global Tag from tag uri').deepEquals({
        handle: GlobalTag.fromTagShorthand(
          handle,
          TagShorthand.fromTagUri(TagHandle.primary(), localTag),
        ),
      });
    });

    test('Throws if duplicate global tags are declared', () {
      final yaml = '''
%TAG ! !foo
%TAG ! !foo''';

      check(() => vanillaDirectives(yaml)).throwsAFormatException(
        'A global tag directive with the "!" has already '
        'been declared in this document',
      );
    });

    test(
      'Throws if no uri/tag prefix/separation space to the uri/tag prefix'
      ' was declared',
      () {
        final yaml = '%TAG !no-prefix-or-separation-after!';

        check(() => vanillaDirectives(yaml)).throwsAFormatException(
          'A global tag must have a separation space after its handle',
        );
      },
    );

    test(
      'Throws if no uri/tag prefix was declared',
      () {
        final yaml = '%TAG !no-uri-or-local-tag-prefix! ';

        check(() => vanillaDirectives(yaml)).throwsAFormatException(
          'A global tag only accepts valid uri characters as a tag prefix',
        );
      },
    );

    test(
      'Throws if an invalid uri char is used in prefix',
      () {
        final yaml =
            '%TAG !no-uri-or-local-tag-prefix! '
            '${bell.asString()}';

        check(() => vanillaDirectives(yaml)).throwsAFormatException(
          'A global tag only accepts valid uri characters as a tag prefix',
        );
      },
    );
  });

  group('Local Tag', () {
    test('Parses a tag shorthand with primary tag handle', () {
      final suffix = 'primary';
      final yaml = '!$suffix "Not to be included"';

      check(
        parseTagShorthand(GraphemeScanner.of(yaml)),
      ).equals(TagShorthand.fromTagUri(TagHandle.primary(), suffix));
    });

    test('Parses a tag shorthand with secondary tag handle', () {
      final suffix = 'secondary';
      final yaml = '!!$suffix "Not to be included"';

      check(
        parseTagShorthand(GraphemeScanner.of(yaml)),
      ).equals(TagShorthand.fromTagUri(TagHandle.secondary(), suffix));
    });

    test('Parses a tag shorthand with named tag handle', () {
      final suffix = 'named';
      final yaml = '!$suffix!$suffix "Not to be included"';

      check(
        parseTagShorthand(GraphemeScanner.of(yaml)),
      ).equals(TagShorthand.fromTagUri(TagHandle.named(suffix), suffix));
    });

    test(
      'Parses a tag shorthand with escaped non-uri char',
      () {
        const suffix = 'localTag';
        const node = "Not to be included";

        // Special yaml delimiters that must be escaped in tag uri
        final escaped = [
          '%21', // "!"
          '%7B', // "{"
          '%7D', // "}"
          '%5B', // "["
          '%5D', // "]"
          '%2C', // ","
        ];

        for (var hex in escaped) {
          final tag = '$suffix$hex';
          final yaml = '!$tag $node';

          check(
            parseTagShorthand(GraphemeScanner.of(yaml)),
          ).equals(TagShorthand.fromTagUri(TagHandle.primary(), tag));
        }
      },
    );

    test('Throws if a non-uri char is used in tag', () {
      final offender = bell.asString();
      final yaml = '!local$offender';

      check(
        () => parseTagShorthand(GraphemeScanner.of(yaml)),
      ).throwsAFormatException('"$offender" is not a valid URI char');
    });

    test('Throws if a flow indicator is not escaped', () {
      const yaml = '!!flow-indicator-in-shorthand';

      for (final string in flowDelimiters) {
        check(
          () => parseTagShorthand(GraphemeScanner.of('$yaml$string')),
        ).throwsAFormatException(
          'Expected "$string" to be escaped. Flow collection characters must be'
          ' escaped.',
        );
      }
    });

    test('Throws if a tag indicator is not escaped', () {
      final offender = tag.asString();
      final yaml = '!!tag-indicator-in-shorthand$offender';

      check(
        () => parseTagShorthand(GraphemeScanner.of(yaml)),
      ).throwsAFormatException(
        'Expected "$offender" to be escaped. The "$offender" character must be'
        ' escaped.',
      );
    });

    test('Throws if a named tag handle has a non-alphanumeric char', () {
      const yaml = '!non-alpha-in-named*!ref';

      check(
        () => parseTagShorthand(GraphemeScanner.of(yaml)),
      ).throwsAFormatException(
        'A named tag can only have alphanumeric characters',
      );
    });

    group('Verbatim Tag', () {
      test('Parses a verbatim tag', () {
        final tags = [
          '!<tag:yaml.org,2002:str>', // Global Unresolvable uri
          '!<!local>',
        ];

        const ignored = 'Not to be parsed';

        for (final tag in tags) {
          check(
            parseVerbatimTag(GraphemeScanner.of('$tag $ignored')).verbatim,
          ).equals(tag);
        }
      });

      test("Throws if verbatim tag doesn't start with tag indicator", () {
        final node = '<!must-start-with-%21>';

        check(
          () => parseVerbatimTag(GraphemeScanner.of(node)),
        ).throwsAFormatException('A verbatim tag must start with "!"');
      });

      test("Throws if verbatim start indicator is missing (<)", () {
        final node = '!!must-start-with-%3C>';

        check(
          () => parseVerbatimTag(GraphemeScanner.of(node)),
        ).throwsAFormatException('Expected to find a "<" after "!"');
      });

      test("Throws if verbatim end indicator is missing (>)", () {
        final node = '!<!must-end-with-%3E';

        check(
          () => parseVerbatimTag(GraphemeScanner.of(node)),
        ).throwsAFormatException(
          'Expected to find a ">" after parsing a verbatim tag',
        );
      });

      test("Throws if a non-specific tag shorthand is declared verbatim", () {
        final node = '!<!>';

        check(
          () => parseVerbatimTag(GraphemeScanner.of(node)),
        ).throwsAFormatException(
          'Verbatim tags are never resolved and should have a non-empty suffix',
        );
      });
    });
  });

  // TODO: Add tests for nodes with resolved tags. Error if tag cannot
  // be resolved
}
