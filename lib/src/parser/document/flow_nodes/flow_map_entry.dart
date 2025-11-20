import 'package:rookie_yaml/src/parser/delegates/parser_delegate.dart';
import 'package:rookie_yaml/src/parser/document/document_events.dart';
import 'package:rookie_yaml/src/parser/document/flow_nodes/flow_node.dart';
import 'package:rookie_yaml/src/parser/document/node_utils.dart';
import 'package:rookie_yaml/src/parser/document/parser_state.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// A flow map entry.
typedef FlowMapEntry<T> = ParsedEntry<T>;

/// Parses an explicit flow key and its value (if present) and composes a
/// compact flow map.
MappingDelegate<Obj, Dict> parseExplicitAsFlowMap<
  Obj,
  Seq extends Iterable<Obj>,
  Dict extends Map<Obj, Obj?>
>(
  ParserState<Obj, Seq, Dict> state, {
  required int indentLevel,
  required int minIndent,
  required bool forceInline,
}) => _parseExplicitFlow(
  state,
  indentLevel: indentLevel,
  minIndent: minIndent,
  forceInline: forceInline,
  onExplicitKey: (indicatorOffset, key, value) {
    return MappingDelegate(
        collectionStyle: NodeStyle.flow,
        indentLevel: indentLevel,
        indent: minIndent,
        start: indicatorOffset,
        mapResolver: state.mapFunction,
      )
      ..accept(key.parsed(), value?.parsed())
      ..updateEndOffset = value?.endOffset ?? key.endOffset
      ..hasLineBreak =
          key.encounteredLineBreak || (value?.encounteredLineBreak ?? false);
  },
);

/// Parses an explicit flow key and its value (if present) using the current
/// parser [state].
FlowMapEntry<Obj>
parseExplicitEntry<Obj, Seq extends Iterable<Obj>, Dict extends Map<Obj, Obj?>>(
  ParserState<Obj, Seq, Dict> state, {
  required int indentLevel,
  required int minIndent,
  required bool forceInline,
}) => _parseExplicitFlow(
  state,
  indentLevel: indentLevel,
  minIndent: minIndent,
  forceInline: forceInline,
  onExplicitKey: (_, key, value) => (key, value),
);

/// Parses an explicit flow key in arbitrary flow contexts and composes an
/// object [R] using the [onExplicitKey] callback.
R _parseExplicitFlow<
  R,
  Obj,
  Seq extends Iterable<Obj>,
  Dict extends Map<Obj, Obj?>
>(
  ParserState<Obj, Seq, Dict> state, {
  required int indentLevel,
  required int minIndent,
  required bool forceInline,
  required R Function(
    RuneOffset indicatorOffset,
    ParserDelegate<Obj> key,
    ParserDelegate<Obj>? value,
  )
  onExplicitKey,
}) {
  final ParserState(:scanner, :comments) = state;

  final keyStart = scanner.lineInfo().current;

  if (scanner.charAtCursor != mappingKey) {
    throwWithSingleOffset(
      scanner,
      message: 'Expected an explicit key indicator "?"',
      offset: keyStart,
    );
  }

  scanner.skipCharAtCursor();

  final key = parseFlowNode(
    state,
    currentIndentLevel: indentLevel,
    minIndent: minIndent,
    isImplicit: false,
    forceInline: forceInline,
    collectionDelimiter: mappingEnd,
  );

  key.updateEndOffset = scanner.lineInfo().current;

  ParserDelegate<Obj>? value;

  if (inferNextEvent(
        scanner,
        isBlockContext: false,
        lastKeyWasJsonLike: keyIsJsonLike(key),
      ) ==
      FlowCollectionEvent.startEntryValue) {
    scanner.skipCharAtCursor();
    value = parseFlowNode(
      state,
      currentIndentLevel: indentLevel + 1,
      minIndent: minIndent,
      isImplicit: false,
      forceInline: forceInline,
      collectionDelimiter: mappingEnd,
    );
  }

  return onExplicitKey(keyStart, key, value);
}

/// Parses an implicit flow key and its value if present.
FlowMapEntry<Obj>
parseImplicitEntry<Obj, Seq extends Iterable<Obj>, Dict extends Map<Obj, Obj?>>(
  ParserState<Obj, Seq, Dict> state, {
  required int indentLevel,
  required int minIndent,
  required bool forceInline,
}) {
  final ParserState(:scanner, :comments) = state;

  if (scanner.charAtCursor case flowEntryEnd || mappingEnd) {
    throwWithSingleOffset(
      scanner,
      message: 'Expected the start of an implicit flow key but found',
      offset: scanner.lineInfo().current,
    );
  }

  final parsedKey = parseFlowNode(
    state,
    currentIndentLevel: indentLevel,
    minIndent: minIndent,
    isImplicit: true,
    forceInline: forceInline,
    collectionDelimiter: mappingEnd,
  );

  final expectedCharErr =
      'Expected a next flow entry indicator "," or a map value indicator ":" '
      'or a terminating delimiter "}"';

  // Value must be parsed in a safe state
  if (!nextSafeLineInFlow(
    scanner,
    minIndent: minIndent,
    forceInline: forceInline,
    onParseComment: comments.add,
  )) {
    throwWithSingleOffset(
      scanner,
      message: expectedCharErr,
      offset: scanner.lineInfo().current,
    );
  }

  // Move end offset ahead for key
  parsedKey.updateEndOffset = scanner.lineInfo().current;

  if (scanner.charAtCursor case null || flowEntryEnd || mappingEnd) {
    return (parsedKey, null);
  }

  // We must see ":"
  if (inferNextEvent(
        scanner,
        isBlockContext: false,
        lastKeyWasJsonLike: keyIsJsonLike(parsedKey),
      ) !=
      FlowCollectionEvent.startEntryValue) {
    throwWithSingleOffset(
      scanner,
      message: expectedCharErr,
      offset: scanner.lineInfo().current,
    );
  }

  scanner.skipCharAtCursor();

  return (
    parsedKey,
    parseFlowNode(
      state,
      currentIndentLevel: indentLevel + 1,
      minIndent: minIndent,
      isImplicit: false,
      forceInline: forceInline,
      collectionDelimiter: mappingEnd,
    ),
  );
}
