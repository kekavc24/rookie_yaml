import 'dart:math';

import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/scalar_buffer.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';

part 'block_header.dart';
part 'block_utils.dart';

/// Parses a block style scalar, that is `folded` or `literal`.
///
/// Returns a [PlainStyleInfo] record since a block style scalar is a plain
/// scalar with explicit indicators qualifying it as a block scalar. A plain
/// and block scalar both use indentation to convey content information.
PreScalar parseBlockStyle(
  SourceIterator iterator, {
  required int minimumIndent,
  required int indentLevel,
  required void Function(YamlComment comment) onParseComment,
}) {
  var indentOnExit = seamlessIndentMarker;
  final (:isLiteral, :chomping, :indentIndicator) = _parseBlockHeader(
    iterator,
    onParseComment: onParseComment,
  );

  final style = isLiteral ? ScalarStyle.literal : ScalarStyle.folded;

  int? trueIndent;

  /// If not null, we know the indent. Otherwise we have to infer from the
  /// first non-empty line.
  if (indentIndicator != null) {
    trueIndent = indentLevel + indentIndicator;
  }

  final lineBreaks = <int>[
    if (!isLiteral && iterator.current.isLineBreak())
      skipCrIfPossible(iterator.current, iterator: iterator),
  ];

  final buffer = ScalarBuffer();

  var lastWasIndented = false;
  var didRun = false;

  /// Block scalar have no set indent. They infer indent using the first
  /// non-empty line.
  int? previousMaxIndent;

  RuneOffset? end;
  var docMarkerType = DocumentMarker.none;

  blockParser:
  while (!iterator.isEOF) {
    final indent = trueIndent ?? minimumIndent;
    var char = iterator.current;

    switch (char) {
      case carriageReturn || lineFeed:
        {
          char = skipCrIfPossible(char, iterator: iterator);

          if (didRun) {
            lineBreaks.add(char);
          }

          final scannedIndent = skipWhitespace(iterator, max: indent).length;
          final charAfter = iterator.peekNextChar();
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
              iterator.nextChar();

              /// If we have more characters, our actual scalar starts where
              /// the current line starts since the indent change caused the
              /// exit
              end = hasCharAfter
                  ? iterator.currentLineInfo.start
                  : iterator.currentLineInfo.current;
              break blockParser;
            }

            // Attempt to infer indent if null
            if (trueIndent == null) {
              final (
                :inferredIndent,
                :isEmptyLine,
                :startsWithTab,
              ) = _inferIndent(
                iterator,
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
                  throwWithApproximateRange(
                    iterator,
                    message:
                        'A previous empty line was more indented with '
                        '$previousMaxIndent space(s). Indent must be at least'
                        ' equal to or greater than this indent.',
                    current: iterator.currentLineInfo.current,
                    charCountBefore: inferredIndent,
                  );
                }

                trueIndent = inferredIndent;
              }

              lastWasIndented = startsWithTab || lastWasIndented;
            }
          }

          iterator.nextChar();
          didRun = true;
        }

      case blockSequenceEntry || period when trueIndent == 0:
        {
          // Ends when we see first "-" of "---" or "." of "..."
          final maybeEnd = iterator.currentLineInfo.current;

          docMarkerType = checkForDocumentMarkers(
            iterator,
            onMissing: buffer.writeAll,
          );

          if (docMarkerType.stopIfParsingDoc) {
            end = maybeEnd;
            break blockParser;
          }
        }

      // All block scalar styles only accept printable characters
      case _ when char.isPrintable():
        {
          if (char.isWhiteSpace()) {
            buffer.writeAll(lineBreaks);
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
          final OnChunk(:sourceEnded) = iterateAndChunk(
            iterator,
            onChar: buffer.writeChar,
            exitIf: (_, curr) => curr.isLineBreak(),
          );

          if (sourceEnded) break blockParser;
        }

      default:
        throwWithSingleOffset(
          iterator,
          message:
              'Block scalar styles are restricted to the printable '
              'character set',
          offset: iterator.currentLineInfo.current,
        );
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
    end: end ?? iterator.currentLineInfo.current,
  );
}
