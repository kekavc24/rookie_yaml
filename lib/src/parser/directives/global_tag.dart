part of 'directives.dart';

const _globalTagDirective = 'TAG';

/// Describes a tag shorthand notation for specifying node tags. It must begin
/// with the `%TAG` directive.
///
/// ```yaml
/// `%TAG !yaml! tag:yaml.org,2002:`
///
/// # %TAG = directive
/// # !yaml! = shorthand
/// # tag:yaml.org,2002: = prefix
/// ```
///
/// {@category yaml_docs}
/// {@category tag_types}
/// {@category declare_tags}
final class GlobalTag<T> extends SpecificTag<T> implements Directive {
  GlobalTag._(super.tagHandle, super.suffix) : super.fromString();

  /// Creates a global tag whose prefix is a [TagShorthand].
  GlobalTag.fromTagShorthand(super.tagHandle, super.tag)
    : super.fromTagShorthand();

  /// Creates a global tag whose prefix is a valid tag uri
  factory GlobalTag.fromTagUri(TagHandle handle, String uri) => GlobalTag._(
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
      other is GlobalTag &&
      other.tagHandle == tagHandle &&
      other.prefix == prefix;

  @override
  int get hashCode => Object.hashAll([tagHandle, prefix]);
}

/// Parses a [GlobalTag].
GlobalTag<dynamic> _parseGlobalTag(
  GraphemeScanner scanner, {
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

  if (scanner.charAtCursor.isNullOr((c) => !c.isWhiteSpace())) {
    throw FormatException(
      'A global tag must have a separation space after its handle',
    );
  }

  // Skip whitespace, move cursor to next character
  scanner
    ..skipWhitespace(skipTabs: true)
    ..skipCharAtCursor();

  switch (scanner.charAtCursor) {
    // A prefix represented by a local tag
    case tag:
      {
        scanner.skipCharAtCursor();

        /// A global ga cannot be affected by flow indicators or the tag
        /// indicator as long we already removed the leading "!". A hack or
        /// just common sense.
        return GlobalTag.fromTagShorthand(
          tagHandle,
          TagShorthand._(
            TagHandle.primary(),
            _parseTagUri(scanner, allowRestrictedIndicators: true),
          ),
        );
      }

    // A normal non-empty/null uri character
    case int char when isUriChar(char):
      {
        return GlobalTag._(
          tagHandle,
          _parseTagUri(
            scanner,
            allowRestrictedIndicators: true,
            includeScheme: true,
          ),
        );
      }

    default:
      // TODO: Shabby exception
      throw FormatException(
        'A global tag only accepts valid uri characters as a tag prefix',
      );
  }
}
