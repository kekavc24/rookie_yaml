import 'package:rookie_yaml/src/parser/scalars/block/block_scalar.dart';
import 'package:rookie_yaml/src/parser/scalars/scalar_utils.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/scanner/scalar_buffer.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

typedef FoldFlowInfo = ({
  bool indentDidChange,
  int foldIndent,
  bool hasLineBreak,
});

/// Ignores an escaped line break and excludes it from content in
/// [ScalarStyle.doubleQuoted].
///
/// See [escaped linebreak](https://yaml.org/spec/1.2.2/#731-double-quoted-style:~:text=In%20a%20multi,at%20arbitrary%20positions.)
({bool indentDidChange, int indentOnExit, bool exit}) _ignoreEscapedLineBreak(
  GraphemeScanner scanner, {
  required ScalarBuffer buffer,
  required List<int> bufferedWhitespace,
  required int minIndent,
}) {
  do {
    buffer.writeAll(bufferedWhitespace);
    bufferedWhitespace.clear();

    // Skip to linebreak.
    scanner.skipCharAtCursor();
    skipCrIfPossible(scanner.charAtCursor!, scanner: scanner);

    if (!scanner.canChunkMore) break;

    // Determine indent
    final indent = scanner.skipWhitespace(max: minIndent).length;
    scanner.skipCharAtCursor();

    if (indent < minIndent) {
      return (indentDidChange: true, indentOnExit: indent, exit: true);
    }

    // Capture whitespace incase the next char combination is "\" + linebreak.
    if (scanner.charAtCursor case int char when char == space || char == tab) {
      bufferedWhitespace.add(char);
      scanner
        ..skipWhitespace(skipTabs: true, previouslyRead: bufferedWhitespace)
        ..skipCharAtCursor();
    }
  } while (scanner.charAtCursor == slash &&
      scanner.charAfter.isNotNullAnd((c) => c.isLineBreak()));

  bufferedWhitespace.clear(); // Also escaped.

  return (
    indentDidChange: false,
    indentOnExit: seamlessIndentMarker,
    exit: scanner.charAtCursor.isNullOr(
      (c) => !c.isWhiteSpace() || !c.isLineBreak(),
    ),
  );
}

/// Folds a [ScalarStyle.singleQuoted] or [ScalarStyle.doubleQuoted] flow
/// scalar.
bool foldQuotedFlowScalar(
  GraphemeScanner scanner, {
  required ScalarBuffer scalarBuffer,
  required int minIndent,
  required bool isImplicit,
  bool resumeOnEscapedLineBreak = false,
}) {
  final (:indentDidChange, :foldIndent, :hasLineBreak) = foldFlowScalar(
    scanner,
    scalarBuffer: scalarBuffer,
    minIndent: minIndent,
    isImplicit: isImplicit,
    resumeOnEscapedLineBreak: resumeOnEscapedLineBreak,
  );

  // Quoted scalar never allow an indent change before seeing closing quote
  if (indentDidChange) {
    throwWithApproximateRange(
      scanner,
      message:
          'Invalid indent! Expected $minIndent space(s), found $foldIndent'
          ' space(s)',
      current: scanner.lineInfo().current,
      charCountBefore: foldIndent,
    );
  }

  return hasLineBreak;
}

/// Folds a flow scalar(`plain`, `double quoted` and `single quoted`) that
/// spans more than 1 line.
///
/// [resumeOnEscapedLineBreak] should only be provided when parsing a [Scalar]
/// with [ScalarStyle.doubleQuoted] which allows `\n` to be escaped. See
/// [parseDoubleQuoted]
FoldFlowInfo foldFlowScalar(
  GraphemeScanner scanner, {
  required ScalarBuffer scalarBuffer,
  required int minIndent,
  required bool isImplicit,
  bool resumeOnEscapedLineBreak = false,
}) {
  final bufferedWhitespace = <int>[];

  var didFold = false;

  folding:
  while (scanner.canChunkMore) {
    var current = scanner.charAtCursor;

    switch (current) {
      case carriageReturn || lineFeed when !isImplicit:
        {
          didFold = true;
          var lastWasLineBreak = false;

          void foldCurrent(int? current) {
            scalarBuffer.writeChar(
              lastWasLineBreak || current != null ? lineFeed : space,
            );

            bufferedWhitespace.clear();
          }

          void cleanUpFolding() {
            // The linebreak is excluded from folding if it was escaped.
            if (!lastWasLineBreak) {
              foldCurrent(null);
            } else {
              /// Never apply dangling whitespace if the new line was
              /// escaped. Safe fallback
              bufferedWhitespace.clear();
            }
          }

          /// Fold continuously until we encounter a char that is not a
          /// linebreak or whitespace.
          while (current != null && current.isLineBreak()) {
            current = skipCrIfPossible(current, scanner: scanner);
            bufferedWhitespace.clear();

            // Ensure we fold cautiously. Skip indent first
            final indent = scanner.skipWhitespace(max: minIndent).length;
            scanner.skipCharAtCursor();

            current = scanner.charAtCursor;

            final isDifferentScalar = indent < minIndent;

            /// We don't want to impede on the next scalar by consuming its
            /// content
            if (current != null &&
                current.isWhiteSpace() &&
                !isDifferentScalar) {
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
            if (current != null && current.isLineBreak()) {
              current = skipCrIfPossible(current, scanner: scanner);
              foldCurrent(current);
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

      case space || tab:
        bufferedWhitespace.add(current!);
        scanner.skipCharAtCursor();

      default:
        {
          /// Reserved for double quoted scalar where the linebreak can be
          /// escaped. All other flow styles should return false!
          if (resumeOnEscapedLineBreak &&
              current == backSlash &&
              scanner.charAfter.isNotNullAnd((c) => c.isLineBreak())) {
            final (
              :indentDidChange,
              :indentOnExit,
              :exit,
            ) = _ignoreEscapedLineBreak(
              scanner,
              buffer: scalarBuffer,
              bufferedWhitespace: bufferedWhitespace,
              minIndent: minIndent,
            );

            if (exit || indentDidChange) {
              return (
                indentDidChange: indentDidChange,
                foldIndent: indentOnExit,
                hasLineBreak: false, // Excluded from content
              );
            }

            break;
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
