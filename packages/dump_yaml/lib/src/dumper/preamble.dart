import 'package:dump_yaml/src/dumper/dumper.dart';
import 'package:dump_yaml/src/dumper/inline_flow_dumper.dart';
import 'package:dump_yaml/src/event_tree/node.dart';
import 'package:dump_yaml/src/views/dumpable.dart';
import 'package:rookie_yaml/rookie_yaml.dart';

/// Called before a block sequence entry is dumped.
typedef EntryStart =
    void Function(CommentStyle style, Iterable<String> comments);

/// Called after a block sequence has been dumped.
typedef EntryEnd =
    void Function(bool hasNext, CommentStyle style, Iterable<String> comments);

extension on String? {
  /// Converts `this` to an anchor.
  String? asAnchor() => this == null ? null : '&$this';
}

/// Attempts to write a collection's preamble information and returns `false`
/// if the preamble attempt was successful.
bool exitAfterPreamble<T>(
  CollectionNode<T> node,
  YamlStringBuffer buffer,
  InlinedFlowDumper dumper,
) {
  if (!node.forcedInline) return _writePreamble(buffer, node);

  dumper.dump(node);
  buffer.write(dumper.dumped());
  dumper.reset();
  return true;
}

/// Writes the collection [node]'s properties and returns whether to exit.
bool _writePreamble<T>(YamlStringBuffer buffer, CollectionNode<T> collection) {
  final props = [
    ?collection.anchor?.asAnchor(),
    ?collection.localTag,
  ].join(' ');

  if (collection.node.isEmpty) {
    buffer.write(
      '${props.isNotEmpty ? '$props ' : ''}'
      '${collection.nodeType == NodeType.map ? '{}' : '[]'}',
    );

    return true;
  }

  collection.nodeStyle.isBlock
      ? _blockPreamble(buffer, props)
      : _flowPreamble(buffer, props, collection.nodeType);

  return false;
}

/// Writes the flow collection's properties to the [buffer].
void _flowPreamble(YamlStringBuffer buffer, String props, NodeType nodeType) {
  if (props.isNotEmpty) {
    buffer.write('$props ');
  }

  // ```yaml
  //
  // &flow-map !hello {
  // # <- cursor is now before the comment
  //
  //    key: value
  //
  // }
  //--- # Next doc
  //
  // &flow-sequence !world [
  // # <- cursor is now before the comment
  //
  //   entry,
  //   next
  // ]
  //```
  buffer
    ..write(nodeType == NodeType.map ? '{' : '[')
    ..moveToNextLine()
    ..writeSpaceOrIndent(buffer.indent + buffer.step); // Indent of child
}

/// Writes the block collection's properties if present.
void _blockPreamble(YamlStringBuffer buffer, String props) {
  // Block collections have no indicators and its indent is same as the indent
  // of the first node.
  if (props.isEmpty) return;

  // ```yaml
  //
  // &map !hello
  // # <- cursor is now before the comment
  // key: value
  //
  //--- # Next doc
  //
  // &sequence !world
  // # <- cursor is now before the comment
  // - entry
  // - next
  //```
  buffer
    ..write(props)
    ..moveToNextLine()
    ..writeSpaceOrIndent();
}

/// Terminates a [ListNode] or [MapNode] after it has been dumped.
void collectionEnd(
  YamlStringBuffer buffer, {
  required NodeStyle style,
  required NodeType nodeType,
  required int collectionIndent,
}) {
  buffer.indent = collectionIndent;

  // The collection must end with a line feed. Block collections cannot have
  // trailing indicators or comments. Flow collections need to write their
  // closing delimiters on a new line.
  if (!buffer.lastWasLineEnding) buffer.moveToNextLine();
  if (style.isBlock) return;

  buffer
    ..writeSpaceOrIndent()
    ..write(nodeType == NodeType.map ? '}' : ']');
}

/// Writes the [comments] provided to the [buffer].
void _writeComments(
  YamlStringBuffer buffer,
  Iterable<String> comments, [
  int? indent,
  bool writeIndent = true,
]) {
  if (comments.isEmpty) return;
  buffer.writeComments(comments, indent);
  if (writeIndent) buffer.writeSpaceOrIndent(indent);
}

/// Writes the [comments] of a flow entry/key to the [buffer].
void flowEntryStart(
  YamlStringBuffer buffer,
  CommentStyle style,
  Iterable<String> comments,
) {
  if (!style.isPreamble) return;
  _writeComments(buffer, comments);
}

/// Writes the [comments] of a block entry based on its comments [style].
///
/// [charIfPossessive] is used to dump the [comments] when the [style] is
/// [CommentStyle.possessive].
void blockEntryStart(
  YamlStringBuffer buffer,
  CommentStyle style,
  int parentIndent,
  String charIfPossessive,
  Iterable<String> comments,
) {
  if (style == CommentStyle.block) {
    // On the same indentation level as parent.
    if (style.isPreamble) _writeComments(buffer, comments, parentIndent);

    if (charIfPossessive.isNotEmpty) {
      buffer
        ..write(charIfPossessive)
        ..writeSpaceOrIndent(1);
    }

    return;
  }

  // Applies to most block indicators. This applies to "?" and ":"(when used as
  // explicit keys and values.
  //
  // ```yaml
  // - # comment
  //   # comment
  //   node
  // ```
  buffer
    ..write(charIfPossessive)
    ..writeSpaceOrIndent(1);

  // Use the entry indent
  if (style.isPreamble) _writeComments(buffer, comments);
}

/// Writes the trailing [comments] of a node to the [buffer].
void _trailingComments(
  YamlStringBuffer buffer,
  CommentStyle style,
  Iterable<String> comments,
) {
  if (style.isPreamble || comments.isEmpty) return;
  buffer.writeSpaceOrIndent(1);
  _writeComments(buffer, comments, buffer.distanceFromMargin, false);
}

/// Terminates a flow entry from a [ListNode] or the value from a [MappingEntry]
/// in a [MapNode].
void flowEntryEnd(
  YamlStringBuffer buffer,
  CommentStyle style,
  Iterable<String> comments,
  bool hasNext,
) {
  _trailingComments(buffer, style, comments);

  if (hasNext) {
    // Flow entry had trailing comments. Plain style cannot have trailing
    // line breaks.
    if (buffer.lastWasLineEnding) buffer.writeSpaceOrIndent();

    // Never place the comma on the same line as the next value even with
    // comments.
    //
    // [
    //   some value # comment
    //   ,
    //   next value
    // ]
    buffer
      ..write(',')
      ..moveToNextLine()
      ..writeSpaceOrIndent();

    return;
  }

  // The flow collection ends after this value/entry
  if (buffer.lastWasLineEnding) return;
  buffer.moveToNextLine();
}

/// Terminates a block node/entry.
void blockEntryEnd(
  YamlStringBuffer buffer,
  CommentStyle style,
  Iterable<String> comments,
  int parentIndent,
  bool hasNext,
) {
  /*
   * Block nodes must always be left in a "forward-writing" state with no
   * backpedalling whatsoever. Block nodes have no indicators and this makes
   * any dangling/omitted line breaks a problem.
  */
  _trailingComments(buffer, style, comments);
  if (!buffer.lastWasLineEnding) buffer.moveToNextLine();
  if (hasNext) buffer.writeSpaceOrIndent(parentIndent);
}
