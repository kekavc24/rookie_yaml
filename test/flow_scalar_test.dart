import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/double_quoted.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/plain.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/single_quoted.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
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
          UnicodeIterator.ofString(doubleQuoted(value)),
          indent: 0,
          isImplicit: false,
        ),
      ).hasFormattedContent(value);
    });

    test('Parses and folds double quoted scalar', () {
      check(
        parseDoubleQuoted(
          UnicodeIterator.ofString(doubleQuoted(defaultLineToFold)),
          indent: 0,
          isImplicit: false,
        ),
      ).hasFormattedContent(foldedLine);
    });

    test('Folds double quoted scalar with escaped line breaks', () {
      final value = '''
value will preserve the spaces ->  \t\\
since the line break is escaped.\\

This line will have a space before after folding''';

      // Space never emitted if line break is escaped
      final folded =
          'value will preserve the spaces ->  \t'
          'since the line break is escaped. This line will have a space before '
          'after folding';

      check(
        parseDoubleQuoted(
          UnicodeIterator.ofString(doubleQuoted(value)),
          indent: 0,
          isImplicit: false,
        ),
      ).hasFormattedContent(folded);
    });

    test('Never fold when all linebreaks are escaped', () {
      const string = r'''
This string will be inline. \
It's like in bash where \
lines \
can \
be escaped. Or even \
C with code.''';

      check(
        parseDoubleQuoted(
          UnicodeIterator.ofString(doubleQuoted(string)),
          indent: 0,
          isImplicit: false,
        ),
      ).hasFormattedContent(
        "This string will be inline. It's like in bash where lines can be "
        'escaped. Or even C with code.',
      );
    });

    test('Never folds when string is fill of whitespace', () {
      const string = '''
\t\\
\\   \\


\\t <- that tab is in its raw form,
\\
<- Whitespace before this space was consumed.''';

      check(
        parseDoubleQuoted(
          UnicodeIterator.ofString(doubleQuoted(string)),
          indent: 0,
          isImplicit: false,
        ),
      ).hasFormattedContent(
        '\t   '
        '\n'
        '\t <- that tab is in its raw form, '
        '<- Whitespace before this space was consumed.',
      );
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
1. ${backSlash.asString()} - backslash
2. " - double quoted
3. \n - Line feed
4. \r - Carriage return
5. \t - tab
6. \v - vertical tab
7. ${unicodeNull.asString()} - ascii null
8. ${nbsp.asString()} - nonbreaking space
9. ${nextLine.asString()} - nextline
10. ${paragraphSeparator.asString()} - paragraph separator
11. ${bell.asString()} - ascii bell
12. ${backspace.asString()} - backspace
13. ${asciiEscape.asString()} - escape
14. A - UTF8 A
15. A - UTF16 A
16. A - UTF32 A''';

      check(
        parseDoubleQuoted(
          UnicodeIterator.ofString(doubleQuoted(value)),
          indent: 0,
          isImplicit: false,
        ),
      ).hasFormattedContent(parsed);
    });

    test('Throws if leading quote is missing', () {
      check(
        () => parseDoubleQuoted(
          UnicodeIterator.ofString('unquoted'),
          indent: 0,
          isImplicit: false,
        ),
      ).throwsParserException('Expected an opening double quote (")');
    });

    test('Throws if trailing quote is missing', () {
      check(
        () => parseDoubleQuoted(
          UnicodeIterator.ofString('"unquoted'),
          indent: 0,
          isImplicit: false,
        ),
      ).throwsParserException(
        'Expected a closing quote (") after the last character',
      );
    });

    test('Throws on premature exit if implicit and no quote', () {
      check(
        () => parseDoubleQuoted(
          UnicodeIterator.ofString(doubleQuoted('unquoted\n')),
          indent: 0,
          isImplicit: true,
        ),
      ).throwsParserException(
        'Expected a closing quote (") after the last character',
      );
    });

    test('Throws if unknown characters are escaped', () {
      check(
        () => parseDoubleQuoted(
          UnicodeIterator.ofString(doubleQuoted('Unknown escaped \\c')),
          indent: 0,
          isImplicit: true,
        ),
      ).throwsParserException('Unknown escaped character found');
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
          UnicodeIterator.ofString(doubleQuoted(value)),
          indent: 2,
          isImplicit: false,
        ),
      ).throwsParserException(
        'Invalid indent! Expected 2 space(s), found 1 space(s)',
      );
    });

    test('Throws when document markers are used before closing quote', () {
      final value = '\n...\n';

      check(
        () => parseDoubleQuoted(
          UnicodeIterator.ofString(doubleQuoted(value)),
          indent: 0,
          isImplicit: false,
        ),
      ).throwsParserException(
        'Expected a (") before the current document was terminated',
      );
    });
  });

  group('Single Quoted Flow Scalar', () {
    test('Parses simple single quoted scalar', () {
      final value = 'value';

      check(
        parseSingleQuoted(
          UnicodeIterator.ofString(singleQuoted(value)),
          indent: 0,
          isImplicit: false,
        ),
      ).hasFormattedContent(value);
    });

    test('Parses and folds a single quoted scalar', () {
      check(
        parseSingleQuoted(
          UnicodeIterator.ofString(singleQuoted(defaultLineToFold)),
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
          UnicodeIterator.ofString(singleQuoted(value)),
          indent: 0,
          isImplicit: false,
        ),
      ).hasFormattedContent(formatted);
    });

    test('Throws if leading single quote is missing', () {
      check(
        () => parseSingleQuoted(
          UnicodeIterator.ofString('unquoted'),
          indent: 0,
          isImplicit: false,
        ),
      ).throwsParserException("Expected an opening single quote (')");
    });

    test('Throws if trailing single quote is missing', () {
      check(
        () => parseSingleQuoted(
          UnicodeIterator.ofString("'unquoted"),
          indent: 0,
          isImplicit: false,
        ),
      ).throwsParserException(
        "Expected a closing single quote (') after the last character",
      );
    });

    test('Throws on premature exit if implicit and no quote', () {
      check(
        () => parseSingleQuoted(
          UnicodeIterator.ofString(singleQuoted('unquoted\n')),
          indent: 0,
          isImplicit: true,
        ),
      ).throwsParserException(
        "Expected a closing single quote (') after the last character",
      );
    });

    test('Throws if unprintable characters are used', () {
      check(
        () => parseSingleQuoted(
          UnicodeIterator.ofString(
            singleQuoted('unquoted with ${bell.asString()}'),
          ),
          indent: 0,
          isImplicit: false,
        ),
      ).throwsParserException(
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
          UnicodeIterator.ofString(singleQuoted(value)),
          indent: 2,
          isImplicit: false,
        ),
      ).throwsParserException(
        'Invalid indent! Expected 2 space(s), found 1 space(s)',
      );
    });

    test('Throws when document markers are used before closing quote', () {
      final value = '\n...\n';

      check(
        () => parseSingleQuoted(
          UnicodeIterator.ofString(singleQuoted(value)),
          indent: 0,
          isImplicit: false,
        ),
      ).throwsParserException(
        "Expected a (') before the current document was terminated",
      );
    });
  });

  group('Plain Flow Scalar', () {
    test('Parses simple plain value', () {
      final value = 'value';

      check(
        parsePlain(
          UnicodeIterator.ofString(value),
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
          UnicodeIterator.ofString(defaultLineToFold),
          indent: 0,
          isImplicit: false,
          charsOnGreedy: '',
          isInFlowContext: false,
        ),
      ).hasFormattedContent(foldedLine);
    });

    test('Exits gracefully if leading char is restricted', () {
      /// Never starts with "?<space>" or "-<space>" or ":<space>" combinations
      /// Intentional with "consts"

      check(
        parsePlain(
          UnicodeIterator.ofString('${mappingKey.asString()} '),
          indent: 0,
          charsOnGreedy: '',
          isImplicit: false,
          isInFlowContext: false,
        ),
      ).isNull();

      check(
        parsePlain(
          UnicodeIterator.ofString('${blockSequenceEntry.asString()} '),
          indent: 0,
          charsOnGreedy: '',
          isImplicit: false,
          isInFlowContext: false,
        ),
      ).isNull();

      // Assumes we have a missing key!
      check(
        parsePlain(
          UnicodeIterator.ofString('${mappingValue.asString()} '),
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
      for (final string in flowDelimiters) {
        check(
          parsePlain(
            UnicodeIterator.ofString('$prefix$string'),
            indent: 0,
            charsOnGreedy: '',
            isImplicit: false,
            isInFlowContext: true,
          ),
        ).hasFormattedContent(prefix);
      }

      // When not in flow context
      for (final string in flowDelimiters) {
        final curr = '$prefix$string'; // Parsed "as-is" completely as valid

        check(
          parsePlain(
            UnicodeIterator.ofString(curr),
            indent: 0,
            charsOnGreedy: '',
            isImplicit: false,
            isInFlowContext: false,
          ),
        ).hasFormattedContent(curr);
      }
    });

    test('Exits gracefully if disallowed character combinations are found', () {
      final restricted = Iterable.withIterator(
        () => [comment, mappingValue].map((e) => e.asString()).iterator,
      );

      const yaml = 'Plain';

      // Exits for ": " and " # "
      for (final str in restricted) {
        check(
          parsePlain(
            UnicodeIterator.ofString('$yaml $str '),
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
            UnicodeIterator.ofString(complete),
            indent: 0,
            charsOnGreedy: '',
            isImplicit: false,
            isInFlowContext: false,
          ),
        ).hasFormattedContent(complete.replaceFirst(':', ''));
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
            UnicodeIterator.ofString(yaml),
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
          UnicodeIterator.ofString(yaml),
          indent: 0,
          charsOnGreedy: '',
          isImplicit: true,
          isInFlowContext: false,
        ),
      ).hasFormattedContent(parsed);
    });
  });
}
