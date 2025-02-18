import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scalars/flow/fold_flow_scalar.dart';
import 'package:rookie_yaml/src/scanner/chunk_scanner.dart';
import 'package:rookie_yaml/src/yaml_nodes/node.dart';
import 'package:rookie_yaml/src/yaml_nodes/node_styles.dart';

const _doubleQuoteIndicator = Indicator.doubleQuote;

final _doubleQuoteDelimiters = <ReadableChar>{
  _doubleQuoteIndicator,
  SpecialEscaped.backSlash,
  ...WhiteSpace.values,
  ...LineBreak.values,
};

const _doubleQuoteException = FormatException(
  'Expected to find a closing quote',
);

// TODO: Implicit
Scalar parseDoubleQuoted(ChunkScanner scanner, {required int indent}) {
  /// Nested function to check if we can exit the parsing. Usually after we
  /// find the first un-escaped closing `doubleQuote`.
  bool canExit(int quoteCount) => quoteCount == 2;

  var foundClosingQuote = false;
  var quoteCount = 0;
  final doubleQuoteBuffer = StringBuffer();

  var lineBreakIgnoreSpace = false;

  // TODO: Save offsets etc.

  while (scanner.canChunkMore && !foundClosingQuote) {
    final (:offset, :sourceEnded, :lineEnded, :charOnExit) = scanner
        .bufferChunk(
          doubleQuoteBuffer,
          exitIf: (_, current) => _doubleQuoteDelimiters.contains(current),
        );

    if (charOnExit == null) {
      throw _doubleQuoteException;
    }

    if (sourceEnded) {
      foundClosingQuote = canExit(quoteCount);
      break;
    }

    switch (charOnExit) {
      case final SpecialEscaped escaped:
        lineBreakIgnoreSpace = _parseEscaped(
          doubleQuoteBuffer,
          char: escaped,
          scanner: scanner,
        );

      /// Tracks number of times we saw an unescaped `double quote`
      case _doubleQuoteIndicator:
        ++quoteCount;

      // Always fold by default if not escaped
      default:
        {
          final (:ignoreInfo, :indentInfo, :matchedDelimiter) = foldScalar(
            doubleQuoteBuffer,
            scanner: scanner,
            curr: charOnExit,
            indent: indent,
            canExitOnNull: false,
            lineBreakWasEscaped: lineBreakIgnoreSpace,
            exitOnNullInfo: (
              delimiter: _doubleQuoteIndicator.string,
              description: 'double quote',
            ),
            ignoreGreedyNonBreakWrite:
                (char) =>
                    char == _doubleQuoteIndicator ||
                    char == SpecialEscaped.backSlash,
            matchesDelimiter: (char) => char == _doubleQuoteIndicator,
          );

          if (indentInfo.indentChanged) {
            throw indentException(indent, indentInfo.indentFound);
          } else if (ignoreInfo.ignoredNext || matchedDelimiter) {
            /// We need to handle the `escape` in a specific way in double
            /// quotes while maintaning the `fold` function's versatility
            if (scanner.charAtCursor == SpecialEscaped.backSlash) {
              lineBreakIgnoreSpace = _parseEscaped(
                doubleQuoteBuffer,
                char: SpecialEscaped.backSlash,
                scanner: scanner,
              );
            } else {
              ++quoteCount; // Otherwise, always the closing quote
            }
          }
        }
    }

    foundClosingQuote = canExit(quoteCount);
  }

  if (!foundClosingQuote) {
    throw _doubleQuoteException;
  }

  return Scalar(
    scalarStyle: ScalarStyle.doubleQuoted,
    content: doubleQuoteBuffer.toString(),
  );
}

bool _parseEscaped(
  StringBuffer buffer, {
  required SpecialEscaped char,
  required ChunkScanner scanner,
}) {
  if (char != SpecialEscaped.backSlash) {
    safeWriteChar(buffer, char);
    return false;
  }

  var charAfter = scanner.peekCharAfterCursor();

  if (charAfter == null) {
    throw _doubleQuoteException;
  }

  /// Resolve raw representations of characters in double quotes. This also
  /// helps resolves ASCII characters not represented correctly in Dart.
  ///
  /// The downside/upside (subjective), we implicitly replace any escaped
  /// characters with their expected `unicode` representations.
  charAfter = SpecialEscaped.resolveUnrecognized(charAfter) ?? charAfter;

  /// Concatenate without adding space when folding in the next call
  if (charAfter is LineBreak) {
    return true;
  } else if (charAfter
      case WhiteSpace _ || SpecialEscaped _ || _doubleQuoteIndicator) {
    // Write it greedily to buffer and skip to it.
    safeWriteChar(buffer, charAfter);
    scanner.skipCharAtCursor();
  } else {
    // Unicode at this point. Anything else is an error.
    var countToRead = SpecialEscaped.checkHexWidth(charAfter);

    if (countToRead == 0) {
      throw const FormatException('Invalid escaped character');
    }

    // TODO: Should hex characters be converted
    final hexBuffer = StringBuffer(charAfter.string);

    /// Move cursor forward to point the next character i.e `charAfter`
    scanner.skipCharAtCursor();

    /// Further reads are safe peeks to prevent us from pointing
    /// the cursor too far ahead. Intentionally expressive rather than using
    /// `scanner.chunkWhile(...)`
    while (countToRead > 0 && scanner.canChunkMore) {
      final hexChar = scanner.peekCharAfterCursor();

      if (hexChar == null) {
        throw const FormatException(
          'Expected an hexadecimal digit but found nothing',
        );
      }

      if (!isHexDigit(hexChar)) {
        throw const FormatException('Invalid hex digit found!');
      }

      hexBuffer.write(hexChar.string);
      --countToRead;
      scanner.skipCharAtCursor();
    }

    if (countToRead > 0) {
      throw FormatException(
        '$countToRead hex digit(s) are missing.'
        ' Only found $hexBuffer',
      );
    }

    buffer.writeAll([SpecialEscaped.backSlash.string, hexBuffer]);
  }

  return false;
}
