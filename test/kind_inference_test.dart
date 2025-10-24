import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';
import 'package:test/test.dart';

import 'helpers/bootstrap_parser.dart';
import 'helpers/model_helpers.dart';

void main() {
  test('Defaults non-specific tags to their default schema kind', () {
    const string = '''
- ! 24
- ! {} # map
- ! []
''';

    final sequence = bootstrapDocParser(
      string,
    ).parseNodeSingle()!.castTo<Sequence>();

    check(sequence[0]).isA<Scalar>()
      ..hasInferred('Value', '24')
      ..hasTag(yamlGlobalTag, suffix: stringTag);

    check(sequence[1]).isA<Mapping>().hasTag(yamlGlobalTag, suffix: mappingTag);

    check(
      sequence[2],
    ).isA<Sequence>().hasTag(yamlGlobalTag, suffix: sequenceTag);
  });

  group('Scalar kinds', () {
    test('Infers base 10 int in different scalars', () {
      const integer = 24;

      const yaml =
          '''
- "$integer" # Double quoted
- '$integer' # Single quoted
-  $integer  # Plain
- |-         # Literal
   $integer
- >-         # Folded
   $integer
''';

      check(
        bootstrapDocParser(yaml).parseNodeSingle(),
      ).isA<Sequence>().every(
        (d) => d.isA<Scalar>().which(
          (d) => d
            ..hasTag(yamlGlobalTag, suffix: integerTag)
            ..hasParsedInteger(integer),
        ),
      );
    });

    test('Infers base 8 int in different scalars', () {
      const integer = '0o30';

      const yaml =
          '''
- "$integer" # Double quoted
- '$integer' # Single quoted
-  $integer  # Plain
- |-         # Literal
   $integer
- >-         # Folded
   $integer
''';

      check(
        bootstrapDocParser(yaml).parseNodeSingle(),
      ).isA<Sequence>().every(
        (d) => d.isA<Scalar>().which(
          (d) => d
            ..hasTag(yamlGlobalTag, suffix: integerTag)
            ..hasParsedInteger(24),
        ),
      );
    });

    test('Infers base 16 int in different scalars', () {
      const integer = '0x18';

      const yaml =
          '''
- "$integer" # Double quoted
- '$integer' # Single quoted
-  $integer  # Plain
- |-         # Literal
   $integer
- >-         # Folded
   $integer
''';

      check(
        bootstrapDocParser(yaml).parseNodeSingle(),
      ).isA<Sequence>().every(
        (d) => d.isA<Scalar>().which(
          (d) => d
            ..hasTag(yamlGlobalTag, suffix: integerTag)
            ..hasParsedInteger(24),
        ),
      );
    });

    test('Infers floats/doubles in different scalars', () {
      const float = 24.0;

      const yaml =
          '''
- "$float" # Double quoted
- '$float' # Single quoted
-  $float  # Plain
- |-         # Literal
   $float
- >-         # Folded
   $float
''';

      check(
        bootstrapDocParser(yaml).parseNodeSingle(),
      ).isA<Sequence>().every(
        (d) => d.isA<Scalar>().which(
          (d) => d
            ..hasTag(yamlGlobalTag, suffix: floatTag)
            ..inferredFloat(float),
        ),
      );
    });

    test('Infers booleans in different scalars', () {
      final booleans = [true, false];

      for (final inferred in booleans) {
        final yaml =
            '''
- "$inferred" # Double quoted
- '$inferred' # Single quoted
-  $inferred  # Plain
- |-         # Literal
   $inferred
- >-         # Folded
   $inferred
''';

        check(
          bootstrapDocParser(yaml).parseNodeSingle(),
        ).isA<Sequence>().every(
          (d) => d.isA<Scalar>().which(
            (d) => d
              ..hasTag(yamlGlobalTag, suffix: booleanTag)
              ..inferredBool(inferred),
          ),
        );
      }
    });

    test('Infers booleans in different scalars', () {
      void checker(String yaml) {
        check(
          bootstrapDocParser(yaml).parseNodeSingle(),
        ).isA<Sequence>().every(
          (d) => d.isA<Scalar>().which(
            (d) => d
              ..hasTag(yamlGlobalTag, suffix: nullTag)
              ..inferredNull(),
          ),
        );
      }

      final nullables = [null, 'Null', 'NULL', '~'];

      for (final inferred in nullables) {
        final yaml =
            '''
- "$inferred" # Double quoted
- '$inferred' # Single quoted
-  $inferred  # Plain
- |-         # Literal
   $inferred
- >-         # Folded
   $inferred
''';

        checker(yaml);
      }

      checker(
        '''
- "" # Double quoted
- '' # Single quoted
-    # Plain
- |-         # Literal
- >-         # Folded
''',
      );
    });

    test('Defaults to string', () {
      const expected = 'Just a string';

      final yaml =
          '''
- "$expected" # Double quoted
- '$expected' # Single quoted
-  $expected  # Plain
- |-     # Literal
   $expected
- >-     # Folded
   $expected
''';

      check(
        bootstrapDocParser(yaml).parseNodeSingle(),
      ).isA<Sequence>().every(
        (d) => d.isA<Scalar>().which(
          (d) => d
            ..hasTag(yamlGlobalTag, suffix: stringTag)
            ..hasInferred('Normal content', expected),
        ),
      );
    });

    test('Ignores inference if content has linebreak', () {
      const content = 'Wrote lf';

      final expected = '$content\n';

      // Plain scalars cannot have leading & trailing whitespaces
      final yaml =
          '''
- "$content\n\n " # Double quoted
- '$content\n\n ' # Single quoted
- |              # Literal
   $content\n\n
- >              # Folded
   $content\n\n
''';

      check(
        bootstrapDocParser(yaml).parseNodeSingle(),
      ).isA<Sequence>().every(
        (d) => d.isA<Scalar>().which(
          (d) => d
            ..hasTag(yamlGlobalTag, suffix: stringTag)
            ..hasInferred('Normal content', expected),
        ),
      );
    });

    test('Ignores inference if a string tag is specified', () {
      // Use a map to showcase uniqueness
      const edgyYAML = '''
# First inferred as int.
# Rest ignored due to string tag even though all will be inferred as "24"

24: value
!!str 24: value
!!str 0x18: value
!!str 0o30: value
''';

      check(
        bootstrapDocParser(edgyYAML).nodeAsSimpleString(),
      ).equals(
        {
          24: 'value',
          "24": 'value',
          "0x18": 'value',
          "0o30": 'value',
        }.toString(),
      );
    });

    test('Infers type but verbatim tags are not overriden', () {
      final tag = VerbatimTag.fromTagShorthand(
        TagShorthand.fromTagUri(TagHandle.primary(), 'verbatim'),
      );

      final yaml = '$tag 24';

      check(
          bootstrapDocParser(yaml).parseNodeSingle(),
        ).isNotNull().isA<Scalar>()
        ..withTag().equals(tag)
        ..hasParsedInteger(24);
    });

    //     test('Dart types can be used as keys in DynamicMapping', () {
    //       const string = 'key';
    //       const integer = 24;

    //       const yaml =
    //           '''
    // $string: $integer
    // $integer: $string
    // ''';

    //       check(bootstrapDocParser(yaml).parseNodeSingle())
    //           .isNotNull()
    //           .isA<Mapping>()
    //           .has((m) => m.castTo<DynamicMapping>(), 'DynamicMapping cast')
    //           .which(
    //             (dm) => dm
    //               ..has((v) => v[string], 'String key').isNotNull()
    //               ..has((v) => v[integer], 'Integer key').isNotNull(),
    //           );
    //     });
  });
}
