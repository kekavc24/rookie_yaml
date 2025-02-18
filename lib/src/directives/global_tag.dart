part of 'directives.dart';

const _globalTagDirective = 'TAG';

final class GlobalTag<T> extends SpecificTag<T> implements _Directive {
  GlobalTag._(super.tagHandle, super.suffix) : super.fromString();
  GlobalTag.fromLocalTag(super.tagHandle, super.tag) : super.fromLocalTag();

  factory GlobalTag.raw(TagHandle handle, String uri) => GlobalTag._(
    handle,
    _ensureIsTagUri(uri, allowRestrictedIndicators: true),
  );

  @override
  String get name => _globalTagDirective;

  @override
  List<String> get parameters =>
      UnmodifiableListView([tagHandle.handle, prefix]);

  @override
  String get prefix => content.toString();

  @override
  String toString() => _dumpDirective(this);

  @override
  bool operator ==(Object other) =>
      other is GlobalTag<T> &&
      other.tagHandle == tagHandle &&
      other.prefix == prefix;

  @override
  int get hashCode => Object.hashAll([tagHandle, content]);
}

GlobalTag _parseGlobalTag(
  ChunkScanner scanner, {
  required bool Function(TagHandle handle) isDuplicate,
}) {
  // Must have a tag handle present
  final tagHandle = parseTagHandle(scanner);

  // Exit early if we already a global tag with this handle
  if (isDuplicate(tagHandle)) {
    throw FormatException(
      'A global tag directive with the "${tagHandle.handle}" has already '
      'been declared in this document',
    );
  }

  if (scanner.charAtCursor is! WhiteSpace) {
    throw FormatException(
      'A global tag must have a separation space '
      'after its handle',
    );
  }

  // Skip whitespace, move cursor to next character
  scanner.skipWhitespace(skipTabs: true);
  scanner.skipCharAtCursor();

  switch (scanner.charAtCursor) {
    // A prefix represented by a local tag
    case _tagIndicator:
      {
        scanner.skipCharAtCursor();

        /// A global ga cannot be affected by flow indicators or the tag
        /// indicator as long we already removed the leading "!". A hack or
        /// just common sense.
        return GlobalTag.fromLocalTag(
          tagHandle,
          LocalTag._(
            TagHandle.primary(),
            _parseTagUri(scanner, allowRestrictedIndicators: true),
          ),
        );
      }

    // A normal non-empty/null uri character
    case ReadableChar char when isUriChar(char):
      {
        return GlobalTag._(
          tagHandle,
          _parseTagUri(scanner, allowRestrictedIndicators: true),
        );
      }

    default:
      // TODO: Shabby exception
      throw FormatException(
        'A global tag only accepts valid uri characters as a tag prefix',
      );
  }
}
