import 'package:rookie_yaml/src/parser/scalars/block/block_scalar.dart';
import 'package:rookie_yaml/src/parser/scalars/flow/fold_flow_scalar.dart';
import 'package:rookie_yaml/src/parser/scalars/scalar_utils.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/scanner/scalar_buffer.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Characters that must not be parsed as the first character in a plain scalar
final _mustNotBeFirst = <int>{
  mappingKey,
  mappingValue,
  blockSequenceEntry,
};

/// Characters that disrupt normal buffering of characters that have no
/// meaning in/affect a plain scalar.
final _delimiters = <int>{
  lineFeed,
  carriageReturn,
  space,
  tab,
  mappingValue,
  comment,
};

const _style = ScalarStyle.plain;

/// Parses a `plain` scalar
PreScalar? parsePlain(
  GraphemeScanner scanner, {
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
    if (scanner.charAfter case space || tab) {
      // Intentionally expressive with if statement! We eval once.
      if (firstChar == mappingValue) {
        // TODO: Pass in null when refactoring scalar
        return (
          content: '',
          scalarStyle: _style,
          scalarIndent: indent,
          docMarkerType: DocumentMarker.none,
          hasLineBreak: false,
          wroteLineBreak: false,
          indentDidChange: false,
          indentOnExit: seamlessIndentMarker,
          end: scanner.lineInfo().current,
        );
      }

      // Return null for the other two indicators
      return null;
    }
  }

  final buffer = ScalarBuffer(StringBuffer(greedyChars));

  var docMarkerType = DocumentMarker.none;
  var foundLineBreak = false;
  RuneOffset? end;

  chunker:
  while (scanner.canChunkMore) {
    final char = scanner.charAtCursor;

    if (char == null) {
      break;
    }

    final charBefore = scanner.charBeforeCursor;
    var charAfter = scanner.charAfter;

    switch (char) {
      /// Check for the document end markers first always
      case blockSequenceEntry || period
          when indent == 0 &&
              charBefore.isNotNullAnd((c) => c.isLineBreak()) &&
              charAfter == char:
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
      case mappingValue
          when charAfter.isNullOr((c) => c.isWhiteSpace() || c.isLineBreak()):
        break chunker;

      /// A look behind condition if encountered while folding the scalar.
      case comment
          when charBefore.isNotNullAnd(
            (c) => c.isWhiteSpace() || c.isLineBreak(),
          ):
        break chunker;

      /// A lookahead condition of the rule above before folding the scalar
      case space || tab when charAfter == comment:
        break chunker;

      /// Restricted to a single line when implicit. Instead of throwing,
      /// exit and allow parser to determine next course of action
      case carriageReturn || lineFeed when isImplicit:
        break chunker;

      /// Attempt to fold by default anytime we see a line break or white space
      case space || tab || carriageReturn || lineFeed:
        {
          final (:indentDidChange, :foldIndent, :hasLineBreak) = foldFlowScalar(
            scanner,
            scalarBuffer: buffer,
            minIndent: indent,
            isImplicit: isImplicit,
          );

          if (indentDidChange) {
            end = scanner.lineInfo().start;
            indentOnExit = foldIndent;
            break chunker;
          }

          foundLineBreak = foundLineBreak || hasLineBreak;
        }

      case _ when (isImplicit || isInFlowContext) && char.isFlowDelimiter():
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
            exitIf: (_, curr) =>
                _delimiters.contains(curr) || curr.isFlowDelimiter(),
          );

          if (sourceEnded) break chunker;
        }
    }
  }

  return (
    /// Cannot have leading and trailing whitespaces.
    /// TODO: Include line breaks?
    content: trimYamlWhitespace(buffer.bufferedContent()),
    scalarStyle: _style,
    scalarIndent: indent,
    docMarkerType: docMarkerType,
    indentOnExit: indentOnExit,
    hasLineBreak: foundLineBreak,
    wroteLineBreak: buffer.wroteLineBreak,
    indentDidChange: indentOnExit != seamlessIndentMarker,
    end: end ?? scanner.lineInfo().current,
  );
}
