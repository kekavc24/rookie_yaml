import 'package:rookie_yaml/src/parser/delegates/one_pass_scalars/efficient_scalar_delegate.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Represents the kind of node to be parsed.
///
/// {@category custom_resolvers_intro}
sealed class NodeKind {
  NodeKind();

  /// Represents a node whose kind could not be determined.
  factory NodeKind.unknown() = _UnknownKind;

  /// Represents a node with a non-specific tag whose kind will be determined
  /// by the parser.
  factory NodeKind.generic() = _GenericKind;

  /// Whether an object's kind was inferred from its tag.
  bool get isKnown => false;

  /// Whether an object will be inferred as !!map or !!seq or !!str only when
  /// the tag is non-specific.
  bool get isGeneric => false;
}

/// A node without a tag or with a tag whose kind cannot be ascertained.
final class _UnknownKind extends NodeKind {}

/// A node resolved to the generic map/sequence/string when the local tag
/// is non-specific.
///
/// ```yaml
/// ! { ! scalar: ! [ sequence ] }
/// ```
final class _GenericKind extends NodeKind {
  @override
  bool get isGeneric => true;
}

/// Represents a node with a custom tag.
///
/// {@category custom_resolvers_intro}
enum CustomKind implements NodeKind {
  /// Custom map-like structure that accepts keys.
  map,

  /// Custom iterable that accepts elements.
  iterable,

  /// A custom object that is not a [CustomKind.map] or [CustomKind.iterable].
  scalar;

  @override
  bool get isKnown => true;

  @override
  bool get isGeneric => false;
}

/// Represents a node with(out) a tag that contains other nodes.
///
/// {@category custom_resolvers_intro}
enum YamlCollectionKind implements NodeKind {
  /// [Set] or [Sequence] with unique elements. This could also represent a
  /// [YamlCollectionKind.orderedMap] or [YamlCollectionKind.mapping].
  set,

  /// Normal [Sequence] or [List].
  sequence,

  /// [YamlCollectionKind.mapping] or a [Sequence]/[List] of
  /// [YamlCollectionKind.mapping].
  orderedMap,

  /// [Mapping] or [Map].
  mapping;

  @override
  bool get isKnown => true;

  @override
  bool get isGeneric => false;
}

/// Represents any node with a scalar tag.
///
/// {@category custom_resolvers_intro}
enum YamlScalarKind implements NodeKind {
  /// [String].
  string,

  /// [String] that is mapped to a type after it has been buffered.
  stringToType,

  /// [Null].
  nullString,

  /// [bool].
  booleanString,

  /// [int].
  integer,

  /// [double].
  float;

  @override
  bool get isKnown => true;

  @override
  bool get isGeneric => false;
}

/// Callback that creates a low level delegate that eagerly parsed a
/// [YamlScalarKind].
typedef DelegatedValue = ScalarValueDelegate<Object?> Function();

/// Maps a scalar [kind] to its `BytesToScalar` delegate and creates the
/// callback.
DelegatedValue scalarImpls(YamlScalarKind kind) => switch (kind) {
  YamlScalarKind.nullString => () => LazyType.forNull(),
  YamlScalarKind.booleanString => () => LazyType.boolean(),
  YamlScalarKind.integer => () => RecoverableDelegate.forInt(),
  YamlScalarKind.float => () => LazyType.float(),
  _ => () => StringDelegate(),
};

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
  required T Function(YamlScalarKind kind) onMatchScalar,
  required T Function() defaultFallback,
}) {
  switch (kind) {
    case YamlCollectionKind.set || YamlCollectionKind.orderedMap:
      {
        if (sequenceOnMatchSetOrOrderedMap()) {
          continue sequence;
        }

        continue mapping;
      }

    mapping:
    case YamlCollectionKind.mapping:
      return onMatchMapping();

    sequence:
    case YamlCollectionKind.sequence:
      return onMatchSequence();

    case YamlScalarKind _:
      return onMatchScalar(kind);

    default:
      return defaultFallback();
  }
}
