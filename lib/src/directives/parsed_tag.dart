part of 'directives.dart';

/// Formats a [tag] into its verbatim form.
///
/// [suffix] - must not be empty if a [GlobalTag] is provided.
///
/// Example: the [LocalTag] `!!str` is normally resolved to [GlobalTag]
/// `tag:yaml.org,2002:str` which in verbatim is represented as
/// `!<tag:yaml.org,2002:str>`. Thus, `str` is the [suffix] in this case and
/// `tag:yaml.org,2002` is the global tag prefix.
String _formatAsVerbatim(SpecificTag<dynamic> tag, String suffix) {
  var prepend = '';
  final formattedSuffix = suffix.trim();

  if (tag is GlobalTag) {
    if (formattedSuffix.isEmpty) {
      throw const FormatException('A global tag must have a non-empty suffix');
    }

    prepend = tag.prefix;
    prepend += prepend.endsWith('/') || prepend.endsWith(':') ? '' : ':';
  } else {
    prepend = tag.toString();
  }

  return _wrapAsVerbatim('$prepend$formattedSuffix');
}

/// Represents a [LocalTag] shorthand that has (not) been resolved to a
/// [GlobalTag] after it has been parsed.
@immutable
final class ParsedTag<T> implements ResolvedTag {
  ParsedTag(this._resolvedTag, LocalTag? suffix)
    : verbatim = _formatAsVerbatim(_resolvedTag, suffix?.content ?? ''),
      suffix = suffix ?? _resolvedTag as LocalTag;

  /// A [LocalTag] shorthand resolved to a [GlobalTag] or the tag itself.
  final SpecificTag<T> _resolvedTag;

  @override
  final LocalTag suffix; // A parsed tag always has a suffix

  @override
  String get prefix => _resolvedTag.prefix;

  @override
  TagHandle get tagHandle => _resolvedTag.tagHandle;

  @override
  final String verbatim;

  @override
  bool operator ==(Object other) =>
      other is ParsedTag && other._resolvedTag == _resolvedTag;

  @override
  int get hashCode => _resolvedTag.hashCode;

  @override
  String toString() => verbatim;
}
