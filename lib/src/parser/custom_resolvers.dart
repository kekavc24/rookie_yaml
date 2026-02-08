import 'package:rookie_yaml/src/parser/delegates/object_delegate.dart';
import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/document/nodes_by_kind/node_kind.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Callback for creating a [ContentResolver] tag.
typedef ResolverCreator<R> = ContentResolver<R> Function(NodeTag tag);

/// A resolver for a [Scalar]. The type emitted by this resolver lives within
/// the scalar itself or acts as the type inferred when directly parsed as a
/// `Dart` object.
///
/// Unlike a [ObjectFromScalarBytes], this resolver allows the parser to recover
/// if the type could not be assigned.
///
/// {@category scalar_resolvers}
final class ScalarResolver<O> {
  ScalarResolver._(this.target, this.onTarget);

  /// A suffix associated with a local tag with any [TagHandle].
  final TagShorthand target;

  /// Creates a resolver tag.
  final ResolverCreator<Object?> onTarget;

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

/// Template callback for an object [T] using a parsing delegate [D].
typedef OnObject<T, D extends ObjectDelegate<T>> = D Function();

/// Callback that creates a [MappingToObject].
typedef OnCustomMap<K, V, T> = OnObject<T, MappingToObject<K, V, T>>;

/// Callback that creates a [SequenceToObject].
typedef OnCustomList<E, T> = OnObject<T, SequenceToObject<E, T>>;

/// Callback that creates a [ScalarLikeDelegate].
typedef OnCustomScalar<T> = OnObject<T, BytesToScalar<T>>;

/// Called when a custom object [T] of style [S] has been completely parsed.
///
/// This allows external delegates to be treated like a [NodeDelegate] without
/// the tag-to-type resolution process by giving access to the node's styles.
///
/// Called only once.
typedef OnResolvedObject<S, T> =
    void Function(S style, T object, String? anchor, RuneSpan nodeSpan);

/// Called when a custom object from a [MappingToObject] or [SequenceToObject]
/// has been parsed completely.
///
/// This allows an external [MappingToObject] or [SequenceToObject] to be
/// treated like a qualified [NodeDelegate] to the parser without the
/// tag-to-type resolution process by giving access to the node's styles.
///
/// Called only once.
typedef AfterCollection<T> = OnResolvedObject<NodeStyle, T>;

/// Called when a custom object from a [ScalarLikeDelegate] has been parsed
/// completely.
///
/// This allows an external [BytesToScalar] to be  treated like a qualified
/// [EfficientScalarDelegate] to the parser without the tag-to-type resolution
/// process by giving access to the node's information.
///
/// Called only once.
typedef AfterScalar<T> = OnResolvedObject<ScalarStyle, T>;

/// A resolver for any `Dart` object dumped as YAML.
///
/// {@category resolvers_intro}
/// {@category custom_resolvers_intro}
sealed class CustomResolver<S, T> {
  CustomResolver(this._onResolvedObject);

  /// Called when the object is fully resolved at the parser level.
  final OnResolvedObject<S, T> _onResolvedObject;

  /// [NodeKind] represent by this resolver.
  CustomKind get kind;

  /// Callback for the parser once the object [R] is resolved.
  OnResolvedObject<Object, R> afterObject<R>() =>
      (style, object, anchor, nodeSpan) =>
          _onResolvedObject(style as S, object as T, anchor, nodeSpan);
}

/// A resolver that creates a delegate that accepts a key-value pair.
///
/// {@category mapping_to_obj}
final class ObjectFromMap<K, V, T> extends CustomResolver<NodeStyle, T> {
  /// Creates a resolver that lazily instantiates an [ObjectDelegate] which
  /// behaves like a map and accepts a key-value pair. Resolves to an object of
  /// type [T].
  ObjectFromMap({
    required this.onCustomMap,
    AfterCollection<T>? onParsed,
  }) : super(onParsed ?? ((_, type, _, _) {}));

  /// A callback used to instatiate a delegate when a matching [TagShorthand] is
  /// encountered.
  final OnCustomMap<K, V, T> onCustomMap;

  @override
  CustomKind get kind => CustomKind.map;
}

/// A resolver that creates a delegate that accepts elements.
///
/// {@category sequence_to_obj}
final class ObjectFromIterable<E, T> extends CustomResolver<NodeStyle, T> {
  /// Creates a resolver that lazily instantiates a [ObjectDelegate] which
  /// behaves like an iterable and accepts elements. Resolves to an object of
  /// type [T].
  ObjectFromIterable({
    required this.onCustomIterable,
    AfterCollection<T>? onParsed,
  }) : super(onParsed ?? ((_, type, _, _) {}));

  /// A callback used to instatiate a delegate when a matching [TagShorthand] is
  /// encountered.
  final OnCustomList<E, T> onCustomIterable;

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
/// {@category bytes_to_scalar}
final class ObjectFromScalarBytes<T> extends CustomResolver<ScalarStyle, T> {
  /// Creates a resolver that lazily instantiates a [ObjectDelegate] which
  /// behaves like a scalar and accepts bytes/ utf code units and resolves to an
  /// object of type [T].
  ///
  /// The parser will call [onParsed] only \***ONCE**\* when the scalar is done.
  /// Unlike the `onComplete` method provided by the [BytesToScalar] interface,
  /// this function will always be called once the scalar is complete even when
  /// no content is available.
  ObjectFromScalarBytes({
    required this.onCustomScalar,
    AfterScalar<T>? onParsed,
  }) : super(onParsed ?? ((_, type, _, _) {}));

  /// A callback used to instatiate a delegate when a matching [TagShorthand] is
  /// encountered.
  final OnCustomScalar<T> onCustomScalar;

  @override
  CustomKind get kind => CustomKind.scalar;
}
