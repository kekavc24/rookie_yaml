part of 'directives.dart';

/// Formats a [tag] into its verbatim form.
///
/// [suffix] - must not be empty if a [GlobalTag] is provided.
///
/// Example: the [TagShorthand] `!!str` is normally resolved to [GlobalTag]
/// `tag:yaml.org,2002:str` which in verbatim is represented as
/// `!<tag:yaml.org,2002:str>`. Thus, `str` is the [suffix] in this case and
/// `tag:yaml.org,2002` is the global tag prefix.
String _formatAsVerbatim(
  SpecificTag<dynamic> tag,
  String suffix, {
  required bool suffixIsNonSpecific,
}) {
  var prepend = '';
  final formattedSuffix = suffix.trim();

  if (tag is GlobalTag) {
    prepend = tag.prefix;

    // Local tags can be empty if non-specific
    if (!suffixIsNonSpecific && formattedSuffix.isEmpty) {
      throw FormatException('A global tag must have a non-empty suffix');
    }

    // Add ":" only if it is not a local tag prefix
    if (!prepend.startsWith("!") &&
        !(prepend.endsWith('/') || prepend.endsWith(':'))) {
      prepend += ":";
    }
  } else {
    prepend = tag.toString();
  }

  return _wrapAsVerbatim('$prepend$formattedSuffix');
}

/// Represents a [TagShorthand] shorthand that has (not) been resolved to a
/// [GlobalTag] after it has been parsed.
///
/// {@category tag_types}
/// {@category declare_tags}
final class NodeTag<T> extends ResolvedTag {
  NodeTag(this._resolvedTag, [TagShorthand? suffix])
    : verbatim = _formatAsVerbatim(
        _resolvedTag,
        suffix?.content ?? '',
        suffixIsNonSpecific: suffix?.isNonSpecific ?? false,
      ),
      suffix = suffix ?? _resolvedTag as TagShorthand;

  /// A [TagShorthand] shorthand resolved to a [GlobalTag] or the tag itself.
  final SpecificTag<T> _resolvedTag;

  @override
  final TagShorthand suffix; // A parsed tag always has a suffix

  @override
  String get prefix => _resolvedTag.prefix;

  @override
  TagHandle get tagHandle => _resolvedTag.tagHandle;

  @override
  final String verbatim;

  @override
  bool operator ==(Object other) =>
      other is NodeTag && other._resolvedTag == _resolvedTag;

  @override
  int get hashCode => _resolvedTag.hashCode;

  @override
  String toString() => verbatim;
}
