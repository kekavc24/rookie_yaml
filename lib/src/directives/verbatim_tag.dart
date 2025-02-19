part of 'directives.dart';

final _verbatimStart = GraphemeChar.wrap('<');
final _verbatimEnd = GraphemeChar.wrap('>');

String _wrapAsVerbatim(String uri) =>
    '${_tagIndicator.string}$_verbatimStart$uri$_verbatimEnd';

final class VerbatimTag implements _ResolvedTag {
  VerbatimTag._(this.verbatim);

  factory VerbatimTag.fromTagUri(String uri) {
    return VerbatimTag._(
      _ensureIsTagUri(uri, allowRestrictedIndicators: false),
    );
  }

  factory VerbatimTag.fromLocalTag(LocalTag tag) {
    final uri = tag.toString().trim();

    if (tag.tagHandle.handleVariant != TagHandleVariant.primary) {
      throw FormatException(
        'Verbatim tags with a local tag must have a single "!" prefix',
      );
    } else if (uri.isEmpty) {
      throw FormatException(
        'Verbatim tags are never resolved and should have a non-empty suffix',
      );
    }

    return VerbatimTag._(_wrapAsVerbatim(uri));
  }

  @override
  TagHandle get tagHandle => TagHandle.primary();

  @override
  String get prefix => '';

  @override
  final String verbatim;

  @override
  String toString() => verbatim;

  @override
  bool operator ==(Object other) =>
      other is VerbatimTag && other.verbatim == verbatim;

  @override
  int get hashCode => verbatim.hashCode;
}
