import 'package:rookie_yaml/src/parser/scalars/flow/fold_flow_scalar.dart';
import 'package:rookie_yaml/src/parser/scalars/scalar_utils.dart';
import 'package:rookie_yaml/src/scanner/chunk_scanner.dart';
import 'package:rookie_yaml/src/scanner/scalar_buffer.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

const _doubleQuoteException = FormatException(
  'Expected to find a closing quote',
);

/// Parses a `double quoted` scalar
PreScalar parseDoubleQuoted(
  GraphemeScanner scanner, {
  required int indent,
  required bool isImplicit,
}) {
  final leadingChar = scanner.charAtCursor;

  if (leadingChar != doubleQuote) {
    throw FormatException(
      'Expected an opening double quote (") but found'
      ' "${leadingChar?.asString()}"',
    );
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

  // TODO: Save offsets etc.
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
          if (scanner.peekCharAfterCursor().isNotNullAnd(
            (c) => c.isLineBreak(),
          )) {
            foldDoubleQuoted();
            break;
          }

          _parseEscaped(scanner, buffer: buffer);
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
    throw _doubleQuoteException;
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
    throw _doubleQuoteException;
  }

  // Attempt to resolve as an hex
  if (checkHexWidth(charAfterEscape) case int hexToRead) {
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
        throw const FormatException(
          'Expected an hexadecimal digit but found nothing',
        );
      }

      if (!hexChar.isHexDigit()) {
        throw const FormatException('Invalid hex digit found!');
      }

      --hexToRead;
      convertRollingHex(hexChar.asString());
      scanner.skipCharAtCursor();
    }

    if (hexCode == null || hexToRead > 0) {
      throw FormatException('$hexToRead hex digit(s) are missing.');
    }

    buffer.writeChar(hexCode!);
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

  throw FormatException(
    'Unknown escaped character found: "${charAfterEscape.asString()}"',
  );
}
