import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/parser/document/scalars/flow/flow_scalar_utils.dart';
import 'package:rookie_yaml/src/scanner/scalar_buffer.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

Never _doubleQuoteException(
  SourceIterator iterator,
  String message,
) => throwWithSingleOffset(
  iterator,

  // Defaults to a closing quote exceptions
  message: message,
  offset: iterator.currentLineInfo.current,
);

Never _closingQuoteException(
  SourceIterator iterator,
) => throwWithApproximateRange(
  iterator,
  message: 'Expected a closing quote (") after the last character',
  current: iterator.currentLineInfo.current,
  charCountBefore: iterator.current.isLineBreak() ? 1 : 0,
);

/// Parses a scalar with [ScalarStyle.doubleQuoted].
///
/// This is the parser's low level implementation for parsing a double quoted
/// scalar which returns a [PreScalar]. This is intentional. The delegate that
/// will be assigned to this function will contain more context on how this
/// scalar will be resolved.
PreScalar parseDoubleQuoted(
  SourceIterator iterator, {
  required int indent,
  required bool isImplicit,
}) {
  final buffer = ScalarBuffer();
  final info = doubleQuotedParser(
    iterator,
    buffer: buffer.writeChar,
    indent: indent,
    isImplicit: isImplicit,
  );

  return (
    content: buffer.bufferedContent(),
    scalarInfo: info,
    wroteLineBreak: buffer.wroteLineBreak,
  );
}

/// Parses the double quoted scalar.
///
/// Calls [buffer] for every byte/utf code unit that it reads as valid content
/// from the [iterator]. Always calls [onParsingComplete] and returns the
/// object [T] after the closing quote has been skipped.
ParsedScalarInfo doubleQuotedParser(
  SourceIterator iterator, {
  required CharWriter buffer,
  required int indent,
  required bool isImplicit,
}) {
  if (iterator.current != doubleQuote) {
    _doubleQuoteException(iterator, 'Expected an opening double quote (")');
  }

  var quoteCount = 1;
  iterator.nextChar();
  var foundLineBreak = false;

  // Inject variables directly
  void foldDoubleQuoted() {
    foundLineBreak =
        foldQuotedFlowScalar(
          iterator,
          scalarBuffer: buffer,
          minIndent: indent,
          isImplicit: isImplicit,
          resumeOnEscapedLineBreak: true,
        ) ||
        foundLineBreak;
  }

  dQuotedLoop:
  while (!iterator.isEOF && quoteCount != 2) {
    final current = iterator.current;

    switch (current) {
      // Tracks number of times we saw an unescaped `double quote`
      case doubleQuote:
        ++quoteCount;
        iterator.nextChar();

      // Implicit keys are restricted to a single line
      case carriageReturn || lineFeed when isImplicit:
        break dQuotedLoop;

      // Attempt to fold or parsed escaped
      case backSlash:
        {
          if (iterator.peekNextChar().isNotNullAnd((c) => c.isLineBreak())) {
            foldDoubleQuoted();
            break;
          }

          _parseEscaped(iterator, buffer: buffer);
        }

      // Ensure the `---` or `...` combination is never used in quoted scalars
      case blockSequenceEntry || period
          when indent == 0 &&
              iterator.before.isNotNullAnd((c) => c.isLineBreak()) &&
              iterator.peekNextChar() == current:
        {
          throwIfDocEndInQuoted(
            iterator,
            onDocMissing: (missed) => bufferHelper(missed, buffer),
            quoteChar: doubleQuote,
          );
        }

      // Always fold by default if not escaped
      case space || tab || carriageReturn || lineFeed:
        foldDoubleQuoted();

      default:
        {
          buffer(current);

          final OnChunk(:sourceEnded) = iterateAndChunk(
            iterator,
            onChar: buffer,
            exitIf: (_, current) =>
                current.isWhiteSpace() ||
                current.isLineBreak() ||
                current == doubleQuote ||
                current == backSlash,
          );

          if (sourceEnded) {
            break dQuotedLoop;
          }
        }
    }
  }

  if (quoteCount != 2) {
    _closingQuoteException(iterator);
  }

  return (
    scalarStyle: ScalarStyle.doubleQuoted,
    scalarIndent: indent,
    docMarkerType: DocumentMarker.none,
    hasLineBreak: foundLineBreak,
    indentDidChange: false,
    indentOnExit: seamlessIndentMarker,
    end: iterator.currentLineInfo.current,
  );
}

/// Parses an escaped character present in a double quoted string.
void _parseEscaped(SourceIterator iterator, {required CharWriter buffer}) {
  iterator.nextChar();

  if (iterator.isEOF) {
    _closingQuoteException(iterator);
  }

  final charAfterEscape = iterator.current;

  // Attempt to resolve as an hex
  if (checkHexWidth(charAfterEscape) case int hexWidth) {
    var hexToRead = hexWidth;
    var hexCode = 0;

    void convertRollingHex(int code) {
      hexCode =
          (hexCode << 4) |
          (code > asciiNine
              ? (10 + (code - (code > capF ? lowerA : capA)))
              : (code - asciiZero));
    }

    iterator.nextChar(); // Point the hex character

    /// Further reads are safe peeks to prevent us from pointing
    /// the cursor too far ahead. Intentionally expressive rather than using
    /// `scanner.chunkWhile(...)`
    while (hexToRead > 0 && !iterator.isEOF) {
      final hexChar = iterator.current;

      if (!hexChar.isHexDigit()) {
        _doubleQuoteException(iterator, 'Invalid hex digit found!');
      }

      --hexToRead;
      convertRollingHex(hexChar);
      iterator.nextChar();
    }

    // Must read all expected hex characters to be valid
    if (hexToRead > 0) {
      throwWithApproximateRange(
        iterator,
        message: '$hexToRead hex digit(s) are missing.',
        current: iterator.currentLineInfo.current,

        /// If no characters were read, we can safely assume the offset will
        /// point to the hex width identifier (x, u or U). In this case, we just
        /// include the previous character. In all other cases, we have to
        /// highlight all the other characters read and hex width identifiers.
        charCountBefore: (hexWidth - hexToRead) + 1,
      );
    }

    buffer(hexCode); // Will never be null if [hexToRead] is 0
    return;
  } else if (resolveDoubleQuotedEscaped(charAfterEscape) case int escaped) {
    buffer(escaped);
    iterator.nextChar();
    return;
  }

  throwWithApproximateRange(
    iterator,
    message: 'Unknown escaped character found',
    current: iterator.currentLineInfo.current,
    charCountBefore: 1, // Include the "\"
  );
}
