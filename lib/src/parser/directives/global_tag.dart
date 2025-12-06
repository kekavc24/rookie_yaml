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
  GlobalTag.fromTagUri(TagHandle handle, String uri)
    : this._(
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
  SourceIterator iterator, {
  required bool Function(TagHandle handle) isDuplicate,
}) {
  // Must have a tag handle present
  final tagHandle = parseTagHandle(iterator);

  // Exit early if we already a global tag with this handle
  if (isDuplicate(tagHandle)) {
    throwForCurrentLine(
      iterator,
      message:
          'A global tag directive with the "${tagHandle.handle}" has already '
          'been declared in this document',
    );
  }

  if (iterator.isEOF || !iterator.current.isWhiteSpace()) {
    throwWithSingleOffset(
      iterator,
      message: 'A global tag must have a separation space after its handle',
      offset: iterator.currentLineInfo.current,
    );
  }

  // Skip whitespace, move cursor to next character
  skipWhitespace(iterator, skipTabs: true);
  iterator.nextChar();

  // A prefix represented by a local tag
  if (iterator.current == tag) {
    iterator.nextChar();

    /// A global tag cannot be affected by flow indicators or the tag
    /// indicator as long we already removed the leading "!". A hack or
    /// just common sense.
    return GlobalTag.fromTagShorthand(
      tagHandle,
      TagShorthand._(
        TagHandle.primary(),
        _parseTagUri(iterator, allowRestrictedIndicators: true),
      ),
    );
  } else if (isUriChar(iterator.current)) {
    return GlobalTag._(
      tagHandle,
      _parseTagUri(
        iterator,
        allowRestrictedIndicators: true,
        includeScheme: true,
      ),
    );
  }

  throwWithSingleOffset(
    iterator,
    message: 'A global tag only accepts valid uri characters in its tag prefix',
    offset: iterator.currentLineInfo.current,
  );
}
