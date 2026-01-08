import 'package:rookie_yaml/src/dumping/dumpable_node.dart';
import 'package:rookie_yaml/src/dumping/dumper_utils.dart';
import 'package:rookie_yaml/src/dumping/scalar.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Information about a dumped [Iterable].
typedef DumpedSequence = ({bool preferExplicit, String node});

/// An input for an [IterableDumper].
typedef IterableEntry = (
  Object? entry,
  String Function(Object? object)? dumper,
);

/// Callback for inserting a nested [Iterable] into a previous evicted parent
/// [Iterable] after it has been completely dumped.
typedef _OnNestedDone =
    (bool hasTrailing, String node) Function(String content);

/// Information about an [Iterable] that was evicted to allow a nested
/// [Iterable] to be parsed.
typedef _IterableState = ({
  bool isRoot,
  bool preferExplicit,
  bool lastHadTrailingComments,
  int currentIndent,
  Iterator<IterableEntry> iterator,
  String state,
  _OnNestedDone onIterableDone,
});

/// A dumper for an [Iterable].
sealed class IterableDumper {
  IterableDumper({
    required this.commentDumper,
    required this.scalarDumper,
    required this.globals,
  });

  /// Comment style
  final CommentDumper commentDumper;

  /// Dumper for scalars
  final ScalarDumper scalarDumper;

  /// Tracks the object and its properties.
  final PushProperties globals;

  /// Tracks evicted [Iterable]s while another nested [Iterable] is being
  /// parsed.
  final _states = <_IterableState>[];

  /// Stores the state of the [Iterable] being dumped.
  final _dumpedIterable = StringBuffer();

  /// Iterator of the [Iterable] being dumped.
  Iterator<IterableEntry>? _current;

  /// Whether this iterable should be dumped as an explicit key if it's
  /// parent is a map. This is also indicates if the list is multiline.
  var _isExplicit = false;

  /// Whether this is the root iterable.
  var _isRoot = true;

  /// Indent for the list. Will never be negative when the iterable is being
  /// parsed.
  var _indent = -1;

  /// Whether the last entry has trailing comments.
  ///
  /// This has no meaning in block sequences since block sequence entries are
  /// always dumped on a new line with a `-` before.
  var _lastHadTrailing = false;

  /// Resets the internal state of the dumper.
  void _reset({
    Iterator<IterableEntry>? iterator,
    int indent = -1,
    bool isRoot = true,
    bool isExplicit = false,
    bool lastHadTrailing = false,
  }) {
    _isRoot = isRoot;
    _isExplicit = isExplicit;
    _indent = indent;
    _lastHadTrailing = lastHadTrailing;
    _current = iterator;
    _dumpedIterable.clear();
  }

  /// Stashes the current iterator.
  ///
  /// If [pop] is `true`, a previously stashed iterator is removed. May throw
  /// an error if no [_states] were previously stashed or stored.
  void _stashIterator({bool pop = false}) {
    if (pop) {
      final stashed = _states.removeLast();
      _isRoot = stashed.isRoot;
      _isExplicit = stashed.preferExplicit;
      _indent = stashed.currentIndent;
      _current = stashed.iterator;

      _dumpedIterable.write(stashed.state);
      return;
    }

    _states.add((
      isRoot: _isRoot,
      preferExplicit: _isExplicit,
      currentIndent: _indent,
      lastHadTrailingComments: _lastHadTrailing,
      iterator: _current!,
      state: _dumpedIterable.toString(),
      onIterableDone: (_) => (false, ''),
    ));

    _reset();
  }

  /// Stashes the current parent and set its [child] (a nested [Iterable]) as
  /// the current [Iterable] being dumped.
  void _evictParent(
    Iterable<Object?> child, {
    required int childIndent,
    required _OnNestedDone onIterableDone,
    bool alwayExplicit = false,
  }) {
    _states.add((
      isRoot: _isRoot,
      preferExplicit: _isExplicit,
      lastHadTrailingComments: _lastHadTrailing,
      onIterableDone: onIterableDone,
      state: _dumpedIterable.toString(),
      currentIndent: _indent,
      iterator: _current!,
    ));

    _reset(
      iterator: child.map((e) => (e, null)).iterator,
      indent: childIndent,
      isRoot: false,
      isExplicit: alwayExplicit,
    );
  }

  /// Checks whether the current [entry] can be dumped.
  (bool canDump, Object? entry) _canDump(IterableEntry entry) {
    final (object, dumper) = entry;
    if (dumper != null) {
      _writeEntry(dumper(object));
      return (false, null);
    }

    return (true, object);
  }

  /// Writes the [entry] to the [_dumpedIterable] buffer tracking dumped
  /// entries.
  void _writeEntry(
    String entry, {
    String? indentation,
    bool hasTrailingComments = false,
  });

  /// Dumps an [Iterable] whose [_current] iterator is set. Nothing happens if
  /// it's `null`.
  void _dumpCurrent();

  /// Applies the [tag] and [anchor] to the root [Iterable] dumped as the
  /// provided [node].
  String _iterableProperties(String? tag, String? anchor, String node);

  /// Dumps an [iterable] with the provided [indent].
  DumpedSequence dump(
    ConcreteNode<Iterable<IterableEntry>> iterable,
    int indent,
  ) {
    final ConcreteNode(:dumpable, :tag, :anchor) = iterable;
    _reset(iterator: dumpable.iterator, indent: indent);

    do {
      if (_current != null) {
        _dumpCurrent();
        continue;
      } else if (_isRoot) {
        break;
      }

      final parent = _states.removeLast();
      final nested = _dumpedIterable.toString();

      _reset(
        iterator: parent.iterator,
        indent: parent.currentIndent,
        isRoot: parent.isRoot,
        isExplicit: parent.preferExplicit,
        lastHadTrailing: parent.lastHadTrailingComments,
      );

      _dumpedIterable.write(parent.state);
      final (hasTrailing, obj) = parent.onIterableDone(nested);
      _writeEntry(obj, hasTrailingComments: hasTrailing, indentation: null);
    } while (true);

    final dumpedIterable = (
      preferExplicit: _isExplicit,
      node: _iterableProperties(
        globals(tag, anchor, iterable),
        anchor,
        _dumpedIterable.toString(),
      ),
    );

    _reset();
    return dumpedIterable;
  }

  /// Dumps a custom [object] as an [Iterable].
  ///
  /// The [tag] and [anchor] are included with the [object] after the [expand]
  /// has been called.
  DumpedSequence dumpObject<T>(
    T object, {
    required Iterable<IterableEntry> Function(T object) expand,
    required int indent,
    ResolvedTag? tag,
    String? anchor,
  }) => dump(
    dumpableType(expand(object))
      ..tag = tag
      ..anchor = anchor,
    indent,
  );
}

/// Dumps an [Iterable] as [NodeStyle.block].
final class BlockSequenceDumper extends IterableDumper with PropertyDumper {
  BlockSequenceDumper({
    required super.commentDumper,
    required super.scalarDumper,
    required super.globals,
  });

  @override
  String _iterableProperties(String? tag, String? anchor, String node) =>
      applyBlock(tag, anchor, _indent, node);

  @override
  void _writeEntry(
    String entry, {
    String? indentation,
    bool hasTrailingComments = false,
  }) {
    // First entry never indented.
    if (_dumpedIterable.isNotEmpty) {
      _dumpedIterable.write(indentation ?? ' ' * _indent);
    }

    _dumpedIterable
      ..write('- ')
      ..write(entry)
      ..write(entry.endsWith('\n') ? '' : '\n');
  }

  @override
  void _dumpCurrent() {
    assert(_current != null, 'Invalid dumping state');
    final entryIndent = _indent + 1;
    final indentation = ' ' * _indent;

    while (_current!.moveNext()) {
      final (canDump, object) = _canDump(_current!.current);
      if (!canDump) continue;

      final dumpable = dumpableObject(object);

      switch (dumpable.dumpable) {
        case Map<Object?, Object?> map:
          _stashIterator();
          _writeEntry('{}');
          _stashIterator(pop: true);

        // Iterable. Nested objects must define their own dumping functions
        // which is called before reaching here.
        case Iterable<Object?> iterable:
          {
            final iterableIndent = entryIndent + 1;

            _evictParent(
              iterable,
              childIndent: iterableIndent,
              onIterableDone: (entry) => (
                false,
                _onIterableDone(
                  entry,
                  iterableIndent,
                  dumpable as ConcreteNode<Object?>,
                ),
              ),
              alwayExplicit: true,
            );

            return;
          }

        // Scalar
        default:
          {
            final forceBlock =
                scalarDumper.defaultStyle.nodeStyle == NodeStyle.block;

            final (isMultiline: _, :tentativeOffsetFromMargin, :node) =
                scalarDumper.dump(dumpable, indent: entryIndent, style: null);

            _writeEntry(
              commentDumper.applyComments(
                node,
                comments: dumpable.comments,
                forceBlock: forceBlock,
                indent: entryIndent + 1,
                offsetFromMargin: tentativeOffsetFromMargin,
              ),
              indentation: indentation,
            );
          }
      }
    }

    if (_dumpedIterable.isEmpty) {
      _isExplicit = false;
      _dumpedIterable.write('[]\n');
    }

    _current = null;
  }

  /// Applies the comments present in the [dumpable] wrapper to its dumped
  /// [iterable].
  String _onIterableDone(
    String iterable,
    int indent,
    ConcreteNode<Object?> dumpable,
  ) {
    final anchor = dumpable.anchor;
    final localTag = globals(dumpable.tag, anchor, dumpable);

    return commentDumper.applyComments(
      iterable.startsWith('[')
          ? applyInline(localTag, anchor, iterable)
          : applyBlock(localTag, anchor, indent, iterable),
      comments: dumpable.comments,
      forceBlock: true,
      indent: indent,
      offsetFromMargin: -1, // No effect
    );
  }
}

/// Dumps an [Iterable] as [NodeStyle.flow].
final class FlowSequenceDumper extends IterableDumper with PropertyDumper {
  FlowSequenceDumper({
    required this.preferInline,
    required super.commentDumper,
    required super.scalarDumper,
    required super.globals,
  }) {
    _isExplicit = !preferInline;
  }

  /// Whether the [Iterable] should be inlined.
  final bool preferInline;

  @override
  String _iterableProperties(String? tag, String? anchor, String node) =>
      applyInline(tag, anchor, node);

  @override
  void _writeEntry(
    String entry, {
    String? indentation,
    bool hasTrailingComments = false,
  }) {
    if (!_lastHadTrailing && _dumpedIterable.length > 1) {
      _dumpedIterable.write(',');
    }

    _dumpedIterable
      ..write(preferInline ? ' ' : '\n${indentation ?? ' ' * (_indent + 1)}')
      ..write(entry);
    _lastHadTrailing = hasTrailingComments;
  }

  @override
  void _dumpCurrent() {
    assert(_current != null, 'Invalid dumping state');

    if (_dumpedIterable.isEmpty) {
      _dumpedIterable.write('[');
    }

    final entryIndent = _indent + 1;
    final indentation = ' ' * entryIndent;

    while (_current!.moveNext()) {
      final (canDump, object) = _canDump(_current!.current);
      if (!canDump) continue;

      final dumpable = dumpableObject(object);

      switch (dumpable.dumpable) {
        case Map<Object?, Object?> map:
          _stashIterator();
          _writeEntry('{}');
          _stashIterator(pop: true);

        // Iterable. Nested objects must define their own dumping functions
        // which is called before reaching here.
        case Iterable<Object?> iterable:
          {
            _evictParent(
              iterable,
              childIndent: entryIndent,
              onIterableDone: (entry) => _onIterableDone(
                entry,
                entryIndent,
                dumpable as ConcreteNode<Object?>,
              ),
              alwayExplicit: true,
            );

            return;
          }

        // Scalar
        default:
          {
            final (:isMultiline, :tentativeOffsetFromMargin, :node) =
                scalarDumper.dump(dumpable, indent: entryIndent, style: null);

            _isExplicit = _isExplicit || isMultiline;

            final (hasTrailing, modded) = _applyComments(
              dumpable.comments,
              node: node,
              indent: entryIndent,
              offsetFromMargin: tentativeOffsetFromMargin,
            );

            _writeEntry(
              modded,
              indentation: indentation,
              hasTrailingComments: hasTrailing,
            );
          }
      }
    }

    final hasContent = _dumpedIterable.length > 1;

    if (!preferInline && hasContent) {
      _dumpedIterable.write('\n${' ' * _indent}');
    } else if (hasContent) {
      _dumpedIterable.write(' ');
    }

    _dumpedIterable.write(']');
    _current = null;
    _lastHadTrailing = false;
  }

  /// Applies the [comments] of a flow node. If [offsetFromMargin] is `null` and
  /// the comment style is [CommentStyle.inline], it scans backwards for a line
  /// break and uses that offset.
  (bool hasTrailing, String node) _applyComments(
    List<String> comments, {
    required String node,
    required int indent,
    required int? offsetFromMargin,
  }) {
    if (preferInline || comments.isEmpty) {
      return (false, node);
    } else if (commentDumper.style == CommentStyle.block) {
      return (
        false,
        commentDumper.applyComments(
          node,
          comments: comments,
          forceBlock: false,
          indent: indent,
          offsetFromMargin: -1,
        ),
      );
    }

    return (
      true,
      commentDumper.applyComments(
        '$node,',
        comments: comments,
        forceBlock: false,
        indent: indent,
        offsetFromMargin:
            offsetFromMargin ??
            switch (node.lastIndexOf('\n')) {
              -1 => node.length + indent,
              int value => (node.length - value),
            },
      ),
    );
  }

  /// Applies the comments of a nested iterable once it has been dumped.
  (bool hasTrailing, String node) _onIterableDone(
    String entry,
    int indent,
    ConcreteNode<Object?> dumpable,
  ) {
    final anchor = dumpable.anchor;
    return _applyComments(
      dumpable.comments,
      node: applyInline(globals(dumpable.tag, anchor, dumpable), anchor, entry),
      indent: indent,
      offsetFromMargin: null,
    );
  }
}
