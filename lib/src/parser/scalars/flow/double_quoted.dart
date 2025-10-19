import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/flow_scalar_utils.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/scanner/scalar_buffer.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

Never _doubleQuoteException(
  GraphemeScanner scanner,
  String message,
) => throwWithSingleOffset(
  scanner,

  // Defaults to a closing quote exceptions
  message: message,
  offset: scanner.lineInfo().current,
);

Never _closingQuoteException(
  GraphemeScanner scanner,
) => throwWithApproximateRange(
  scanner,
  message: 'Expected a closing quote (") after the last character',
  current: scanner.lineInfo().current,
  charCountBefore: scanner.charAtCursor?.isLineBreak() ?? true ? 1 : 0,
);

/// Parses a `double quoted` scalar
PreScalar parseDoubleQuoted(
  GraphemeScanner scanner, {
  required int indent,
  required bool isImplicit,
}) {
  final leadingChar = scanner.charAtCursor;

  if (leadingChar != doubleQuote) {
    _doubleQuoteException(scanner, 'Expected an opening double quote (")');
  }

  var quoteCount = 1;
  scanner.skipCharAtCursor();

  final buffer = ScalarBuffer();
  var foundLineBreak = false;

  /// Code reusability in loop
  void foldDoubleQuoted() {
    foundLineBreak =
        foldQuotedFlowScalar(
          scanner,
          scalarBuffer: buffer,
          minIndent: indent,
          isImplicit: isImplicit,
          resumeOnEscapedLineBreak: true,
        ) ||
        foundLineBreak;
  }

  dQuotedLoop:
  while (scanner.canChunkMore && quoteCount != 2) {
    final current = scanner.charAtCursor;

    if (current == null) break;

    switch (current) {
      // Tracks number of times we saw an unescaped `double quote`
      case doubleQuote:
        ++quoteCount;
        scanner.skipCharAtCursor();

      // Implicit keys are restricted to a single line
      case carriageReturn || lineFeed when isImplicit:
        break dQuotedLoop;

      // Attempt to fold or parsed escaped
      case backSlash:
        {
          if (scanner.charAfter.isNotNullAnd((c) => c.isLineBreak())) {
            foldDoubleQuoted();
            break;
          }

          _parseEscaped(scanner, buffer: buffer);
        }

      // Ensure the `---` or `...` combination is never used in quoted scalars
      case blockSequenceEntry || period
          when indent == 0 &&
              scanner.charBeforeCursor.isNotNullAnd((c) => c.isLineBreak()) &&
              scanner.charAfter == current:
        {
          throwIfDocEndInQuoted(
            scanner,
            onDocMissing: buffer.writeAll,
            quoteChar: doubleQuote,
          );
        }

      // Always fold by default if not escaped
      case space || tab || carriageReturn || lineFeed:
        foldDoubleQuoted();

      default:
        {
          buffer.writeChar(current);

          final ChunkInfo(:sourceEnded) = scanner.bufferChunk(
            buffer.writeChar,
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
    _closingQuoteException(scanner);
  }

  return (
    content: buffer.bufferedContent(),
    scalarStyle: ScalarStyle.doubleQuoted,
    scalarIndent: indent,
    docMarkerType: DocumentMarker.none,
    hasLineBreak: foundLineBreak,
    wroteLineBreak: buffer.wroteLineBreak,
    indentDidChange: false,
    indentOnExit: seamlessIndentMarker,
    end: scanner.lineInfo().current,
  );
}

/// Parses an escaped character in a double quoted scalar and returns `true`
/// only if it is a line break.
void _parseEscaped(
  GraphemeScanner scanner, {
  required ScalarBuffer buffer,
}) {
  scanner.skipCharAtCursor();

  final charAfterEscape = scanner.charAtCursor;

  if (charAfterEscape == null) {
    _closingQuoteException(scanner);
  }

  // Attempt to resolve as an hex
  if (checkHexWidth(charAfterEscape) case int hexWidth) {
    var hexToRead = hexWidth;
    int? hexCode;

    void convertRollingHex(String digit) {
      final binary = int.parse(digit, radix: 16); // We know it is valid

      hexCode = hexCode == null
          ? binary
          : (hexCode! << 4) ^ binary; // Shift 4 bits at a time
    }

    scanner.skipCharAtCursor(); // Point the hex character

    /// Further reads are safe peeks to prevent us from pointing
    /// the cursor too far ahead. Intentionally expressive rather than using
    /// `scanner.chunkWhile(...)`
    while (hexToRead > 0 && scanner.canChunkMore) {
      final hexChar = scanner.charAtCursor;

      if (hexChar == null) {
        _doubleQuoteException(
          scanner,
          'Expected an hexadecimal digit but found nothing',
        );
      }

      if (!hexChar.isHexDigit()) {
        _doubleQuoteException(scanner, 'Invalid hex digit found!');
      }

      --hexToRead;
      convertRollingHex(hexChar.asString());
      scanner.skipCharAtCursor();
    }

    // Must read all expected hex characters to be valid
    if (hexToRead > 0) {
      throwWithApproximateRange(
        scanner,
        message: '$hexToRead hex digit(s) are missing.',
        current: scanner.lineInfo().current,

        /// If no characters were read, we can safely assume the offset will
        /// point to the hex width identifier (x, u or U). In this case, we just
        /// include the previous character. In all other cases, we have to
        /// highlight all the other characters read and hex width identifiers.
        charCountBefore: (hexWidth - hexToRead) + 1,
      );
    }

    buffer.writeChar(hexCode!); // Will never be null if [hexToRead] is 0
    return;
  }

  /// Resolve raw representations of characters in double quotes. This also
  /// helps resolves ASCII characters not represented correctly in Dart but the
  /// caller wants to (maybe?).
  ///
  /// The downside/upside (subjective), we implicitly replace any escaped
  /// characters with their expected `unicode` representations.
  ///
  /// TODO: May need more work. For now, just throw.
  if (resolveDoubleQuotedEscaped(charAfterEscape) case int escaped) {
    buffer.writeChar(escaped);
    scanner.skipCharAtCursor();
    return;
  }

  throwWithApproximateRange(
    scanner,
    message: 'Unknown escaped character found',
    current: scanner.lineInfo().current,
    charCountBefore: 1, // Include the "\"
  );
}
