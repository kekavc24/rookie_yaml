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
  if (scanner.charAtCursor != _singleQuote) {
    throw _exception;
  }

  scanner.skipCharAtCursor();

  final buffer = ScalarBuffer(ensureIsSafe: false);
  var quoteCount = 1;

  while (scanner.canChunkMore && quoteCount != 2) {
    final possibleChar = scanner.charAtCursor;

    if (possibleChar == null) {
      throw _exception;
    }

    sQuotedLoop:
    switch (possibleChar) {
      case _singleQuote:
        {
          // Single quotes can also be a form of escaping.
          if (scanner.peekCharAfterCursor() == _singleQuote) {
            buffer.writeChar(_singleQuote);
            scanner.skipCharAtCursor(); // Skip the quote escaping it
          } else {
            ++quoteCount;
          }

          scanner.skipCharAtCursor(); // Skip quote normally
        }

      case LineBreak _ when isImplicit:
        break sQuotedLoop;

      // Fold without any restrictions by default
      case WhiteSpace _ || LineBreak _:
        {
          final FoldFlowInfo(:indentDidChange, :foldIndent) = foldFlowScalar(
            scanner,
            scalarBuffer: buffer,
            minIndent: indent,
            isImplicit: isImplicit,
            onExitResumeIf: (_, _) => false,
          );

          // We must see closing quote before anything else
          if (indentDidChange) {
            throw indentException(indent, foldIndent);
          }
        }

      // Single quoted style is restricted to printable characters.
      default:
        {
          if (!isPrintable(possibleChar)) {
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

  return preformatScalar(
    buffer,
    scalarStyle: ScalarStyle.singleQuoted,
    actualIdent: indent,
  );
}
