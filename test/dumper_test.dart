import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/dumping/dumping.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:test/test.dart';

import 'helpers/exception_helpers.dart';

void main() {
  group('Dumps scalar', () {
    group('Dumps plain', () {
      test('Dumps plain scalar', () {
        check(
          dumpScalar(24, indent: 0, dumpingStyle: ScalarStyle.plain),
        ).equals('24');
      });

      test('Unfolds plain scalar', () {
        check(
          dumpScalar(
            'my unfolded\n\nstring',
            indent: 0,
            dumpingStyle: ScalarStyle.plain,
          ),
        ).equals('my unfolded\n\n\nstring');
      });

      test(
        'Normalizes all escaped characters excluding tabs and linebreaks',
        () {
          check(
            dumpScalar(
              'Normalized '
              '${unicodeNull.asString()}'
              '${bell.asString()}'
              '${backspace.asString()}'
              '${verticalTab.asString()}'
              '${formFeed.asString()}'
              '${nextLine.asString()}'
              '${lineSeparator.asString()}'
              '${paragraphSeparator.asString()}'
              '${asciiEscape.asString()}'
              '${nbsp.asString()}'
              ' sandwich',
              indent: 0,
              dumpingStyle: ScalarStyle.plain,
            ),
          ).equals(r'Normalized \0\a\b\v\f\N\L\P\e\_ sandwich');
        },
      );
    });

    group('Dumps single quoted', () {
      test('Dumps single quoted scalar', () {
        check(
          dumpScalar(24, indent: 0, dumpingStyle: ScalarStyle.singleQuoted),
        ).equals("'24'");
      });

      test('Unfolds single quoted scalar', () {
        check(
          dumpScalar(
            'my unfolded\n\nstring',
            indent: 0,
            dumpingStyle: ScalarStyle.singleQuoted,
          ),
        ).equals("'my unfolded\n\n\nstring'");
      });

      test('Escapes all single quotes', () {
        check(
          dumpScalar(
            "It's my quoted's scalar. Go brrrr''''",
            indent: 0,
            dumpingStyle: ScalarStyle.singleQuoted,
          ),
        ).equals("'It''s my quoted''s scalar. Go brrrr'''''''''");
      });

      test('Throws when a non-printable character is used', () {
        check(
          () => dumpScalar(
            bell.asString(),
            indent: 0,
            dumpingStyle: ScalarStyle.singleQuoted,
          ),
        ).throwsAFormatException(
          'Non-printable character cannot be encoded as single quoted',
        );
      });
    });

    group('Dumps double quoted', () {
      test('Dumps double quoted scalar', () {
        check(
          dumpScalar(24, indent: 0, dumpingStyle: ScalarStyle.doubleQuoted),
        ).equals('"24"');
      });

      test('Unfolds a simple double quoted scalar', () {
        check(
          dumpScalar(
            'my unfolded\n\nstring',
            indent: 0,
            dumpingStyle: ScalarStyle.doubleQuoted,
          ),
        ).equals('"my unfolded\n\n\nstring"');
      });

      test('Unfolds a complex double quoted scalar', () {
        check(
          dumpScalar(
            'my folded \n'
            'string with spaces \n'
            ' \n'
            'weirdly placed',
            indent: 0,
            dumpingStyle: ScalarStyle.doubleQuoted,
          ),
        ).equals(
          r'"my folded \'
          '\n\n\n'
          r'string with spaces \'
          '\n\n\n'
          r'\ '
          '\n\n'
          'weirdly placed"',
        );
      });

      test(
        'Normalizes all escaped characters excluding tabs and linebreaks'
        ' when not in json mode',
        () {
          check(
            dumpScalar(
              '${unicodeNull.asString()}'
              '${bell.asString()}'
              '${backspace.asString()}'
              '${verticalTab.asString()}'
              '${formFeed.asString()}'
              '${nextLine.asString()}'
              '${lineSeparator.asString()}'
              '${paragraphSeparator.asString()}'
              '${asciiEscape.asString()}'
              '${nbsp.asString()}'
              '"'
              r'\/',
              indent: 0,
              dumpingStyle: ScalarStyle.doubleQuoted,
            ),
          ).equals(r'"\0\a\b\v\f\N\L\P\e\_\"\\\/"');
        },
      );

      test(
        'Normalizes all escaped characters including tabs and linebreaks'
        ' when in json mode',
        () {
          check(
            dumpScalar(
              '${unicodeNull.asString()}'
              '${bell.asString()}'
              '${backspace.asString()}'
              '${verticalTab.asString()}'
              '${formFeed.asString()}'
              '${nextLine.asString()}'
              '${lineSeparator.asString()}'
              '${paragraphSeparator.asString()}'
              '${asciiEscape.asString()}'
              '${nbsp.asString()}'
              '"'
              r'\/'
              '\t\n',
              indent: 0,
              jsonCompatible: true,
            ),
          ).equals(r'"\0\a\b\v\f\N\L\P\e\_\"\\\/\t\n"');
        },
      );
    });

    group('Dumps literal', () {
      test('Dumps literal scalar', () {
        check(
          dumpScalar(24, indent: 0, dumpingStyle: ScalarStyle.literal),
        ).equals('|-\n24');
      });

      test('Never unfolds literal scalar', () {
        check(
          dumpScalar(
            'my unfoldable\n\nstring',
            indent: 0,
            dumpingStyle: ScalarStyle.literal,
          ),
        ).equals('|-\nmy unfoldable\n\nstring');
      });

      test(
        'Preserves trailing linebreaks from being chomped in literal scalar',
        () {
          check(
            dumpScalar(
              'my literal string\n\n',
              indent: 0,
              dumpingStyle: ScalarStyle.literal,
            ),
          ).equals('|+\nmy literal string\n\n');
        },
      );

      test(
        'Preserves leading whitespace from being consumed as indent in first '
        'non-empty line in literal scalar',
        () {
          check(
            dumpScalar(
              ' literal string',
              indent: 0,
              dumpingStyle: ScalarStyle.literal,
            ),
          ).equals('" literal string"');
        },
      );

      test('Throws when a non-printable character is used', () {
        check(
          () => dumpScalar(
            bell.asString(),
            indent: 0,
            dumpingStyle: ScalarStyle.literal,
          ),
        ).throwsAFormatException(
          'Non-printable character cannot be encoded as literal/folded',
        );
      });
    });

    group('Dumps block folded', () {
      test('Dumps folded scalar', () {
        check(
          dumpScalar(24, indent: 0, dumpingStyle: ScalarStyle.folded),
        ).equals('>-\n24');
      });

      test('Unfolds block folded scalar', () {
        check(
          dumpScalar(
            'my unfolded\n\nstring',
            indent: 0,
            dumpingStyle: ScalarStyle.folded,
          ),
        ).equals('>-\nmy unfolded\n\n\nstring');
      });

      test(
        'Preserves trailing linebreaks from being chomped in folded scalar'
        ' without unfolding them',
        () {
          check(
            dumpScalar(
              'my block folded string\n\n',
              indent: 0,
              dumpingStyle: ScalarStyle.folded,
            ),
          ).equals('>+\nmy block folded string\n\n');
        },
      );

      test(
        'Preserves leading whitespace from being consumed as indent in first '
        'non-empty line in block folded scalar',
        () {
          check(
            dumpScalar(
              ' folded string',
              indent: 0,
              dumpingStyle: ScalarStyle.folded,
            ),
          ).equals('" folded string"');
        },
      );

      test('Never unfolds line breaks joining indented line', () {
        check(
          dumpScalar(
            'folded string\n'
            ' with indented \n\n'
            'line',
            indent: 0,
            dumpingStyle: ScalarStyle.folded,
          ),
        ).equals(
          '>-\n'
          'folded string\n'
          ' with indented \n\n'
          'line',
        );
      });

      test('Throws when a non-printable character is used', () {
        check(
          () => dumpScalar(
            bell.asString(),
            indent: 0,
            dumpingStyle: ScalarStyle.folded,
          ),
        ).throwsAFormatException(
          'Non-printable character cannot be encoded as literal/folded',
        );
      });
    });

    group('Dumps map', () {
      final funkyMap = {
        'key': 24,
        24: ['rookie', 'yaml'],
        ['is', 'dumper']: {true: 24.0},
        '24\n0': 'value',
      };

      group('Dumps flow map', () {
        test('Dumps map with default double quoted scalar style', () {
          check(
            dumpMapping(funkyMap, collectionNodeStyle: NodeStyle.flow),
          ).equals('''
{
 "key": "24",
 "24": [
   "rookie",
   "yaml"
  ],
 ? [
  "is",
  "dumper"
 ]: {
   "true": "24.0"
  },
 ? "24

 0": "value"
}''');
        });

        test('Dumps map with single quoted style', () {
          check(
            dumpMapping(
              funkyMap,
              collectionNodeStyle: NodeStyle.flow,
              keyScalarStyle: ScalarStyle.singleQuoted,
              valueScalarStyle: ScalarStyle.singleQuoted,
            ),
          ).equals('''
{
 'key': '24',
 '24': [
   'rookie',
   'yaml'
  ],
 ? [
  'is',
  'dumper'
 ]: {
   'true': '24.0'
  },
 ? '24

 0': 'value'
}''');
        });

        test('Dumps map with plain style', () {
          check(
            dumpMapping(
              funkyMap,
              collectionNodeStyle: NodeStyle.flow,
              keyScalarStyle: ScalarStyle.plain,
              valueScalarStyle: ScalarStyle.plain,
            ),
          ).equals('''
{
 key: 24,
 24: [
   rookie,
   yaml
  ],
 ? [
  is,
  dumper
 ]: {
   true: 24.0
  },
 ? 24

 0: value
}''');
        });

        test(
          'Dumps map with block style or json compatible as true defaults to'
          ' double quoted',
          () {
            const output = '''
{
 "key": "24",
 "24": [
   "rookie",
   "yaml"
  ],
 ? [
  "is",
  "dumper"
 ]: {
   "true": "24.0"
  },''';

            const block =
                '''
$output
 ? "24

 0": "value"
}''';

            const json =
                '$output\n'
                r' "24\n0": "value"'
                '\n}';

            check(
              [
                dumpMapping(
                  funkyMap,
                  collectionNodeStyle: NodeStyle.flow,
                  keyScalarStyle: ScalarStyle.literal,
                  valueScalarStyle: ScalarStyle.literal,
                ),
                dumpMapping(
                  funkyMap,
                  collectionNodeStyle: NodeStyle.flow,
                  keyScalarStyle: ScalarStyle.folded,
                  valueScalarStyle: ScalarStyle.folded,
                ),
                dumpMapping(funkyMap, jsonCompatible: true),
              ],
            ).deepEquals([block, block, json]);
          },
        );
      });

      group('Dumps block map', () {
        test('Dumps map with default literal scalar style', () {
          check(
            dumpMapping(funkyMap, collectionNodeStyle: NodeStyle.block),
          ).equals('''
? |-
  key
: |-
  24
? |-
  24
: - |-
    rookie
  - |-
    yaml
? - |-
    is
  - |-
    dumper
: ? |-
    true
  : |-
    24.0
? |-
  24
  0
: |-
  value
''');
        });

        test('Dumps map with folded scalar style', () {
          check(
            dumpMapping(
              funkyMap,
              collectionNodeStyle: NodeStyle.block,
              keyScalarStyle: ScalarStyle.folded,
              valueScalarStyle: ScalarStyle.folded,
            ),
          ).equals('''
? >-
  key
: >-
  24
? >-
  24
: - >-
    rookie
  - >-
    yaml
? - >-
    is
  - >-
    dumper
: ? >-
    true
  : >-
    24.0
? >-
  24

  0
: >-
  value
''');
        });

        test('Dumps map with double quoted scalar style', () {
          check(
            dumpMapping(
              funkyMap,
              collectionNodeStyle: NodeStyle.block,
              keyScalarStyle: ScalarStyle.doubleQuoted,
              valueScalarStyle: ScalarStyle.doubleQuoted,
            ),
          ).equals('''
"key": "24"
"24":
  - "rookie"
  - "yaml"
? - "is"
  - "dumper"
: "true": "24.0"
? "24

  0"
: "value"
''');
        });

        test('Dumps map with single quoted scalar style', () {
          check(
            dumpMapping(
              funkyMap,
              collectionNodeStyle: NodeStyle.block,
              keyScalarStyle: ScalarStyle.singleQuoted,
              valueScalarStyle: ScalarStyle.singleQuoted,
            ),
          ).equals('''
'key': '24'
'24':
  - 'rookie'
  - 'yaml'
? - 'is'
  - 'dumper'
: 'true': '24.0'
? '24

  0'
: 'value'
''');
        });

        test('Dumps map with plain scalar style', () {
          check(
            dumpMapping(
              funkyMap,
              collectionNodeStyle: NodeStyle.block,
              keyScalarStyle: ScalarStyle.plain,
              valueScalarStyle: ScalarStyle.plain,
            ),
          ).equals('''
key: 24
24:
  - rookie
  - yaml
? - is
  - dumper
: true: 24.0
? 24

  0
: value
''');
        });
      });

      group('Dumps with different scalar styles for key and value', () {
        test('Dumps key as flow and value as block in block map', () {
          check(
            dumpMapping(
              funkyMap,
              collectionNodeStyle: NodeStyle.block,
              keyScalarStyle: ScalarStyle.plain,
            ),
          ).equals('''
key: |-
  24
24:
  - |-
    rookie
  - |-
    yaml
? - is
  - dumper
: true: |-
    24.0
? 24

  0
: |-
  value
''');
        });

        test(
          'Dumps key as single quoted and values as double quoted in flow map',
          () {
            check(
              dumpMapping(
                funkyMap,
                collectionNodeStyle: NodeStyle.flow,
                keyScalarStyle: ScalarStyle.singleQuoted,
                valueScalarStyle: ScalarStyle.doubleQuoted,
              ),
            ).equals('''
{
 'key': "24",
 '24': [
   "rookie",
   "yaml"
  ],
 ? [
  'is',
  'dumper'
 ]: {
   'true': "24.0"
  },
 ? '24

 0': "value"
}''');
          },
        );
      });
    });

    group('Dumps list', () {
      const sequence = [
        'value',
        24,
        true,
        ['rookie', 'yaml', 'is', 'dumper'],
        {true: 24.0},
        '24\n0',
      ];

      group('Dumps flow list', () {
        test('Dumps sequence with default double quoted scalar style', () {
          check(
            dumpSequence(sequence, collectionNodeStyle: NodeStyle.flow),
          ).equals('''
[
 "value",
 "24",
 "true",
 [
  "rookie",
  "yaml",
  "is",
  "dumper"
 ],
 {
  "true": "24.0"
 },
 "24

 0"
]''');
        });

        test('Dumps sequence with single quoted scalar style', () {
          check(
            dumpSequence(
              sequence,
              collectionNodeStyle: NodeStyle.flow,
              preferredScalarStyle: ScalarStyle.singleQuoted,
            ),
          ).equals('''
[
 'value',
 '24',
 'true',
 [
  'rookie',
  'yaml',
  'is',
  'dumper'
 ],
 {
  'true': '24.0'
 },
 '24

 0'
]''');
        });

        test('Dumps sequence with plain scalar style', () {
          check(
            dumpSequence(
              sequence,
              collectionNodeStyle: NodeStyle.flow,
              preferredScalarStyle: ScalarStyle.plain,
            ),
          ).equals('''
[
 value,
 24,
 true,
 [
  rookie,
  yaml,
  is,
  dumper
 ],
 {
  true: 24.0
 },
 24

 0
]''');
        });

        test(
          'Dumps sequence with block style or json compatible as true defaults '
          'to double quoted',
          () {
            const output = '''
[
 "value",
 "24",
 "true",
 [
  "rookie",
  "yaml",
  "is",
  "dumper"
 ],
 {
  "true": "24.0"
 },''';

            const block =
                '''
$output
 "24

 0"
]''';

            const json =
                '$output\n'
                r' "24\n0"'
                '\n]';

            check(
              [
                dumpSequence(
                  sequence,
                  collectionNodeStyle: NodeStyle.flow,
                  preferredScalarStyle: ScalarStyle.literal,
                ),
                dumpSequence(
                  sequence,
                  collectionNodeStyle: NodeStyle.flow,
                  preferredScalarStyle: ScalarStyle.folded,
                ),
                dumpSequence(sequence, jsonCompatible: true),
              ],
            ).deepEquals([block, block, json]);
          },
        );
      });

      group('Dumps block list', () {
        test('Dumps sequence with default literal style', () {
          check(
            dumpSequence(sequence, collectionNodeStyle: NodeStyle.block),
          ).equals('''
- |-
  value
- |-
  24
- |-
  true
- - |-
    rookie
  - |-
    yaml
  - |-
    is
  - |-
    dumper
- ? |-
    true
  : |-
    24.0
- |-
  24
  0
''');
        });

        test('Dumps sequence with folded style', () {
          check(
            dumpSequence(
              sequence,
              collectionNodeStyle: NodeStyle.block,
              preferredScalarStyle: ScalarStyle.folded,
            ),
          ).equals('''
- >-
  value
- >-
  24
- >-
  true
- - >-
    rookie
  - >-
    yaml
  - >-
    is
  - >-
    dumper
- ? >-
    true
  : >-
    24.0
- >-
  24

  0
''');
        });

        test('Dumps sequence with double quoted style', () {
          check(
            dumpSequence(
              sequence,
              collectionNodeStyle: NodeStyle.block,
              preferredScalarStyle: ScalarStyle.doubleQuoted,
            ),
          ).equals('''
- "value"
- "24"
- "true"
- - "rookie"
  - "yaml"
  - "is"
  - "dumper"
- "true": "24.0"
- "24\n\n  0"
''');
        });

        test('Dumps sequence with single quoted style', () {
          check(
            dumpSequence(
              sequence,
              collectionNodeStyle: NodeStyle.block,
              preferredScalarStyle: ScalarStyle.singleQuoted,
            ),
          ).equals('''
- 'value'
- '24'
- 'true'
- - 'rookie'
  - 'yaml'
  - 'is'
  - 'dumper'
- 'true': '24.0'
- '24\n\n  0'
''');
        });

        test('Dumps sequence with plain style', () {
          check(
            dumpSequence(
              sequence,
              collectionNodeStyle: NodeStyle.block,
              preferredScalarStyle: ScalarStyle.plain,
            ),
          ).equals('''
- value
- 24
- true
- - rookie
  - yaml
  - is
  - dumper
- true: 24.0
- 24\n\n  0
''');
        });
      });
    });
  });
}
