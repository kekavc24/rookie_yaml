part of 'directives.dart';

/// A tag that wraps a [ResolvedTag] and defines a mapping function for any
/// node annotated with the tag.
final class TypeResolverTag<T> implements ResolvedTag {
  TypeResolverTag(this._resolvedTag, {required this.resolver});

  /// Underlying [ResolvedTag]
  final ResolvedTag _resolvedTag;

  /// Function that generates
  final T Function(ParsedYamlNode node) resolver;

  @override
  String get prefix => _resolvedTag.prefix;

  @override
  TagHandle get tagHandle => _resolvedTag.tagHandle;

  @override
  String get verbatim => _resolvedTag.verbatim;

  @override
  bool operator ==(Object other) => _resolvedTag == other;

  @override
  int get hashCode => _resolvedTag.hashCode;

  @override
  String toString() => verbatim;
}
