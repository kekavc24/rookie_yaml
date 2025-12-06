import 'package:rookie_yaml/src/parser/document/block_nodes/block_node.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Parses an explicit key/value.
BlockNode<Obj>
_parseExplicit<R, Obj, Seq extends Iterable<Obj>, Dict extends Map<Obj, Obj?>>(
  ParserState<Obj, Seq, Dict> state, {
  required int indentLevel,
  required int indent,
  required ParserEvent expectedEvent,
  required BlockNode<Obj> Function(SourceIterator iterator) fallback,
}) {
  final ParserState(:iterator, :comments) = state;

  if (inferNextEvent(
        iterator,
        isBlockContext: true,
        lastKeyWasJsonLike: false,
      ) !=
      expectedEvent) {
    return fallback(iterator);
  }

  final nodeIndentLevel = indentLevel + 1;
  final explicitCharOffset = iterator.currentLineInfo.current;

  iterator.nextChar();

  final indentOrSeparation = skipToParsableChar(
    iterator,
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
        start: iterator.isEOF
            ? iterator.currentLineInfo.current
            : iterator.currentLineInfo.start,
      ),
    );
  }

  final (:laxIndent, :inlineFixedIndent) = indentOfBlockChild(
    indentOrSeparation,
    blockParentIndent: indent,
    yamlNodeStartOffset: explicitCharOffset.utfOffset,
    contentOffset: iterator.currentLineInfo.current.utfOffset,
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
    fallback: (iterator) => throwWithSingleOffset(
      iterator,
      message: 'Expected "?" followed by a whitespace',
      offset: iterator.currentLineInfo.current,
    ),
  );

  switch (keyInfo.exitIndent) {
    case int indent:
      {
        if (indent > entryIndent) {
          final scanner = state.iterator;
          throwWithRangedOffset(
            scanner,
            message: 'Dangling node found when parsing explicit entry',
            start: key.endOffset!,
            end: state.iterator.currentLineInfo.current,
          );
        } else if (indent < entryIndent) {
          continue valueIsNull;
        }

        final (blockInfo: valueInfo, node: value) = _parseExplicit(
          state,
          indentLevel: entryIndentLevel,
          indent: entryIndent,
          expectedEvent: BlockCollectionEvent.startEntryValue,
          fallback: (iterator) {
            final (:start, :current) = iterator.currentLineInfo;
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
