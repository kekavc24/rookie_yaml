import 'package:checks/checks.dart';
import 'package:dump_yaml/src/unfolding.dart';
import 'package:rookie_yaml/rookie_yaml.dart';
import 'package:test/test.dart';

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
    () => defaultFolded.split('\n').iterator,
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

  void parserMatches(String unfolded, String folded) =>
      check(loadObject(YamlSource.simpleString(unfolded))).equals(folded);

  test('Unfolds a string normally (plain & single-quoted styles)', () {
    final unfolded = unfoldNormal(defaultStringSplit).join('\n');

    check(unfolded).equals(defaultUnfolded);

    // Check single quoted
    parserMatches("'$unfolded'", defaultFolded);

    // Check plain.
    parserMatches(
      unfolded,
      defaultFolded.trim(), // Cannot have leading and trailing whitespace
    );
  });

  test('Unfolds a string normally (folded block style)', () {
    final unfolded = unfoldBlockFolded(defaultStringSplit).join('\n');

    // Trailing line breaks are chomped not folded
    check(
      unfolded,
    ).equals(defaultUnfolded.substring(0, defaultUnfolded.length - 1));

    parserMatches('>\n$unfolded', defaultFolded);
  });

  test('Unfolds a string normally (double quoted)', () {
    final unfolded = unfoldDoubleQuoted(defaultStringSplit).join('\n');

    check(unfolded).equals(defaultUnfolded);
    parserMatches('"$unfolded"', defaultFolded);
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

      final unfolded = unfoldDoubleQuoted(foldTarget.split('\n')).join('\n');
      check(unfolded).equals(expected);

      parserMatches('"$unfolded"', foldTarget);
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

    final unfolded = unfoldBlockFolded(foldTarget.split('\n')).join('\n');
    check(unfolded).equals(expected);

    parserMatches('>$unfolded', foldTarget);
  });
}
