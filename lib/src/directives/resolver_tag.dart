part of 'directives.dart';

/// A tag that wraps a [NodeTag] and defines a mapping function for any
/// node annotated with the tag.
sealed class TypeResolverTag<I, O> extends ResolvedTag {
  TypeResolverTag(this.resolvedTag, {required this.resolver});

  /// Underlying [NodeTag]
  final NodeTag resolvedTag;

  /// Mapping function
  final O Function(I input) resolver;

  @override
  String get prefix => resolvedTag.prefix;

  @override
  TagHandle get tagHandle => resolvedTag.tagHandle;

  @override
  String get verbatim => resolvedTag.verbatim;

  @override
  bool operator ==(Object other) => resolvedTag == other;

  @override
  int get hashCode => resolvedTag.hashCode;

  @override
  String toString() => verbatim;
}

/// Resolves a [ParsedYamlNode] on demand at a later time.
///
/// A [NodeResolver] works best with [Mapping] and [Sequence] nodes that are
/// a collection of values. For a [Scalar], the parsed content is left
/// untouched. This may prove problematic for scalars that are keys to a map and
/// depend on the parser's ability to infer a type to determine uniqueness. In
/// all other cases, it is fine!
///
/// Prefer declaring a [ContentResolver] for a [Scalar] which gives you total
/// control and allows the parser to determine its type if your custom
/// function cannot. Additionally, the value type will belong to the scalar
/// rather than having to call `asCustomType` method for a later resolution.
final class NodeResolver<O> extends TypeResolverTag<ParsedYamlNode, O> {
  NodeResolver(super.resolvedTag, {required super.resolver});
}

/// Resolves a [Scalar]'s parsed content and requires the function to return
/// `null` if mapping fails. This allows the parser to provide a (partial) kind.
/// Avoid throwing within the mapping function.
///
/// `NOTE:` This resolver will be ignored if the tag belongs to a [Mapping]
/// or [Sequence]
final class ContentResolver<O> extends TypeResolverTag<String, O?> {
  ContentResolver(
    super.resolvedTag, {
    required super.resolver,
    required this.toYamlSafe,
    this.acceptNullAsValue = false,
  });

  /// Maps the [O] object back to a dumpable string.
  final String Function(O object) toYamlSafe;

  /// Indicates if the `null` value after calling the [resolver] function
  /// should be treated as a value.
  final bool acceptNullAsValue;
}
