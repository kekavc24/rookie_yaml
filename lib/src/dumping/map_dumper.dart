import 'package:rookie_yaml/src/dumping/dumpable_node.dart';
import 'package:rookie_yaml/src/dumping/dumper_utils.dart';
import 'package:rookie_yaml/src/dumping/formatter.dart';
import 'package:rookie_yaml/src/dumping/list_dumper.dart';
import 'package:rookie_yaml/src/dumping/scalar_dumper.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

part 'entry_formatter.dart';

/// A callback every parent provides once its child has been dumped.
typedef _OnNestedMap = void Function(bool isExplicit, String content);

/// Information about a [Map] that was evicted to allow a nested [Map] to be
/// dumped.
typedef _MapState = ({
  bool isRoot,
  bool preferExplicit,
  bool lastHadTrailingComments,
  int mapIndent,
  int entryIndent,
  Iterator<MapEntry<Object?, Object?>> iterator,
  _KeyStore? currentKey,
  _ValueStore? currentValue,
  int entriesFormatted,
  String mapState,
  _OnNestedMap onMapDone,
});

/// A dumper for a [Map].
final class MapDumper with PropertyDumper, EntryFormatter {
  MapDumper._(
    this._entryStore, {
    required this.inlineNestedIterable,
    required this.inlineNestedMap,

    required this.mapStyle,
    required this.canApplyTrailingComments,
    required this.onObject,
    required this.pushAnchor,
    required this.asLocalTag,
    required OnCollectionEnd onMapEnd,
    required this.scalarDumper,
  }) : _onMapEnd = onMapEnd {
    _onWrite = (entry, indentation, lastHadTrailing, isNotFirst) =>
        _entryStore.isFlow
        ? formatFlowEntry(
            entry,
            indentation,
            preferInline: _entryStore.preferInline,
            lastHadTrailing: lastHadTrailing,
            isNotFirst: isNotFirst,
          )
        : formatBlockEntry(entry, indentation, isNotFirst: isNotFirst);

    _onMapDumped = (tag, anchor, indent, node) =>
        _entryStore.isFlow || node.startsWith('{')
        ? applyInline(tag, anchor, node)
        : applyBlock(tag, anchor, indent, node);
  }

  /// Dumper for block maps.
  MapDumper.block({
    required ScalarDumper scalarDumper,
    required CommentDumper commentDumper,
    required Compose onObject,
    required PushAnchor pushAnchor,
    required AsLocalTag asLocalTag,
    bool inlineNestedFlowIterable = false,
    bool inlineNestedFlowMap = false,
  }) : this._(
         _KVStore(commentDumper),
         inlineNestedIterable: inlineNestedFlowIterable,
         inlineNestedMap: inlineNestedFlowMap,
         mapStyle: NodeStyle.block,
         canApplyTrailingComments: false,
         onObject: onObject,
         pushAnchor: pushAnchor,
         asLocalTag: asLocalTag,
         scalarDumper: scalarDumper,
         onMapEnd: (hasContent, _, _) {
           if (hasContent) return noCollectionEnd;
           return (explicit: true, ending: '{}');
         },
       );

  /// Dumper for flow maps.
  MapDumper.flow({
    required bool preferInline,
    required ScalarDumper scalarDumper,
    required CommentDumper commentDumper,
    required Compose onObject,
    required PushAnchor pushAnchor,
    required AsLocalTag asLocalTag,
    bool inlineIterable = true,
  }) : this._(
         _KVStore(
           commentDumper,
           isFlowNode: true,
           alwaysInline: preferInline,
         ),
         inlineNestedMap: preferInline,
         inlineNestedIterable: inlineIterable,
         mapStyle: NodeStyle.flow,
         canApplyTrailingComments: true,
         scalarDumper: scalarDumper,
         onObject: onObject,
         pushAnchor: pushAnchor,
         asLocalTag: asLocalTag,
         onMapEnd: (hasContent, isInline, indent) {
           return (
             explicit: null,
             ending: '${hasContent && !isInline ? '\n$indent' : ''}}',
           );
         },
       );

  /// Whether nested flow iterables are inlined.
  final bool inlineNestedIterable;

  /// Whether nested flow maps are inlined.
  final bool inlineNestedMap;

  /// Map style
  final NodeStyle mapStyle;

  bool get isBlockDumper => mapStyle == NodeStyle.block;

  /// Whether this map accepts trailing comments.
  final bool canApplyTrailingComments;

  /// A helper function for composing a dumpable object.
  final Compose onObject;

  /// A callback for pushing anchors.
  final PushAnchor pushAnchor;

  /// A callback for validating, tracking and normalizing a resolved tag.
  final AsLocalTag asLocalTag;

  /// Called after the map has been dumped. Applies the node's properties.
  late final OnCollectionDumped _onMapDumped;

  /// Called when an entry has been dumped.
  late final OnCollectionFormat _onWrite;

  /// Called when no more entries are present.
  final OnCollectionEnd _onMapEnd;

  /// Dumper for scalars.
  final ScalarDumper scalarDumper;

  /// Whether an [_iterableDumper] has been initialized.
  var _hasIterableDumper = false;

  /// Dumper for iterables.
  late final IterableDumper _iterableDumper;

  /// Tracks evicted [Map]s while another nested [Map] is being parsed.
  final _states = <_MapState>[];

  /// Stores the state of the [Map] being dumped.
  final _dumpedMap = StringBuffer();

  /// Stores the state of the [Map] being dumped.
  Iterator<MapEntry<Object?, Object?>>? _current;

  /// Tracks the key-value pair of the current map being dumped.
  final _KVStore _entryStore;

  /// Whether this iterable should be dumped as an explicit key if it's
  /// parent is a map. This is also indicates if the map is multiline.
  var _isExplicit = false;

  /// Whether this is the root iterable.
  var _isRoot = true;

  /// Indent for the map. Will never be negative when the map is being parsed.
  var _mapIndent = -1;

  /// Whether the last entry has trailing comments.
  ///
  /// This has no meaning in block maps since block map entries always end with
  /// a line break.
  var _lastHadTrailing = false;

  /// Whether the [Map] span multiple lines.
  bool _preferExplicit(String node) {
    return _entryStore.parentIsMultiline() || _isExplicit || node.length > 1024;
  }

  /// Sets the internal [Iterable] to [dumper].
  ///
  /// `NOTE:` A [NodeStyle.block] iterable [dumper] should not be provided to a
  /// [NodeStyle.flow] map dumper. This results in invalid YAML since block
  /// nodes are not allowed in flow nodes. Use `ObjectDumper` or prefer calling
  /// [initialize]. Alternatively, never call this setter unless you are
  /// \*EXTREMELY\* sure the YAML will be valid.
  set iterableDumper(IterableDumper dumper) {
    if (_hasIterableDumper) return;
    _hasIterableDumper = true;
    _iterableDumper = dumper;
  }

  /// Ensures the internal [_iterableDumper] was set.
  ///
  /// If not initialized, a [IterableDumper] matching the [mapStyle] is created.
  void initialize() {
    if (_hasIterableDumper) return;

    _hasIterableDumper = true;
    _iterableDumper = switch (mapStyle) {
      NodeStyle.block => IterableDumper.block(
        scalarDumper: scalarDumper,
        commentDumper: _entryStore.dumper,
        onObject: onObject,
        pushAnchor: pushAnchor,
        asLocalTag: asLocalTag,
        inlineNestedFlowIterable: inlineNestedIterable,
        inlineNestedFlowMap: inlineNestedMap,
      ),
      _ => IterableDumper.flow(
        preferInline: inlineNestedIterable,
        scalarDumper: scalarDumper,
        commentDumper: _entryStore.dumper,
        onObject: onObject,
        pushAnchor: pushAnchor,
        asLocalTag: asLocalTag,
        inlineMap: _entryStore.preferInline,
      ),
    }..mapDumper = this;
  }

  /// Resets the internal state of the dumper.
  void _reset({
    Iterator<MapEntry<Object?, Object?>>? iterator,
    int indent = -1,
    bool isRoot = true,
    bool isExplicit = false,
    bool lastHadTrailing = false,
  }) {
    _isRoot = isRoot;
    _isExplicit = isExplicit;
    _mapIndent = indent;
    _lastHadTrailing = lastHadTrailing;
    _current = iterator;
    _dumpedMap.clear();
    _entryStore.reset();
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
      _mapIndent = stashed.mapIndent;
      _current = stashed.iterator;
      _entryStore.reset(
        newKey: stashed.currentKey,
        newValue: stashed.currentValue,
        indent: stashed.entryIndent,
        count: stashed.entriesFormatted,
      );

      _dumpedMap.write(stashed.mapState);
      return;
    }

    _states.add((
      isRoot: _isRoot,
      preferExplicit: _isExplicit,
      lastHadTrailingComments: _lastHadTrailing,
      mapIndent: _mapIndent,
      entryIndent: _entryStore.entryIndent,
      iterator: _current!,
      currentKey: _entryStore.key,
      currentValue: _entryStore.value,
      entriesFormatted: _entryStore.countFormatted,
      mapState: _dumpedMap.toString(),
      onMapDone: (_, _) {},
    ));

    _reset();
  }

  /// Stashes the current parent and set its [child] (a nested [Map]) as the
  /// current [Map] being dumped.
  void _evictParent(
    Iterator<MapEntry<Object?, Object?>> child, {
    required int childIndent,
    required _OnNestedMap onMapDone,
    bool alwayExplicit = false,
  }) {
    _states.add((
      isRoot: _isRoot,
      preferExplicit: _isExplicit,
      lastHadTrailingComments: _lastHadTrailing,
      mapIndent: _mapIndent,
      entryIndent: _entryStore.entryIndent,
      iterator: _current!,
      currentKey: _entryStore.key,
      currentValue: _entryStore.value,
      entriesFormatted: _entryStore.countFormatted,
      mapState: _dumpedMap.toString(),
      onMapDone: onMapDone,
    ));

    _reset(
      iterator: child,
      indent: childIndent,
      isRoot: false,
      isExplicit: alwayExplicit,
    );
  }

  /// Writes the first character needed for a map. No op for block maps.
  void _mapStart() {
    if (mapStyle == NodeStyle.flow) {
      _dumpedMap.write('{');
    }
  }

  /// Writes the current state of the [_entryStore] to the [_dumpedMap] buffer.
  void _writeEntry() {
    final (:content, :hasTrailing) = _entryStore.format();

    _dumpedMap.write(
      _onWrite(
        content,
        ' ' * _entryStore.entryIndent,
        _lastHadTrailing,
        _entryStore.formattedAny,
      ),
    );
    _lastHadTrailing = hasTrailing;
    _entryStore.next();
  }

  /// Terminates the current map being dumped.
  void _mapEnd() {
    final (:explicit, :ending) = _onMapEnd(
      _entryStore.formattedAny,
      _entryStore.preferInline,
      ' ' * _mapIndent,
    );

    _isExplicit = explicit ?? _isExplicit;
    _dumpedMap.write(ending);
    _current = null;
    _lastHadTrailing = false;
    _entryStore.reset(indent: -1);
  }

  /// Initializes a map being dumped.
  void _warmUpEntry() {
    // We want flow maps to look "pretty" even if they are inline. The
    // distinction should be somewhat clear. It should be noted indent is
    // meaningless if flow nodes unless embedded within a block node.
    _entryStore.entryIndent = _entryStore.isFlow ? _mapIndent + 1 : _mapIndent;
    _mapStart();
  }

  /// Expands an [Entry] and returns the object being dumped.
  Object? _currentOfPair(bool isKey) {
    final entry = _current!.current;
    return isKey ? entry.key : entry.value;
  }

  /// Dumpes the key or value of the current [Entry] in the iterator.
  void _dumpEntry({required bool isKey}) {
    final dumpingIndent =
        _entryStore.entryIndent + (isKey || _entryStore.keyWasExplicit ? 2 : 1);

    void completeEntry({
      required bool applyTrailingComments,
      required String content,
      bool isExplicit = false,
      bool isBlockNode = false,
      List<String>? comments,
      int? offsetFromMargin,
    }) {
      // Content cannot have leading indent.
      final trimmed = content.trimLeft();
      final commentsToDump = comments ?? [];

      if (isKey) {
        final keyIsExplicit = isExplicit || isBlockNode;

        _entryStore.key = (
          explicit: keyIsExplicit,
          info: (
            indent: keyIsExplicit ? dumpingIndent : _entryStore.entryIndent,
            offsetFromMargin: offsetFromMargin,
            canApplyTrailingComments: applyTrailingComments,
            comments: commentsToDump,
            content: trimmed,
          ),
        );
        return;
      }

      _entryStore.value = (
        isBlock: isBlockNode,
        info: (
          indent: dumpingIndent,
          offsetFromMargin: offsetFromMargin,
          canApplyTrailingComments: applyTrailingComments,
          comments: commentsToDump,
          content: trimmed,
        ),
      );
    }

    final dumpable = onObject(_currentOfPair(isKey));

    // Dumps a map in the current dumper's context.
    void iterativeSelf(Map<Object?, Object?> map) {
      final isBlockMap = mapStyle == NodeStyle.block;

      if (isBlockDumper && !isBlockMap) {
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
            commentDumper: _entryStore.dumper,
            onObject: onObject,
            pushAnchor: pushAnchor,
            asLocalTag: asLocalTag,
            inlineIterable: inlineNestedIterable,
          ),
          dump: (dumper) => dumper.dumpMapLike(
            map,
            expand: identity,
            indent: dumpingIndent,
            tag: dumpable.tag,
            anchor: dumpable.anchor,
          ),
          onDump: (dumped) => completeEntry(
            isExplicit: dumped.preferExplicit,
            isBlockNode: false,
            applyTrailingComments: canApplyTrailingComments,
            comments: dumpable.comments,
            content: _onMapDumped(
              asLocalTag(dumpable.tag),
              dumpable.anchor,
              dumpingIndent,
              dumped.node,
            ),
          ),
        );
      }

      final isBlockNode = isBlockMap && isBlockDumper;

      _evictParent(
        map.entries.iterator,
        childIndent: dumpingIndent,
        onMapDone: (isExplicit, dumped) {
          completeEntry(
            isExplicit: isExplicit || isBlockNode,
            isBlockNode: isBlockNode,
            applyTrailingComments: canApplyTrailingComments,
            comments: dumpable.comments,
            content: _onMapDumped(
              asLocalTag(dumpable.tag),
              dumpable.anchor,
              dumpingIndent,
              dumped,
            ),
          );
        },
      );
    }

    // Dumps an iterable after stashing the state of the current dumper.
    void iterativeIterable(IterativeCollection<IterableDumper> dumpIterable) {
      if (_iterableDumper.isBlockDumper &&
          dumpable.nodeStyle != NodeStyle.block) {
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
            commentDumper: _entryStore.dumper,
            onObject: onObject,
            pushAnchor: pushAnchor,
            asLocalTag: asLocalTag,
            inlineMap: inlineNestedMap,
          ),
          dump: (dumper) => dumpIterable(dumpingIndent, dumper),
          onDump: (dumped) => completeEntry(
            isExplicit: dumped.preferExplicit,
            isBlockNode: false,
            applyTrailingComments: true,
            comments: dumpable.comments,
            content: dumped.node,
          ),
        );
      }

      _stashIterator();
      final (:applyTrailingComments, :preferExplicit, :node) = dumpIterable(
        dumpingIndent,
        _iterableDumper,
      );
      _stashIterator(pop: true);
      completeEntry(
        isExplicit: preferExplicit,
        isBlockNode: _iterableDumper.iterableStyle == NodeStyle.block,
        applyTrailingComments: applyTrailingComments,
        comments: dumpable.comments,
        content: node,
      );
    }

    unwrappedDumpable(
      dumpable,
      onIterable: (iterable) => iterativeIterable(
        (iterableIndent, dumper) => dumper.dumpIterableLike(
          iterable,
          expand: identity,
          indent: iterableIndent,
          tag: dumpable.tag,
          anchor: dumpable.anchor,
        ),
      ),
      onMap: iterativeSelf,
      onScalar: () {
        final (:isMultiline, :tentativeOffsetFromMargin, :node) = scalarDumper
            .dump(
              dumpable,
              indent: dumpingIndent,
              parentIndent: (_entryStore.key?.explicit ?? true)
                  ? _entryStore.entryIndent
                  : _entryStore.key!.info.indent,
              style: null,
            );

        completeEntry(
          isExplicit: isMultiline,
          isBlockNode: scalarDumper.defaultStyle.nodeStyle == NodeStyle.block,
          applyTrailingComments: true,
          offsetFromMargin: tentativeOffsetFromMargin,
          comments: dumpable.comments,
          content: node,
        );
      },
    );

    pushAnchor(dumpable.anchor, dumpable);
  }

  /// Dumps a map based on its stored state.
  void _dumpCurrent() {
    if (_entryStore.hasKey) {
      if (!_entryStore.hasValue) return _dumpEntry(isKey: false);

      _writeEntry();
    } else {
      _warmUpEntry();
    }

    _current!.moveNext() ? _dumpEntry(isKey: true) : _mapEnd();
  }

  /// Dumps a sequence of [mapEntries] with the provided [indent] of the map.
  DumpedCollection dump(
    ConcreteNode<Map<Object?, Object?>> mapEntries,
    int indent,
  ) {
    initialize();
    final ConcreteNode(:dumpable, :tag, :anchor) = mapEntries;
    _reset(iterator: dumpable.entries.iterator, indent: indent);

    do {
      if (_current != null) {
        _dumpCurrent();
        continue;
      } else if (_isRoot) {
        break;
      }

      final mapBefore = _states.removeLast();
      final nested = _dumpedMap.toString();
      final nestedIsExplicit = _preferExplicit(nested);

      _reset(
        iterator: mapBefore.iterator,
        indent: mapBefore.mapIndent,
        isRoot: mapBefore.isRoot,
        isExplicit: mapBefore.preferExplicit,
        lastHadTrailing: mapBefore.lastHadTrailingComments,
      );

      _entryStore.reset(
        newKey: mapBefore.currentKey,
        newValue: mapBefore.currentValue,
        indent: mapBefore.entryIndent,
        count: mapBefore.entriesFormatted,
      );

      _dumpedMap.write(mapBefore.mapState);
      mapBefore.onMapDone(nestedIsExplicit, nested);
    } while (true);

    final dumped = _dumpedMap.toString();

    final dumpedMap = (
      preferExplicit:
          !_entryStore.isFlow || _isExplicit || dumped.length > 1024,
      node: _onMapDumped(asLocalTag(tag), anchor, _mapIndent, dumped),
      applyTrailingComments: canApplyTrailingComments,
    );

    _reset();
    return dumpedMap;
  }

  /// Dumps an [object] as a [Map].
  ///
  /// The [tag] and [anchor] are included with the [object] after the [expand]
  /// has been called.
  DumpedCollection dumpMapLike<T>(
    T object, {
    required Map<Object?, Object?> Function(T object) expand,
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
