import 'package:rookie_yaml/src/parser/delegates/parser_delegate.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/nodes_by_kind/node_kind.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Callback for creating a [ContentResolver] tag.
typedef ResolverCreator = ContentResolver Function(NodeTag tag);

/// A resolver for a [Scalar]. The type emitted by this resolver lives within
/// the scalar itself or acts as the type inferred when directly parsed as a
/// `Dart` object.
///
/// Unlike a [ObjectFromScalarBytes], this resolver allows the parser to recover
/// if the type could not be assigned.
final class ScalarResolver<O> {
  ScalarResolver._(this.target, this.onTarget);

  /// A suffix associated with a local tag with any [TagHandle].
  final TagShorthand target;

  /// Creates a resolver tag.
  final ResolverCreator onTarget;

  /// Creates a resolver that only resolves a scalar's content after the parser
  /// has buffered the content as a string.
  ///
  /// The [contentResolver] must return `null` if the type cannot be assigned
  /// thus allowing the parser to partially represent it as a string. If
  /// [acceptNullAsValue] is `true`, the null returned will be treated as value.
  ///
  /// A [toYamlSafe] is required if the scalar is a [YamlSourceNode] and not a
  /// `Dart` object.
  ScalarResolver.onMatch(
    TagShorthand tag, {
    required O? Function(String input) contentResolver,
    required String Function(O input) toYamlSafe,
    bool acceptNullAsValue = false,
  }) : this._(
         tag,
         (nodeTag) => ContentResolver(
           nodeTag,
           resolver: contentResolver,
           toYamlSafe: (s) => toYamlSafe(s as O),
           acceptNullAsValue: acceptNullAsValue,
         ),
       );
}

/// Template callback for an object [T] using a parsing delegate [D] with a
/// node style [S].
typedef OnObject<S, T, D extends ParserDelegate<T>> =
    D Function(
      S nodeStyle,
      int indentLevel,
      int indent,
      RuneOffset start,
    );

/// Template callback that returns [T] from a collection-like delegate of
/// subtype [D].
typedef OnCollection<T, D extends ParserDelegate<T>> =
    OnObject<NodeStyle, T, D>;

/// Callback that creates a [MapToObjectDelegate].
typedef OnCustomMap<T> = OnCollection<T, MapToObjectDelegate<T>>;

/// Callback that creates a [IterableToObjectDelegate].
typedef OnCustomList<T> = OnCollection<T, IterableToObjectDelegate<T>>;

/// Callback that creates a [ScalarLikeDelegate].
typedef OnCustomScalar<T> = OnObject<ScalarStyle, T, BytesToScalar<T>>;

/// A resolver for any `Dart` object dumped as YAML.
///
/// {@category resolvers}
sealed class CustomResolver {
  CustomResolver();

  /// [NodeKind] represent by this resolver.
  CustomKind get kind;
}

/// A resolver that creates a delegate that accepts a key-value pair.
///
/// {@category resolvers}
final class ObjectFromMap<T> extends CustomResolver {
  /// Creates a resolver that lazily instantiates a [ParserDelegate] which
  /// behaves like a map and accepts a key-value pair. Resolves to an object of
  /// type [T].
  ObjectFromMap({required this.onCustomMap});

  /// A callback used to instatiate a delegate when a matching [TagShorthand] is
  /// encountered.
  final OnCustomMap<T> onCustomMap;

  @override
  CustomKind get kind => CustomKind.map;
}

/// A resolver that creates a delegate that accepts elements.
///
/// {@category resolvers}
final class ObjectFromIterable<T> extends CustomResolver {
  /// Creates a resolver that lazily instantiates a [ParserDelegate] which
  /// behaves like an iterable and accepts elements. Resolves to an object of
  /// type [T].
  ObjectFromIterable({required this.onCustomIterable});

  /// A callback used to instatiate a delegate when a matching [TagShorthand] is
  /// encountered.
  final OnCustomList<T> onCustomIterable;

  @override
  CustomKind get kind => CustomKind.iterable;
}

/// A resolver that creates a delegate which accepts the bytes/code units
/// representing a scalar.
///
/// Creating an [ObjectFromScalarBytes] resolver allows you to directly manage
/// what happens to the bytes the parser deems as valid content in a scalar.
/// Under the hood, the parser still abides by the spec but your
/// [ScalarLikeDelegate] must maintain a buffer or some kind of logic that will
/// emit your final custom type [T] since the parser will only call the `parsed`
/// method you override when implementing your own delegate.
///
/// Consider using a [ScalarResolver] which allows the parser itself to resolve
/// the parsed string if this seems too mechanical.
///
/// {@category resolvers}
final class ObjectFromScalarBytes<T> extends CustomResolver {
  /// Creates a resolver that lazily instantiates a [ParserDelegate] which
  /// behaves like a scalar and accepts bytes/ utf code units and resolves to an
  /// object of type [T].
  ObjectFromScalarBytes({required this.onCustomScalar});

  /// A callback used to instatiate a delegate when a matching [TagShorthand] is
  /// encountered.
  final OnCustomScalar<T> onCustomScalar;

  @override
  CustomKind get kind => CustomKind.scalar;
}
