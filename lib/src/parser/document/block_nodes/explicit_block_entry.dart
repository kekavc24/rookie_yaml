import 'package:rookie_yaml/src/parser/document/block_nodes/block_node.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Parses an explicit key/value.
BlockNode<Obj>
_parseExplicit<R, Obj, Seq extends Iterable<Obj>, Dict extends Map<Obj, Obj?>>(
  ParserState<Obj, Seq, Dict> state, {
  required int indentLevel,
  required int indent,
  required ParserEvent expectedEvent,
  required BlockNode<Obj> Function(GraphemeScanner scanner) fallback,
}) {
  final ParserState(:scanner, :comments) = state;

  if (inferNextEvent(
        scanner,
        isBlockContext: true,
        lastKeyWasJsonLike: false,
      ) !=
      expectedEvent) {
    return fallback(scanner);
  }

  final nodeIndentLevel = indentLevel + 1;
  final explicitCharOffset = scanner.lineInfo().current;

  scanner.skipCharAtCursor();

  final indentOrSeparation = skipToParsableChar(
    scanner,
    onParseComment: comments.add,
  );

  /// The indent is on the same level as "?" or ":". This may also indicate
  /// that we are now pointing to the next key that may be implicit or explicit
  if (indentOrSeparation != null && indentOrSeparation <= indent) {
    return (
      blockInfo: (
        docMarker: DocumentMarker.none,
        exitIndent: indentOrSeparation,
      ),
      node: nullBlockNode(
        state,
        indentLevel: nodeIndentLevel,
        indent: indent + 1,
        start: scanner.canChunkMore
            ? scanner.lineInfo().start
            : scanner.lineInfo().current,
      ),
    );
  }

  final (:laxIndent, :inlineFixedIndent) = indentOfBlockChild(
    indentOrSeparation,
    blockParentIndent: indent,
    yamlNodeStartOffset: explicitCharOffset.utfOffset,
    contentOffset: scanner.lineInfo().current.utfOffset,
  );

  return parseBlockNode(
    state,
    indentLevel: nodeIndentLevel,
    inferredFromParent: indentOrSeparation,
    laxBlockIndent: indent + 1,
    fixedInlineIndent: inlineFixedIndent,
    forceInlined: false,
    composeImplicitMap: true,
  );
}

/// Parses an explicit block key and its value (if present).
BlockEntry<Obj> parseExplicitBlockEntry<
  Obj,
  Seq extends Iterable<Obj>,
  Dict extends Map<Obj, Obj?>
>(
  ParserState<Obj, Seq, Dict> state, {
  required int entryIndent,
  required int entryIndentLevel,
}) {
  // Parse the explicit key
  final (blockInfo: keyInfo, node: key) = _parseExplicit(
    state,
    indentLevel: entryIndentLevel,
    indent: entryIndent,
    expectedEvent: BlockCollectionEvent.startExplicitKey,
    fallback: (scanner) => throwWithSingleOffset(
      scanner,
      message: 'Expected "?" followed by a whitespace',
      offset: scanner.lineInfo().current,
    ),
  );

  switch (keyInfo.exitIndent) {
    case int indent:
      {
        if (indent > entryIndent) {
          final scanner = state.scanner;
          throwWithRangedOffset(
            scanner,
            message: 'Dangling node found when parsing explicit entry',
            start: key.endOffset!,
            end: state.scanner.lineInfo().current,
          );
        } else if (indent < entryIndent) {
          continue valueIsNull;
        }

        final (blockInfo: valueInfo, node: value) = _parseExplicit(
          state,
          indentLevel: entryIndentLevel,
          indent: entryIndent,
          expectedEvent: BlockCollectionEvent.startEntryValue,
          fallback: (scanner) {
            final (:start, :current) = scanner.lineInfo();
            return (
              blockInfo: keyInfo,
              node: nullBlockNode(
                state,
                indentLevel: entryIndentLevel,
                indent: entryIndent,
                start: keyInfo.exitIndent == null ? current : start,
              ),
            );
          },
        );

        return (blockInfo: valueInfo, node: (key, value));
      }

    valueIsNull:
    default:
      return (blockInfo: keyInfo, node: (key, null));
  }
}
