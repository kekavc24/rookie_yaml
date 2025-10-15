import 'package:checks/checks.dart';
import 'package:rookie_yaml/src/parser/scalars/block/block_scalar.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';
import 'package:test/test.dart';

import 'helpers/exception_helpers.dart';
import 'helpers/model_helpers.dart';

void main() {
  const defaultBlockIndicators = [
    '|', // Literal
    '>', // Folded
  ];

  final comments = <YamlComment>[];

  tearDown(comments.clear);

  group('General block styling', () {
    test('Parses block header with indentation indicator', () {
      const indent = 2;

      final trailing =
          '''
$indent
  Content with indent of 2 spaces''';

      for (final block in defaultBlockIndicators) {
        check(
          parseBlockStyle(
            GraphemeScanner.of('$block$trailing'),
            minimumIndent: 0,
            onParseComment: comments.add,
          ),
        ).hasIndent(indent);
      }
    });

    test('Parses block header with comments', () {
      final holder = (columnIndex: 0, lineIndex: 0, utfOffset: 0);

      final comment = YamlComment(
        'Block comment',
        commentSpan: (start: holder, end: holder),
      );

      final trailing =
          '''
 $comment
  Content with indent of 2 spaces''';

      for (final block in defaultBlockIndicators) {
        parseBlockStyle(
          GraphemeScanner.of('$block$trailing'),
          minimumIndent: 0,
          onParseComment: comments.add,
        );
      }

      // Parsed in folded & literal in tandem
      check(comments).unorderedEquals([comment, comment]);
    });

    test('Parses block scalar with header only', () {
      for (final block in defaultBlockIndicators) {
        check(
            parseBlockStyle(
              GraphemeScanner.of(block),
              minimumIndent: 0,
              onParseComment: comments.add,
            ),
          )
          ..hasIndent(0)
          ..hasFormattedContent('');
      }
    });

    test('Throws if indent indicator is not in range of 1 - 9', () {
      // 0 is a single digit. Will check range before throwing
      check(
        () => parseBlockStyle(
          GraphemeScanner.of('|0\n'),
          minimumIndent: 0,
          onParseComment: comments.add,
        ),
      ).throwsWithMessage<RangeError>(
        'Invalid block indentation indicator. Value must be between 1 - 9',
        (r) => r.message,
      );

      /// 10 is a double digit. Will throw without checking range. The first
      /// digit of "10" which "1" is acceptable. Any other violates YAML format.
      /// We expect a chomping indicator
      check(
        () => parseBlockStyle(
          GraphemeScanner.of('|10\n'),
          minimumIndent: 0,
          onParseComment: comments.add,
        ),
      ).throwsParserException(
        'Invalid block indentation indicator. Value must be between 1 - 9',
      );
    });

    test('Throws if duplicate chomping indicators are declared', () {
      const yaml =
          '|+-'
          ' # No duplicates allowed';

      check(
        () => parseBlockStyle(
          GraphemeScanner.of(yaml),
          minimumIndent: 0,
          onParseComment: comments.add,
        ),
      ).throwsParserException(
        'Duplicate chomping indicators not allowed!',
      );
    });

    test('Throws if no separation space is present before comment', () {
      const yaml =
          '|'
          '#Expected a space after the indicator';

      check(
        () => parseBlockStyle(
          GraphemeScanner.of(yaml),
          minimumIndent: 0,
          onParseComment: comments.add,
        ),
      ).throwsParserException(
        'Expected a whitespace character before the start of the comment',
      );
    });

    test('Exits if indent is less than the indent specified by indicator', () {
      const lessIndented = '''
2
  This line is not indented by at least 2 spaces more than minimum indent
''';

      const minIndent = 2;

      for (final str in defaultBlockIndicators) {
        check(
            parseBlockStyle(
              GraphemeScanner.of('$str$lessIndented'),
              minimumIndent: minIndent,
              onParseComment: comments.add,
            ),
          )
          ..hasFormattedContent('')
          ..indentDidChangeTo(minIndent);
      }
    });

    test('Throws if a previous empty line was more indented', () {
      const emptyLineIsMoreIndented = '''
    \t
  Empty line has 4 spaces. This content line has 2 spaces!
''';

      for (final str in defaultBlockIndicators) {
        check(
          () => parseBlockStyle(
            GraphemeScanner.of(
              '$str'
              '\n'
              '$emptyLineIsMoreIndented',
            ),
            minimumIndent: 0,
            onParseComment: comments.add,
          ),
        ).throwsParserException(
          'A previous empty line was more indented with 4 space(s). '
          'Indent must be at least equal to or greater than this indent.',
        );
      }
    });
  });

  group('Literal Block Style', () {
    test('Parses simple scalar', () {
      const scalar =
          '|\n'
          ' literal with inferredIndent of 1 space.\n'
          ' Nothing more, nothing less';

      const parsed =
          'literal with inferredIndent of 1 space.\n'
          'Nothing more, nothing less';

      check(
          parseBlockStyle(
            GraphemeScanner.of(scalar),
            minimumIndent: 0,
            onParseComment: comments.add,
          ),
        )
        ..hasIndent(1)
        ..hasFormattedContent(parsed);
    });

    test('Treats leading space in more indented lines as content', () {
      const scalar =
          '|\n'
          '\n\n'
          ' Indent inferred here.\n'
          '  This line is more indented. It will have leading space\n'
          ' \tTab is not an indent but content';

      const parsed =
          '\n\n'
          'Indent inferred here.\n'
          ' This line is more indented. It will have leading space\n'
          '\tTab is not an indent but content';

      check(
          parseBlockStyle(
            GraphemeScanner.of(scalar),
            minimumIndent: 0,
            onParseComment: comments.add,
          ),
        )
        ..hasIndent(1)
        ..hasFormattedContent(parsed);
    });

    test('Keeps trailing line breaks', () {
      const scalar =
          '|+\n'
          'Literal keeps all line breaks\n\n\n';

      const parsed = 'Literal keeps all line breaks\n\n\n';

      check(
        parseBlockStyle(
          GraphemeScanner.of(scalar),
          minimumIndent: 0,
          onParseComment: comments.add,
        ),
      ).hasFormattedContent(parsed);
    });

    test('Clips all trailing line breaks after final line break', () {
      const scalar =
          '|\n'
          'Literal keeps final line break\n\n\n';

      const parsed = 'Literal keeps final line break\n';

      check(
        parseBlockStyle(
          GraphemeScanner.of(scalar),
          minimumIndent: 0,
          onParseComment: comments.add,
        ),
      ).hasFormattedContent(parsed);
    });

    test('Trims all trailing line breaks', () {
      const scalar =
          '|-\n'
          'Literal trims all line breaks\n\n\n';

      const parsed = 'Literal trims all line breaks';

      check(
        parseBlockStyle(
          GraphemeScanner.of(scalar),
          minimumIndent: 0,
          onParseComment: comments.add,
        ),
      ).hasFormattedContent(parsed);
    });
  });

  group('Folded Block Style', () {
    test('Parses simple scalar', () {
      const scalar =
          '>\n'
          ' folded with inferredIndent of 1 space.\n'
          ' Nothing more, nothing less';

      const parsed =
          'folded with inferredIndent of 1 space. Nothing more, nothing less';

      check(
          parseBlockStyle(
            GraphemeScanner.of(scalar),
            minimumIndent: 0,
            onParseComment: comments.add,
          ),
        )
        ..hasIndent(1)
        ..hasFormattedContent(parsed);
    });

    test('Never folds and preserves empty lines when more indented', () {
      /// From YAML site: https://yaml.org/spec/1.2.2/#813-folded-style
      /// Visit if view isn't appealing (applies to the result shown too 😉).
      const scalar =
          '>\n'
          '\n'
          ' folded\n'
          ' line\n'
          '\n'
          ' next\n'
          ' line\n'
          '   * bullet\n'
          '\n'
          '   * list\n'
          '   * lines\n'
          '\n'
          ' last\n'
          ' line';

      /// Leading indent space consumed for each and result formatted exactly
      /// as the human eye expects(subjective) it to be.
      const parsed =
          '\n'
          'folded line\n'
          'next line\n'
          '  * bullet\n'
          ' \n' // Space in between more indented line
          '  * list\n'
          '  * lines\n'
          '\n' // No space since next line is not indented
          'last line';

      check(
          parseBlockStyle(
            GraphemeScanner.of(scalar),
            minimumIndent: 0,
            onParseComment: comments.add,
          ),
        )
        ..hasIndent(1)
        ..hasFormattedContent(parsed);
    });

    test('Keeps trailing line breaks', () {
      const scalar =
          '>+\n'
          'Folded keeps all line breaks\n\n\n';

      const parsed = 'Folded keeps all line breaks\n\n\n';

      check(
        parseBlockStyle(
          GraphemeScanner.of(scalar),
          minimumIndent: 0,
          onParseComment: comments.add,
        ),
      ).hasFormattedContent(parsed);
    });

    test('Clips all trailing line breaks after final line break', () {
      const scalar =
          '>\n'
          'Folded keeps final line break\n\n\n';

      const parsed = 'Folded keeps final line break\n';

      check(
        parseBlockStyle(
          GraphemeScanner.of(scalar),
          minimumIndent: 0,
          onParseComment: comments.add,
        ),
      ).hasFormattedContent(parsed);
    });

    test('Trims all trailing line breaks', () {
      const scalar =
          '>-\n'
          'Folded trims all line breaks\n\n\n';

      const parsed = 'Folded trims all line breaks';

      check(
        parseBlockStyle(
          GraphemeScanner.of(scalar),
          minimumIndent: 0,
          onParseComment: comments.add,
        ),
      ).hasFormattedContent(parsed);
    });
  });
}
