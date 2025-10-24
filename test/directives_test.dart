import 'package:checks/checks.dart';
import 'package:collection/collection.dart';
import 'package:rookie_yaml/rookie_yaml.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:test/test.dart';

import 'helpers/bootstrap_parser.dart';
import 'helpers/exception_helpers.dart';
import 'helpers/model_helpers.dart';

void main() {
  group('Reserved directives', () {
    test('Parse reserved directives', () {
      const yaml = '''
%MMH.. A reserved directive
%RESERVED cannot be constructed
%WHY? Irriz warririz https://youtu.be/y9r_pZL4boE?si=IQyibJXzS1agg2GN
''';

      check(vanillaDirectives('$yaml\n---'))
          .has(
            (d) => d.reservedDirectives.map((r) => r.toString()).join('\n'),
            'Reserved Directives',
          )
          .equalsIgnoringWhitespace(yaml);
    });

    test('Throws if non-printable character are used', () {
      final yaml = '%RESERVED ${bell.asString()}';

      check(() => vanillaDirectives(yaml)).throwsParserException(
        'Only printable characters are allowed in a directive parameter',
      );
    });
  });

  group('YAML directive', () {
    test('Parse yaml directive', () {
      final yaml =
          '%YAML 1.2\n'
          '---';

      check(vanillaDirectives(yaml))
          .has((d) => d.yamlDirective, 'Yaml Directive')
          .equals(YamlDirective.ofVersion(1, 2));
    });

    test('Logs warning of an unsupported but parsable version', () {
      final directive = YamlDirective.ofVersion(1, 3);

      final logs = <String>[];
      check(
        parseDirectives(
          GraphemeScanner.of('$directive\n---'),
          onParseComment: (_) {},
          warningLogger: (m) => logs.add(m),
        ).yamlDirective,
      ).isNotNull().equals(directive);

      check(logs).deepEquals(
        [
          'YamlParser only supports YAML version "${parserVersion.version}". '
              'Found YAML version "${directive.version}" which may have'
              ' unsupported features.',
        ],
      );
    });

    test('Supported YAML version can be ascertained', () {
      check(YamlDirective.ofVersion(1, 0).isSupported).isTrue();
      check(YamlDirective.ofVersion(1, 3).isSupported).isTrue();
      check(YamlDirective.ofVersion(2, 0).isSupported).isFalse();
    });

    test('Throws if duplicate version directives are declared', () {
      final yaml = '''
%YAML 1.2
%YAML 2.2
''';

      check(() => vanillaDirectives(yaml)).throwsParserException(
        'A YAML directive can only be declared once per document',
      );
    });

    test('Throws if version is specified incorrectly', () {
      check(() => vanillaDirectives('%YAML 10.0')).throwsParserException(
        'Unsupported YAML version requested. '
        'Current parser version is ${parserVersion.version}',
      );

      check(() => vanillaDirectives('%YAML ..1')).throwsParserException(
        'A YAML directive cannot start with a version separator',
      );

      check(() => vanillaDirectives('%YAML 1..1')).throwsParserException(
        'A YAML directive cannot have consecutive version separators',
      );

      check(() => vanillaDirectives('%YAML 1.1.2')).throwsParserException(
        'A YAML version directive can only have 2 integers separated by "."',
      );

      check(() => vanillaDirectives('%YAML A.B')).throwsParserException(
        'A YAML version directive can only have digits separated by a "."',
      );
    });
  });

  group('General directives', () {
    test('Comments in directives', () {
      final comments = <YamlComment>[];

      const yaml = '''
%YAML 1.2 # We only support YAML
          # version 1.2+

%WHY Earlier features are buggy # It goes without saying
    # without them we would not have 1.2

%TAG !okay! !make-sense # Thanks
  # for
      # understanding
        # and
          # not
            # getting
              # mad
---
      ''';

      parseDirectives(
        GraphemeScanner.of(yaml),
        onParseComment: comments.add,
        warningLogger: (_) {},
      );

      check(comments.map((e) => e.comment)).deepEquals([
        'We only support YAML',
        'version 1.2+',
        'It goes without saying',
        'without them we would not have 1.2',
        'Thanks',
        'for',
        'understanding',
        'and',
        'not',
        'getting',
        'mad',
      ]);
    });

    test('Empty lines in between directives', () {
      const yaml = '''
%HELLO Just testing empty lines

%IN between directives


%THAT also includes empty lines with just

\t\t\t

%TABS :)
''';

      check(vanillaDirectives('$yaml\n---'))
          .has(
            (d) => d.reservedDirectives.map((r) => r.toString()).join('\n'),
            'Reserved Directives',
          )
          .equalsIgnoringWhitespace(
            yaml.split('\n').whereNot((e) => e.trim().isEmpty).join('\n'),
          );
    });

    test('Throws if directive end markers are absent', () {
      check(
        () => bootstrapDocParser('%TEST Yess it is').parseNodeSingle(),
      ).throwsParserException(
        'Expected a directives end marker after the last directive',
      );
    });

    test('Throws if indented directives are found', () {
      check(
        () => bootstrapDocParser(
          '''
%HELLO Just testing empty lines
 %IN between directives
''',
        ).parseNodeSingle(),
      ).throwsParserException(
        'Expected a non-indented directive line with directives or a '
        'directive end marker',
      );
    });
  });
}
