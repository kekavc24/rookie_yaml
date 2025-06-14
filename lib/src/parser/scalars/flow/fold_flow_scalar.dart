import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';
import 'package:rookie_yaml/src/parser/scalars/block/block_scalar.dart';
import 'package:rookie_yaml/src/parser/scalars/scalar_utils.dart';
import 'package:rookie_yaml/src/parser/scanner/chunk_scanner.dart';
import 'package:rookie_yaml/src/parser/scanner/scalar_buffer.dart';
import 'package:rookie_yaml/src/schema/nodes/node.dart';

// TODO: Simplify line break etc. etc.

typedef FoldFlowInfo = ({
  bool indentDidChange,
  int foldIndent,
  bool hasLineBreak,
});

bool foldQuotedFlowScalar(
  ChunkScanner scanner, {
  required ScalarBuffer scalarBuffer,
  required int minIndent,
  required bool isImplicit,
  bool Function(ReadableChar current, ReadableChar? next)? onExitResumeIf,
}) {
  final shouldResume = onExitResumeIf ?? (_, _) => false;

  final (:indentDidChange, :foldIndent, :hasLineBreak) = foldFlowScalar(
    scanner,
    scalarBuffer: scalarBuffer,
    minIndent: minIndent,
    isImplicit: isImplicit,
    onExitResumeIf: shouldResume,
  );

  // Quoted scalar never allow an indent change before seeing closing quote
  if (indentDidChange) {
    throw FormatException(
      'Invalid indent! Expected $minIndent space(s), found $foldIndent'
      ' space(s)',
    );
  }

  return hasLineBreak;
}

/// Folds a flow scalar(`plain`, `double quoted` and `single quoted`) that
/// spans more than 1 line.
///
/// [onExitResumeIf] should only be provided when parsing a [Scalar] with
/// [ScalarStyle.doubleQuoted] which allows `\n` to be escaped. See
/// [parseDoubleQuoted]
FoldFlowInfo foldFlowScalar(
  ChunkScanner scanner, {
  required ScalarBuffer scalarBuffer,
  required int minIndent,
  required bool isImplicit,
  required bool Function(ReadableChar current, ReadableChar? next)
  onExitResumeIf,
}) {
  final bufferedWhitespace = <WhiteSpace>[];

  var linebreakWasEscaped = false; // Whether we escaped in the current run
  var didFold = false;

  folding:
  while (scanner.canChunkMore) {
    var current = scanner.charAtCursor;

    switch (current) {
      case LineBreak _ when !isImplicit:
        {
          didFold = true;
          const space = WhiteSpace.space;
          const lf = LineBreak.lineFeed;

          var lastWasLineBreak = false;

          void foldCurrent(LineBreak? current) {
            scalarBuffer.writeChar(
              lastWasLineBreak || current != null ? lf : space,
            );

            bufferedWhitespace.clear(); // Just to be safe!
          }

          void cleanUpFolding() {
            // The linebreak is excluded from folding if it was escaped.
            if (!linebreakWasEscaped && !lastWasLineBreak) {
              foldCurrent(null);
            } else {
              /// Never apply dangling whitespace if the new line was
              /// escaped. Safe fallback
              bufferedWhitespace.clear();
            }
          }

          /// Fold continuously until we encounter a char that is not a
          /// linebreak or whitespace.
          while (current is LineBreak) {
            current = skipCrIfPossible(current, scanner: scanner);

            // Ensure we fold cautiously. Skip indent first
            final indent = scanner.skipWhitespace(max: minIndent).length;
            scanner.skipCharAtCursor();

            current = scanner.charAtCursor;

            final isDifferentScalar = indent < minIndent;

            /// We don't want to impede on the next scalar by consuming its
            /// content
            if (current is WhiteSpace && !isDifferentScalar) {
              bufferedWhitespace.add(current);

              scanner
                ..skipWhitespace(
                  skipTabs: true,
                  previouslyRead: bufferedWhitespace,
                )
                ..skipCharAtCursor();

              current = scanner.charAtCursor;
            }

            /// It could be consecutive line breaks with no indent that made us
            /// think this is a different scalar. It was just an empty line.
            ///
            /// It doesn't matter if the line break was escaped. Resume the
            /// folding.
            if (current is LineBreak) {
              foldCurrent(current);
              linebreakWasEscaped = false;
              lastWasLineBreak = true;
              continue;
            }

            /// Plain scalars can be used in block styles. This indent change
            /// indicates we need to alert any block styles on the indent that
            /// triggered this exit.
            ///
            /// This can also be used to restrict double/single quoted styles
            /// nested in a block style.
            if (isDifferentScalar) {
              cleanUpFolding();
              return (
                foldIndent: indent,
                indentDidChange: true,
                hasLineBreak: true,
              );
            }

            break; // Always exit after finding a non space/line break char.
          }

          cleanUpFolding();
        }

      case WhiteSpace whiteSpace:
        bufferedWhitespace.add(whiteSpace);
        scanner.skipCharAtCursor();

      default:
        {
          /// Reserved for double quoted scalar where the linebreak can be
          /// escaped. All other flow styles should return false!
          if (current != null &&
              onExitResumeIf(current, scanner.peekCharAfterCursor())) {
            scalarBuffer.writeAll(bufferedWhitespace);
            bufferedWhitespace.clear();

            scanner.skipCharAtCursor();

            // Continue folding only if not implicit
            if (!isImplicit) {
              linebreakWasEscaped = true;
              break;
            }
          }

          scalarBuffer.writeAll(bufferedWhitespace);
          break folding;
        }
    }
  }

  return (
    indentDidChange: false,
    foldIndent: seamlessIndentMarker,
    hasLineBreak: didFold,
  );
}
