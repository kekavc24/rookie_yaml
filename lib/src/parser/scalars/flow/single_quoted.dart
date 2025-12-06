import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/flow_scalar_utils.dart';
import 'package:rookie_yaml/src/scanner/scalar_buffer.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Parses a `single quoted` scalar
PreScalar parseSingleQuoted(
  SourceIterator iterator, {
  required int indent,
  required bool isImplicit,
}) {
  if (iterator.current != singleQuote) {
    throwWithSingleOffset(
      iterator,
      message: "Expected an opening single quote (')",
      offset: iterator.currentLineInfo.current,
    );
  }

  iterator.nextChar();

  final buffer = ScalarBuffer();
  var quoteCount = 1;
  var foundLineBreak = false;

  sQuotedLoop:
  while (!iterator.isEOF && quoteCount != 2) {
    final char = iterator.current;

    switch (char) {
      case singleQuote:
        {
          // Single quotes can also be a form of escaping.
          if (iterator.peekNextChar() == singleQuote) {
            buffer.writeChar(singleQuote);
            iterator.nextChar();
          } else {
            ++quoteCount;
          }

          iterator.nextChar(); // Skip quote normally
        }

      case carriageReturn || lineFeed when isImplicit:
        break sQuotedLoop;

      // Ensure the `---` or `...` combination is never used in quoted scalars
      case blockSequenceEntry || period
          when indent == 0 &&
              iterator.before.isNotNullAnd((c) => c.isLineBreak()) &&
              iterator.peekNextChar() == char:
        {
          throwIfDocEndInQuoted(
            iterator,
            onDocMissing: buffer.writeAll,
            quoteChar: singleQuote,
          );
        }

      // Fold without any restrictions by default
      case space || tab || carriageReturn || lineFeed:
        {
          foundLineBreak =
              foldQuotedFlowScalar(
                iterator,
                scalarBuffer: buffer,
                minIndent: indent,
                isImplicit: isImplicit,
              ) ||
              foundLineBreak;
        }

      // Single quoted style is restricted to printable characters.
      default:
        {
          if (!char.isPrintable()) {
            throwWithSingleOffset(
              iterator,
              message:
                  'Single-quoted scalars are restricted to printable '
                  'characters only',
              offset: iterator.currentLineInfo.current,
            );
          }

          buffer.writeChar(char);
          iterator.nextChar();
        }
    }
  }

  if (quoteCount != 2) {
    throwWithApproximateRange(
      iterator,
      message: "Expected a closing single quote (') after the last character",
      current: iterator.currentLineInfo.current,
      charCountBefore: iterator.current.isLineBreak() ? 1 : 0,
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
    end: iterator.currentLineInfo.current,
  );
}
