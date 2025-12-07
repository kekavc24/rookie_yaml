import 'package:rookie_yaml/src/parser/delegates/parser_delegate.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/block_node.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/special_block_entry.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Parses an explicit key/value.
({bool ignoreValueIfKey, BlockInfo blockInfo})
_parseExplicit<R, Obj, Seq extends Iterable<Obj>, Dict extends Map<Obj, Obj?>>(
  ParserState<Obj, Seq, Dict> state, {
  required int indentLevel,
  required int indent,
  required ParserEvent expectedEvent,
  required BlockInfo Function(SourceIterator iterator) fallback,
  required void Function(ParserDelegate<Obj> blockNode) onSequenceOrBlockNode,
  required OnBlockMapEntry<Obj> maybeOnEntry,
}) {
  final ParserState(:iterator, :comments) = state;

  if (inferBlockEvent(iterator) != expectedEvent) {
    return (ignoreValueIfKey: true, blockInfo: fallback(iterator));
  }

  final nodeIndentLevel = indentLevel + 1;
  final explicitCharOffset = iterator.currentLineInfo.current;

  iterator.nextChar();

  final indentOrSeparation = skipToParsableChar(
    iterator,
    onParseComment: comments.add,
  );

  final expectedLaxIndent = indent + 1;

  /// The indent is on the same level as "?" or ":". This may also indicate
  /// that we are now pointing to the next key that may be implicit or explicit
  if (indentOrSeparation != null && indentOrSeparation < expectedLaxIndent) {
    final ignoreValue = indentOrSeparation < indent;
    final explicit = nullBlockNode(
      state,
      indentLevel: nodeIndentLevel,
      indent: indent + 1,
      start: iterator.isEOF
          ? iterator.currentLineInfo.current
          : iterator.currentLineInfo.start,
    );

    // Optionally check if we must exit or can recover and parse a block
    // sequence.
    if (iterator.isEOF ||
        ignoreValue ||
        inferBlockEvent(iterator) != BlockCollectionEvent.startBlockListEntry) {
      onSequenceOrBlockNode(explicit);
      return (
        ignoreValueIfKey: ignoreValue,
        blockInfo: (
          docMarker: DocumentMarker.none,
          exitIndent: indentOrSeparation,
        ),
      );
    }

    final (:parsedNextImplicitKey, :blockInfo) = parseSpecialBlockSequence(
      state,
      keyIndent: indent,
      keyIndentLevel: indentLevel,
      property: null,
      onSequence: onSequenceOrBlockNode,
      onNextImplicitEntry: maybeOnEntry,
    );

    return (ignoreValueIfKey: parsedNextImplicitKey, blockInfo: blockInfo);
  }

  final (laxIndent: _, :inlineFixedIndent) = indentOfBlockChild(
    indentOrSeparation,
    blockParentIndent: indent,
    yamlNodeStartOffset: explicitCharOffset.utfOffset,
    contentOffset: iterator.currentLineInfo.current.utfOffset,
  );

  final (:parsedNextImplicitKey, :blockInfo) = composeSpecialBlockSequence(
    state,
    blockNode: parseBlockNode(
      state,
      indentLevel: nodeIndentLevel,
      inferredFromParent: indentOrSeparation,
      laxBlockIndent: indent + 1,
      fixedInlineIndent: inlineFixedIndent,
      forceInlined: false,
      composeImplicitMap: true,
    ),
    keyIndent: indent,
    keyIndentLevel: indentLevel,
    onSequenceOrBlockNode: onSequenceOrBlockNode,
    onNextImplicitEntry: maybeOnEntry,
  );

  return (ignoreValueIfKey: parsedNextImplicitKey, blockInfo: blockInfo);
}

/// Parses an explicit block key and its value (if present).
BlockInfo parseExplicitBlockEntry<
  Obj,
  Seq extends Iterable<Obj>,
  Dict extends Map<Obj, Obj?>
>(
  ParserState<Obj, Seq, Dict> state, {
  required int entryIndent,
  required int entryIndentLevel,
  required OnBlockMapEntry<Obj> onExplicitEntry,
}) {
  final ParserState(:iterator) = state;
  var marker = iterator.currentLineInfo.current;

  ParserDelegate<Obj>? key;
  final (:ignoreValueIfKey, blockInfo: keyInfo) = _parseExplicit(
    state,
    indentLevel: entryIndentLevel,
    indent: entryIndent,
    expectedEvent: BlockCollectionEvent.startExplicitKey,
    fallback: (iterator) => throwWithSingleOffset(
      iterator,
      message: 'Expected "?" followed by a whitespace',
      offset: iterator.currentLineInfo.current,
    ),
    onSequenceOrBlockNode: (blockNode) => key = blockNode,
    maybeOnEntry: onExplicitEntry,
  );

  if (key == null) {
    throwWithRangedOffset(
      iterator,
      message: 'Dirty explicit entry state! Key was never set!',
      start: marker,
      end: iterator.currentLineInfo.current,
    );
  } else if (ignoreValueIfKey) {
    onExplicitEntry(key!, null);
    return keyInfo;
  } else if (keyInfo.exitIndent != null) {
    if (keyInfo.exitIndent! > entryIndent) {
      final scanner = state.iterator;
      throwWithRangedOffset(
        scanner,
        message: 'Dangling node found when parsing explicit entry',
        start: key!.endOffset!,
        end: state.iterator.currentLineInfo.current,
      );
    } else if (keyInfo.exitIndent! < entryIndent) {
      onExplicitEntry(key!, null);
      return keyInfo;
    }
  }

  // Parse value
  return _parseExplicit(
    state,
    indentLevel: entryIndentLevel,
    indent: entryIndent,
    expectedEvent: BlockCollectionEvent.startEntryValue,

    // We can fallback to null if we don't find ":".
    fallback: (_) {
      onExplicitEntry(key!, null);
      return keyInfo;
    },
    onSequenceOrBlockNode: (value) => onExplicitEntry(key!, value),
    maybeOnEntry: onExplicitEntry,
  ).blockInfo;
}
