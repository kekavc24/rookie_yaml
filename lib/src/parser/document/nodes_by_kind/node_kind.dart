import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Represents the kind of node to be parsed.
sealed class NodeKind {
  NodeKind();

  /// Creates a node whose kind could not be determined.
  factory NodeKind.unknown() = _UnknownKind;

  /// Whether an object's kind was inferred from its tag.
  bool get isKnown => false;
}

/// A node without a tag or with a tag whose kind cannot be ascertained.
final class _UnknownKind extends NodeKind {}

/// Represents a node with a custom tag.
enum CustomKind implements NodeKind {
  /// Custom map-like structure that accepts keys.
  map,

  /// Custom iterable that accepts elements.
  iterable,

  /// A custom object that is not a [CustomKind.map] or [CustomKind.iterable].
  scalar;

  @override
  bool get isKnown => true;
}

/// Represents a node with(out) a tag.
enum YamlKind implements NodeKind {
  /// [Scalar].
  scalar,

  /// [Set] or [Sequence] with unique elements. This could also represent a
  /// [YamlKind.orderedMap] or [YamlKind.mapping].
  set,

  /// Normal [Sequence] or [List].
  sequence,

  /// [YamlKind.mapping] or a [Sequence]/[List] of [YamlKind.mapping].
  orderedMap,

  /// [Mapping] or [Map].
  mapping;

  @override
  bool get isKnown => true;
}

/// Parses a node based on its [kind].
///
/// This is a template for both block and flow nodes which can choose a quick
/// parsing path when a [NodeKind] was inferred from its resolved tag.
///
/// [sequenceOnMatchSetOrOrderedMap] callback returns a `bool` because a set
/// or ordered map can be parsed as a sequence or mapping.
T parseNodeOfKind<T>(
  NodeKind kind, {
  required bool Function() sequenceOnMatchSetOrOrderedMap,
  required T Function() onMatchMapping,
  required T Function() onMatchSequence,
  required T Function() onMatchScalar,
  required T Function() defaultFallback,
}) {
  switch (kind) {
    case YamlKind.set || YamlKind.orderedMap:
      {
        if (sequenceOnMatchSetOrOrderedMap()) {
          continue sequence;
        }

        continue mapping;
      }

    mapping:
    case YamlKind.mapping:
      return onMatchMapping();

    sequence:
    case YamlKind.sequence:
      return onMatchSequence();

    case YamlKind.scalar:
      return onMatchScalar();

    default:
      return defaultFallback();
  }
}
