part of 'directives.dart';

final class ParsedTag<T> implements _ResolvedTag {
  ParsedTag({required SpecificTag<T> resolvedTag, required this.suffix})
    : _resolvedTag = resolvedTag;

  final SpecificTag<T> _resolvedTag;

  final String suffix;

  @override
  String get prefix => _resolvedTag.prefix;

  @override
  TagHandle get tagHandle => _resolvedTag.tagHandle;

  @override
  String get verbatim {
    var prepend = '';

    if (_resolvedTag is GlobalTag) {
      prepend = _resolvedTag.prefix;
      prepend += prepend.endsWith('/') || prepend.endsWith(':') ? '' : ':';
    } else {
      prepend = _resolvedTag.toString();
    }

    return '!<$prepend$suffix>';
  }

  @override
  bool operator ==(Object other) =>
      other is ParsedTag && other.verbatim == verbatim;

  @override
  int get hashCode => verbatim.hashCode;

  @override
  String toString() => verbatim;
}
