import 'package:rookie_yaml/src/parser/scalars/flow/fold_flow_scalar.dart';
import 'package:rookie_yaml/src/parser/scalars/scalar_utils.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/scanner/scalar_buffer.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

const _exception = FormatException('Expected a single quote');
const _printableException = FormatException(
  'Single-quoted scalars are restricted to printable characters only',
);

/// Parses a `single quoted` scalar
PreScalar parseSingleQuoted(
  GraphemeScanner scanner, {
  required int indent,
  required bool isImplicit,
}) {
  if (scanner.charAtCursor != singleQuote) {
    throw _exception;
  }

  scanner.skipCharAtCursor();

  final buffer = ScalarBuffer();
  var quoteCount = 1;
  var foundLineBreak = false;

  sQuotedLoop:
  while (scanner.canChunkMore && quoteCount != 2) {
    final possibleChar = scanner.charAtCursor;

    if (possibleChar == null) {
      throw _exception;
    }

    switch (possibleChar) {
      case singleQuote:
        {
          // Single quotes can also be a form of escaping.
          if (scanner.charAfter == singleQuote) {
            buffer.writeChar(singleQuote);
            scanner.skipCharAtCursor(); // Skip the quote escaping it
          } else {
            ++quoteCount;
          }

          scanner.skipCharAtCursor(); // Skip quote normally
        }

      case carriageReturn || lineFeed when isImplicit:
        break sQuotedLoop;

      // Fold without any restrictions by default
      case space || tab || carriageReturn || lineFeed:
        {
          foundLineBreak =
              foldQuotedFlowScalar(
                scanner,
                scalarBuffer: buffer,
                minIndent: indent,
                isImplicit: isImplicit,
              ) ||
              foundLineBreak;
        }

      // Single quoted style is restricted to printable characters.
      default:
        {
          if (!possibleChar.isPrintable()) {
            throw _printableException;
          }

          buffer.writeChar(possibleChar);
          scanner.skipCharAtCursor();
        }
    }
  }

  if (quoteCount != 2) {
    throw _exception;
  }

  return (
    content: buffer.bufferedContent(),
    scalarStyle: ScalarStyle.singleQuoted,
    scalarIndent: indent,
    docMarkerType: DocumentMarker.none,
    hasLineBreak: foundLineBreak,
    wroteLineBreak: buffer.wroteLineBreak,
    indentDidChange: false,
    indentOnExit: seamlessIndentMarker,
    end: scanner.lineInfo().current,
  );
}
