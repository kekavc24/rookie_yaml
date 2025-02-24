part of 'directives.dart';

/// Describes the type of native data structure represented by a `YAML` node.
sealed class Tag {
  /// Prefix of the tag
  TagHandle get tagHandle;

  /// Actual prefix of the tag. This should not be confused with the
  /// [tagHandle] which describes a compact way of representing the prefix.
  ///
  /// That is, for [GlobalTag]s, this presents the full prefix aliased by the
  /// [tagHandle]. [LocalTag]s, on the other hand, are normally (not) resolved
  /// to [GlobalTag]s and thus their [prefix] is just a [tagHandle].
  String get prefix;
}

/// Represents any [Tag] resolved to a [GlobalTag] or declared in verbatim as
/// a [VerbatimTag]
sealed class ResolvedTag extends Tag {
  /// Full representation of a tag.
  ///
  /// Example: `!<tag:yaml.org,2002:str>` for a string's [GlobalTag].
  /// `!<!foo>` for any (un)resolved [LocalTag].
  String get verbatim;
}

/// Represents a [Tag] that can be represented as a [GlobalTag] or [LocalTag].
/// `YAML` requires that after parsing a node must either be resolved to a
/// [SpecificTag] or be represented as is as a [VerbatimTag].
sealed class SpecificTag<T> implements Tag {
  SpecificTag._(this.tagHandle, this._content);

  SpecificTag.fromLocalTag(TagHandle tagHandle, LocalTag tag)
    : this._(tagHandle, tag as T);

  SpecificTag.fromString(TagHandle tagHandle, String uri)
    : this._(tagHandle, uri as T);

  @override
  final TagHandle tagHandle;

  final T _content;
}

/// Indicates a node has no native data structure preference and allows `YAML`
/// to assign one based on its kind.
///
/// Typically, indicated either by a `!` only with no trailing uri characters or
/// no tag altogether. Must always be resolved to a [SpecificTag].
final class NonSpecificTag implements Tag {
  @override
  TagHandle get tagHandle => TagHandle.primary();

  @override
  String get prefix => tagHandle.handle;
}
