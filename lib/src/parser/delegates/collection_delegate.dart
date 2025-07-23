part of 'parser_delegate.dart';

final _bareScalar = Scalar(
  null,
  content: '',
  scalarStyle: ScalarStyle.plain,
  tag: null,
  anchor: null,
);

ScalarDelegate nullScalarDelegate({
  required int indentLevel,
  required int indent,
  required int startOffset,
  // TODO: Introduce tag & anchor
}) => ScalarDelegate(
  indentLevel: indentLevel,
  indent: indent,
  startOffset: -1,
);

/// A delegate that represents a single key-value pair within a flow/block
/// [Sequence]
final class MapEntryDelegate extends ParserDelegate {
  MapEntryDelegate({
    required this.nodeStyle,
    required this.keyDelegate,
  }) : super(
         indent: keyDelegate.indent,
         indentLevel: keyDelegate.indentLevel,
         startOffset: keyDelegate.startOffset,
       ) {
    hasLineBreak = keyDelegate.encounteredLineBreak;
    updateEndOffset = keyDelegate._endOffset;
  }

  final NodeStyle nodeStyle;

  /// Key delegate that qualifies this entry as a key in a map
  final ParserDelegate keyDelegate;

  /// Optional value delegate.
  ///
  /// `YAML` allows for keys to be specified alone with no value in maps.
  ParserDelegate? _valueDelegate;

  set updateValue(ParserDelegate? value) {
    if (value == null) return;

    hasLineBreak = value.encounteredLineBreak;
    updateEndOffset = value._endOffset;
    _valueDelegate = value;
  }

  @override
  bool isChild(int indent) =>
      indent > this.indent || (_valueDelegate?.indent ?? -1) == indent;

  /// Usually returns a [Mapping].
  ///
  /// This will rarely be called, but if so, this must a return a mapping with
  /// only a single value. A key must exist.
  @override
  Mapping _resolveNode() => Mapping(
    {keyDelegate.parsed(): _valueDelegate?.parsed() ?? _bareScalar},
    nodeStyle: nodeStyle,
    tag: _tag,
    anchor: _anchor,
  );
}

/// A collection delegate
abstract base class CollectionDelegate extends ParserDelegate {
  CollectionDelegate({
    required this.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.startOffset,
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
  });

  /// Node delegates that resolve to nodes that are elements of the sequence.
  final List<ParsedYamlNode> _nodes = [];

  void pushEntry(ParserDelegate entry) {
    _firstEntry ??= entry;
    hasLineBreak = entry._hasLineBreak;
    _nodes.add(entry.parsed());
  }

  /// Returns a [Sequence]
  @override
  Sequence _resolveNode() =>
      Sequence(_nodes, nodeStyle: collectionStyle, tag: _tag, anchor: _anchor);
}

/// A delegate that resolves to a [Mapping]
final class MappingDelegate extends CollectionDelegate {
  MappingDelegate({
    required super.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.startOffset,
  });

  /// A map that is resolved as a key is added
  final _map = <ParsedYamlNode, ParsedYamlNode>{};

  /// Returns `true` if the [entry] is added. Otherwise, `false`.
  bool pushEntry(ParserDelegate key, ParserDelegate? value) {
    _firstEntry ??= key;
    final keyNode = key.parsed();

    // A key must not occur more than once.
    if (_map.containsKey(keyNode)) {
      return false;
    }

    _map[keyNode] = value?.parsed() ?? _bareScalar;
    hasLineBreak = key._hasLineBreak || (value?._hasLineBreak ?? false);
    return true;
  }

  /// Returns a [Mapping].
  @override
  Mapping _resolveNode() =>
      Mapping(_map, nodeStyle: collectionStyle, tag: _tag, anchor: _anchor);
}
