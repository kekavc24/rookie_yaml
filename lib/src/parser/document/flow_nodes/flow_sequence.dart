import 'package:rookie_yaml/src/parser/delegates/parser_delegate.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_map_entry.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_node.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/parser_state.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Parses a flow sequence entry using the current parser [state].
ParserDelegate<Obj> _parseFlowSequenceEntry<
  Obj,
  Seq extends Iterable<Obj>,
  Dict extends Map<Obj, Obj?>
>(
  ParserState<Obj, Seq, Dict> state, {
  required int indentLevel,
  required int minIndent,
  required bool forceInline,
}) {
  final ParserState(:scanner, :comments) = state;
  final peekEvent = inferNextEvent(
    scanner,
    isBlockContext: false,
    lastKeyWasJsonLike: false,
  );

  if (peekEvent == FlowCollectionEvent.startExplicitKey) {
    return parseExplicitAsFlowMap(
          state,
          indentLevel: indentLevel,
          minIndent: minIndent,
          forceInline: forceInline,
        )
        as ParserDelegate<Obj>;
  }

  final keyOrElement = parseFlowNode(
    state,
    currentIndentLevel: indentLevel,
    minIndent: minIndent,
    isImplicit: false,
    forceInline: forceInline,
    collectionDelimiter: flowSequenceEnd,
  );

  // Track if we switched lines
  final lineIndex = scanner.lineInfo().current.lineIndex;

  /// Normally a list is a wildcard. We must assume that we parsed
  /// an implicit key unless we never see ":". Encountering a
  /// linebreak means the current flow node cannot be an implicit key.
  if (!nextSafeLineInFlow(
        scanner,
        minIndent: minIndent,
        forceInline: forceInline,
        onParseComment: comments.add,
      ) ||
      (scanner.lineInfo().current.lineIndex != lineIndex) ||
      keyOrElement.encounteredLineBreak ||
      inferNextEvent(
            scanner,
            isBlockContext: false,
            lastKeyWasJsonLike: keyIsJsonLike(keyOrElement),
          ) !=
          FlowCollectionEvent.startEntryValue) {
    return keyOrElement;
  }

  // TODO: Throw if key has properties

  scanner.skipCharAtCursor();

  // We want this value inline. Override implicit and force inline param.
  final value = parseFlowNode(
    state,
    currentIndentLevel: indentLevel + 1,
    minIndent: minIndent,
    isImplicit: true,
    forceInline: true,
    collectionDelimiter: flowSequenceEnd,
  );

  final map =
      MappingDelegate<Obj, Dict>(
          collectionStyle: NodeStyle.flow,
          indentLevel: indentLevel,
          indent: minIndent,
          start: keyOrElement.start,
          mapResolver: state.mapFunction,
        )
        ..accept(keyOrElement.parsed(), value.parsed())
        ..updateEndOffset = value.endOffset;

  return map as ParserDelegate<Obj>;
}

/// Parses a flow sequence.
///
/// If [forceInline] is `true`, the sequence must be declared on the same line
/// with no line breaks and throws if otherwise.
SequenceDelegate<Obj, Seq>
parseFlowSequence<Obj, Seq extends Iterable<Obj>, Dict extends Map<Obj, Obj?>>(
  ParserState<Obj, Seq, Dict> state, {
  required int indentLevel,
  required int minIndent,
  required bool forceInline,
  NodeKind kind = NodeKind.sequence,
}) {
  final ParserState(:scanner, :comments, :listFunction, :onMapDuplicate) =
      state;

  final sequence = initFlowCollection(
    scanner,
    flowStartIndicator: flowSequenceStart,
    minIndent: minIndent,
    forceInline: forceInline,
    onParseComment: comments.add,
    flowEndIndicator: flowSequenceEnd,
    init: (start) => SequenceDelegate.byKind(
      style: NodeStyle.flow,
      indentLevel: indentLevel,
      indent: minIndent,
      start: start,
      resolver: listFunction,
      kind: kind,
    ),
  );

  do {
    if (scanner.charAtCursor case null || flowEntryEnd || flowSequenceEnd) {
      break;
    }

    final entry = _parseFlowSequenceEntry(
      state,
      indentLevel: indentLevel,
      minIndent: minIndent,
      forceInline: forceInline,
    );

    sequence
      ..accept(entry.parsed())
      ..hasLineBreak = entry.encounteredLineBreak;

    if (!continueToNextEntry(
      scanner,
      minIndent: minIndent,
      forceInline: forceInline,
      onParseComment: comments.add,
    )) {
      break;
    }
  } while (scanner.canChunkMore);

  return terminateFlowCollection(scanner, sequence, flowSequenceEnd);
}
