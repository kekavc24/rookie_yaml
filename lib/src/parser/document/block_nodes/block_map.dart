import 'package:rookie_yaml/src/parser/delegates/parser_delegate.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/explicit_block_entry.dart';
import 'package:rookie_yaml/src/parser/document/block_nodes/implicit_block_entry.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/parser_state.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Attempts to compose and parse a block map using the [keyOrNode] as the
/// first implicit key. [keyOrNode] is not restricted to a [Scalar] but may
/// also represent any flow collection that is implicit.
///
/// If a block map cannot be parsed then the [keyOrNode] is returned. A block
/// map is never parsed if:
///   - [composeImplicitMap] is `false`.
///   - [keyOrNode] spans multiple lines.
///   - [keyOrNode] is a block style node. Block scalars cannot be implicit
///     keys.
///   - [documentMarker] is [DocumentMarker.directiveEnd] or
///     [DocumentMarker.documentEnd] which both signify the end of the current
///     document.
BlockNode<Obj> composeBlockMapFromScalar<
  Obj,
  Seq extends Iterable<Obj>,
  Dict extends Map<Obj, Obj?>
>(
  ParserState<Obj, Seq, Dict> state, {
  required ParserDelegate<Obj> keyOrNode,
  required ParsedProperty? keyOrMapProperty,
  required int? indentOnExit,
  required DocumentMarker documentMarker,
  required bool keyIsBlock,
  required bool composeImplicitMap,
  required int composedMapIndent,
}) {
  final ParserState(:iterator, :comments) = state;

  if (!composeImplicitMap ||
      documentMarker.stopIfParsingDoc ||
      iterator.isEOF ||
      keyIsBlock ||
      keyOrNode.encounteredLineBreak) {
    state.trackAnchor(keyOrNode, keyOrMapProperty);

    return (
      blockInfo: (docMarker: documentMarker, exitIndent: indentOnExit),
      node: keyOrNode,
    );
  }

  if (iterator.current != mappingValue) {
    final indentOrSeparation = skipToParsableChar(
      iterator,
      onParseComment: comments.add,
    );

    // Indent must be null. This must be an inlined key
    if (iterator.isEOF ||
        indentOrSeparation != null ||
        inferNextEvent(
              iterator,
              isBlockContext: true,
              lastKeyWasJsonLike: false,
            ) !=
            BlockCollectionEvent.startEntryValue) {
      state.trackAnchor(keyOrNode, keyOrMapProperty);
      return (
        blockInfo: (exitIndent: indentOrSeparation, docMarker: documentMarker),
        node: keyOrNode,
      );
    }
  }

  final (keyProp, mapProp) = (keyOrMapProperty?.isMultiline ?? false)
      ? (null, keyOrMapProperty)
      : (keyOrMapProperty, null);

  return composeAndParseBlockMap(
    state,
    key: state.trackAnchor(
      keyOrNode..updateEndOffset = iterator.currentLineInfo.current,
      keyProp,
    ),
    mapProperty: mapProp,
    fixedMapIndent: composedMapIndent,
  );
}

/// Parses the value of the provided [key] and uses the first entry to create a
/// [MappingDelegate] representing the block map with an indent of
/// [fixedMapIndent].
///
/// [parseBlockMap] is only called if more entries can be parsed after the
/// first [key]'s value has been parsed.
BlockNode<Obj> composeAndParseBlockMap<
  Obj,
  Seq extends Iterable<Obj>,
  Dict extends Map<Obj, Obj?>
>(
  ParserState<Obj, Seq, Dict> state, {
  required ParserDelegate<Obj> key,
  required ParsedProperty? mapProperty,
  required int fixedMapIndent,
}) {
  final ParserDelegate(:indent, :start) = key;

  final map = MappingDelegate(
    collectionStyle: NodeStyle.block,
    indentLevel: key.indentLevel,
    indent: fixedMapIndent,
    start: start,
    mapResolver: state.mapFunction,
  );

  // Key move one level deeper than the map
  key.indentLevel += 1;

  final (:node, :blockInfo) = parseImplicitValue(
    state,
    keyIndent: fixedMapIndent,
    keyIndentLevel: key.indentLevel,
  );

  map
    ..accept(key.parsed(), node.parsed())
    ..hasLineBreak = key.encounteredLineBreak || node.encounteredLineBreak;

  final valueExitIndent = blockInfo.exitIndent;

  final iterator = state.iterator;

  // Exit if we can't parse more entries.
  if (iterator.isEOF ||
      blockInfo.docMarker.stopIfParsingDoc ||
      valueExitIndent == null ||
      valueExitIndent < fixedMapIndent) {
    return (
      blockInfo: blockInfo,
      node:
          state.trackAnchor(map..updateEndOffset = node.endOffset, mapProperty)
              as ParserDelegate<Obj>,
    );
  } else if (valueExitIndent > fixedMapIndent) {
    throwWithRangedOffset(
      iterator,
      message: "Dangling indent does not belong to the current block map",
      start: node.endOffset!,
      end: iterator.currentLineInfo.current,
    );
  }

  final (node: _, blockInfo: mapInfo) = parseBlockMap(map, state: state);

  // Intentional. Track anchor only after the whole map is parsed.
  return (
    node: state.trackAnchor(map, mapProperty) as ParserDelegate<Obj>,
    blockInfo: mapInfo,
  );
}

/// Parses the entries of a block [map].
BlockNode<Obj>
parseBlockMap<Obj, Seq extends Iterable<Obj>, Dict extends Map<Obj, Obj?>>(
  MappingDelegate<Obj, Dict> map, {
  required ParserState<Obj, Seq, Dict> state,
}) {
  final ParserState(:iterator, :onMapDuplicate) = state;
  final MappingDelegate(indent: mapIndent, :indentLevel) = map;

  final entryIndentLevel = indentLevel + 1;

  while (!iterator.isEOF) {
    final (:blockInfo, node: (key, value)) = switch (inferNextEvent(
      iterator,
      isBlockContext: true,
      lastKeyWasJsonLike: false,
    )) {
      BlockCollectionEvent.startExplicitKey => parseExplicitBlockEntry(
        state,
        entryIndent: mapIndent,
        entryIndentLevel: entryIndentLevel,
      ),
      _ => parseImplicitBlockEntry(
        state,
        keyIndent: mapIndent,
        keyIndentLevel: entryIndentLevel,
      ),
    };

    // Only implicit keys can return null when the document ends.
    if (key != null) {
      if (!map.accept(key.parsed(), value?.parsed())) {
        onMapDuplicate(
          key.start,
          value?.endOffset ?? iterator.currentLineInfo.current,
          'A block map cannot contain duplicate entries by the same key',
        );
      }

      map
        ..hasLineBreak =
            key.encounteredLineBreak || (value?.encounteredLineBreak ?? false)
        ..updateEndOffset = value?.endOffset ?? key.endOffset!;
    } else {
      // Use start of the current line if document is ending
      map.updateEndOffset = iterator.currentLineInfo.start;
    }

    final (:docMarker, :exitIndent) = blockInfo;

    if (iterator.isEOF ||
        docMarker.stopIfParsingDoc ||
        exitIndent == null ||
        exitIndent < mapIndent) {
      return (blockInfo: blockInfo, node: map as ParserDelegate<Obj>);
    } else if (exitIndent > mapIndent) {
      throwWithRangedOffset(
        iterator,
        message: 'Dangling block node found when parsing block map',
        start: value?.endOffset ?? key!.endOffset!,
        end: iterator.currentLineInfo.current,
      );
    }
  }

  return (blockInfo: emptyScanner, node: map as ParserDelegate<Obj>);
}
