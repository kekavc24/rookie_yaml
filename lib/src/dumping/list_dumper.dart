import 'package:rookie_yaml/src/dumping/dumpable_node.dart';
import 'package:rookie_yaml/src/dumping/dumper_utils.dart';
import 'package:rookie_yaml/src/dumping/map_dumper.dart';
import 'package:rookie_yaml/src/dumping/scalar_dumper.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

part 'iterable_entry_formatter.dart';

/// An input for an [IterableDumper].
typedef IterableEntry = CollectionEntry<Object?>;

/// Callback for inserting a nested [Iterable] into a previous evicted parent
/// [Iterable] after it has been completely dumped.
typedef _OnNestedIterable = void Function(bool isExplicit, String content);

/// Information about an [Iterable] that was evicted to allow a nested
/// [Iterable] to be dumped.
typedef _IterableState = ({
  bool isRoot,
  bool preferExplicit,
  bool lastHadTrailingComments,
  int currentIndent,
  Iterator<IterableEntry> iterator,
  String state,
  _OnNestedIterable onIterableDone,
});

/// A dumper for an [Iterable].
final class IterableDumper with PropertyDumper, EntryFormatter {
  IterableDumper._(
    this._listEntry, {
    required this.iterableStyle,
    required this.canApplyTrailingComments,
    required this.onObject,
    required this.globals,
    required OnCollectionEnd onIterableEnd,
    required this.scalarDumper,
  }) : _onIterableEnd = onIterableEnd {
    _onFormat = (entry, indentation, lastHadTrailing, isNotFirst) =>
        _listEntry.isFlow
        ? formatFlowEntry(
            entry,
            indentation,
            preferInline: _listEntry.preferInline,
            lastHadTrailing: lastHadTrailing,
            isNotFirst: isNotFirst,
          )
        : formatBlockEntry(entry, indentation, isNotFirst: isNotFirst);

    _onIterableDumped = (tag, anchor, indent, node) =>
        _listEntry.isFlow || node.startsWith('[')
        ? applyInline(tag, anchor, node)
        : applyBlock(tag, anchor, indent, node);
  }

  IterableDumper.block({
    required ScalarDumper scalarDumper,
    required CommentDumper commentDumper,
    required Compose onObject,
    required PushProperties globals,
  }) : this._(
         _ListEntry(commentDumper),
         iterableStyle: NodeStyle.block,
         canApplyTrailingComments: false,
         onObject: onObject,
         globals: globals,
         onIterableEnd: (hasContent, _, _) {
           if (hasContent) return noCollectionEnd;
           return (explicit: true, ending: '[]\n');
         },
         scalarDumper: scalarDumper,
       );

  IterableDumper.flow({
    required bool preferInline,
    required ScalarDumper scalarDumper,
    required CommentDumper commentDumper,
    required Compose onObject,
    required PushProperties globals,
  }) : this._(
         _ListEntry(
           commentDumper,
           isFlowSequence: true,
           alwaysInline: preferInline,
         ),
         iterableStyle: NodeStyle.flow,
         canApplyTrailingComments: true,
         onObject: onObject,
         globals: globals,
         onIterableEnd: (hasContent, isInline, indent) {
           return (
             explicit: null,
             ending: '${hasContent && !isInline ? '\n$indent' : ''}]',
           );
         },
         scalarDumper: scalarDumper,
       );

  final NodeStyle iterableStyle;

  final bool canApplyTrailingComments;

  /// Dumper for scalars.
  final ScalarDumper scalarDumper;

  var _hasMapDumper = false;

  /// Dumper for maps.
  late final MapDumper _mapDumper;

  /// A helper function for composing a dumpable object.
  final Compose onObject;

  /// Tracks the object and its properties.
  final PushProperties globals;

  final _ListEntry _listEntry;

  late final OnCollectionFormat _onFormat;

  final OnCollectionEnd _onIterableEnd;

  late final OnCollectionDumped _onIterableDumped;

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

  /// Sets the internal [MapDumper] to [dumper].
  ///
  /// `NOTE:` A [NodeStyle.block] map [dumper] should not be provided to a
  /// [NodeStyle.flow] iterable dumper. This results in invalid YAML since
  /// block nodes are not allowed in flow nodes. Use `ObjectDumper` or prefer
  /// calling [initialize]. Alternatively, never call this setter :)
  set mapDumper(MapDumper dumper) {
    if (_hasMapDumper) return;
    _hasMapDumper = true;
    _mapDumper = dumper;
  }

  /// Ensures the internal [_mapDumper] was set.
  ///
  /// If not initialized, a [MapDumper] matching the [iterableStyle] is created.
  /// Otherwise, nothing happens.
  void initialize() {
    if (_hasMapDumper) return;

    _hasMapDumper = true;
    final dumper = switch (iterableStyle) {
      NodeStyle.block => MapDumper.block(
        scalarDumper: scalarDumper,
        commentDumper: _listEntry.dumper,
        onObject: onObject,
        globals: globals,
      ),
      _ => MapDumper.flow(
        preferInline: _listEntry.preferInline,
        scalarDumper: scalarDumper,
        commentDumper: _listEntry.dumper,
        onObject: onObject,
        globals: globals,
      ),
    };

    mapDumper = dumper..iterableDumper = this;
  }

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
      _lastHadTrailing = stashed.lastHadTrailingComments;

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
      onIterableDone: (_, _) => {},
    ));

    _reset();
  }

  /// Stashes the current parent and set its [child] (a nested [Iterable]) as
  /// the current [Iterable] being dumped.
  void _evictParent(
    Iterable<Object?> child, {
    required int childIndent,
    required _OnNestedIterable onIterableDone,
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

  /// Writes the first character needed for a map. No op for block maps.
  void _listStart() {
    if (_listEntry.isFlow) {
      _dumpedIterable.write('[');
    }
  }

  /// Writes the current state of the [_listEntry] to the [_dumpedIterable]
  /// buffer.
  void _writeEntry() {
    final (:hasTrailing, :content) = _listEntry.format();

    final isNotFirst = _listEntry.isFlow
        ? _dumpedIterable.length > 1
        : _dumpedIterable.isNotEmpty;

    _dumpedIterable.write(
      _onFormat(
        content,
        ' ' * _listEntry.entryIndent,
        _lastHadTrailing,
        isNotFirst,
      ),
    );

    _lastHadTrailing = hasTrailing;
    _listEntry.reset(); // Avoid resetting indent.
  }

  /// Terminates the current iterable being dumped.
  void _listEnd() {
    final (:explicit, :ending) = _onIterableEnd(
      _listEntry.isFlow
          ? _dumpedIterable.length > 1
          : _dumpedIterable.isNotEmpty,
      _listEntry.preferInline,
      ' ' * _indent,
    );

    _isExplicit = explicit ?? _isExplicit;
    _dumpedIterable.write(ending);
    _current = null;
    _lastHadTrailing = false;
    _listEntry.reset(null, -1);
  }

  /// Initializes the current iterable being dumped.
  void _warmUpEntry() {
    // We want flow maps to look "pretty" even if they are inline. The
    // distinction should be somewhat clear. It should be noted indent is
    // meaningless if flow nodes unless embedded within a block node.
    _listEntry.entryIndent = _listEntry.isFlow ? _indent + 1 : _indent;
    _listStart();
  }

  void _dumpCurrentEntry() {
    int indent([bool isBlockCollection = false]) {
      final indent = _listEntry.isFlow
          ? _listEntry.entryIndent
          : _listEntry.entryIndent + 1;

      if (!isBlockCollection) return indent;
      return indent + 1;
    }

    void completeEntry({
      required int indent,
      required bool preferExplicit,
      required bool applyTrailingComments,
      required String content,
      required List<String>? comments,
      int? offsetFromMargin,
    }) {
      // Content cannot have leading indent.
      final trimmed = content.trimLeft();
      final commentsToDump = comments ?? [];

      _isExplicit = _isExplicit || preferExplicit;

      _listEntry.node = (
        indent: indent,
        offsetFromMargin: offsetFromMargin,
        canApplyTrailingComments: applyTrailingComments,
        comments: commentsToDump,
        content: trimmed,
      );
    }

    final (object, dumper) = _current!.current;

    if (dumper != null) {
      final objectIndent = indent();

      final (:isMultiline, :isBlockCollection, :content, :comments) = dumper(
        objectIndent,
        object,
      );

      return completeEntry(
        preferExplicit: isMultiline,
        indent: objectIndent,
        applyTrailingComments: !isBlockCollection,
        content: content,
        comments: comments,
      );
    }

    final dumpable = onObject(object);

    switch (dumpable.dumpable) {
      case Map<Object?, Object?> map:
        {
          _stashIterator();

          final mapIndent = indent(_mapDumper.mapStyle == NodeStyle.block);

          final (:applyTrailingComments, :preferExplicit, :node) = _mapDumper
              .dump(
                dumpableType(map.entries.map((e) => (e, null)))
                  ..anchor = dumpable.anchor
                  ..tag = dumpable.tag,
                mapIndent,
              );

          _stashIterator(pop: true);

          completeEntry(
            indent: mapIndent,
            preferExplicit: preferExplicit,
            applyTrailingComments: applyTrailingComments,
            content: node,
            comments: dumpable.comments,
          );
        }

      case Iterable<Object?> iterable:
        {
          final isBlockList = iterableStyle == NodeStyle.block;
          final iterableIndent = indent(isBlockList);

          _evictParent(
            iterable,
            childIndent: iterableIndent,
            onIterableDone: (isExplicit, content) => completeEntry(
              indent: iterableIndent,
              preferExplicit: isExplicit || isBlockList,
              applyTrailingComments: canApplyTrailingComments,
              content: _onIterableDumped(
                globals(
                  dumpable.tag,
                  dumpable.anchor,
                  dumpable as ConcreteNode<Object?>,
                ),
                dumpable.anchor,
                iterableIndent,
                content,
              ),
              comments: dumpable.comments,
            ),
          );
        }

      default:
        {
          final indentation = indent();

          final (:isMultiline, :tentativeOffsetFromMargin, :node) = scalarDumper
              .dump(dumpable, indent: indentation, style: null);

          completeEntry(
            indent: indentation,
            preferExplicit: isMultiline,
            applyTrailingComments:
                scalarDumper.defaultStyle.nodeStyle != NodeStyle.block,
            offsetFromMargin: tentativeOffsetFromMargin + 1,
            comments: dumpable.comments,
            content: node,
          );
        }
    }
  }

  /// Dumps the next entry in an [Iterable] using its set iterator, [_current].
  void _dumpCurrent() {
    _listEntry.isEmpty ? _warmUpEntry() : _writeEntry();
    _current!.moveNext() ? _dumpCurrentEntry() : _listEnd();
  }

  /// Dumps an [iterable] with the provided [indent].
  DumpedCollection dump(
    ConcreteNode<Iterable<IterableEntry>> iterable,
    int indent,
  ) {
    initialize();
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
      final nestedIsExplicit = _isExplicit;

      _reset(
        iterator: parent.iterator,
        indent: parent.currentIndent,
        isRoot: parent.isRoot,
        isExplicit: parent.preferExplicit,
        lastHadTrailing: parent.lastHadTrailingComments,
      );

      _dumpedIterable.write(parent.state);
      parent.onIterableDone(nestedIsExplicit, nested);
    } while (true);

    final dumped = _dumpedIterable.toString();

    final dumpedIterable = (
      preferExplicit: _isExplicit || dumped.length > 1024,
      node: _onIterableDumped(
        globals(tag, anchor, iterable),
        anchor,
        _indent,
        dumped,
      ),
      applyTrailingComments: canApplyTrailingComments,
    );

    _reset();
    return dumpedIterable;
  }

  /// Dumps a custom [object] as an [Iterable].
  ///
  /// The [tag] and [anchor] are included with the [object] after the [expand]
  /// has been called.
  DumpedCollection dumpObject<T>(
    T object, {
    required Iterable<IterableEntry> Function(T object) expand,
    required int indent,
    ResolvedTag? tag,
    String? anchor,
    List<String> comments = const [],
  }) => dump(
    dumpableType(expand(object))
      ..tag = tag
      ..anchor = anchor
      ..comments.addAll(comments),
    indent,
  );
}
