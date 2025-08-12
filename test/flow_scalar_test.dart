import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/double_quoted.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/plain.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/single_quoted.dart';
import 'package:rookie_yaml/src/parser/scanner/chunk_scanner.dart';
import 'package:test/test.dart';

import 'helpers/exception_helpers.dart';
import 'helpers/model_helpers.dart';

void main() {
  String wrapQuoted(String value, String char) => '$char$value$char';

  String doubleQuoted(String value) => wrapQuoted(value, '"');

  String singleQuoted(String value) => wrapQuoted(value, "'");

  const defaultLineToFold = '''
This line will get a space
while this one will get

a line break''';

  const foldedLine =
      'This line will get a space '
      'while this one will get\na line break';

  // PS: Intentionally expressive to prevent ambiguity
  group('Double Quoted Flow Scalar', () {
    test('Parses a simple double quoted scalar', () {
      final value = "value";

      check(
        parseDoubleQuoted(
          GraphemeScanner.of(doubleQuoted(value)),
          indent: 0,
          isImplicit: false,
        ),
      ).hasFormattedContent(value);
    });

    test('Parses and folds double quoted scalar', () {
      check(
        parseDoubleQuoted(
          GraphemeScanner.of(doubleQuoted(defaultLineToFold)),
          indent: 0,
          isImplicit: false,
        ),
      ).hasFormattedContent(foldedLine);
    });

    test('Folds double quoted scalar with escaped line breaks', () {
      final value = '''
value will preserve the spaces ->  \t\\
since the line break is escaped.\\

This line will have a line break between it and the period''';

      // Space never emitted if line break is escaped
      final folded =
          'value will preserve the spaces ->  \t'
          'since the line break is escaped.\nThis line will have a line break'
          ' between it and the period';

      check(
        parseDoubleQuoted(
          GraphemeScanner.of(doubleQuoted(value)),
          indent: 0,
          isImplicit: false,
        ),
      ).hasFormattedContent(folded);
    });

    test('Parses escaped characters in double quoted', () {
      // Additional line breaks to negate folding
      final value = '''
Fun with escapes:\n
1. \\\\ - backslash\n
2. \\" - double quoted\n
3. \\n - Line feed\n
4. \\r - Carriage return\n
5. \t - tab\n
6. \v - vertical tab\n
7. \\0 - ascii null\n
8. \\_ - nonbreaking space\n
9. \\N - nextline\n
10. \\P - paragraph separator\n
11. \\a - ascii bell\n
12. \\b - backspace\n
13. \\e - escape\n
14. \\x41 - UTF8 A\n
15. \\u0041 - UTF16 A\n
16. \\U00000041 - UTF32 A''';

      final parsed =
          '''
Fun with escapes:
1. ${SpecialEscaped.backSlash.string} - backslash
2. " - double quoted
3. ${LineBreak.lf} - Line feed
4. ${LineBreak.carriageReturn.string} - Carriage return
5. ${WhiteSpace.tab.string} - tab
6. ${SpecialEscaped.verticalTab.string} - vertical tab
7. ${SpecialEscaped.unicodeNull.string} - ascii null
8. ${SpecialEscaped.nbsp.string} - nonbreaking space
9. ${SpecialEscaped.nextLine.string} - nextline
10. ${SpecialEscaped.paragraphSeparator.string} - paragraph separator
11. ${SpecialEscaped.bell.string} - ascii bell
12. ${SpecialEscaped.backspace.string} - backspace
13. ${SpecialEscaped.asciiEscape.string} - escape
14. A - UTF8 A
15. A - UTF16 A
16. A - UTF32 A''';

      check(
        parseDoubleQuoted(
          GraphemeScanner.of(doubleQuoted(value)),
          indent: 0,
          isImplicit: false,
        ),
      ).hasFormattedContent(parsed);
    });

    test('Throws if leading quote is missing', () {
      check(
        () => parseDoubleQuoted(
          GraphemeScanner.of('unquoted'),
          indent: 0,
          isImplicit: false,
        ),
      ).throwsAFormatException(
        'Expected an opening double quote (") but found "u"',
      );
    });

    test('Throws if trailing quote is missing', () {
      check(
        () => parseDoubleQuoted(
          GraphemeScanner.of('"unquoted'),
          indent: 0,
          isImplicit: false,
        ),
      ).throwsAFormatException('Expected to find a closing quote');
    });

    test('Throws on premature exit if implicit and no quote', () {
      check(
        () => parseDoubleQuoted(
          GraphemeScanner.of(doubleQuoted('unquoted\n')),
          indent: 0,
          isImplicit: true,
        ),
      ).throwsAFormatException('Expected to find a closing quote');
    });

    test('Throws if unknown characters are escaped', () {
      check(
        () => parseDoubleQuoted(
          GraphemeScanner.of(doubleQuoted('Unknown escaped \\c')),
          indent: 0,
          isImplicit: true,
        ),
      ).throwsAFormatException('Unknown escaped character found: "c"');
    });

    test('Throws on indent change before closing quote', () {
      final value = '''
\n
  This is indented at 2 spaces.
  It's okay like this
 and an error when shifted 1 space left
''';

      check(
        () => parseDoubleQuoted(
          GraphemeScanner.of(doubleQuoted(value)),
          indent: 2,
          isImplicit: false,
        ),
      ).throwsAFormatException(
        'Invalid indent! Expected 2 space(s), found 1 space(s)',
      );
    });
  });

  group('Single Quoted Flow Scalar', () {
    test('Parses simple single quoted scalar', () {
      final value = 'value';

      check(
        parseSingleQuoted(
          GraphemeScanner.of(singleQuoted(value)),
          indent: 0,
          isImplicit: false,
        ),
      ).hasFormattedContent(value);
    });

    test('Parses and folds a single quoted scalar', () {
      check(
        parseSingleQuoted(
          GraphemeScanner.of(singleQuoted(defaultLineToFold)),
          indent: 0,
          isImplicit: false,
        ),
      ).hasFormattedContent(foldedLine);
    });

    test('Parses escaped single quotes correctly', () {
      const value = "here''s to \"quotes\"";

      final formatted = value.replaceFirst("'", '');

      check(
        parseSingleQuoted(
          GraphemeScanner.of(singleQuoted(value)),
          indent: 0,
          isImplicit: false,
        ),
      ).hasFormattedContent(formatted);
    });

    test('Throws if leading single quote is missing', () {
      check(
        () => parseSingleQuoted(
          GraphemeScanner.of('unquoted'),
          indent: 0,
          isImplicit: false,
        ),
      ).throwsAFormatException('Expected a single quote');
    });

    test('Throws if trailing single quote is missing', () {
      check(
        () => parseSingleQuoted(
          GraphemeScanner.of("'unquoted"),
          indent: 0,
          isImplicit: false,
        ),
      ).throwsAFormatException('Expected a single quote');
    });

    test('Throws on premature exit if implicit and no quote', () {
      check(
        () => parseSingleQuoted(
          GraphemeScanner.of(singleQuoted('unquoted\n')),
          indent: 0,
          isImplicit: true,
        ),
      ).throwsAFormatException('Expected a single quote');
    });

    test('Throws if unprintable characters are used', () {
      check(
        () => parseSingleQuoted(
          GraphemeScanner.of(
            singleQuoted('unquoted with ${SpecialEscaped.bell.string}'),
          ),
          indent: 0,
          isImplicit: false,
        ),
      ).throwsAFormatException(
        'Single-quoted scalars are restricted to printable characters only',
      );
    });

    test('Throws on indent change before closing quote', () {
      final value = '''
\n
  This is indented at 2 spaces.
  It''s okay like this
 and an error when shifted 1 space left
''';

      check(
        () => parseSingleQuoted(
          GraphemeScanner.of(singleQuoted(value)),
          indent: 2,
          isImplicit: false,
        ),
      ).throwsAFormatException(
        'Invalid indent! Expected 2 space(s), found 1 space(s)',
      );
    });
  });

  group('Plain Flow Scalar', () {
    test('Parses simple plain value', () {
      final value = 'value';

      check(
        parsePlain(
          GraphemeScanner.of(value),
          indent: 0,
          charsOnGreedy: '',
          isImplicit: false,
          isInFlowContext: false,
        ),
      ).hasFormattedContent(value);
    });

    test('Parses and folds plain scalar', () {
      check(
        parsePlain(
          GraphemeScanner.of(defaultLineToFold),
          indent: 0,
          isImplicit: false,
          charsOnGreedy: '',
          isInFlowContext: false,
        ),
      ).hasFormattedContent(foldedLine);
    });

    test('Exits gracefully if leading char is restricted', () {
      /// Never starts with "?<space>" or "-<space>" or ":<space>" combinations
      /// Intentional with enums

      check(
        parsePlain(
          GraphemeScanner.of('${Indicator.mappingKey.string} '),
          indent: 0,
          charsOnGreedy: '',
          isImplicit: false,
          isInFlowContext: false,
        ),
      ).isNull();

      check(
        parsePlain(
          GraphemeScanner.of('${Indicator.blockSequenceEntry.string} '),
          indent: 0,
          charsOnGreedy: '',
          isImplicit: false,
          isInFlowContext: false,
        ),
      ).isNull();

      // Assumes we have a missing key!
      check(
        parsePlain(
          GraphemeScanner.of('${Indicator.mappingValue.string} '),
          indent: 0,
          charsOnGreedy: '',
          isImplicit: false,
          isInFlowContext: false,
        ),
      ).hasFormattedContent('');
    });

    test('Handles flow indicators gracefully based on context', () {
      const prefix = 'Exit or not';

      // When in flow context. Exits immediately as delimiter is found
      for (final ReadableChar(:string) in flowDelimiters) {
        check(
          parsePlain(
            GraphemeScanner.of('$prefix$string'),
            indent: 0,
            charsOnGreedy: '',
            isImplicit: false,
            isInFlowContext: true,
          ),
        ).hasFormattedContent(prefix);
      }

      // When not in flow context
      for (final ReadableChar(:string) in flowDelimiters) {
        final curr = '$prefix$string'; // Parsed "as-is" completely as valid

        check(
          parsePlain(
            GraphemeScanner.of(curr),
            indent: 0,
            charsOnGreedy: '',
            isImplicit: false,
            isInFlowContext: false,
          ),
        ).hasFormattedContent(curr);
      }
    });

    test('Exits gracefully if disallowed character combinations are found', () {
      final restricted = [
        Indicator.comment.string,
        Indicator.mappingValue.string,
      ];

      const yaml = 'Plain';

      // Exits for ": " and " # "
      for (final str in restricted) {
        check(
          parsePlain(
            GraphemeScanner.of('$yaml $str '),
            indent: 0,
            charsOnGreedy: '',
            isImplicit: false,
            isInFlowContext: false,
          ),
        ).hasFormattedContent(yaml);
      }

      // Doesn't exit
      for (final str in restricted) {
        final complete = '$yaml$str';

        check(
          parsePlain(
            GraphemeScanner.of(complete),
            indent: 0,
            charsOnGreedy: '',
            isImplicit: false,
            isInFlowContext: false,
          ),
        ).hasFormattedContent(complete);
      }
    });

    test('Exits gracefully on indent change', () {
      const yaml = '''
  This plain has an indent of 2 space(s)
  and will fold till this line
 This line will be ignore. Indent change = 1 space!
''';

      const parsed =
          'This plain has an indent of 2 space(s) '
          'and will fold till this line';

      check(
          parsePlain(
            GraphemeScanner.of(yaml),
            indent: 2,
            charsOnGreedy: '',
            isImplicit: false,
            isInFlowContext: false,
          ),
        )
        ..hasFormattedContent(parsed)
        ..indentDidChangeTo(1);
    });

    test('Exits gracefully if implicit and line break is encountered', () {
      const yaml = '''
This line will be parsed
This will be ignored!
''';

      const parsed = 'This line will be parsed';

      check(
        parsePlain(
          GraphemeScanner.of(yaml),
          indent: 0,
          charsOnGreedy: '',
          isImplicit: true,
          isInFlowContext: false,
        ),
      ).hasFormattedContent(parsed);
    });
  });
}
