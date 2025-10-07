import 'package:checks/checks.dart';
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
      final yaml = '''
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

      check(() => vanillaDirectives(yaml)).throwsAFormatException(
        'Only printable characters are allowed in a parameter',
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

      check(() => vanillaDirectives(yaml)).throwsAFormatException(
        'A YAML directive can only be declared once per document',
      );
    });

    test('Throws if version is specified incorrectly', () {
      const prefix = 'Invalid YAML version format. ';

      check(() => vanillaDirectives('%YAML 10.0')).throwsAFormatException(
        'Unsupported YAML version requested.\n'
        '\tSource string version: 10.0\n'
        '\tParser version: ${parserVersion.version}',
      );

      check(() => vanillaDirectives('%YAML ..1')).throwsAFormatException(
        '$prefix'
        'Version cannot start with a "."',
      );

      check(() => vanillaDirectives('%YAML 1..1')).throwsAFormatException(
        '$prefix'
        'Version cannot have consecutive "." characters',
      );

      check(() => vanillaDirectives('%YAML 1.1.2')).throwsAFormatException(
        '$prefix'
        'A YAML version must have only 2 integers separated by "." but found: '
        '%YAML 1.1.2',
      );

      check(() => vanillaDirectives('%YAML A.B')).throwsAFormatException(
        'Invalid "A" character in YAML version. '
        'Only digits separated by "."'
        ' characters are allowed.',
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

    test('Throws if directive end markers are absent', () {
      check(
        () => bootstrapDocParser(
          '%TEST Yess it is',
        ).parseDocuments().parseNodeSingle(),
      ).throwsAFormatException(
        'Expected a directive end marker but found "nullnull.." as the first '
        'two characters',
      );
    });
  });
}
