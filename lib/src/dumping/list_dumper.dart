import 'package:rookie_yaml/src/dumping/dumpable_node.dart';
import 'package:rookie_yaml/src/dumping/dumper_utils.dart';
import 'package:rookie_yaml/src/dumping/formatter.dart';
import 'package:rookie_yaml/src/dumping/map_dumper.dart';
import 'package:rookie_yaml/src/dumping/scalar_dumper.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

part 'iterable_entry_formatter.dart';

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
  int entryIndent,
  Iterator<Object?> iterator,
  int elementsDumped,
  String state,
  _OnNestedIterable onIterableDone,
});

/// A dumper for an [Iterable].
///
/// {@category dump_sequence}
final class IterableDumper with PropertyDumper, EntryFormatter {
  IterableDumper._(
    this._listEntry, {
    required this.inlineNestedIterable,
    required this.inlineNestedMap,
    required this.iterableStyle,
    required this.canApplyTrailingComments,
    required this.onObject,
    required this.pushAnchor,
    required this.asLocalTag,
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
    required PushAnchor pushAnchor,
    required AsLocalTag asLocalTag,
    bool inlineNestedFlowIterable = false,
    bool inlineNestedFlowMap = false,
  }) : this._(
         _ListEntry(commentDumper),
         inlineNestedIterable: inlineNestedFlowIterable,
         inlineNestedMap: inlineNestedFlowMap,
         iterableStyle: NodeStyle.block,
         canApplyTrailingComments: false,
         onObject: onObject,
         pushAnchor: pushAnchor,
         asLocalTag: asLocalTag,
         onIterableEnd: (hasContent, _, _) {
           if (hasContent) return noCollectionEnd;
           return (explicit: false, ending: '[]');
         },
         scalarDumper: scalarDumper,
       );

  IterableDumper.flow({
    required bool preferInline,
    required ScalarDumper scalarDumper,
    required CommentDumper commentDumper,
    required Compose onObject,
    required PushAnchor pushAnchor,
    required AsLocalTag asLocalTag,
    bool inlineMap = true,
  }) : this._(
         _ListEntry(
           commentDumper,
           isFlowNode: true,
           alwaysInline: preferInline,
         ),
         inlineNestedIterable: preferInline,
         inlineNestedMap: inlineMap,
         iterableStyle: NodeStyle.flow,
         canApplyTrailingComments: true,
         onObject: onObject,
         pushAnchor: pushAnchor,
         asLocalTag: asLocalTag,
         onIterableEnd: (hasContent, isInline, indent) {
           return (
             explicit: null,
             ending: '${hasContent && !isInline ? '\n$indent' : ''}]',
           );
         },
         scalarDumper: scalarDumper,
       );

  /// Whether nested flow iterables are inlined.
  final bool inlineNestedIterable;

  /// Whether nested flow maps are inlined.
  final bool inlineNestedMap;

  final NodeStyle iterableStyle;

  bool get isBlockDumper => iterableStyle == NodeStyle.block;

  final bool canApplyTrailingComments;

  /// Dumper for scalars.
  final ScalarDumper scalarDumper;

  var _hasMapDumper = false;

  /// Dumper for maps.
  late final MapDumper _mapDumper;

  /// A helper function for composing a dumpable object.
  final Compose onObject;

  /// A callback for pushing anchors.
  final PushAnchor pushAnchor;

  /// A callback for validating, tracking and normalizing a resolved tag.
  final AsLocalTag asLocalTag;

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
  Iterator<Object?>? _current;

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

  /// Whether the [Iterable] span multiple lines.
  bool _preferExplicit(String node) {
    // Block nodes must not be empty.
    return _listEntry.parentIsMultiline() || _isExplicit || node.length > 1024;
  }

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
    _mapDumper = switch (iterableStyle) {
      NodeStyle.block => MapDumper.block(
        scalarDumper: scalarDumper,
        commentDumper: _listEntry.dumper,
        onObject: onObject,
        pushAnchor: pushAnchor,
        asLocalTag: asLocalTag,
        inlineNestedFlowIterable: inlineNestedIterable,
        inlineNestedFlowMap: inlineNestedMap,
      ),
      _ => MapDumper.flow(
        preferInline: inlineNestedMap,
        scalarDumper: scalarDumper,
        commentDumper: _listEntry.dumper,
        onObject: onObject,
        pushAnchor: pushAnchor,
        asLocalTag: asLocalTag,
        inlineIterable: _listEntry.preferInline,
      ),
    }..iterableDumper = this;
  }

  /// Resets the internal state of the dumper.
  void _reset({
    Iterator<Object?>? iterator,
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
    _listEntry.reset();
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

      _listEntry.reset(
        indent: stashed.entryIndent,
        count: stashed.elementsDumped,
      );

      _dumpedIterable.write(stashed.state);
      return;
    }

    _states.add((
      isRoot: _isRoot,
      preferExplicit: _isExplicit,
      currentIndent: _indent,
      entryIndent: _listEntry.entryIndent,
      lastHadTrailingComments: _lastHadTrailing,
      iterator: _current!,
      elementsDumped: _listEntry.countFormatted,
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
      entryIndent: _listEntry.entryIndent,
      iterator: _current!,
      elementsDumped: _listEntry.countFormatted,
    ));

    _reset(
      iterator: child.iterator,
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

    _dumpedIterable.write(
      _onFormat(
        content,
        ' ' * _listEntry.entryIndent,
        _lastHadTrailing,
        _listEntry.formattedAny,
      ),
    );

    _isExplicit = _isExplicit || _listEntry.parentIsMultiline();
    _lastHadTrailing = hasTrailing;
    _listEntry.next();
  }

  /// Terminates the current iterable being dumped.
  void _listEnd() {
    final (:explicit, :ending) = _onIterableEnd(
      _listEntry.formattedAny,
      _listEntry.preferInline,
      ' ' * _indent,
    );

    _isExplicit = explicit ?? _isExplicit;
    _dumpedIterable.write(ending);
    _current = null;
    _lastHadTrailing = false;
    _listEntry.reset(indent: -1);
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

    final dumpable = onObject(_current!.current);

    // Dumps an iterable in the current dumper's context.
    void iterativeSelf(Iterable<Object?> iterable) {
      final isBlockList =
          dumpable.nodeStyle == NodeStyle.block && isBlockDumper;
      final iterableIndent = indent(isBlockList);

      if (isBlockDumper && !isBlockList) {
        return flowInBlockDumper(
          dumper: () => IterableDumper.flow(
            preferInline: inlineNestedIterable,
            scalarDumper: scalarDumper.defaultStyle.nodeStyle == NodeStyle.block
                ? ScalarDumper.classic(
                    onObject,
                    asLocalTag,
                    inlineNestedIterable,
                  )
                : scalarDumper,
            commentDumper: _listEntry.dumper,
            onObject: onObject,
            pushAnchor: pushAnchor,
            asLocalTag: asLocalTag,
            inlineMap: inlineNestedMap,
          ),
          dump: (dumper) => dumper.dumpIterableLike(
            iterable,
            expand: identity,
            indent: iterableIndent,
            tag: dumpable.tag,
            anchor: dumpable.anchor,
          ),
          onDump: (dumped) => completeEntry(
            indent: iterableIndent,
            preferExplicit: dumped.preferExplicit,
            applyTrailingComments: true,
            content: dumped.node,
            comments: dumpable.comments,
          ),
        );
      }

      _evictParent(
        iterable,
        childIndent: iterableIndent,
        onIterableDone: (isExplicit, content) => completeEntry(
          indent: iterableIndent,
          preferExplicit: isExplicit || isBlockDumper,
          applyTrailingComments: canApplyTrailingComments,
          content: _onIterableDumped(
            asLocalTag(dumpable.tag),
            dumpable.anchor,
            iterableIndent,
            content,
          ),
          comments: dumpable.comments,
        ),
      );
    }

    // Dumps a map after stashing the state of the current dumper.
    void iterativeMap(IterativeCollection<MapDumper> dumpMap) {
      final isBlockMap = dumpable.nodeStyle == NodeStyle.block && isBlockDumper;
      final mapIndent = indent(isBlockMap);

      if (_mapDumper.isBlockDumper && !isBlockMap) {
        return flowInBlockDumper(
          dumper: () => MapDumper.flow(
            preferInline: inlineNestedMap,
            scalarDumper: scalarDumper.defaultStyle.nodeStyle == NodeStyle.block
                ? ScalarDumper.classic(
                    onObject,
                    asLocalTag,
                    inlineNestedIterable,
                  )
                : scalarDumper,
            commentDumper: _listEntry.dumper,
            onObject: onObject,
            pushAnchor: pushAnchor,
            asLocalTag: asLocalTag,
            inlineIterable: inlineNestedIterable,
          ),
          dump: (dumper) => dumpMap(mapIndent, dumper),
          onDump: (dumped) => completeEntry(
            indent: mapIndent,
            preferExplicit: dumped.preferExplicit,
            applyTrailingComments: true,
            content: dumped.node,
            comments: dumpable.comments,
          ),
        );
      }

      _stashIterator();

      final (:applyTrailingComments, :preferExplicit, :node) = dumpMap(
        mapIndent,
        _mapDumper,
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

    unwrappedDumpable(
      dumpable,
      onIterable: iterativeSelf,
      onMap: (map) => iterativeMap(
        (mapIndent, dumper) => dumper.dumpMapLike(
          map,
          expand: identity,
          indent: mapIndent,
          tag: dumpable.tag,
          anchor: dumpable.anchor,
        ),
      ),
      onScalar: () {
        final indentation = indent();

        final (:isMultiline, :tentativeOffsetFromMargin, :node) = scalarDumper
            .dump(
              dumpable,
              indent: indentation,
              parentIndent: _listEntry.entryIndent,
              style: null,
            );

        completeEntry(
          // Align the comments correctly.
          indent: isBlockDumper && _listEntry.dumper.style == CommentStyle.block
              ? indentation + 1
              : indentation,
          preferExplicit: isMultiline,
          applyTrailingComments:
              scalarDumper.defaultStyle.nodeStyle != NodeStyle.block,
          offsetFromMargin: tentativeOffsetFromMargin + 1,
          comments: dumpable.comments,
          content: node,
        );
      },
    );

    pushAnchor(dumpable.anchor, dumpable);
  }

  /// Dumps the next entry in an [Iterable] using its set iterator, [_current].
  void _dumpCurrent() {
    _listEntry.isEmpty ? _warmUpEntry() : _writeEntry();
    _current!.moveNext() ? _dumpCurrentEntry() : _listEnd();
  }

  /// Dumps an [iterable] with the provided [indent].
  DumpedCollection dump(ConcreteNode<Iterable<Object?>> iterable, int indent) {
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
      final nestedIsExplicit = _preferExplicit(nested);

      _reset(
        iterator: parent.iterator,
        indent: parent.currentIndent,
        isRoot: parent.isRoot,
        isExplicit: parent.preferExplicit,
        lastHadTrailing: parent.lastHadTrailingComments,
      );

      _listEntry.reset(
        indent: parent.entryIndent,
        count: parent.elementsDumped,
      );

      _dumpedIterable.write(parent.state);
      parent.onIterableDone(nestedIsExplicit, nested);
    } while (true);

    final dumped = _dumpedIterable.toString();

    final dumpedIterable = (
      preferExplicit: _preferExplicit(dumped),
      node: _onIterableDumped(asLocalTag(tag), anchor, _indent, dumped),
      applyTrailingComments: canApplyTrailingComments,
    );

    _reset();
    return dumpedIterable;
  }

  /// Dumps a custom [object] as an [Iterable].
  ///
  /// The [tag] and [anchor] are included with the [object] after the [expand]
  /// has been called.
  DumpedCollection dumpIterableLike<T>(
    T object, {
    required Iterable<Object?> Function(T object) expand,
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
