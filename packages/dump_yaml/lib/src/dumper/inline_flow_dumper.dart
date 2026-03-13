import 'dart:collection';

import 'package:dump_yaml/src/dumper/dumper.dart';
import 'package:dump_yaml/src/event_tree/node.dart';
import 'package:dump_yaml/src/event_tree/visitor.dart';

/// Dumps an inlined flow [CollectionNode].
final class InlinedFlowDumper extends Dumper<TreeNode<Object>>
    with TreeNodeVisitor {
  /// A flag for map keys/values since YAML has a set of rules for map keys.
  /// The arbitary length for such nodes cannot be determined at constant time
  /// until its entire content is buffered.
  var _disjoint = false;

  /// Stack for maintaining the state of disjointed keys and values.
  final _dumped = ListQueue<String>();

  /// Buffer for the content.
  final _buffer = StringBuffer();

  /// Pushes the node's [content] into the buffer after applying its [anchor]
  /// and [localTag] inline.
  ///
  /// Performs any housekeeping if the previous node marked the current node
  /// as [_disjoint].
  void _push(String content, [String? anchor, String? localTag]) {
    if (_disjoint) {
      _dumped.add(_buffer.toString());
      _buffer.clear();
      _disjoint = false;
    }

    _buffer.write(content.applyInline(tag: localTag, anchor: anchor));
  }

  /// Pops any content buffered after marking the next node as [_disjoint].
  String _pop() {
    final buffered = _buffer.toString();

    _buffer
      ..clear()
      ..write(_dumped.removeLast());

    return buffered;
  }

  /// Flushes the buffer after the entire node has been dumped.
  void _flush() {
    // Flow nodes have delimiters.
    if (_dumped.isNotEmpty) return;
    _dumped.addLast(_buffer.toString());
    _buffer.clear();
  }

  @override
  void visitAliasNode(ReferenceNode node) => _push(node.node);

  @override
  void visitContentNode(ContentNode node) =>
      _push(node.node.join(), node.anchor, node.localTag);

  @override
  void visitList(ListNode node) => _visitFlowCollection(
    node,
    delimiters: ('[', ']'),
    onIteration: visitTreeNode,
  );

  @override
  void visitMap(MapNode node) => _visitFlowCollection(
    node,
    delimiters: ('{', '}'),
    onIteration: (node) {
      final (key, value) = node;

      // We want to capture keys longer than 1024 and make them explicit.
      _disjoint = true;
      visitTreeNode(key);
      var dumpedKey = _pop();

      _disjoint = true; // Capture empty values.
      visitTreeNode(value);
      final dumpedValue = _pop();
      _disjoint = false;

      // We also allow users to preserve empty values in plain scalars. In this
      // case, give a cue to whichever parser they use to guarantee efficiency.
      if (dumpedKey.isEmpty || dumpedKey.length > 1024) {
        dumpedKey = '? $dumpedKey';
      } else if (dumpedKey.startsWith('*')) {
        // Alias accepts ":" in YAML 1.2+
        dumpedKey = '$dumpedKey ';
      }

      // Flow maps are very nifty. They can have keys without the ":". An empty
      // plain value is treated as null.
      if (dumpedValue.isEmpty) {
        _buffer.write(dumpedKey.trim());
        return;
      }

      _buffer
        ..write(dumpedKey)
        ..write(': $dumpedValue');
    },
  );

  /// Visits an inlined flow [collection] and iterates it content.
  void _visitFlowCollection<T>(
    CollectionNode<T> collection, {
    required (String opening, String closing) delimiters,
    required void Function(T node) onIteration,
  }) {
    final (opening, closing) = delimiters;

    _push(opening, collection.anchor, collection.localTag);
    final values = collection.node;

    if (values.isEmpty) {
      _buffer.write(closing);
      return;
    }

    var lastIndex = values.length - 1;
    void nextEntry(int index) {
      if (index >= lastIndex) return;
      _buffer.write(', ');
    }

    for (final (index, value) in values.indexed) {
      onIteration(value);
      nextEntry(index);
    }

    _buffer.write(closing);
  }

  @override
  String dumped() {
    _flush();
    return _dumped.first;
  }

  @override
  void dump(TreeNode<Object> node) {
    reset();
    visitTreeNode(node);
  }

  @override
  void reset() {
    _disjoint = false;
    _buffer.clear();
    _dumped.clear();
  }
}
