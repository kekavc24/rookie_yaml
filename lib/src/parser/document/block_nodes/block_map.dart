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
BlockNode<Obj> composeBlockMapFromScalar<Obj>(
  ParserState<Obj> state, {
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
        inferBlockEvent(iterator) != BlockCollectionEvent.startEntryValue) {
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
BlockNode<Obj> composeAndParseBlockMap<Obj>(
  ParserState<Obj> state, {
  required ParserDelegate<Obj> key,
  required ParsedProperty? mapProperty,
  required int fixedMapIndent,
}) {
  final iterator = state.iterator;
  final ParserDelegate(:indent, :start) = key;

  final map = MappingDelegate(
    collectionStyle: NodeStyle.block,
    indentLevel: key.indentLevel,
    indent: fixedMapIndent,
    start: start,
    mapResolver: state.mapFunction,
  );

  final blockInfo = parseImplicitValue(
    state,
    keyIndent: fixedMapIndent,
    keyIndentLevel: key.indentLevel,
    onValue: (implicitValue) {
      map
        ..accept(key.parsed(), implicitValue.parsed())
        ..updateEndOffset = implicitValue.endOffset;
    },
    onEntryValue: (key, value) {
      if (!map.accept(key.parsed(), value?.parsed())) {
        state.onMapDuplicate(
          key.start,
          value?.endOffset ?? iterator.currentLineInfo.current,
          'A block map cannot contain duplicate entries by the same key',
        );
      }

      map
        ..hasLineBreak = true
        ..updateEndOffset = value?.endOffset ?? key.endOffset!;
    },
  );

  final valueExitIndent = blockInfo.exitIndent;

  // Exit if we can't parse more entries.
  if (iterator.isEOF ||
      blockInfo.docMarker.stopIfParsingDoc ||
      valueExitIndent == null ||
      valueExitIndent < fixedMapIndent) {
    return (
      blockInfo: blockInfo,
      node: state.trackAnchor(map, mapProperty) as ParserDelegate<Obj>,
    );
  } else if (valueExitIndent > fixedMapIndent) {
    throwWithRangedOffset(
      iterator,
      message: "Dangling indent does not belong to the current block map",
      start: map.endOffset ?? iterator.currentLineInfo.current,
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
BlockNode<Obj> parseBlockMap<Obj>(
  MapLikeDelegate<Obj, Obj> map, {
  required ParserState<Obj> state,
}) {
  final ParserState(:iterator, :onMapDuplicate) = state;
  final MapLikeDelegate(indent: mapIndent, :indentLevel) = map;

  void onParseEntry(ParserDelegate<Obj> key, ParserDelegate<Obj>? value) {
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
  }

  while (!iterator.isEOF) {
    final blockInfo = switch (inferBlockEvent(iterator)) {
      BlockCollectionEvent.startExplicitKey => parseExplicitBlockEntry(
        state,
        entryIndent: mapIndent,
        entryIndentLevel: indentLevel,
        onExplicitEntry: onParseEntry,
      ),
      _ => parseImplicitBlockEntry(
        state,
        keyIndent: mapIndent,
        keyIndentLevel: indentLevel,
        onImplicitEntry: onParseEntry,
      ),
    };

    final (:docMarker, :exitIndent) = blockInfo;

    if (iterator.isEOF ||
        docMarker.stopIfParsingDoc ||
        exitIndent == null ||
        exitIndent < mapIndent) {
      return (blockInfo: blockInfo, node: map as ParserDelegate<Obj>);
    } else if (exitIndent > mapIndent) {
      throwForCurrentLine(
        iterator,
        message: 'Dangling block node found when parsing block map',
      );
    }
  }

  return (blockInfo: emptyScanner, node: map as ParserDelegate<Obj>);
}
