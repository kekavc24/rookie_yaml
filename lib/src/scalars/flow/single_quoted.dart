import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scalars/flow/fold_flow_scalar.dart';
import 'package:rookie_yaml/src/scanner/chunk_scanner.dart';
import 'package:rookie_yaml/src/yaml_nodes/node.dart';
import 'package:rookie_yaml/src/yaml_nodes/node_styles.dart';

const _singleQuote = Indicator.singleQuote;

const _exception = FormatException('Expected a single quote');
const _printableException = FormatException(
  'Single-quoted scalars are restricted to printable characters only',
);

// TODO: Implicit
Scalar parseSingleQuoted(ChunkScanner scanner, {required int indent}) {
  // Advance then parse
  if (scanner.charAtCursor != _singleQuote) {
    scanner.skipCharAtCursor();
  }

  final buffer = StringBuffer();
  var quoteCount = 0;
  var shouldEvaluateCurrentChar = false;

  while (scanner.canChunkMore && quoteCount != 2) {
    final possibleChar = scanner.charAtCursor;

    if (possibleChar == null) {
      throw _exception;
    }

    // Single quoted style is restricted to printable characters
    if (!isPrintable(possibleChar)) {
      throw _printableException;
    }

    switch (possibleChar) {
      case _singleQuote:
        {
          /// Single quotes can also be a form of escaping. We need to be
          /// sure we already saw the opening quotes.
          if (scanner.peekCharAfterCursor() == _singleQuote &&
              quoteCount != 0) {
            buffer.write(_singleQuote.string);
            scanner.skipCharAtCursor();
          } else {
            ++quoteCount;
          }

          shouldEvaluateCurrentChar = false;
        }

      // Fold without any restrictions by default
      case WhiteSpace _ || LineBreak _:
        {
          final (:matchedDelimiter, :indentInfo, ignoreInfo: _) = foldScalar(
            buffer,
            scanner: scanner,
            curr: possibleChar,
            indent: indent,
            canExitOnNull: false,
            lineBreakWasEscaped: false,
            exitOnNullInfo: (
              delimiter: _singleQuote.string,
              description: 'single quote',
            ),
            ignoreGreedyNonBreakWrite: null,
            matchesDelimiter: (char) => char == _singleQuote,
          );

          if (indentInfo.indentChanged) {
            throw indentException(indent, indentInfo.indentFound);
          }

          shouldEvaluateCurrentChar = matchedDelimiter;
        }

      // Safe to write. Must be printable
      default:
        buffer.write(possibleChar.string);
        shouldEvaluateCurrentChar = false;
    }

    if (shouldEvaluateCurrentChar) {
      continue;
    }

    scanner.skipCharAtCursor();
  }

  if (quoteCount != 2) {
    throw _exception;
  }

  return Scalar(
    scalarStyle: ScalarStyle.singleQuoted,
    content: buffer.toString(),
  );
}
