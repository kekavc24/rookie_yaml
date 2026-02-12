import 'dart:collection';

import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/node_properties.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_schema.dart';

/// Contains utility methods for editable maps and lists.
mixin _CollectionUtils<T extends YamlSourceNode> {
  /// Map/list collection.
  late final T _collection;

  YamlSourceNode? first;

  /// Whether the [_collection]'s first and last child were linked.
  var _resolved = false;

  /// Links the first and last child only if [_resolved] is `false`.
  void _resolve(
    int quickLength,
    ParsedProperty? property,
    TagShorthand ifNull,
  ) {
    if (_resolved) return;
    _resolved = true;

    if (quickLength > 1) {
      _createCyclicLink();
    }

    ResolvedTag? resolved;

    if (property case NodeProperty(:final ResolvedTag tag)) {
      resolved = tag is NodeTag ? overrideNonSpecific(tag, ifNull) : tag;
    }

    _resolveTag(resolved ?? NodeTag(yamlGlobalTag, suffix: ifNull));
  }

  /// Inserts the editable [child] and links it to the parent [_collection]
  /// and its preceding sibling.
  void _insertAndLinkChildren(YamlSourceNode child) {
    final children = _collection.children;

    if (first == null) {
      child.isCyclicRoot = true;
      first = child;
    } else {
      final before = children.last;
      before.siblingRight = child..siblingLeft = before;
    }

    children.add(child);
    child.parent = _collection;
  }

  /// Creates a cyclic link between the first and last child.
  void _createCyclicLink() {
    final first = _collection.children.first;
    final last = _collection.children.last;

    first.siblingLeft = last;
    last.siblingRight = first;
  }

  /// Sets the resolved [tag] to [T].
  @pragma('vm:prefer-inline')
  void _resolveTag(ResolvedTag tag);
}

/// A delegate for a transversable [Mapping].
final class YamlSourceMap
    extends MappingToObject<YamlSourceNode, YamlSourceNode, YamlSourceNode>
    with _CollectionUtils<Mapping> {
  YamlSourceMap() {
    _collection = Mapping(_actualMap);
  }

  /// Actual map with the generic objects.
  final _actualMap = LinkedHashMap<Object?, Object?>(
    equals: yamlCollectionEquality.equals,
    hashCode: yamlCollectionEquality.hash,
  );

  @override
  bool accept(YamlSourceNode key, YamlSourceNode? value) {
    final keyValue = key.node;

    if (_actualMap.containsKey(keyValue)) {
      return false;
    }

    _actualMap[keyValue] = value?.node;
    key.childOfKey = value;
    _insertAndLinkChildren(key);
    return true;
  }

  @override
  Mapping parsed() {
    _resolve(_actualMap.length, property, mappingTag);
    return _collection;
  }

  @override
  void _resolveTag(ResolvedTag tag) {
    throwIfNotMapTag(
      tag is ContentResolver ? tag.resolvedTag.suffix : tag.suffix!,
    );
    _collection.tag = tag;
  }
}

/// A delegate for a transversable [Sequence].
final class YamlSourceList
    extends SequenceToObject<YamlSourceNode, YamlSourceNode>
    with _CollectionUtils<Sequence> {
  YamlSourceList() {
    _collection = Sequence(_list);
  }

  /// Actual list with generic objects.
  final _list = <Object?>[];

  @override
  void accept(YamlSourceNode input) {
    _list.add(input.node);
    _insertAndLinkChildren(input);
  }

  @override
  Sequence parsed() {
    _resolve(_list.length, property, sequenceTag);
    return _collection;
  }

  @override
  void _resolveTag(ResolvedTag tag) {
    throwIfNotListTag(
      tag is ContentResolver ? tag.resolvedTag.suffix : tag.suffix!,
    );
    _collection.tag = tag;
  }
}
