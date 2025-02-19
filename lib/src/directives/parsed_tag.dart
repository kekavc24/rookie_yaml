part of 'directives.dart';

String _formatAsVerbatim(SpecificTag tag, String suffix) {
  var prepend = '';
  var formattedSuffix = suffix.trim();

  if (tag is GlobalTag) {
    if (formattedSuffix.isEmpty) {
      throw FormatException('A global tag must have a non-empty suffix');
    }

    prepend = tag.prefix;
    prepend += prepend.endsWith('/') || prepend.endsWith(':') ? '' : ':';
  } else {
    prepend = tag.toString();
  }

  return _wrapAsVerbatim('$prepend$formattedSuffix');
}

final class ParsedTag<T> implements _ResolvedTag {
  ParsedTag(this._resolvedTag, String suffix)
    : _verbatim = _formatAsVerbatim(_resolvedTag, suffix);

  final SpecificTag<T> _resolvedTag;

  final String _verbatim;

  @override
  String get prefix => _resolvedTag.prefix;

  @override
  TagHandle get tagHandle => _resolvedTag.tagHandle;

  @override
  String get verbatim => _verbatim;

  @override
  bool operator ==(Object other) =>
      other is ParsedTag && other._verbatim == _verbatim;

  @override
  int get hashCode => _verbatim.hashCode;

  @override
  String toString() => _verbatim;
}
