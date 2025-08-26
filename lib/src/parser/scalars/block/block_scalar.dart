import 'dart:math';

import 'package:rookie_yaml/src/parser/scalars/scalar_utils.dart';
import 'package:rookie_yaml/src/scanner/chunk_scanner.dart';
import 'package:rookie_yaml/src/scanner/scalar_buffer.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';
import 'package:source_span/source_span.dart';

part 'block_header.dart';
part 'block_utils.dart';

/// Parses a block style scalar, that is `folded` or `literal`.
///
/// Returns a [PlainStyleInfo] record since a block style scalar is a plain
/// scalar with explicit indicators qualifying it as a block scalar. A plain
/// and block scalar both use indentation to convey content information.
PreScalar parseBlockStyle(
  GraphemeScanner scanner, {
  required int minimumIndent,
  required void Function(YamlComment comment) onParseComment,
}) {
  var indentOnExit = seamlessIndentMarker;
  final (:isLiteral, :chomping, :indentIndicator) = _parseBlockHeader(
    scanner,
    onParseComment: onParseComment,
  );

  final style = isLiteral ? ScalarStyle.literal : ScalarStyle.folded;

  int? trueIndent;

  /// If not null, we know the indent. Otherwise we have to infer from the
  /// first non-empty line.
  if (indentIndicator != null) {
    trueIndent = minimumIndent + indentIndicator;
  }

  var char = scanner.charAtCursor;

  final lineBreaks = <int>[
    if (!isLiteral && char.isNotNullAnd((c) => c.isLineBreak()))
      skipCrIfPossible(char!, scanner: scanner),
  ];

  final buffer = ScalarBuffer();

  var lastWasIndented = false;
  var didRun = false;

  /// Block scalar have no set indent. They infer indent using the first
  /// non-empty line.
  int? previousMaxIndent;

  SourceLocation? end;
  var docMarkerType = DocumentMarker.none;

  blockParser:
  while (scanner.canChunkMore) {
    final indent = trueIndent ?? minimumIndent;
    char = scanner.charAtCursor!;

    switch (char) {
      case carriageReturn || lineFeed:
        {
          char = skipCrIfPossible(char, scanner: scanner);

          if (didRun) {
            lineBreaks.add(char);
          }

          final scannedIndent = scanner.skipWhitespace(max: indent).length;
          final charAfter = scanner.peekCharAfterCursor();
          final hasCharAfter = charAfter != null;

          if (charAfter != carriageReturn && charAfter != lineFeed) {
            /// While `YAML` suggested we parse the comment thereafter, it is
            /// better to exit and allow the `root` parser to determine how to
            /// parse it.
            ///
            /// Also check if we need to exit incase a document/directives
            /// end marker is found in a top level scalar
            if (!hasCharAfter || scannedIndent < indent) {
              indentOnExit = scannedIndent;
              scanner.skipCharAtCursor();

              final lineInfo = scanner.lineInfo();

              /// If we have more characters, our actual scalar starts where
              /// the current line starts since the indent change caused the
              /// exit
              end = hasCharAfter ? lineInfo.start : lineInfo.current;
              break blockParser;
            }

            // Attempt to infer indent if null
            if (trueIndent == null) {
              final (
                :inferredIndent,
                :isEmptyLine,
                :startsWithTab,
              ) = _inferIndent(
                scanner,
                contentBuffer: buffer,
                scannedIndent: scannedIndent,
                callBeforeTabWrite: () => _maybeFoldLF(
                  buffer,
                  isLiteral: isLiteral,
                  lastNonEmptyWasIndented: false, // Not possible with no indent
                  lineBreaks: lineBreaks,
                ),
              );

              if (isEmptyLine) {
                previousMaxIndent = max(previousMaxIndent ?? 0, inferredIndent);
              } else {
                if (previousMaxIndent != null &&
                    previousMaxIndent > inferredIndent) {
                  throw FormatException(
                    'A previous empty line was more indented than the current'
                    ' line',
                  );
                }

                trueIndent = inferredIndent;
              }

              lastWasIndented = startsWithTab || lastWasIndented;
            }
          }

          scanner.skipCharAtCursor();
          didRun = true;
        }

      case blockSequenceEntry || period when trueIndent == 0:
        {
          // Ends when we see first "-" of "---" or "." of "..."
          final maybeEnd = scanner.lineInfo().current;

          docMarkerType = checkForDocumentMarkers(
            scanner,
            onMissing: buffer.writeAll,
          );

          if (docMarkerType.stopIfParsingDoc) {
            end = maybeEnd;
            break blockParser;
          }
        }

      // Literal & folded restricted to printable charset
      case _ when !char.isPrintable():
        throw FormatException(
          'Block scalar styles are restricted to the printable character set',
        );

      default:
        {
          if (char.isWhiteSpace()) {
            buffer.writeAll(
              _preserveEmptyIndented(
                isLiteral: isLiteral,
                lineBreaks: lineBreaks,
                lastWasIndented: lastWasIndented,
              ),
            );

            lastWasIndented = true;
            lineBreaks.clear();
          } else {
            _maybeFoldLF(
              buffer,
              isLiteral: isLiteral,
              lastNonEmptyWasIndented: lastWasIndented,
              lineBreaks: lineBreaks,
            );
            lastWasIndented = false;
          }

          buffer.writeChar(char);

          // Write the remaining line to the end without including line break
          final ChunkInfo(:sourceEnded) = scanner.bufferChunk(
            buffer.writeChar,
            exitIf: (_, curr) => curr.isLineBreak(),
          );

          if (sourceEnded) break blockParser;
        }
    }
  }

  _chompLineBreaks(chomping, contentBuffer: buffer, lineBreaks: lineBreaks);

  return (
    content: buffer.bufferedContent(),
    scalarStyle: style,
    scalarIndent: trueIndent ?? minimumIndent,
    indentOnExit: indentOnExit,
    indentDidChange: indentOnExit != seamlessIndentMarker,
    docMarkerType: docMarkerType,
    hasLineBreak: indentOnExit != seamlessIndentMarker || buffer.isNotEmpty,
    wroteLineBreak: buffer.wroteLineBreak,
    end: end ?? scanner.lineInfo().current,
  );
}
