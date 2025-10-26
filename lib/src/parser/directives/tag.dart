part of 'directives.dart';

/// Describes the kind of native data structure represented by a `YAML` node.
///
/// {@category tags}
sealed class Tag {
  /// Prefix of the tag
  TagHandle get tagHandle;

  /// Actual prefix of the tag. This should not be confused with the
  /// [tagHandle] which describes a compact way of representing the prefix. For
  /// a [GlobalTag] or a [TagShorthand] resolved to a [GlobalTag], this is the
  /// full prefix aliased by the [tagHandle]. For an unresolved [TagShorthand],
  /// this defaults to its [tagHandle].
  String get prefix;
}

/// Represents any [Tag] resolved to a [GlobalTag] prefix or declared in
/// verbatim as a [VerbatimTag]
///
/// {@category tag_types}
/// {@category declare_tags}
/// {@category resolvers}
sealed class ResolvedTag extends Tag {
  /// Represents the [TagShorthand] suffix resolved to [GlobalTag] prefix in a
  /// `YAML` source string. Defaults to `null` if the [Tag] is a [VerbatimTag]
  /// or a [TypeResolverTag]
  TagShorthand? get suffix => null;

  /// Full representation of a tag. Any [SpecificTag] can be represented this
  /// way even if it is unresolved.
  ///
  /// ```yaml
  /// !<tag:yaml.org,2002:str> # Global Tag for strings
  /// !<!foo> # Local Tag
  /// ```
  String get verbatim;
}

/// Represents a [Tag] that can be represented as a [GlobalTag] or
/// [TagShorthand]. `YAML` requires a parsed node to be resolved as a
/// [SpecificTag] or be represented as is as a [VerbatimTag].
///
/// {@category tag_types}
/// {@category declare_tags}
sealed class SpecificTag<T> extends Tag {
  SpecificTag._(this.tagHandle, this.content);

  SpecificTag.fromTagShorthand(TagHandle tagHandle, TagShorthand tag)
    : this._(tagHandle, tag as T);

  SpecificTag.fromString(TagHandle tagHandle, String uri)
    : this._(tagHandle, uri as T);

  @override
  final TagHandle tagHandle;

  final T content;
}

/// Extracts a resolved [tag]'s information.
///
/// By default for a normal [NodeTag], a [TagShorthand] suffix is returned and
/// optionally its [GlobalTag] prefix if present.
///
/// A [VerbatimTag] is returned in verbatim as a string and a
/// [TypeResolverTag]'s [NodeTag] is extracted.
({GlobalTag<dynamic>? globalTag, TagShorthand? tag, String? verbatim})
resolvedTagInfo(ResolvedTag tag) {
  if (tag is VerbatimTag) {
    return (globalTag: null, tag: null, verbatim: tag.verbatim);
  }

  final nodeTag = switch (tag) {
    TypeResolverTag(:final resolvedTag) => resolvedTag,
    _ => tag as NodeTag,
  };

  final NodeTag(:resolvedTag, :suffix) = nodeTag;

  return (
    globalTag: resolvedTag == suffix ? null : resolvedTag as GlobalTag<dynamic>,
    tag: suffix,
    verbatim: null,
  );
}
