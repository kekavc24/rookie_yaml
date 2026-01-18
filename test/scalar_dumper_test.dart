import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/dumping/dumpable_node.dart';
import 'package:rookie_yaml/src/dumping/dumper_utils.dart';
import 'package:rookie_yaml/src/dumping/scalar_dumper.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:test/test.dart';

extension on Subject<DumpedScalar> {
  void isMultiline() => has((s) => s.isMultiline, 'Multiline').isTrue();

  void dumps(String node) => has((s) => s.node, 'Dumped node').equals(node);
}

ScalarDumper classicDumper([AsLocalTag? push]) {
  return ScalarDumper.classic((o) => dumpableObject(o), push ?? (_) => null);
}

void main() {
  group('General', () {
    test('Ignores style replaces empty strings with null', () {
      check(
        classicDumper().dump(
          '',
          indent: 0,
          style: ScalarStyle.doubleQuoted,
        ),
      ).dumps('null');
    });

    test('Replaces empty strings with null in plain', () {
      check(
        ScalarDumper.fineGrained(
          replaceEmpty: false,
          onScalar: (o) => dumpableType(o),
          asLocalTag: (_) => null,
        ).dump('', indent: 0, style: ScalarStyle.plain),
      ).dumps('null');
    });

    test('Applies properties correctly', () {
      final scalar = dumpableType(24)..anchor = '24';

      void checkDump(String expected, [ScalarStyle? style]) {
        check(
          classicDumper((_) => '!!24').dump(scalar, indent: 1, style: style),
        ).dumps('&24 !!24 $expected');
      }

      checkDump('24'); // No style

      checkDump('"24"', ScalarStyle.doubleQuoted);
      checkDump("'24'", ScalarStyle.singleQuoted);
      checkDump('24', ScalarStyle.plain);
      checkDump('>-\n 24', ScalarStyle.folded);
      checkDump('|-\n 24', ScalarStyle.literal);
    });

    test(
      'Defaults to double quoted and normalizes line breaks if forced inline',
      () {
        const value = 'hello \n\n here';
        const dumped = r'"hello \n\n here"';

        for (final style in ScalarStyle.values) {
          check(
            ScalarDumper.fineGrained(
              replaceEmpty: false,
              onScalar: (o) => dumpableType(o),
              asLocalTag: (_) => null,
              forceInline: true,
            ).dump(value, indent: 0, style: style),
          ).dumps(dumped);
        }
      },
    );
  });

  group('Dumps plain', () {
    test('Dumps plain scalar', () {
      check(
        classicDumper().dump(24, indent: 0, style: ScalarStyle.plain),
      ).dumps('24');
    });

    test('Unfolds plain scalar', () {
      check(
          classicDumper().dump(
            'my unfolded\n\nstring',
            indent: 0,
            style: ScalarStyle.plain,
          ),
        )
        ..isMultiline()
        ..dumps('my unfolded\n\n\nstring');
    });

    test(
      'Normalizes all escaped characters excluding tabs and linebreaks',
      () {
        check(
          classicDumper().dump(
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
            style: ScalarStyle.plain,
          ),
        ).dumps(r'Normalized \0\a\b\v\f\N\L\P\e\_ sandwich');
      },
    );

    test('Defaults to double quoted if plain starts with # (comment)'
        ' or is comment-like', () {
      check(
        classicDumper().dump('# 24', indent: 0, style: ScalarStyle.plain),
      ).dumps('"# 24"');

      check(
        classicDumper().dump(
          '24 but # comment',
          indent: 0,
          style: ScalarStyle.plain,
        ),
      ).dumps('"24 but # comment"');

      check(
        classicDumper().dump(
          '24 but\t# comment',
          indent: 0,
          style: ScalarStyle.plain,
        ),
      ).dumps('"24 but\t# comment"');

      check(
        classicDumper().dump(
          '24 but\n# comment',
          indent: 0,
          style: ScalarStyle.plain,
        ),
      ).dumps('"24 but\n\n# comment"');

      check(
        classicDumper().dump(
          '24 but\r# comment',
          indent: 0,
          style: ScalarStyle.plain,
        ),
      ).dumps('"24 but\n\n# comment"');
    });

    test(
      'Defaults to double quoted if plain has characters not allowed at the'
      ' start',
      () {
        const restricted = ['?', ':', '-'];

        for (final char in restricted) {
          check(
            classicDumper().dump(
              '$char 24',
              indent: 0,
              style: ScalarStyle.plain,
            ),
          ).dumps('"$char 24"');
        }
      },
    );

    test(
      'Defaults to double quoted if plain has characters not allowed at the'
      ' start',
      () {
        const restricted = ['{', '}', '[', ']', ','];

        for (final char in restricted) {
          check(
            classicDumper().dump(
              '$char 24',
              indent: 0,
              style: ScalarStyle.plain,
              parentIndent: seamlessIndentMarker,
            ),
          ).dumps('"$char 24"');
        }
      },
    );
  });

  group('Dumps single quoted', () {
    test('Dumps single quoted scalar', () {
      check(
        classicDumper().dump(24, indent: 0, style: ScalarStyle.singleQuoted),
      ).dumps("'24'");
    });

    test('Unfolds single quoted scalar', () {
      check(
          classicDumper().dump(
            'my unfolded\n\nstring',
            indent: 0,
            style: ScalarStyle.singleQuoted,
          ),
        )
        ..isMultiline()
        ..dumps("'my unfolded\n\n\nstring'");
    });

    test('Escapes all single quotes', () {
      check(
        classicDumper().dump(
          "It's my quoted's scalar. Go brrrr''''",
          indent: 0,
          style: ScalarStyle.singleQuoted,
        ),
      ).dumps("'It''s my quoted''s scalar. Go brrrr'''''''''");
    });

    test(
      'Defaults to double quoted when a non-printable character is used',
      () {
        check(
          classicDumper().dump(
            bell.asString(),
            indent: 0,
            style: ScalarStyle.singleQuoted,
          ),
        ).dumps(r'"\a"');
      },
    );
  });

  group('Dumps double quoted', () {
    test('Dumps double quoted scalar', () {
      check(
        classicDumper().dump(24, indent: 0, style: ScalarStyle.doubleQuoted),
      ).dumps('"24"');
    });

    test('Unfolds a simple double quoted scalar', () {
      check(
          classicDumper().dump(
            'my unfolded\n\nstring',
            indent: 0,
            style: ScalarStyle.doubleQuoted,
          ),
        )
        ..isMultiline()
        ..dumps('"my unfolded\n\n\nstring"');
    });

    test('Unfolds a complex double quoted scalar', () {
      check(
        classicDumper().dump(
          'my folded \n'
          'string with spaces \n'
          ' \n'
          'weirdly placed',
          indent: 0,
          style: ScalarStyle.doubleQuoted,
        ),
      ).dumps(
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
          classicDumper().dump(
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
            style: ScalarStyle.doubleQuoted,
          ),
        ).dumps(r'"\0\a\b\v\f\N\L\P\e\_\"\\\/"');
      },
    );
  });

  group('Dumps literal', () {
    test('Dumps literal scalar', () {
      check(
        classicDumper().dump(24, indent: 0, style: ScalarStyle.literal),
      ).dumps('|-\n24');
    });

    test('Never unfolds literal scalar', () {
      check(
          classicDumper().dump(
            'my unfoldable\n\nstring',
            indent: 0,
            style: ScalarStyle.literal,
          ),
        )
        ..isMultiline()
        ..dumps('|-\nmy unfoldable\n\nstring');
    });

    test(
      'Preserves trailing linebreaks from being chomped in literal scalar',
      () {
        check(
          classicDumper().dump(
            'my literal string\n\n',
            indent: 0,
            style: ScalarStyle.literal,
          ),
        ).dumps('|+\nmy literal string\n\n');
      },
    );

    test(
      'Preserves leading whitespace from being consumed as indent in first '
      'non-empty line in literal scalar',
      () {
        check(
          classicDumper().dump(
            ' literal string',
            indent: 0,
            style: ScalarStyle.literal,
          ),
        ).dumps(
          '|1-\n'
          '  literal string', // Indented by additional space
        );
      },
    );

    test('Defaults to double quoted when non-printable character is used', () {
      check(
        classicDumper().dump(
          bell.asString(),
          indent: 0,
          style: ScalarStyle.literal,
        ),
      ).dumps(r'"\a"');
    });
  });

  group('Dumps block folded', () {
    test('Dumps folded scalar', () {
      check(
        classicDumper().dump(24, indent: 0, style: ScalarStyle.folded),
      ).dumps('>-\n24');
    });

    test('Unfolds block folded scalar', () {
      check(
          classicDumper().dump(
            'my unfolded\n\nstring',
            indent: 0,
            style: ScalarStyle.folded,
          ),
        )
        ..isMultiline()
        ..dumps('>-\nmy unfolded\n\n\nstring');
    });

    test(
      'Preserves trailing linebreaks from being chomped in folded scalar'
      ' without unfolding them',
      () {
        check(
          classicDumper().dump(
            'my block folded string\n\n',
            indent: 0,
            style: ScalarStyle.folded,
          ),
        ).dumps('>+\nmy block folded string\n\n');
      },
    );

    test(
      'Preserves leading whitespace from being consumed as indent in first '
      'non-empty line in block folded scalar',
      () {
        check(
          classicDumper().dump(
            ' folded string',
            indent: 0,
            style: ScalarStyle.folded,
          ),
        ).dumps(
          '>1-\n'
          '  folded string', // Indented by additional space
        );
      },
    );

    test('Never unfolds line breaks joining indented line', () {
      check(
        classicDumper().dump(
          'folded string\n'
          ' with indented \n\n'
          'line',
          indent: 0,
          style: ScalarStyle.folded,
        ),
      ).dumps(
        '>-\n'
        'folded string\n'
        ' with indented \n\n'
        'line',
      );
    });

    test('Defaults to double quoted when non-printable character is used', () {
      check(
        classicDumper().dump(
          bell.asString(),
          indent: 0,
          style: ScalarStyle.folded,
        ),
      ).dumps(r'"\a"');
    });
  });
}
