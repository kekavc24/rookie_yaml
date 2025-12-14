part of 'directives.dart';

/// Resolves a [Scalar]'s parsed content and requires the function to return
/// `null` if mapping fails. This allows the parser to provide a (partial) kind.
/// Avoid throwing within the mapping function.
///
/// `NOTE:` This resolver will be ignored if the tag belongs to a [Mapping]
/// or [Sequence]
///
/// {@category tag_types}
/// {@category resolvers}
final class ContentResolver<O> extends ResolvedTag {
  ContentResolver(
    this.resolvedTag, {
    required this.resolver,
    required this.toYamlSafe,
    this.acceptNullAsValue = false,
  });

  /// Maps the scalar's content.
  final O? Function(String content) resolver;

  /// Maps the [O] object back to a dumpable string.
  final String Function(O object) toYamlSafe;

  /// Indicates if the `null` value after calling the [resolver] function
  /// should be treated as a value.
  final bool acceptNullAsValue;

  /// Underlying [NodeTag]
  final NodeTag resolvedTag;

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
