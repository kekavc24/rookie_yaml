import 'dart:collection';

import 'package:dump_yaml/src/dumper/dumper.dart';
import 'package:dump_yaml/src/dumper/inline_flow_dumper.dart';
import 'package:dump_yaml/src/dumper/preamble.dart';
import 'package:dump_yaml/src/event_tree/node.dart';
import 'package:dump_yaml/src/event_tree/visitor.dart';
import 'package:dump_yaml/src/views/dumpable.dart';
import 'package:rookie_yaml/rookie_yaml.dart' hide flowEntryEnd;

/// Dumps a YAML string line-by-line.
///
/// {@category dumpable_view}
/// {@category dump_scalar}
/// {@category dump_list}
/// {@category dump_map}
/// {@category rep_tree}
final class BlockDumper extends Dumper<TreeNode<Object>> with TreeNodeVisitor {
  BlockDumper(this.buffer);

  /// Represents the reusable buffer used for writing the entire document.
  final YamlStringBuffer buffer;

  /// Helper dumper that quickly inlines flow collection that were forced
  /// inline.
  final inlineDumper = InlinedFlowDumper();

  /// Indentation of the nearest collection collection.
  final _collectionIndents = ListQueue<int>();

  @override
  void visitAliasNode(ReferenceNode node) => buffer.write(node.node);

  @override
  void visitContentNode(ContentNode node) {
    final ContentNode(node: lines, :anchor, :localTag, :inheritParentIndent) =
        node;

    buffer.writeContent(
      [
        (lines.firstOrNull ?? '').applyInline(
          tag: localTag,
          anchor: anchor,
        ),
      ].followedBy(lines.skip(1)),

      // Block scalars with a leading space.
      preferredIndent: inheritParentIndent
          ? _collectionIndents.lastOrNull
          : null,
    );
  }

  /// Visits the [elements] of a [ListNode] and dumps them.
  ///
  /// [preamble] and [onEntry] are called before and after every entry
  /// respectively.
  void _visitListNode(
    ListQueue<TreeNode<Object>> elements, {
    required int childIndent,
    required EntryStart preamble,
    required EntryEnd onEntry,
  }) {
    final lastIndex = elements.length - 1;

    void refresh() {
      buffer.indent = childIndent;
    }

    refresh();
    for (final (index, element) in elements.indexed) {
      final TreeNode(:commentStyle, :comments) = element;

      preamble(commentStyle, comments);
      visitTreeNode(element);
      refresh();
      onEntry(index < lastIndex, commentStyle, comments);
    }
  }

  @override
  void visitList(ListNode node) {
    if (exitAfterPreamble(node, buffer, inlineDumper)) return;

    final CollectionNode(node: elements, :nodeStyle, :nodeType) = node;

    final indent = buffer.indent;
    _collectionIndents.addLast(indent);

    if (nodeStyle.isBlock) {
      _visitListNode(
        elements,
        childIndent: indent + 2,
        preamble: (style, comments) =>
            blockEntryStart(buffer, style, indent, '-', comments),
        onEntry: (hasNext, style, comments) =>
            blockEntryEnd(buffer, style, comments, indent, hasNext),
      );
    } else {
      _visitListNode(
        elements,
        childIndent: indent + buffer.step,
        preamble: (style, comments) => flowEntryStart(buffer, style, comments),
        onEntry: (hasNext, style, comments) =>
            flowEntryEnd(buffer, style, comments, hasNext),
      );
    }

    collectionEnd(
      buffer,
      style: nodeStyle,
      nodeType: nodeType,
      collectionIndent: indent,
    );

    _collectionIndents.removeLast();
  }

  /// Visits an explicit [key] and [value].
  void _visitExplicitEntry(
    TreeNode<Object> key,
    TreeNode<Object> value, {
    required int entryIndent,
    required bool hasNextEntry,
    required NodeStyle mapStyle,
  }) {
    final dumpingIndent = entryIndent + 2;
    buffer.indent = dumpingIndent;

    // Simulate a block-like dumping strategy for the explicit key. While this
    // may seem unorthodox for the flow key, it's being dumped as an explicit
    // key with a block-like syntax.
    blockEntryStart(buffer, key.commentStyle, entryIndent, '?', key.comments);
    visitTreeNode(key);

    // Refresh indent! We don't care who was visited. Not worth it.
    buffer.indent = dumpingIndent;

    // Force true. We still have our value and we want to continue writing to
    // the buffer without additional checks!
    blockEntryEnd(buffer, key.commentStyle, key.comments, entryIndent, true);

    final TreeNode(:commentStyle, :comments) = value;

    // Same as key
    blockEntryStart(buffer, commentStyle, entryIndent, ':', comments);
    visitTreeNode(value);

    // The termination of the map is now style-dependent but revert to the
    // entry indent.
    buffer.indent = entryIndent;

    if (mapStyle.isBlock) {
      blockEntryEnd(buffer, commentStyle, comments, entryIndent, hasNextEntry);
      return;
    }

    flowEntryEnd(buffer, commentStyle, comments, hasNextEntry);
  }

  /// Visits an implicit [key] and its [value].
  void _visitImplicitEntry(
    TreeNode<Object> key,
    TreeNode<Object> value, {
    required int entryIndent,
    required bool hasNextEntry,
    required NodeStyle mapStyle,
  }) {
    buffer.indent = entryIndent;

    // Implicit keys are always inline. Ergo, such a key can only have block
    // comments. No indicators too.
    blockEntryStart(buffer, .block, entryIndent, '', key.comments);
    visitTreeNode(key);

    // Aliases allow ":".
    buffer.write('${key is ReferenceNode ? ' ' : ''}:');

    final valueIndent = entryIndent + buffer.step;
    buffer.indent = valueIndent;

    final TreeNode(:comments, :commentStyle) = value;

    // Block comments must start on the next line. Also, block collections
    // must always start on a new line if the key is implicit.
    if ((comments.isNotEmpty && commentStyle.isPreamble) ||
        (mapStyle.isBlock && value.isBlockCollection())) {
      buffer
        ..moveToNextLine()
        ..writeSpaceOrIndent();

      // Wildcard innit :)
      blockEntryStart(
        buffer,
        commentStyle.isPreamble ? .block : commentStyle,
        valueIndent,
        '',
        comments,
      );
    } else {
      buffer.writeSpaceOrIndent(1);
    }

    visitTreeNode(value);

    // The termination of the map is now style-dependent but revert to the
    // entry indent.
    buffer.indent = entryIndent;

    if (mapStyle.isBlock) {
      blockEntryEnd(buffer, commentStyle, comments, entryIndent, hasNextEntry);
      return;
    }

    flowEntryEnd(buffer, commentStyle, comments, hasNextEntry);
  }

  @override
  void visitMap(MapNode node) {
    if (exitAfterPreamble(node, buffer, inlineDumper)) return;

    final CollectionNode(node: elements, :nodeStyle, :nodeType) = node;

    final indent = buffer.indent;
    _collectionIndents.addLast(indent);

    final lastIndex = elements.length - 1;

    // Flow maps move one indentation level deeper.
    final entryIndent = nodeStyle.isBlock ? indent : indent + buffer.step;

    for (final (index, (key, value)) in elements.indexed) {
      final hasNextEntry = index < lastIndex;

      if (key.isExplicitKey()) {
        _visitExplicitEntry(
          key,
          value,
          entryIndent: entryIndent,
          hasNextEntry: hasNextEntry,
          mapStyle: nodeStyle,
        );
      } else {
        _visitImplicitEntry(
          key,
          value,
          entryIndent: entryIndent,
          hasNextEntry: hasNextEntry,
          mapStyle: nodeStyle,
        );
      }
    }

    collectionEnd(
      buffer,
      style: nodeStyle,
      nodeType: nodeType,
      collectionIndent: indent,
    );

    _collectionIndents.removeLast();
  }

  @override
  String dumped() => buffer.toString();

  @override
  void dump(TreeNode<Object> node) {
    reset();
    visitTreeNode(node);
  }

  @override
  void reset() {
    inlineDumper.reset();
    _collectionIndents.clear();
  }
}
