import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/fold_flow_scalar.dart';
import 'package:rookie_yaml/src/parser/scalars/scalar_utils.dart';
import 'package:rookie_yaml/src/parser/scanner/chunk_scanner.dart';
import 'package:rookie_yaml/src/parser/scanner/scalar_buffer.dart';
import 'package:rookie_yaml/src/schema/nodes/node.dart';

const _singleQuote = Indicator.singleQuote;

const _exception = FormatException('Expected a single quote');
const _printableException = FormatException(
  'Single-quoted scalars are restricted to printable characters only',
);

/// Parses a `single quoted` scalar
PreScalar parseSingleQuoted(
  ChunkScanner scanner, {
  required int indent,
  required bool isImplicit,
}) {
  final buffer = ScalarBuffer(ensureIsSafe: false);
  var quoteCount = 0;
  var shouldEvaluateCurrentChar = false;

  while (scanner.canChunkMore && quoteCount != 2) {
    final possibleChar = scanner.charAtCursor;

    if (possibleChar == null) {
      throw _exception;
    }

    sQuotedLoop:
    switch (possibleChar) {
      case _singleQuote:
        {
          /// Single quotes can also be a form of escaping. We need to be
          /// sure we already saw the opening quotes.
          if (scanner.peekCharAfterCursor() == _singleQuote &&
              quoteCount != 0) {
            buffer.writeChar(_singleQuote);
            scanner.skipCharAtCursor();
          } else {
            ++quoteCount;
          }

          shouldEvaluateCurrentChar = false;
        }

      case LineBreak _ when isImplicit:
        break sQuotedLoop;

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

          // Maybe it could be escaped!
          shouldEvaluateCurrentChar = matchedDelimiter;
        }

      // Single quoted style is restricted to printable characters
      case _ when !isPrintable(possibleChar):
        throw _printableException;

      // Safe to write. Must be printable
      default:
        buffer.writeChar(possibleChar);
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

  return preformatScalar(
    buffer,
    scalarStyle: ScalarStyle.singleQuoted,
    actualIdent: indent,
  );
}
