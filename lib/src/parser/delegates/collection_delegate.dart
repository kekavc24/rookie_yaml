part of 'parser_delegate.dart';

final _bareScalar = Scalar(
  null,
  content: '',
  scalarStyle: ScalarStyle.plain,
  tags: {},
  anchors: {},
);

ScalarDelegate nullScalarDelegate({
  required int indentLevel,
  required int indent,
}) => ScalarDelegate(
  indentLevel: indentLevel,
  indent: indent,
  startOffset: -1,
  blockTags: {},
  inlineTags: {},
  blockAnchors: {},
  inlineAnchors: {},
);

/// A delegate that represents a single key-value pair within a flow/block
/// [Sequence]
final class MapEntryDelegate extends ParserDelegate {
  MapEntryDelegate({
    required this.nodeStyle,
    required this.keyDelegate,
    this.valueDelegate,
  }) : super(
         indent: keyDelegate.indent,
         indentLevel: keyDelegate.indentLevel,
         startOffset: keyDelegate.startOffset,
         blockTags: {}, // Set.from(keyDelegate.blockTags),
         inlineTags: {},
         blockAnchors: {}, // Set.from(keyDelegate.blockAnchors),
         inlineAnchors: {},
       );

  final NodeStyle nodeStyle;

  /// Key delegate that qualifies this entry as a key in a map
  final ParserDelegate keyDelegate;

  /// Optional value delegate.
  ///
  /// `YAML` allows for keys to be specified alone with no value in maps.
  ParserDelegate? valueDelegate;

  @override
  bool isChild(int indent) =>
      indent > this.indent || (valueDelegate?.indent ?? -1) == indent;

  /// Usually returns a [Mapping].
  ///
  /// This will rarely be called, but if so, this must a return a mapping with
  /// only a single value. A key must exist.
  @override
  Node _resolveNode() => Mapping(
    {keyDelegate.parsed(): valueDelegate?.parsed() ?? _bareScalar},
    nodeStyle: nodeStyle,
    tags: tags(),
    anchors: anchors(),
  );
}

/// A collection delegate
abstract base class CollectionDelegate extends ParserDelegate {
  CollectionDelegate({
    required this.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.startOffset,
    required super.blockTags,
    required super.inlineTags,
    required super.blockAnchors,
    required super.inlineAnchors,
  });

  /// Collection style
  final NodeStyle collectionStyle;

  /// First element in collection. Determines the indent & indent level of
  /// its siblings.
  ParserDelegate? _firstEntry;

  @override
  int get indent => _firstEntry?.indent ?? super.indent;

  bool get isEmpty => _firstEntry == null;

  @override
  bool isChild(int indent) {
    return (isEmpty && indent >= this.indent) ||
        (!isEmpty && _firstEntry!.isSibling(indent));
  }
}

/// A delegate that resolves to a [Sequence]
final class SequenceDelegate extends CollectionDelegate {
  SequenceDelegate({
    required super.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.startOffset,
    required super.blockTags,
    required super.inlineTags,
    required super.blockAnchors,
    required super.inlineAnchors,
  });

  /// Node delegates that resolve to nodes that are elements of the sequence.
  final List<Node> _nodes = [];

  void pushEntry(ParserDelegate entry) {
    _firstEntry ??= entry;
    _hasLineBreak = entry._hasLineBreak;

    _nodes.add(entry.parsed());
  }

  /// Returns a [Sequence]
  @override
  Node _resolveNode() => Sequence(
    _nodes,
    nodeStyle: collectionStyle,
    tags: tags(),
    anchors: anchors(),
  );
}

/// A delegate that resolves to a [Mapping]
final class MappingDelegate extends CollectionDelegate {
  MappingDelegate({
    required super.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.startOffset,
    required super.blockTags,
    required super.inlineTags,
    required super.blockAnchors,
    required super.inlineAnchors,
  });

  /// A map that is resolved as a key is added
  final _map = <Node, Node>{};

  /// Returns `true` if the [entry] is added. Otherwise, `false`.
  bool pushEntry(ParserDelegate key, ParserDelegate? value) {
    _firstEntry ??= key;
    final keyNode = key.parsed();

    // A key must not occur more than once.
    if (_map.containsKey(keyNode)) {
      return false;
    }

    _map[keyNode] = value?.parsed() ?? _bareScalar;
    _hasLineBreak = key._hasLineBreak || (value?._hasLineBreak ?? false);
    return true;
  }

  /// Returns a [Mapping].
  @override
  Node _resolveNode() => Mapping(
    _map,
    nodeStyle: collectionStyle,
    tags: tags(),
    anchors: anchors(),
  );
}
