import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/fold_flow_scalar.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/scanner/scalar_buffer.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Parses a `single quoted` scalar
PreScalar parseSingleQuoted(
  GraphemeScanner scanner, {
  required int indent,
  required bool isImplicit,
}) {
  if (scanner.charAtCursor != singleQuote) {
    throwWithSingleOffset(
      scanner,
      message: "Expected an opening single quote (')",
      offset: scanner.lineInfo().current,
    );
  }

  scanner.skipCharAtCursor();

  final buffer = ScalarBuffer();
  var quoteCount = 1;
  var foundLineBreak = false;

  sQuotedLoop:
  while (scanner.canChunkMore && quoteCount != 2) {
    final possibleChar = scanner.charAtCursor;

    if (possibleChar == null) {
      throwWithSingleOffset(
        scanner,
        message: "Expected a closing single quote (')",
        offset: scanner.lineInfo().current,
      );
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
            throwWithSingleOffset(
              scanner,
              message:
                  'Single-quoted scalars are restricted to printable '
                  'characters only',
              offset: scanner.lineInfo().current,
            );
          }

          buffer.writeChar(possibleChar);
          scanner.skipCharAtCursor();
        }
    }
  }

  if (quoteCount != 2) {
    throwWithApproximateRange(
      scanner,
      message: "Expected a closing single quote (') after the last character",
      current: scanner.lineInfo().current,
      charCountBefore: scanner.charAtCursor?.isLineBreak() ?? true ? 1 : 0,
    );
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
