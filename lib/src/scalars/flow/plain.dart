import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';
import 'package:rookie_yaml/src/parser_utils.dart';
import 'package:rookie_yaml/src/scalars/flow/fold_flow_scalar.dart';
import 'package:rookie_yaml/src/yaml_parser.dart';
import 'package:rookie_yaml/src/scanner/chunk_scanner.dart';
import 'package:rookie_yaml/src/yaml_nodes/node.dart';
import 'package:rookie_yaml/src/yaml_nodes/node_styles.dart';

const _kvColon = Indicator.mappingValue;

final _mustNotBeFirst = <ReadableChar>{
  Indicator.mappingKey,
  _kvColon,
  Indicator.blockSequenceEntry,
};

final _delimiters = <ReadableChar>{
  ...LineBreak.values,
  ...WhiteSpace.values,
  _kvColon,
  Indicator.comment,
};

final _flowDelimiters = <Indicator>{
  Indicator.mappingStart,
  Indicator.mappingEnd,
  Indicator.flowSequenceStart,
  Indicator.flowSequenceEnd,
  Indicator.flowEntryEnd,
};

const _style = ScalarStyle.plain;

// TODO: Implicit
PlainStyleInfo parsePlain(
  ChunkScanner scanner, {
  required int indent,
  required String charsOnGreedy,
  required bool isInFlowContext,
}) {
  bool isFlowDelimiter(ReadableChar char) {
    return isInFlowContext && _flowDelimiters.contains(char);
  }

  var greedyChars = charsOnGreedy;
  var indentOnExit = 0;

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
  final firstChar = scanner.peekCharAfterCursor();

  if (greedyChars.isEmpty && _mustNotBeFirst.contains(firstChar)) {
    scanner.skipCharAtCursor(); // Move forward

    if (scanner.peekCharAfterCursor() is WhiteSpace) {
      // Intentionally expressive with if statement! We eval once.
      if (firstChar == Indicator.mappingValue) {
        // TODO: Pass in null when refactoring scalar
        return (
          parseTarget: NextParseTarget.startFlowValue,
          scalar: Scalar(scalarStyle: _style, content: ''),
          indentOnExit: indent + 1, // Parsed null key
        );
      }

      // Return null for the other two indicators
      return (
        parseTarget: NextParseTarget.checkTarget(firstChar),
        scalar: null,
        indentOnExit: indent, // No parsing occured. Indent is "as-is (was)".
      );
    }

    greedyChars += firstChar?.string ?? '';
  }

  final buffer = StringBuffer(greedyChars);

  /// Unlike `double quoted` & `single quoted` styles, YAML `plain` style has
  /// no explicit indicators. We can (in)finitely chunk.
  ///
  /// Thus, we skip the current cursor character and evaluate
  scanner.skipCharAtCursor();

  var extractedComment = false;

  chunker:
  while (scanner.canChunkMore) {
    final char = scanner.charAtCursor;

    if (char == null) {
      break;
    }

    final charBefore = scanner.charBeforeCursor;
    var charAfter = scanner.peekCharAfterCursor();

    switch (char) {
      /// A mapping key can never be followed by a whitespace. Exit regardless
      /// of whether we folded this scalar before.
      case _kvColon when charAfter == WhiteSpace.space:
        break chunker;

      /// Straight up parse a comment if:
      ///   - Preceding character was whitespace
      ///   - We just folded a line break and we encounter a comment
      ///
      /// After we extract a comment, we exit once the cursor points to a
      /// `LineBreak` only if this is the last comment. This ensures we
      /// perform an error free line-folding operation.
      ///
      /// Alternatively, this can be easily achieved by excluding it in the
      /// first comment and including for all other comment after. We are
      /// essentially trying to treat all comments as single line break!
      case Indicator.comment when charBefore is WhiteSpace:
        {
          parseComment(scanner);
          extractedComment = true;
          continue chunker;
        }

      /// Skip so that the next iteration executes condition above. Comments
      /// aren't governed by indentation
      case WhiteSpace _ when charAfter == Indicator.comment:
        {
          scanner.skipCharAtCursor();
          continue chunker;
        }

      /// Restricted to a single line when in flow context. Instead of throwing
      /// exit and allow parser to determine next course of action
      case LineBreak _ when isInFlowContext:
        break chunker;

      /// We have to determine if we are exiting in case of an indent change.
      /// Plain scalars use indent to convey info.
      ///
      /// Additionally, this treats all line breaks after a comment as part
      /// of the comment itself rather than the scalar
      ///
      case LineBreak _ when extractedComment:
        {
          // No effect. Since whitespace is trimmed as part of line folding
          final spaceCount = scanner.skipWhitespace(max: indent).length;

          charAfter = scanner.peekCharAfterCursor();

          // Immediately exit once indent is less. Anything else is folded
          if (spaceCount < indent && charAfter is! LineBreak) {
            indentOnExit = spaceCount;
            break chunker;
          }

          // Truncate any whitespace
          if (charAfter is WhiteSpace) {
            scanner.skipWhitespace(skipTabs: true);
            charAfter = scanner.peekCharAfterCursor();
          }

          /// TODO: Feeling iff-y here! Works for now.
          /// See code commented out in default statement!
          extractedComment = false;
        }

      /// Attempt to fold all scalars by default
      case WhiteSpace _ || LineBreak _:
        {
          final (:ignoreInfo, :indentInfo, matchedDelimiter: _) = foldScalar(
            buffer,
            scanner: scanner,
            curr: char,
            indent: indent,
            canExitOnNull: true,
            lineBreakWasEscaped: false,
            exitOnNullInfo: null,
            ignoreGreedyNonBreakWrite: (iChar) {
              return iChar is WhiteSpace ||
                  iChar == Indicator.comment ||
                  iChar == _kvColon ||
                  isFlowDelimiter(iChar);
            },
            matchesDelimiter: (_) => false,
          );

          if (indentInfo.indentChanged) {
            indentOnExit = indentInfo.indentFound ?? indentOnExit;
            break chunker;
          }

          /// When a linebreak is folded, the character at cursor is not
          /// skipped. This is okay.
          ///
          /// If not, this character at cursor passed our
          /// `ignoreGreedyNonBreakWrite` predicate and needs to be
          /// evaluated
          if (ignoreInfo.ignoredNext && !ignoreInfo.foldedLineBreak) {
            continue chunker;
          }
        }

      // TODO: Implicit
      case _ when isFlowDelimiter(char):
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

          safeWriteChar(buffer, char);

          final ChunkInfo(:sourceEnded) = scanner.bufferChunk(
            buffer,
            exitIf: (_, curr) {
              return _delimiters.contains(curr) || isFlowDelimiter(curr);
            },
          );

          if (sourceEnded) {
            break chunker;
          }

          continue chunker;
        }
    }

    // Only essential after folding and skipping whitespace.
    scanner.skipCharAtCursor();
  }

  return (
    parseTarget: NextParseTarget.checkTarget(scanner.charAtCursor),

    // Plain scalars have no leading/trailing spaces!
    scalar: Scalar(scalarStyle: _style, content: buffer.toString().trim()),
    indentOnExit: indentOnExit,
  );
}
