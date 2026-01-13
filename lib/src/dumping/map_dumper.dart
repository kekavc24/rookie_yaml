import 'package:rookie_yaml/src/dumping/dumpable_node.dart';
import 'package:rookie_yaml/src/dumping/dumper_utils.dart';
import 'package:rookie_yaml/src/dumping/list_dumper.dart';
import 'package:rookie_yaml/src/dumping/scalar_dumper.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

part 'entry_formatter.dart';

/// An input for a [MapDumper].
typedef Entry =
    CollectionEntry<
      MapEntry<Object?, Object?>,
      ({bool isMultiline, bool isBlockCollection, String content})
    >;

/// A single view for an [Entry]. Represents a single key or value based on
/// the dumping progress.
typedef _ExpandedEntry = (
  Object? toDump,
  ({bool isMultiline, bool isBlockCollection, String content}) Function(
    int indent,
    Object? object,
  )?,
);

/// A callback every parent provides once its child has been dumped.
typedef _OnNestedMap = void Function(bool isExplicit, String content);

/// A callback used to dump the root parent depending on its [NodeStyle].
typedef _OnMapDumped =
    String Function(String? tag, String? anchor, int mapIndent, String node);

/// A callback used once a map has been dumped completely. May vary depending
/// on the [NodeStyle].
typedef _OnMapEnd =
    ({bool? explicit, String mapEnding}) Function(
      bool hasContent,
      bool isInline,
      String indentation,
    );

/// Used by maps dumped as [NodeStyle.block].
const _noEnding = (explicit: null, mapEnding: '');

/// Information about a [Map] that was evicted to allow a nested [Map] to be
/// dumped.
typedef _MapState = ({
  bool isRoot,
  bool preferExplicit,
  bool lastHadTrailingComments,
  int mapIndent,
  int entryIndent,
  Iterator<Entry> iterator,
  _KeyStore? currentKey,
  _ValueStore? currentValue,
  String mapState,
  _OnNestedMap onMapDone,
});

/// A dumper for a [Map].
final class MapDumper with PropertyDumper {
  MapDumper._(
    this._entryStore, {
    required this.mapStyle,
    required this.canApplyTrailingComments,
    required this.onObject,
    required this.globals,
    required _EntryFormatter formatter,
    required _OnMapEnd onMapEnd,
    required this.scalarDumper,
  }) : _onWrite = formatter,
       _onMapEnd = onMapEnd {
    _onMapDumped = (tag, anchor, indent, node) =>
        mapStyle == NodeStyle.flow || node.startsWith('{')
        ? applyInline(tag, anchor, node)
        : applyBlock(tag, anchor, indent, node);
  }

  /// Dumper for block maps.
  MapDumper.block({
    required ScalarDumper scalarDumper,
    required CommentDumper commentDumper,
    required Compose onObject,
    required PushProperties globals,
  }) : this._(
         _EntryStore(commentDumper),
         mapStyle: NodeStyle.block,
         canApplyTrailingComments: false,
         onObject: onObject,
         globals: globals,
         scalarDumper: scalarDumper,
         formatter: (entry, indentation, _, _, isNotFirst) =>
             _formatBlock(entry, indentation, isNotFirst: isNotFirst),
         onMapEnd: (hasContent, _, _) {
           if (hasContent) return _noEnding;
           return (explicit: true, mapEnding: '{}\n');
         },
       );

  /// Dumper for flow maps.
  MapDumper.flow({
    required bool preferInline,
    required ScalarDumper scalarDumper,
    required CommentDumper commentDumper,
    required Compose onObject,
    required PushProperties globals,
  }) : this._(
         _EntryStore(
           commentDumper,
           isFlowMap: true,
           alwaysInline: preferInline,
         ),
         mapStyle: NodeStyle.flow,
         canApplyTrailingComments: true,
         scalarDumper: scalarDumper,
         onObject: onObject,
         globals: globals,
         formatter: (entry, indentation, isInline, ignoreComma, isNotFirst) =>
             _formatFlow(
               entry,
               indentation,
               preferInline: isInline,
               lastHadTrailing: ignoreComma,
               isNotFirst: isNotFirst,
             ),
         onMapEnd: (hasContent, isInline, indent) {
           return (
             explicit: null,
             mapEnding: '${hasContent && !isInline ? '\n$indent' : ''}}',
           );
         },
       );

  /// Map style
  final NodeStyle mapStyle;

  /// Whether this map accepts trailing comments.
  final bool canApplyTrailingComments;

  /// A helper function for composing a dumpable object.
  final Compose onObject;

  /// Tracks the object and its properties.
  final PushProperties globals;

  /// Called after the map has been dumped. Applies the node's properties.
  late final _OnMapDumped _onMapDumped;

  /// Called when an entry has been dumped.
  final _EntryFormatter _onWrite;

  /// Called when no more entries are present.
  final _OnMapEnd _onMapEnd;

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
  Iterator<Entry>? _current;

  /// Tracks the key-value pair of the current map being dumped.
  final _EntryStore _entryStore;

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

  /// Sets the internal [IterableDumper] to the [dumper] provided only if none
  /// is assigned.
  ///
  /// If the [dumper] is a flow sequence dumper with `preferInline` set to
  /// `true` then this dumper is also set to `true` for `preferInline` only if
  /// it is a flow map dumper.
  set iterableDumper(IterableDumper dumper) {
    if (_hasIterableDumper) return;

    _hasIterableDumper = true;
    _iterableDumper = dumper;

    // Force map inline if
    if (dumper case FlowSequenceDumper(
      preferInline: true,
    ) when _entryStore.isFlow) {
      _entryStore.preferInline = true;
    }
  }

  /// Resets the internal state of the dumper.
  void _reset({
    Iterator<Entry>? iterator,
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
        stashed.currentKey,
        stashed.currentValue,
        stashed.entryIndent,
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
      mapState: _dumpedMap.toString(),
      onMapDone: (_, _) {},
    ));

    _reset();
  }

  /// Stashes the current parent and set its [child] (a nested [Map]) as the
  /// current [Map] being dumped.
  void _evictParent(
    Map<Object?, Object?> child, {
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
      mapState: _dumpedMap.toString(),
      onMapDone: onMapDone,
    ));

    _reset(
      iterator: child.entries.map((e) => (e, null)).iterator,
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
    final (:content, :hasTrailing) = _entryStore.formatEntry();
    final isNotFirst = _entryStore.isFlow
        ? _dumpedMap.length > 1
        : _dumpedMap.isNotEmpty;

    final onWrite = _onWrite(
      content,
      ' ' * _entryStore.entryIndent,
      _entryStore.preferInline,
      _lastHadTrailing,
      isNotFirst,
    );
    _dumpedMap.write(onWrite);

    _lastHadTrailing = hasTrailing;
    _entryStore.reset(); // Avoid resetting indent.
  }

  /// Terminates the current map being dumped.
  void _mapEnd() {
    final (:explicit, :mapEnding) = _onMapEnd(
      _entryStore.isFlow ? _dumpedMap.length > 1 : _dumpedMap.isNotEmpty,
      _entryStore.preferInline,
      ' ' * _mapIndent,
    );

    _isExplicit = explicit ?? _isExplicit;
    _dumpedMap.write(mapEnding);
    _current = null;
    _lastHadTrailing = false;
    _entryStore.reset(null, null, -1);
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
  _ExpandedEntry _expand(bool isKey) {
    final (entry, dumper) = _current!.current;
    return (isKey ? entry.key : entry.value, dumper);
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

    final (object, dumper) = _expand(isKey);

    if (dumper != null) {
      final (:isMultiline, :isBlockCollection, :content) = dumper(
        dumpingIndent,
        object,
      );

      return completeEntry(
        isExplicit: isMultiline,
        isBlockNode: isBlockCollection,
        applyTrailingComments: !isBlockCollection,
        content: content,
      );
    }

    final dumpable = onObject(object);

    switch (dumpable.dumpable) {
      case Map<Object?, Object?> map:
        {
          _evictParent(
            map,
            childIndent: dumpingIndent,
            onMapDone: (isExplicit, dumped) {
              final isBlockMap = mapStyle == NodeStyle.block;

              completeEntry(
                isExplicit: isExplicit || isBlockMap,
                isBlockNode: isBlockMap,
                applyTrailingComments: canApplyTrailingComments,
                comments: dumpable.comments,
                content: _onMapDumped(
                  globals(
                    dumpable.tag,
                    dumpable.anchor,
                    dumpable as ConcreteNode<Object?>,
                  ),
                  dumpable.anchor,
                  dumpingIndent,
                  dumped,
                ),
              );
            },
          );
        }

      case Iterable<Object?> iterable:
        {
          _stashIterator();

          final (
            :applyTrailingComments,
            :preferExplicit,
            :node,
          ) = _iterableDumper.dump(
            dumpableType(iterable.map((e) => (e, null)))
              ..anchor = dumpable.anchor
              ..tag = dumpable.tag,
            dumpingIndent,
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

      default:
        {
          final (:isMultiline, :tentativeOffsetFromMargin, :node) = scalarDumper
              .dump(dumpable, indent: dumpingIndent, style: null);

          completeEntry(
            isExplicit: isMultiline,
            isBlockNode: scalarDumper.defaultStyle.nodeStyle == NodeStyle.block,
            applyTrailingComments: true,
            offsetFromMargin: tentativeOffsetFromMargin,
            comments: dumpable.comments,
            content: node,
          );
        }
    }
  }

  /// Dumps a map based on its stored state.
  void _dumpCurrent() {
    if (_entryStore.hasKey) {
      if (!_entryStore.hasValue) return _dumpEntry(isKey: false);

      _writeEntry();
    } else {
      _warmUpEntry();
    }

    if (_current!.moveNext()) return _dumpEntry(isKey: true);
    _mapEnd();
  }

  /// Dumps a sequence of [mapEntries] with the provided [indent] of the map.
  DumpedCollection dump(ConcreteNode<Iterable<Entry>> mapEntries, int indent) {
    final ConcreteNode(:dumpable, :tag, :anchor) = mapEntries;
    _reset(iterator: dumpable.iterator, indent: indent);

    do {
      if (_current != null) {
        _dumpCurrent();
        continue;
      } else if (_isRoot) {
        break;
      }

      final mapBefore = _states.removeLast();
      final nested = _dumpedMap.toString();
      final nestedIsExplicit = _isExplicit;

      _reset(
        iterator: mapBefore.iterator,
        indent: mapBefore.mapIndent,
        isRoot: mapBefore.isRoot,
        isExplicit: mapBefore.preferExplicit,
        lastHadTrailing: mapBefore.lastHadTrailingComments,
      );

      _entryStore.reset(
        mapBefore.currentKey,
        mapBefore.currentValue,
        mapBefore.entryIndent,
      );

      _dumpedMap.write(mapBefore.mapState);
      mapBefore.onMapDone(nestedIsExplicit, nested);
    } while (true);

    final dumped = _dumpedMap.toString();

    final dumpedMap = (
      preferExplicit:
          !_entryStore.isFlow || _isExplicit || dumped.length > 1024,
      node: _onMapDumped(
        globals(tag, anchor, mapEntries),
        anchor,
        _mapIndent,
        dumped,
      ),
      applyTrailingComments: canApplyTrailingComments,
    );

    _reset();
    return dumpedMap;
  }

  /// Dumps an [object] as a [Map].
  ///
  /// The [tag] and [anchor] are included with the [object] after the [expand]
  /// has been called.
  DumpedCollection dumpObject<T>(
    T object, {
    required Iterable<Entry> Function(T object) expand,
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
