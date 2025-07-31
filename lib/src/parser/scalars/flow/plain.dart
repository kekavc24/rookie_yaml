import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';
import 'package:rookie_yaml/src/parser/scalars/block/block_scalar.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/fold_flow_scalar.dart';
import 'package:rookie_yaml/src/parser/scalars/scalar_utils.dart';
import 'package:rookie_yaml/src/parser/scanner/chunk_scanner.dart';
import 'package:rookie_yaml/src/parser/scanner/scalar_buffer.dart';
import 'package:rookie_yaml/src/schema/nodes/node.dart';
import 'package:source_span/source_span.dart';

/// Usually denotes end of a plain scalar if followed by a [WhiteSpace]
const _kvColon = Indicator.mappingValue;

/// Characters that must not be parsed as the first character in a plain scalar
final _mustNotBeFirst = <ReadableChar>{
  Indicator.mappingKey,
  _kvColon,
  Indicator.blockSequenceEntry,
};

/// Characters that disrupt normal buffering of characters that have no
/// meaning in/affect a plain scalar.
final _delimiters = <ReadableChar>{
  ...LineBreak.values,
  ...WhiteSpace.values,
  _kvColon,
  Indicator.comment,
};

const _style = ScalarStyle.plain;

/// Parses a `plain` scalar
PreScalar? parsePlain(
  ChunkScanner scanner, {
  required int indent,
  required String charsOnGreedy,
  required bool isImplicit,
  required bool isInFlowContext,
}) {
  var greedyChars = charsOnGreedy;
  var indentOnExit = seamlessIndentMarker;

  /// We need to ensure our chunking is definite to prevent unnecessary cycles
  /// wasted on checking if a plain scalar was a:
  ///   - Explicit key indicated by `?`
  ///   - Block entry indicated by `-`
  ///   - Maps to a value `:`
  ///
  /// Mapping to a value using `:` can be rechecked within the loop as YAML
  /// strictly emphasizes this must not happen within scalar. If so, assume
  /// it's a key.
  ///
  /// See:
  /// https://yaml.org/spec/1.2.2/#733-plain-style:~:text=Plain%20scalars%20must%20not%20begin%20with%20most%20indicators%2C%20as%20this%20would%20cause%20ambiguity%20with%20other%20YAML%20constructs.%20However%2C%20the%20%E2%80%9C%3A%E2%80%9D%2C%20%E2%80%9C%3F%E2%80%9D%20and%20%E2%80%9C%2D%E2%80%9D%20indicators%20may%20be%20used%20as%20the%20first%20character%20if%20followed%20by%20a%20non%2Dspace%20%E2%80%9Csafe%E2%80%9D%20character%2C%20as%20this%20causes%20no%20ambiguity.
  final firstChar = scanner.charAtCursor;

  if (greedyChars.isEmpty && _mustNotBeFirst.contains(firstChar)) {
    if (scanner.peekCharAfterCursor() is WhiteSpace) {
      // Intentionally expressive with if statement! We eval once.
      if (firstChar == Indicator.mappingValue) {
        // TODO: Pass in null when refactoring scalar
        return preformatScalar(
          ScalarBuffer(ensureIsSafe: false),
          scalarStyle: _style,
          actualIdent: indent,
          foundLinebreak: false,
          end: scanner.lineInfo().current,
        );
      }

      // Return null for the other two indicators
      return null;
    }
  }

  final buffer = ScalarBuffer(
    ensureIsSafe: true,
    buffer: StringBuffer(greedyChars),
  );

  var docMarkerType = DocumentMarker.none;
  var foundLineBreak = false;
  SourceLocation? end;

  chunker:
  while (scanner.canChunkMore) {
    final char = scanner.charAtCursor;

    if (char == null) {
      break;
    }

    final charBefore = scanner.charBeforeCursor;
    var charAfter = scanner.peekCharAfterCursor();

    switch (char) {
      /// Check for the document end markers first always
      case Indicator.blockSequenceEntry || Indicator.period
          when indent == 0 && charBefore is LineBreak && charAfter == char:
        {
          final maybeEnd = scanner.lineInfo().current;

          docMarkerType = checkForDocumentMarkers(
            scanner,
            onMissing: (greedy) => buffer.writeAll(greedy),
          );

          if (docMarkerType.stopIfParsingDoc) {
            end = maybeEnd;
            break chunker;
          }
        }

      /// A mapping key can never be followed by a whitespace. Exit regardless
      /// of whether we folded this scalar before.
      case _kvColon
          when charAfter == WhiteSpace.space || charAfter is LineBreak:
        break chunker;

      /// A look behind condition if encountered while folding the scalar.
      case Indicator.comment
          when charBefore is WhiteSpace || charBefore is LineBreak:
        break chunker;

      /// A lookahead condition of the rule above before folding the scalar
      case WhiteSpace _ when charAfter == Indicator.comment:
        break chunker;

      /// Restricted to a single line when implicit. Instead of throwing,
      /// exit and allow parser to determine next course of action
      case LineBreak _ when isImplicit:
        break chunker;

      /// Attempt to fold by default anytime we see a line break or white space
      case WhiteSpace _ || LineBreak _:
        {
          final (:indentDidChange, :foldIndent, :hasLineBreak) = foldFlowScalar(
            scanner,
            scalarBuffer: buffer,
            minIndent: indent,
            isImplicit: isImplicit,
            onExitResumeIf: (_, _) => false,
          );

          if (indentDidChange) {
            end = scanner.lineInfo().start;
            indentOnExit = foldIndent;
            break chunker;
          }

          foundLineBreak = foundLineBreak || hasLineBreak;
        }

      case _
          when (isImplicit || isInFlowContext) && flowDelimiters.contains(char):
        break chunker;

      default:
        {
          /// Compensate for any comments that were extracted before this. We
          /// want to ensure we fold based on the last line break of the
          /// comment(s) we extracted.
          ///
          ///
          // if (extractedComment) {
          //   buffer.write(WhiteSpace.space.string);
          //   extractedComment = false;
          // }

          buffer.writeChar(char);

          final ChunkInfo(:sourceEnded) = scanner.bufferChunk(
            buffer.writeChar,
            exitIf: (_, curr) {
              return _delimiters.contains(curr) ||
                  flowDelimiters.contains(curr);
            },
          );

          if (sourceEnded) break chunker;
        }
    }
  }

  return preformatScalar(
    buffer,
    scalarStyle: _style,
    trim: true, // Plain scalars have no leading/trailing spaces!
    actualIdent: indent,
    indentOnExit: indentOnExit,
    docMarkerType: docMarkerType,
    foundLinebreak: foundLineBreak,
    end: end ?? scanner.lineInfo().current,
  );
}
