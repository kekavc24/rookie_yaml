import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/schema/schema.dart';
import 'package:test/test.dart';

import 'helpers/bootstrap_parser.dart';
import 'helpers/exception_helpers.dart';
import 'helpers/model_helpers.dart';
import 'helpers/object_helper.dart';
import 'helpers/test_resolvers.dart';

void main() {
  test('Defaults non-specific tags to their default schema kind', () {
    const string = '''
- ! 24
- ! {} # map
- ! []
''';

    check(loadDoc(string).first)
        .hasNode()
        .hasObject<List<TestNode>>('List')
        .has((l) => l.map((e) => e.tag), 'Elements with tags')
        .containsEqualInOrder([
          NodeTag(yamlGlobalTag, suffix: stringTag),
          NodeTag(yamlGlobalTag, suffix: mappingTag),
          NodeTag(yamlGlobalTag, suffix: sequenceTag),
        ]);
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

      check(loadDoc(yaml).first)
          .hasNode()
          .hasObject<List<TestNode>>('List')
          .every(
            (d) => d
              ..hasTag(yamlGlobalTag, suffix: integerTag)
              ..hasParsedInteger(integer),
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

      check(loadDoc(yaml).first)
          .hasNode()
          .hasObject<List<TestNode>>('List')
          .every(
            (s) => s
              ..hasTag(yamlGlobalTag, suffix: integerTag)
              ..hasParsedInteger(24),
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

      check(loadDoc(yaml).first)
          .hasNode()
          .hasObject<List<TestNode>>('List')
          .every(
            (d) => d
              ..hasTag(yamlGlobalTag, suffix: integerTag)
              ..hasParsedInteger(24),
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

      check(loadDoc(yaml).first)
          .hasNode()
          .hasObject<List<TestNode>>('List')
          .every(
            (d) => d
              ..hasTag(yamlGlobalTag, suffix: floatTag)
              ..inferredFloat(float),
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

        check(loadDoc(yaml).first)
            .hasNode()
            .hasObject<List<TestNode>>('List')
            .every(
              (d) => d
                ..hasTag(yamlGlobalTag, suffix: booleanTag)
                ..inferredBool(inferred),
            );
      }
    });

    test('Infers nulls in different scalars', () {
      void checker(String yaml) {
        check(loadDoc(yaml).first)
            .hasNode()
            .hasObject<List<TestNode>>('List')
            .every(
              (d) => d
                ..hasTag(yamlGlobalTag, suffix: nullTag)
                ..inferredNull(),
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
-    # Plain
     # Scalar
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

      check(loadDoc(yaml).first)
          .hasNode()
          .hasObject<List<TestNode>>('List')
          .every(
            (d) => d
              ..hasTag(yamlGlobalTag, suffix: stringTag)
              ..hasInferred('Normal content', expected),
          );
    });

    test('Defaults to string when empty (special)', () {
      final yaml = '''
- "" # Empty double quoted string
- '' # Empty Single quoted
- >- # Empty folded string
- |- # Empty literal string
''';

      check(loadDoc(yaml).first)
          .hasNode()
          .hasObject<List<TestNode>>('List')
          .every(
            (d) => d
              ..hasTag(yamlGlobalTag, suffix: stringTag)
              ..hasInferred('Normal content', ""),
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

      check(loadDoc(yaml).first)
          .hasNode()
          .hasObject<List<TestNode>>('List')
          .every(
            (d) => d
              ..hasTag(yamlGlobalTag, suffix: stringTag)
              ..hasInferred('Normal content', expected),
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
        TagShorthand.primary('verbatim'),
      );

      final yaml = '$tag 24';

      check(loadDoc(yaml).first).hasNode()
        ..withTag().equals(tag)
        ..hasInferred('Partial content', '24');
    });

    test('Infers explicit floats ', () {
      const value = -24;

      const inputs = [
        '$value', // Plain
        '"$value"', // Double quoted
        "'$value'", // Single quoted
        '|\n $value', // Literal
        '>\n $value',
      ];

      for (final str in inputs) {
        check(
          loadResolvedDartObject('$floatTag $str'),
        ).isA<double>().equals(value.toDouble());
      }
    });

    group('Recoverable integer delegate with explicit tag', () {
      test('Infers base 10', () {
        check(
          loadResolvedDartObject('$integerTag 24'),
        ).isA<int>().equals(24);

        // With padding
        check(
          loadResolvedDartObject('$integerTag 000000000000000024'),
        ).isA<int>().equals(24);

        check(
          loadResolvedDartObject('$integerTag -24'),
        ).isA<int>().equals(-24);
      });

      test('Infers base 16', () {
        check(loadResolvedDartObject('$integerTag 0x18')).isA<int>().equals(24);

        // With padding
        check(
          loadResolvedDartObject('$integerTag 0x00000000000000000018'),
        ).isA<int>().equals(24);
      });

      test('Infers base 8', () {
        check(loadResolvedDartObject('$integerTag 0o30')).isA<int>().equals(24);

        // With padding
        check(
          loadResolvedDartObject('$integerTag 0o00000000000000000030'),
        ).isA<int>().equals(24);
      });

      test('Recovers on fail as a string', () {
        check(
          loadResolvedDartObject('$integerTag 2459d'),
        ).isA<String>().equals('2459d');

        check(
          loadResolvedDartObject('$integerTag 0x18deaQ'),
        ).isA<String>().equals('0x18deaQ');

        check(
          loadResolvedDartObject('$integerTag 0o12348'),
        ).isA<String>().equals('0o12348');
      });

      test('Recovers on fail as a string with padding', () {
        check(
          loadResolvedDartObject('$integerTag 0000000000024delay'),
        ).isA<String>().equals('0000000000024delay');

        check(
          loadResolvedDartObject('$integerTag 0x0000000000024delay'),
        ).isA<String>().equals('0x0000000000024delay');

        check(
          loadResolvedDartObject('$integerTag 0o0000000000024delay'),
        ).isA<String>().equals('0o0000000000024delay');
      });
    });
  });

  group('Sequences', () {
    test('Variant [1]', () {
      check(
        loadDoc('!!seq\n- sequence').first,
      ).hasNode().hasTag(yamlGlobalTag, suffix: sequenceTag);

      check(
        loadDoc('!!seq [flow]').first,
      ).hasNode().hasTag(yamlGlobalTag, suffix: sequenceTag);
    });

    test('Variant [2]', () {
      check(
          loadDoc('''
- !!seq
  - block
''').first,
        ).hasNode()
        ..hasTag(yamlGlobalTag, suffix: sequenceTag)
        ..hasObject<List<TestNode>>('List').which(
          (s) => s.first.hasTag(yamlGlobalTag, suffix: sequenceTag),
        );
    });

    test('Variant [3]', () {
      check(loadDoc('[ !!seq [flow] ]').first).hasNode()
        ..hasTag(yamlGlobalTag, suffix: sequenceTag)
        ..hasObject<List<TestNode>>('List').which(
          (s) => s.first.hasTag(yamlGlobalTag, suffix: sequenceTag),
        );
    });
  });

  group('Mappings', () {
    test('Variant [1]', () {
      check(
        loadDoc('!!map\nkey: value').first,
      ).hasNode().hasTag(yamlGlobalTag, suffix: mappingTag);
    });

    test('Variant [2]', () {
      check(
        loadDoc('''
!!map
: value
''').first,
      ).hasNode().hasTag(yamlGlobalTag, suffix: mappingTag);
    });

    test('Variant [3]', () {
      check(
        loadDoc('''
!!map
? key
''').first,
      ).hasNode().hasTag(yamlGlobalTag, suffix: mappingTag);
    });

    test('Variant [4]', () {
      check(
            loadDoc('''
- &anchor value
- !!map
  *anchor : value
''').first,
          )
          .hasNode()
          .hasObject<List<TestNode>>('List')
          .has((s) => s[1], 'Block of alias key')
          .hasTag(yamlGlobalTag, suffix: mappingTag);
    });

    test('Variant [5]', () {
      check(
        loadDoc('!!map {flow: map}').first,
      ).hasNode().hasTag(yamlGlobalTag, suffix: mappingTag);
    });
  });

  group('Exceptions', () {
    test('Invalid scalar', () {
      check(
        () => bootstrapDocParser('!!str {  }'),
      ).throwsParserException('Expected the start of a valid scalar');
    });

    test('Invalid sequence: Flow variant', () {
      check(
        () => bootstrapDocParser('[ !!seq value ]'),
      ).throwsParserException('Expected the flow delimiter: "["');
    });

    test('Invalid sequence: Block variant', () {
      check(
        () => bootstrapDocParser('!!seq value'),
      ).throwsParserException('Expected the start of a block/flow sequence');
    });

    test('Invalid map: Flow variant', () {
      check(
        () => bootstrapDocParser('[ !!map value ]'),
      ).throwsParserException('Expected the flow delimiter: "{"');
    });

    test('Invalid map: Block variant', () {
      check(() => bootstrapDocParser('!!map value')).throwsParserException(
        'Expected to find ":" after the key and before its value',
      );
    });
  });
}
