import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scalars/block/block_scalar.dart';
import 'package:rookie_yaml/src/scanner/chunk_scanner.dart';

/// Generates a generic indent exception
FormatException indentException(int expectedIndent, int? foundIndent) {
  final trailing = foundIndent == null ? 'nothing' : '$foundIndent space(s)';
  return FormatException(
    'Invalid indent! Expected $expectedIndent space(s), found $trailing',
  );
}

/// Returns information after a `flow scalar` is folded, that is, a plain/
/// single quote/double quote scalar.
typedef FoldInfo =
    ({
      // If a delimiter was encounter for double/single quote flow scalars
      bool matchedDelimiter,

      //
      ({bool ignoredNext, bool foldedLineBreak}) ignoreInfo,
      ({bool indentChanged, int? indentFound}) indentInfo,
    });

FoldInfo _infoOnFold({
  bool matchedDelimiter = false,
  bool ignoredNextChar = false,
  bool foldedLineBreak = false,
  bool indentChanged = false,
  int? indentFound,
}) => (
  ignoreInfo: (ignoredNext: ignoredNextChar, foldedLineBreak: foldedLineBreak),
  matchedDelimiter: matchedDelimiter,
  indentInfo: (indentChanged: indentChanged, indentFound: indentFound),
);

final _defaultExitInfo = _infoOnFold();

/// TODO: Simplify this function!
FoldInfo foldScalar(
  StringBuffer foldingBuffer, {
  required ChunkScanner scanner,
  required ReadableChar curr,
  required int indent,
  required bool canExitOnNull,
  required bool lineBreakWasEscaped,
  required ({String delimiter, String description})? exitOnNullInfo,
  required bool Function(ReadableChar char)? ignoreGreedyNonBreakWrite,
  required bool Function(ReadableChar char) matchesDelimiter,
}) {
  final whitespaceBuffer = <String>[];
  var lineBreakIgnoreSpace = lineBreakWasEscaped;
  var lineBreakStreak = false;

  final canCheckGreedyNonBreak = ignoreGreedyNonBreakWrite != null;

  ReadableChar? foldTarget = curr;

  final (:delimiter, :description) =
      exitOnNullInfo ?? (delimiter: '', description: 'any character');

  final unexpectedEndException = FormatException(
    'Expected '
    '${delimiter.isEmpty ? description : "a $description ($delimiter)"}'
    ' but found nothing',
  );

  // We move the scanner forward and fold as many lines as we can
  while (true) {
    var charAfter = scanner.peekCharAfterCursor();

    if (foldTarget == null) {
      // Caller doesn't need to evaluate further
      if (canExitOnNull) return _defaultExitInfo;

      throw unexpectedEndException;
    }

    switch (foldTarget) {
      /// Fold if a line break is found. `\r\n` or `\n` or `\r`. Recognized
      /// as line breaks in YAML
      case final LineBreak canBeCrLf:
        {
          var skippedWhiteSpace = false;
          skipCrIfPossible(canBeCrLf, scanner: scanner);
          charAfter = scanner.peekCharAfterCursor();

          if (!lineBreakStreak) {
            whitespaceBuffer.clear();
          } else if (!lineBreakIgnoreSpace) {
            foldingBuffer.write(LineBreak.lf);
          }

          if (charAfter is WhiteSpace) {
            final spaceCount = scanner.skipWhitespace(max: indent).length;

            if (spaceCount < indent) {
              return _infoOnFold(indentChanged: true, indentFound: spaceCount);
            } else if (scanner.peekCharAfterCursor() is WhiteSpace) {
              /// Whitespace in double/single quotes serves no purpose,
              /// implicitly trim it. Simple skip.
              scanner.skipWhitespace(skipTabs: true);
            }

            charAfter = scanner.peekCharAfterCursor();

            if (charAfter == null && !canExitOnNull) {
              throw unexpectedEndException;
            }

            skippedWhiteSpace = true;
          } else {
            skippedWhiteSpace = indent == 0;
          }

          /// We must have a character here as long as we are `folding` in
          /// any flow style that is not `Plain`, that is, `double/single`
          /// quoted styles.
          ///
          /// Those two styles have a closing delimiter.
          if (charAfter == null && !canExitOnNull) {
            throw unexpectedEndException;
          }

          switch (charAfter) {
            // Line breaks don't require whitespace to be skipped.
            case final LineBreak _:
              lineBreakStreak = true;
              lineBreakIgnoreSpace = false;

            /// Any other character as long as we skipped whitespace in
            /// `double/single` or if `plain` style and we can exit on null
            case _ when skippedWhiteSpace:
              {
                /// Write `space` if we never folded consecutive line-breaks
                /// such that:
                ///   - `foo\nbar` becomes `foo bar`
                ///   - `foo\n\nbar` becomes `foo\nbar`
                ///
                /// See https://yaml.org/spec/1.2.2/#65-line-folding
                if (!lineBreakIgnoreSpace && !lineBreakStreak) {
                  foldingBuffer.write(WhiteSpace.space.string);
                }

                // For plain styles
                if (charAfter == null) {
                  return _defaultExitInfo;
                }

                if (canCheckGreedyNonBreak &&
                    ignoreGreedyNonBreakWrite(charAfter)) {
                  return _infoOnFold(
                    ignoredNextChar: true,
                    foldedLineBreak: true,
                  );
                }

                // We must exit. Evaluate to test for the delimiter
                return _infoOnFold(
                  matchedDelimiter: matchesDelimiter(charAfter),
                );
              }

            // Throw exception that the indent doesn't match!
            default:
              return _infoOnFold(indentChanged: true);
          }
        }

      // Buffer whitespaces normally
      case final WhiteSpace whiteSpace:
        whitespaceBuffer.add(whiteSpace.string);

      default:
        {
          /// Any buffer characters are written by default.
          ///
          /// We write by default based on `YAML` spec if a `line break` was
          /// escaped. See for double quotes:
          /// https://yaml.org/spec/1.2.2/#75:~:text=In%20a%20multi,at%20arbitrary%20positions.
          ///
          /// Also, since the next character may be `hex` string or an escaped
          /// `whitespace`, `double quote` or  any `character` that should be
          /// escaped.
          foldingBuffer.writeAll(whitespaceBuffer);
          whitespaceBuffer.clear();

          final isDelimiter = matchesDelimiter(foldTarget);
          final shouldIgnore =
              canCheckGreedyNonBreak && ignoreGreedyNonBreakWrite(foldTarget);

          if (!isDelimiter && !shouldIgnore) {
            safeWriteChar(foldingBuffer, foldTarget);
          }

          return _infoOnFold(
            matchedDelimiter: isDelimiter,
            ignoredNextChar: shouldIgnore,
          );
        }
    }

    foldTarget = scanner.peekCharAfterCursor();
    scanner.skipCharAtCursor();
  }
}
