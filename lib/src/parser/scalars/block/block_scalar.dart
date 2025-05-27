import 'dart:collection';

import 'package:collection/collection.dart';
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
PreScalar parseBlockStyle(ChunkScanner scanner, {required int minimumIndent}) {
  var indentOnExit = 0;
  final (:isLiteral, :chomping, :indentIndicator) = _parseBlockHeader(scanner);

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

  final previousIndents = SplayTreeSet<int>();
  var hasDocMarkers = false;

  blockLoop:
  while (scanner.canChunkMore) {
    final indent = trueIndent ?? minimumIndent;
    char = scanner.charAtCursor;

    if (char is LineBreak) {
      char = skipCrIfPossible(char, scanner: scanner);

      if (didRun) {
        lineBreaks.add(char);
      }

      final scannedIndent = scanner.skipWhitespace(max: indent).length;
      final charAfter = scanner.peekCharAfterCursor();

      if (charAfter is! LineBreak) {
        /// While `YAML` suggested we parse the comment thereafter, it is
        /// better to exit and allow the `root` parser to determine how to
        /// parse it.
        ///
        /// Also check if we need to exit incase a document/directives
        /// end marker is found in a top level scalar
        final isDocEnd =
            scannedIndent == 0 &&
            hasDocumentMarkers(
              scanner,
              onMissing: (greedy) => buffer.writeAll(greedy),
            );

        if (charAfter == null || isDocEnd || scannedIndent < indent) {
          hasDocMarkers = isDocEnd;
          indentOnExit = scannedIndent;
          break blockLoop;
        }

        // Attempt to infer indent if null
        if (trueIndent == null) {
          final (:inferredIndent, :isEmptyLine, :startsWithTab) = _inferIndent(
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
            previousIndents.add(inferredIndent); // Only whitespace
          } else {
            if (previousIndents.isNotEmpty &&
                previousIndents.max > inferredIndent) {
              throw FormatException(
                'A previous empty line was more indented than the current line',
              );
            }

            trueIndent = inferredIndent;
          }

          lastWasIndented = startsWithTab || lastWasIndented;
        }
      }

      scanner.skipCharAtCursor();

      didRun = true;
      continue;
    }

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
    scanner.bufferChunk(
      buffer.writeChar,
      exitIf: (_, curr) => curr is LineBreak,
    );
  }

  _chompLineBreaks(chomping, contentBuffer: buffer, lineBreaks: lineBreaks);

  return preformatScalar(
    buffer,
    scalarStyle: style,
    indentOnExit: indentOnExit,
    hasDocEndMarkers: hasDocMarkers,
  );
}
