import 'dart:collection';

import 'package:dump_yaml/src/event_tree/node.dart';
import 'package:dump_yaml/src/event_tree/scalar_content.dart';
import 'package:dump_yaml/src/event_tree/visitor.dart';
import 'package:dump_yaml/src/utils.dart';
import 'package:dump_yaml/src/views/dumpable.dart';
import 'package:dump_yaml/src/views/views.dart';
import 'package:rookie_yaml/rookie_yaml.dart'
    show
        GlobalTag,
        NodeStyle,
        ResolvedTag,
        ScalarStyle,
        TagHandle,
        TagHandleVariant,
        TagShorthand,
        booleanTag,
        floatTag,
        integerTag,
        mappingTag,
        nullTag,
        resolvedTagInfo,
        sequenceTag,
        stringTag,
        throwIfNotListTag,
        throwIfNotMapTag,
        throwIfNotScalarTag;

mixin _Decomposer {
  /// Anchors in the document.
  final _anchors = <String>{};

  /// Global tags.
  final _globalTags = <TagHandle, GlobalTag>{};

  String? _pushAnchor(String? anchor) {
    if (anchor != null) _anchors.add(anchor);
    return anchor;
  }

  /// Unpacks a resolved [nodeTag] and returns the verbatim/local tag associated
  /// with the node.
  ///
  /// If [includeGeneric] is `true`, generic
  String? _localTag(
    ResolvedTag? nodeTag, {
    required void Function(TagShorthand tag) validate,
    bool includeGeneric = false,
  }) {
    if (nodeTag == null || (!includeGeneric && nodeTag.isGeneric)) return null;
    final (:verbatim, :globalTag, :tag) = resolvedTagInfo(nodeTag);

    // Cannot have verbatim and global/local tag.
    if (verbatim != null) return verbatim;

    var namedHasGlobal = false;

    if (globalTag != null) {
      final globalHandle = globalTag.tagHandle;

      // A global tag is like a anchor URI for a local tag's handle which acts
      // as the alias.
      if (globalHandle != tag?.tagHandle) {
        throw FormatException(
          '''
Global tag handle doesn't match local tag handle.
  Global tag handle: ${globalTag.tagHandle}
  Local tag handle: ${tag?.tagHandle}
''',
        );
      }

      final existing = _globalTags.putIfAbsent(globalHandle, () => globalTag);

      // Multiple global tags cannot alias the same handle multiple times in the
      // same document.
      if (existing != globalTag) {
        throw FormatException(
          '''
A global tag with the current tag handle already exists.
  Existing: $existing
  Update: $globalTag
''',
        );
      }

      namedHasGlobal = true;
    }

    if (tag == null) return null;

    validate(tag);

    // Ensure our named handle has a global tag.
    if (tag.tagHandle.handleVariant == TagHandleVariant.named &&
        !namedHasGlobal) {
      throw FormatException(
        'The named local tag "$tag" has no global tag for its named handle',
      );
    }

    return tag.toString();
  }

  /// Matches the [object] to its YAML Schema tag only if [includeGeneric] is
  /// `true`.
  String? _genericIfMissing(Object? object, {bool includeGeneric = false}) {
    if (!includeGeneric) return null;

    return switch (object) {
      Iterable() => /* object is Set ? setTag : */ sequenceTag,
      Map() => mappingTag,
      int() => integerTag,
      double() => floatTag,
      String() => stringTag,
      bool() => booleanTag,
      null => nullTag,
      _ => null,
    }?.toString();
  }
}

final class EventTreeBuilder with _Decomposer, DartTypeVisitor, ViewVisitor {
  /// Global stack for pushing any built nodes.
  final _nodes = ListQueue<EventTreeNode<Object>>();

  /// Number of nodes currently in the internal build queue.
  int get stackSize => _nodes.length;

  /// Global stack with the current collection's [NodeStyle].
  final _collectionStyles = ListQueue<NodeStyle>();

  /// Path to the current node.
  final _currentPath = ListQueue<String>();

  /// Throws a [StateError] with the [message] and includes the [_currentPath].
  Never _stateErrorWithPath(String message) =>
      _stateError('$message\n\tPath: ${_currentPath.join('/')}');

  /// Throws a [StateError] with the [message].
  Never _stateError(String message) => throw StateError(message);

  /// Adds the [node] to the LIFO queue.
  void _addNode(EventTreeNode<Object> node) => _nodes.add(node);

  /// Nearest collection's [NodeStyle].
  NodeStyle? _nearestCollection() => _collectionStyles.lastOrNull;

  /// Style for a built-in Dart list or map. // TODO: Add config
  NodeStyle _genericStyle() => _nearestCollection() ?? NodeStyle.block;

  /// Whether the current [style] is compatible with the [parent]'s style.
  ///
  /// If [parent] is `null`, this method looks for the last collection's
  /// [NodeStyle] it encountered.
  bool _buildWithStyle(NodeStyle style, [NodeStyle? parent]) =>
      !((parent ?? _nearestCollection())?.isIncompatible(style) ?? false);

  @override
  void visitObject(Object? object) => switch (object) {
    DumpableView() => visitView(object),
    _ => super.visitObject(object),
  };

  @override
  void visitAlias(Alias alias) {
    if (_nodes.isEmpty) {
      throw StateError('An alias cannot be the root of the document');
    }

    final ref = alias.alias;

    if (_anchors.contains(ref)) {
      return _addNode(ReferenceNode(ref, comments: alias.comments));
    }

    _stateErrorWithPath('Unknown alias "$ref"');
  }

  @override
  void visitIterable(Iterable<Object?> iterable) {
    // TODO: Recursive support when?
    _buildIterable(
      iterable,
      style: _genericStyle(),
      localTag: sequenceTag.toString(), // TODO: Add includeGeneric config
    );
  }

  @override
  void visitIterableView(YamlIterable iterable) {
    final YamlIterable(:comments, :anchor, :tag, :forceInline, :nodeStyle) =
        iterable;

    _buildIterable(
      iterable.toFormat(iterable.node),
      style: nodeStyle,
      forceInline: forceInline,
      comments: comments,
      anchor: _pushAnchor(anchor),
      localTag: _localTag(tag, validate: throwIfNotListTag),
    );
  }

  @override
  void visitMap(Map<Object?, Object?> map) {
    // TODO: Recursive support when?
    _buildMap(
      map.entries,
      style: _genericStyle(),
      localTag: mappingTag.toString(), // TODO: Add includeGeneric config
    );
  }

  @override
  void visitMappingView(YamlMapping mapping) {
    final YamlMapping(:comments, :anchor, :tag, :forceInline, :nodeStyle) =
        mapping;

    _buildMap(
      mapping.toFormat(mapping.node),
      style: nodeStyle,
      forceInline: forceInline,
      comments: comments,
      anchor: _pushAnchor(anchor),
      localTag: _localTag(tag, validate: throwIfNotMapTag),
    );
  }

  @override
  void visitScalar(Object? scalar) {
    _buildScalar(
      scalar?.toString() ?? '',
      scalarStyle: classicScalarStyle, // TODO: Add config
      localTag: _genericIfMissing(scalar),
    );
  }

  @override
  void visitScalarView(ScalarView scalar) {
    final ScalarView(:comments, :anchor, :tag, :forceInline, :scalarStyle) =
        scalar;

    _buildScalar(
      scalar.toFormat(scalar.node),
      scalarStyle: scalarStyle,
      forceInline: forceInline,
      comments: comments,
      anchor: _pushAnchor(anchor),
      localTag: _localTag(tag, validate: throwIfNotScalarTag),
    );
  }

  /// Root node of the tree.
  ///
  /// Always throws if [buildFor] was never called at least once.
  EventTreeNode<Object> builtNode<T>() => _nodes.first;

  /// Builds an event tree for an [object].
  ///
  /// The builder expects the [object] to be a built-in Dart type or a
  /// [DumpableView] of any Dart object.
  void buildFor(Object? object) {
    _nodes.clear();
    if (object is DumpableView) return visitView(object);
    visitObject(object);
  }

  void _buildScalar(
    String scalar, {
    required ScalarStyle scalarStyle,
    bool forceInline = false, // TODO: Add to config
    bool emptyAsNull = false, // TODO: Move to formatter
    List<String>? comments,
    String? anchor,
    String? localTag,
  }) {
    final collectionStyle = _nearestCollection();
    final dumpingStyle = _buildWithStyle(scalarStyle.nodeStyle, collectionStyle)
        ? scalarStyle
        : classicScalarStyle;

    final (:isMultiline, :lines, :useParentIndent) = splitScalar(
      scalar,
      style: dumpingStyle,
      emptyAsNull: emptyAsNull, // TODO: Move to formatter
      forceInline: forceInline,

      // It's okay if this is the top level node. By YAML standards, it is.
      parentIsBlock: collectionStyle?.isBlock ?? true,
    );

    _addNode(
      ContentNode(
        lines,
        dumpingStyle.nodeStyle,
        inheritParentIndent: useParentIndent,
        isMultiline: isMultiline,
        comments: comments,
        anchor: anchor,
        localTag: localTag,
      ),
    );
  }

  void _buildIterable(
    YamlIterableEntry iterable, {
    required NodeStyle style,
    bool forceInline = false, // TODO: Add to config
    List<String>? comments,
    String? anchor,
    String? localTag,
  }) => _buildCollection(
    iterable,
    style: style,
    nodeType: NodeType.list,
    iterate: visitObject,
    compose: () {
      // One in, one out
      final element = _nodes.removeLast();
      return (element.isMultiline, element);
    },
    forceInline: forceInline,
    comments: comments,
    anchor: anchor,
    localTag: localTag,
  );

  void _buildMap(
    YamlMappingEntry iterable, {
    required NodeStyle style,
    bool forceInline = false, // TODO: Add to config
    List<String>? comments,
    String? anchor,
    String? localTag,
  }) => _buildCollection(
    iterable,
    style: style,
    nodeType: NodeType.map,
    iterate: (element) {
      visitObject(element.key);
      visitObject(element.value);
    },
    compose: () {
      // Two in, two out
      final value = _nodes.removeLast();
      final key = _nodes.removeLast();
      return (key.isMultiline || value.isMultiline, (key, value));
    },
    forceInline: forceInline,
    comments: comments,
    anchor: anchor,
    localTag: localTag,
  );

  void _buildCollection<E, T>(
    Iterable<E> iterable, {
    required NodeStyle style,
    required NodeType nodeType,
    required void Function(E element) iterate,
    required (bool isMultiline, T value) Function() compose,
    required bool forceInline,
    required List<String>? comments,
    required String? anchor,
    required String? localTag,
  }) {
    final parent = _nearestCollection();
    final buildStyle = _buildWithStyle(style, parent) ? style : parent!;
    _collectionStyles.addLast(buildStyle);

    var spanMultipleLines = buildStyle.isBlock || !forceInline;

    void update(bool isMultiline) {
      if (forceInline) return;
      spanMultipleLines = spanMultipleLines || isMultiline;
    }

    final queue = ListQueue<T>();

    for (final element in iterable) {
      iterate(element);
      final (isMultiline, node) = compose();
      update(isMultiline);
      queue.addLast(node);
    }

    _addNode(
      CollectionNode(
        queue,
        buildStyle,
        nodeType: nodeType,
        isMultiline: spanMultipleLines && queue.isNotEmpty,
        anchor: anchor,
        localTag: localTag,
        comments: comments,
      ),
    );

    _collectionStyles.removeLast();
  }
}
