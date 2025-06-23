import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/fold_flow_scalar.dart';
import 'package:rookie_yaml/src/parser/scalars/scalar_utils.dart';
import 'package:rookie_yaml/src/parser/scanner/chunk_scanner.dart';
import 'package:rookie_yaml/src/parser/scanner/scalar_buffer.dart';
import 'package:rookie_yaml/src/schema/nodes/node.dart';

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
/// Parses a `double quoted` scalar
PreScalar parseDoubleQuoted(
  ChunkScanner scanner, {
  required int indent,
  required bool isImplicit,
}) {
  final leadingChar = scanner.charAtCursor; // TODO: Use single variable?

  if (leadingChar != _doubleQuoteIndicator) {
    throw FormatException(
      'Expected an opening double quote (") but found'
      ' ${leadingChar?.string}',
    );
  }

  var quoteCount = 1;
  scanner.skipCharAtCursor();

  final buffer = ScalarBuffer(ensureIsSafe: false);
  var foundLineBreak = false;

  /// Code reusability in loop
  void foldDoubleQuoted() {
    foundLineBreak =
        foldQuotedFlowScalar(
          scanner,
          scalarBuffer: buffer,
          minIndent: indent,
          isImplicit: isImplicit,

          // Can only escape line breaks
          onExitResumeIf: (curr, next) {
            return curr == SpecialEscaped.backSlash && next is LineBreak;
          },
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
      case _doubleQuoteIndicator:
        ++quoteCount;
        scanner.skipCharAtCursor();

      // Implicit keys are restricted to a single line
      case LineBreak _ when isImplicit:
        break dQuotedLoop;

      // Attempt to fold or parsed escaped
      case SpecialEscaped.backSlash:
        {
          if (scanner.peekCharAfterCursor() is LineBreak) {
            foldDoubleQuoted();
            break;
          }

          _parseEscaped(scanner, buffer: buffer);
        }

      // Always fold by default if not escaped
      case WhiteSpace _ || LineBreak _:
        foldDoubleQuoted();

      default:
        {
          buffer.writeChar(current);

          final ChunkInfo(:sourceEnded) = scanner.bufferChunk(
            buffer.writeChar,
            exitIf: (_, current) => _doubleQuoteDelimiters.contains(current),
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

  return preformatScalar(
    buffer,
    scalarStyle: ScalarStyle.doubleQuoted,
    actualIdent: indent,
    foundLinebreak: foundLineBreak,
  );
}

/// Parses an escaped character in a double quoted scalar and returns `true`
/// only if it is a line break.
void _parseEscaped(
  ChunkScanner scanner, {
  required ScalarBuffer buffer,
}) {
  scanner.skipCharAtCursor();

  var charAfterEscape = scanner.charAtCursor;

  if (charAfterEscape == null) {
    throw _doubleQuoteException;
  }

  // Attempt to resolve as an hex
  if (SpecialEscaped.checkHexWidth(charAfterEscape) case var hexToRead
      when hexToRead != 0) {
    // TODO: Should hex characters be converted?
    buffer
      ..writeChar(SpecialEscaped.backSlash)
      ..writeChar(charAfterEscape);

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

      if (!isHexDigit(hexChar)) {
        throw const FormatException('Invalid hex digit found!');
      }

      buffer.writeChar(hexChar);
      --hexToRead;
      scanner.skipCharAtCursor();
    }

    if (hexToRead > 0) {
      throw FormatException('$hexToRead hex digit(s) are missing.');
    }

    return;
  }

  /// Resolve raw representations of characters in double quotes. This also
  /// helps resolves ASCII characters not represented correctly in Dart.
  ///
  /// The downside/upside (subjective), we implicitly replace any escaped
  /// characters with their expected `unicode` representations. Additionally,
  /// the next char is just written by default without caring
  buffer.writeChar(
    SpecialEscaped.resolveUnrecognized(charAfterEscape) ?? charAfterEscape,
  );

  scanner.skipCharAtCursor();
}
