part of 'map_dumper.dart';

/// Node information about a dumped node
typedef _NodeInfo = ({
  int indent,
  int? offsetFromMargin,
  bool canApplyTrailingComments,
  List<String> comments,
  String content,
});

/// Information about the current key of an [_EntryStore].
typedef _KeyStore = ({bool explicit, _NodeInfo info});

/// Information about the current value of an [_EntryStore].
typedef _ValueStore = ({bool isBlock, _NodeInfo info});

/// A dumped [MapEntry].
typedef _DumpedEntry = ({bool hasTrailing, String content});

/// Adds a space before the `:` of an implicit key that is an alias. The `:`
/// is considered a valid alias character.
String _spacedIfAlias(String key) => key.startsWith('*') ? '$key ' : key;

/// A callback for a dumped entry that formats it to match the state of the
/// map which contained it.
typedef _EntryFormatter =
    String Function(
      String entry,
      String indentation,
      bool isInline,
      bool lastHadTrailing,
      bool isNotFirst,
    );

/// Formats a flow map entry.
String _formatFlow(
  String entry,
  String indentation, {
  required bool preferInline,
  required bool lastHadTrailing,
  required bool isNotFirst,
}) {
  return '${lastHadTrailing && isNotFirst ? ',' : ''}'
      '${preferInline ? (isNotFirst ? ' ' : '') : '\n$indentation'}$entry';
}

/// Formats a block map entry.
String _formatBlock(
  String entry,
  String indentation, {
  required bool isNotFirst,
}) => isNotFirst ? '$indentation$entry' : entry;

/// Represents an entry that is being processed and has not been dumped.
final class _EntryStore {
  _EntryStore(
    this.dumper, {
    bool alwaysInline = false,
    bool isFlowMap = false,
  }) : isFlow = isFlowMap,
       preferInline = isFlowMap && alwaysInline;

  /// Represents the indent of the entry relative to the map that instatiated
  /// it.
  ///
  /// For block maps, this is the indent of the block map itself. For flow maps,
  /// this is `mapIndent + 1`.
  int entryIndent = -1;

  /// Dumper for comments.
  final CommentDumper dumper;

  /// Whether this is an entry in a flow map
  final bool isFlow;

  /// Whether flow map entries are dumped inline. In this state, comments are
  /// ignored.
  bool preferInline;

  /// Tracks the parsed key.
  _KeyStore? key;

  /// Tracks the parsed value.
  _ValueStore? value;

  /// Whether this is entry has no key and value.
  bool get isEmpty => !hasKey && !hasValue;

  bool get hasKey => key != null;

  bool get hasValue => value != null;

  /// Whether the key was parsed as an explicit key.
  bool get keyWasExplicit => key?.explicit ?? false;

  /// Formats the buffered entry.
  _DumpedEntry formatEntry() {
    _throwIfIncomplete();

    if (isFlow && preferInline) {
      return (
        hasTrailing: false,
        content:
            '${key!.explicit ? '?' : ''}${_spacedIfAlias(key!.info.content)}:'
            ' ${value!.info.content}',
      );
    }

    final (:hasTrailing, :content) = _dumpEntry(
      entryIndent,
      dumper: dumper,
      key: key!,
      value: value!,
      isFlow: isFlow,
    );

    return (content: _postProcess(content), hasTrailing: hasTrailing);
  }

  /// Reverts the entry to an empty state.
  void reset([_KeyStore? newKey, _ValueStore? newValue, int? indent]) {
    key = newKey;
    value = newValue;
    entryIndent = indent ?? entryIndent;
  }

  /// Throws if the entry is being dumped to the actual map buffer and the
  /// [key] or [value] is null.
  void _throwIfIncomplete() {
    if (key == null || value == null) {
      throw StateError(
        'Invalid dumping state: \n'
        '\tkey: $key\n'
        '\tvalue: $value',
      );
    }
  }

  /// Applies the trailing line break as required for all block maps.
  String _postProcess(String dumped) =>
      !isFlow && !dumped.endsWith('\n') ? '$dumped\n' : dumped;
}

/// Dumps an key or value.
///
/// This function operates under the assumption that an entry is being dumped
/// as an entry to a block parent or a flow parent that is not inline.
///
/// [char] represents the character to append before the fully dumped [content].
/// By default, no [indent] is applied to the first line.
///
/// The node's [comments] are appended using the comment [dumper] provided. If
/// [canApplyTrailing] is `false`, comments are applied before the node even if
/// the [dumper] is set to [CommentStyle.inline]. [offsetFromMargin] is an hint
/// for the comment [dumper] on how far the last line is from the margin when
/// applying comments with [CommentStyle.inline].
String _dumpGeneric(
  String content, {
  required String char,
  required int indent,
  required CommentDumper dumper,
  required List<String> comments,
  required bool canApplyTrailing,
  required int? offsetFromMargin,
}) {
  if (comments.isEmpty) {
    return '$char $content';
  } else if (!canApplyTrailing || dumper.style == CommentStyle.block) {
    return '$char ${dumper.applyComments(
      content,
      comments: comments,
      forceBlock: true,
      indent: indent,
      offsetFromMargin: -1,
    )}';
  }

  return '$char ${dumper.applyComments(
    content,
    comments: comments,
    forceBlock: false,
    indent: indent,
    offsetFromMargin: offsetFromMargin ?? switch (content.lastIndexOf('\n')) {
          -1 => content.length + indent,
          int value => (content.length - value),
        },
  )}';
}

/// Dumps an implicit key.
(bool, String) _dumpImplicitKey(
  String content, {
  required int indent,
  required CommentDumper dumper,
  required List<String> comments,
  required int? offsetFromMargin,
  required bool canApplyTrailing,
}) {
  final key = '${_spacedIfAlias(content)}:';

  if (comments.isEmpty) {
    return (false, key);
  }

  return (
    canApplyTrailing && dumper.style == CommentStyle.inline,
    dumper.applyComments(
      key,
      comments: comments,
      forceBlock: false,
      indent: indent,
      offsetFromMargin: offsetFromMargin ?? indent + key.length,
    ),
  );
}

/// Dumps an implicit entry to a flow/block map.
_DumpedEntry _dumpImplicitEntry(
  CommentDumper dumper,
  _KeyStore key,
  _ValueStore value, [
  bool isFlow = false,
]) {
  var (keyHasTrailing, formattedKey) = _dumpImplicitKey(
    key.info.content,
    indent: key.info.indent,
    dumper: dumper,
    comments: key.info.comments,
    offsetFromMargin: null,
    canApplyTrailing: key.info.canApplyTrailingComments,
  );

  final valueIndent = value.info.indent;
  final commentsAreInline = dumper.style == CommentStyle.inline;

  formattedKey =
      keyHasTrailing ||
          value.isBlock ||
          (!isFlow && !commentsAreInline && value.info.comments.isNotEmpty)
      ? '$formattedKey'
            '${formattedKey.endsWith('\n') ? '' : '\n'}'
            '${' ' * valueIndent}'
      : '$formattedKey ';

  final commentsMayTrail = value.info.canApplyTrailingComments;

  final comments = value.info.comments;
  final willTrail =
      commentsMayTrail && commentsAreInline && comments.isNotEmpty;

  var formattedValue = willTrail && isFlow
      ? '${value.info.content},'
      : value.info.content;

  // We will have to trim this on the left. We want the benefits
  formattedValue = _dumpGeneric(
    formattedValue,
    char: '',
    indent: valueIndent,
    dumper: dumper,
    comments: comments,
    canApplyTrailing: commentsMayTrail,
    offsetFromMargin: value.info.offsetFromMargin,
  ).trimLeft();

  return (hasTrailing: willTrail, content: '$formattedKey$formattedValue');
}

/// Dumps an explicit entry to a block map or multiline flow map.
_DumpedEntry _dumpBlockExplicitEntry(
  CommentDumper dumper,
  _NodeInfo keyInfo,
  _ValueStore value,
  int entryIndent, [
  bool isFlow = false,
]) {
  final formattedKey = _dumpGeneric(
    keyInfo.content,
    char: '?',
    indent: keyInfo.indent,
    dumper: dumper,
    comments: keyInfo.comments,
    canApplyTrailing: keyInfo.canApplyTrailingComments,
    offsetFromMargin: keyInfo.offsetFromMargin,
  );

  final definitelyTrailing =
      !value.isBlock && value.info.canApplyTrailingComments;
  final dumpedValue = definitelyTrailing && isFlow
      ? '${value.info.content},'
      : value.info.content;

  return (
    hasTrailing: definitelyTrailing,
    content:
        '$formattedKey${formattedKey.endsWith('\n') ? '' : '\n'}'
        '${' ' * entryIndent}'
        '${_dumpGeneric(
          dumpedValue,
          char: ':',
          indent: value.info.indent,
          dumper: dumper,
          comments: value.info.comments,
          canApplyTrailing: definitelyTrailing,
          offsetFromMargin: value.info.offsetFromMargin,
        )}',
  );
}

/// Dumps an entry to a flow/block map.
_DumpedEntry _dumpEntry(
  int entryIndent, {
  required CommentDumper dumper,
  required _KeyStore key,
  required _ValueStore value,
  bool isFlow = false,
}) => key.explicit
    ? _dumpBlockExplicitEntry(dumper, key.info, value, entryIndent, isFlow)
    : _dumpImplicitEntry(dumper, key, value, isFlow);
