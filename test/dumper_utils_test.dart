import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/dumping/dumping.dart';
import 'package:rookie_yaml/src/parser/scalars/block/block_scalar.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/double_quoted.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/plain.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/single_quoted.dart';
import 'package:rookie_yaml/src/parser/scalars/scalar_utils.dart';
import 'package:rookie_yaml/src/scanner/chunk_scanner.dart';
import 'package:rookie_yaml/src/schema/safe_type_wrappers/scalar_value.dart';
import 'package:test/test.dart';

import 'helpers/model_helpers.dart';

void main() {
  const defaultFolded = '''
This is a folded string
spanning multiple lines.

All line breaks will be
preserved
including the trailing one
for the
multiline string.
''';

  final defaultStringSplit = Iterable.withIterator(
    () => splitStringLazy(defaultFolded).iterator,
  );

  // Forgiving to the human eye.
  const defaultUnfolded =
      'This is a folded string'
      '\n\n'
      'spanning multiple lines.'
      '\n\n\n'
      'All line breaks will be'
      '\n\n'
      'preserved'
      '\n\n'
      'including the trailing one'
      '\n\n'
      'for the'
      '\n\n'
      'multiline string.'
      '\n\n';

  void parserMatches(PreScalar? onParsed, String folded) =>
      check(onParsed).hasFormattedContent(folded);

  group('Unfolding', () {
    test('Unfolds a string normally (plain & single-quoted styles)', () {
      final unfolded = unfoldNormal(defaultStringSplit).join('\n');

      check(unfolded).equals(defaultUnfolded);

      // Check single quoted
      parserMatches(
        parseSingleQuoted(
          GraphemeScanner.of("'$unfolded'"),
          indent: 0,
          isImplicit: false,
        ),
        defaultFolded,
      );

      // Check plain
      parserMatches(
        parsePlain(
          GraphemeScanner.of(unfolded),
          indent: 0,
          charsOnGreedy: '',
          isImplicit: false,
          isInFlowContext: false,
        ),
        defaultFolded,
      );
    });

    test('Unfolds a string normally (folded block style)', () {
      final unfolded = unfoldBlockFolded(defaultStringSplit).join('\n');

      // Trailing line breaks are chomped not folded
      check(
        unfolded,
      ).equals(defaultUnfolded.substring(0, defaultUnfolded.length - 1));

      parserMatches(
        parseBlockStyle(
          GraphemeScanner.of('>\n$unfolded'),
          minimumIndent: 0,
          onParseComment: (_) {},
        ),
        defaultFolded,
      );
    });

    test('Unfolds a string normally (double quoted)', () {
      final unfolded = unfoldDoubleQuoted(defaultStringSplit).join('\n');

      check(unfolded).equals(defaultUnfolded);

      parserMatches(
        parseDoubleQuoted(
          GraphemeScanner.of('"$unfolded"'),
          indent: 0,
          isImplicit: false,
        ),
        defaultFolded,
      );
    });

    test(
      'Unfolds a double quoted string with leading & trailing whitespaces',
      () {
        const foldTarget =
            'folded \n'
            'to a space,\t\n'
            ' \n'
            'to a line feed, or \t\n'
            ' \tnon-content';

        const expected =
            r'folded \'
            '\n\n\n'
            'to a space,\t'
            r'\'
            '\n\n\n'
            r'\ '
            '\n\n'
            'to a line feed, or \t'
            r'\'
            '\n\n\n'
            r'\'
            ' \tnon-content';

        final unfolded = unfoldDoubleQuoted(
          splitStringLazy(foldTarget),
        ).join('\n');

        check(unfolded).equals(expected);

        parserMatches(
          parseDoubleQuoted(
            GraphemeScanner.of('"$unfolded"'),
            indent: 0,
            isImplicit: false,
          ),
          foldTarget,
        );
      },
    );

    test('Unfolds a block folded string that is indented', () {
      const foldTarget =
          '\n'
          'folded line\n'
          'next line\n'
          '  * bullet\n'
          ' \n' // Empty indented!
          '  * list\n'
          '  * lines\n\n'
          'last line\n';

      const expected =
          '\n\n'
          'folded line\n\n'
          'next line\n' // Not unfolded. Next line indented!
          '  * bullet\n'
          ' \n'
          '  * list\n'
          '  * lines'
          '\n\n' // Not unfolded. Last non-empty line was indented!
          'last line\n'; // Trailing line breaks are chomped not folded

      final unfolded = unfoldBlockFolded(
        splitStringLazy(foldTarget),
      ).join('\n');

      check(unfolded).equals(expected);

      parserMatches(
        parseBlockStyle(
          GraphemeScanner.of('>$unfolded'),
          minimumIndent: 0,
          onParseComment: (_) {},
        ),
        foldTarget,
      );
    });
  });
}
