part of 'directives.dart';

/// Describes the type of native data structure represented by a `YAML` node.
sealed class Tag {
  /// Prefix of the tag
  TagHandle get tagHandle;

  /// Actual prefix of the tag. This should not be confused with the
  /// [tagHandle] which describes a compact way of representing the prefix.
  ///
  /// For a [GlobalTag] or a [TagShorthand] resolved to a [GlobalTag], this is
  /// the full prefix aliased by the [tagHandle]. For an unresolved
  /// [TagShorthand], this defaults to its [tagHandle].
  String get prefix;
}

/// Represents any [Tag] resolved to a [GlobalTag] or declared in verbatim as
/// a [VerbatimTag]
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
sealed class SpecificTag<T> implements Tag {
  SpecificTag._(this.tagHandle, this.content);

  SpecificTag.fromTagShorthand(TagHandle tagHandle, TagShorthand tag)
    : this._(tagHandle, tag as T);

  SpecificTag.fromString(TagHandle tagHandle, String uri)
    : this._(tagHandle, uri as T);

  @override
  final TagHandle tagHandle;

  final T content;
}
