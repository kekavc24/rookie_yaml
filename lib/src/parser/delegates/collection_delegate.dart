part of 'parser_delegate.dart';

ScalarDelegate nullScalarDelegate({
  required int indentLevel,
  required int indent,
  required RuneOffset startOffset,
}) => ScalarDelegate(
  indentLevel: indentLevel,
  indent: indent,
  start: startOffset,
);

bool _isMapTag(TagShorthand tag) =>
    tag != sequenceTag && !scalarTags.contains(tag);

NodeTag _defaultTo(TagShorthand tag) => NodeTag(yamlGlobalTag, tag);

/// A delegate that represents a single key-value pair within a flow/block
/// [Sequence]
final class MapEntryDelegate extends ParserDelegate {
  MapEntryDelegate({
    required this.nodeStyle,
    required this.keyDelegate,
  }) : super(
         indent: keyDelegate.indent,
         indentLevel: keyDelegate.indentLevel,
         start: keyDelegate.start,
       ) {
    hasLineBreak = keyDelegate.encounteredLineBreak;
    updateEndOffset = keyDelegate._end;
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
    updateEndOffset = value._end;
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
  Mapping _resolveNode<T>() => Mapping.strict(
    {keyDelegate.parsed(): _valueDelegate?.parsed()},
    nodeStyle: nodeStyle,
    tag: _tag ?? _defaultTo(mappingTag),
    anchor: _anchor,
    nodeSpan: (start: start, end: _end!),
  );

  @override
  NodeTag _checkResolvedTag(NodeTag tag) {
    final NodeTag(:suffix) = tag;

    if (!_isMapTag(suffix)) {
      throw FormatException(
        'A mapping entry cannot be resolved as "$suffix" kind',
      );
    }

    return _overrideNonSpecific(tag, mappingTag);
  }
}

/// A collection delegate
abstract base class CollectionDelegate extends ParserDelegate {
  CollectionDelegate({
    required this.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
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
    required super.start,
  });

  /// Node delegates that resolve to nodes that are elements of the sequence.
  final List<YamlSourceNode> _nodes = [];

  void pushEntry(ParserDelegate entry) {
    _firstEntry ??= entry;
    hasLineBreak = entry._hasLineBreak;
    _nodes.add(entry.parsed());
  }

  /// Returns a [Sequence]
  @override
  Sequence _resolveNode<T>() => Sequence(
    _nodes,
    nodeStyle: collectionStyle,
    tag: _tag ?? _defaultTo(sequenceTag),
    anchor: _anchor,
    nodeSpan: (start: start, end: _end!),
  );

  @override
  NodeTag _checkResolvedTag(NodeTag tag) {
    final NodeTag(:suffix) = tag;

    if (suffix == mappingTag || scalarTags.contains(suffix)) {
      throw FormatException('A sequence cannot be resolved as "$suffix" kind');
    }

    return _overrideNonSpecific(tag, sequenceTag);
  }
}

/// A delegate that resolves to a [Mapping]
final class MappingDelegate extends CollectionDelegate {
  MappingDelegate({
    required super.collectionStyle,
    required super.indentLevel,
    required super.indent,
    required super.start,
  });

  /// A map that is resolved as a key is added
  final _map = <YamlSourceNode, YamlSourceNode?>{};

  /// Returns `true` if the [entry] is added. Otherwise, `false`.
  bool pushEntry(ParserDelegate key, ParserDelegate? value) {
    _firstEntry ??= key;
    final keyNode = key.parsed();

    // A key must not occur more than once.
    if (_map.containsKey(keyNode)) {
      return false;
    }

    _map[keyNode] = value?.parsed();
    hasLineBreak = key._hasLineBreak || (value?._hasLineBreak ?? false);
    return true;
  }

  /// Returns a [Mapping].
  @override
  Mapping _resolveNode<T>() => Mapping.strict(
    _map,
    nodeStyle: collectionStyle,
    tag: _tag ?? _defaultTo(mappingTag),
    anchor: _anchor,
    nodeSpan: (start: start, end: _end!),
  );

  @override
  NodeTag _checkResolvedTag(NodeTag tag) {
    final NodeTag(:suffix) = tag;

    if (!_isMapTag(suffix)) {
      throw FormatException('A mapping cannot be resolved as "$suffix" kind');
    }

    return _overrideNonSpecific(tag, mappingTag);
  }
}
