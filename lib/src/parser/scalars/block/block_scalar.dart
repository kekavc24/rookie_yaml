import 'dart:math';

import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';
import 'package:rookie_yaml/src/parser/comment_parser.dart';
import 'package:rookie_yaml/src/parser/scalars/scalar_utils.dart';
import 'package:rookie_yaml/src/parser/scanner/chunk_scanner.dart';
import 'package:rookie_yaml/src/parser/scanner/scalar_buffer.dart';
import 'package:rookie_yaml/src/schema/nodes/node.dart';

part 'block_header.dart';
part 'block_utils.dart';

/// Parses a block style scalar, that is `folded` or `literal`.
///
/// Returns a [PlainStyleInfo] record since a block style scalar is a plain
/// scalar with explicit indicators qualifying it as a block scalar. A plain
/// and block scalar both use indentation to convey content information.
PreScalar parseBlockStyle(
  ChunkScanner scanner, {
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

  final lineBreaks = <LineBreak>[
    if (!isLiteral && char is LineBreak)
      skipCrIfPossible(char, scanner: scanner),
  ];

  final buffer = ScalarBuffer(ensureIsSafe: false);

  var lastWasIndented = false;
  var didRun = false;

  /// Block scalar have no set indent. They infer indent using the first
  /// non-empty line.
  int? previousMaxIndent;

  int? endOffset;
  var hasDocMarkers = false;

  blockParser:
  while (scanner.canChunkMore && !hasDocMarkers) {
    final indent = trueIndent ?? minimumIndent;
    char = scanner.charAtCursor;

    switch (char) {
      case LineBreak _:
        {
          char = skipCrIfPossible(char, scanner: scanner);

          if (didRun) {
            lineBreaks.add(char);
          }

          final scannedIndent = scanner.skipWhitespace(max: indent).length;
          final charAfter = scanner.peekCharAfterCursor();

          if (charAfter is! LineBreak) {
            final hasCharAfter = charAfter != null;

            /// While `YAML` suggested we parse the comment thereafter, it is
            /// better to exit and allow the `root` parser to determine how to
            /// parse it.
            ///
            /// Also check if we need to exit incase a document/directives
            /// end marker is found in a top level scalar
            if (!hasCharAfter || scannedIndent < indent) {
              indentOnExit = scannedIndent;
              scanner.skipCharAtCursor();

              final ChunkScanner(:currentOffset, :source) = scanner;

              endOffset = hasCharAfter
                  ? (currentOffset - scannedIndent)
                  : source.length;
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

      case Indicator.blockSequenceEntry || Indicator.period
          when trueIndent == 0:
        {
          final maybeEndOffset = scanner.currentOffset;

          hasDocMarkers = hasDocumentMarkers(
            scanner,
            onMissing: buffer.writeAll,
          );

          // We will exit in the next iteration
          if (hasDocMarkers) endOffset = maybeEndOffset;
        }

      default:
        {
          if (char is WhiteSpace) {
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

          buffer.writeChar(char!);

          // Write the remaining line to the end without including line break
          final ChunkInfo(:sourceEnded) = scanner.bufferChunk(
            buffer.writeChar,
            exitIf: (_, curr) => curr is LineBreak,
          );

          if (sourceEnded) break blockParser;
        }
    }
  }

  _chompLineBreaks(chomping, contentBuffer: buffer, lineBreaks: lineBreaks);

  return preformatScalar(
    buffer,
    scalarStyle: style,
    actualIdent: trueIndent ?? minimumIndent,
    indentOnExit: indentOnExit,
    hasDocEndMarkers: hasDocMarkers,
    foundLinebreak: indentOnExit != seamlessIndentMarker || !buffer.isEmpty,
    endOffset: currentOrMaxOffset(scanner, endOffset),
  );
}
