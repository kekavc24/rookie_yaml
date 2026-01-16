part of 'map_dumper.dart';

/// Information about the current key of an [_KVStore].
typedef _KeyStore = ({bool explicit, NodeInfo info});

/// Information about the current value of an [_KVStore].
typedef _ValueStore = ({bool isBlock, NodeInfo info});

/// Adds a space before the `:` of an implicit key that is an alias. The `:`
/// is considered a valid alias character.
String _spacedIfAlias(String key) => key.startsWith('*') ? '$key ' : key;

/// Represents a [MapEntry] that is being processed and has not been dumped.
final class _KVStore extends FormattingEntry {
  _KVStore(super.dumper, {super.alwaysInline, super.isFlowNode});

  /// Tracks the parsed key.
  _KeyStore? key;

  /// Tracks the parsed value.
  _ValueStore? value;

  @override
  bool get isEmpty => !hasKey && !hasValue;

  bool get hasKey => key != null;

  bool get hasValue => value != null;

  /// Whether the key was parsed as an explicit key.
  bool get keyWasExplicit => key?.explicit ?? false;

  @override
  DumpedEntry format() {
    throwIfIncomplete(
      throwIf: key == null || value == null,
      message:
          'Invalid dumping state: \n'
          '\tkey: $key\n'
          '\tvalue: $value',
    );

    if (isFlow && preferInline) {
      return (
        hasTrailing: false,
        content:
            '${key!.explicit ? '? ' : ''}${_spacedIfAlias(key!.info.content)}:'
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

  @override
  void next() {
    key = null;
    value = null;
    ++countFormatted;
  }

  /// Reverts the entry to an empty state.
  void reset({
    _KeyStore? newKey,
    _ValueStore? newValue,
    int? indent,
    int? count,
  }) {
    key = newKey;
    value = newValue;
    entryIndent = indent ?? entryIndent;
    resetCount(count);
  }

  /// Applies the trailing line break as required for all block maps.
  String _postProcess(String dumped) =>
      isFlow || dumped.endsWith('\n') ? dumped : '$dumped\n';
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
DumpedEntry _dumpImplicitEntry(
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
DumpedEntry _dumpBlockExplicitEntry(
  CommentDumper dumper,
  NodeInfo keyInfo,
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

  final comments = value.info.comments;

  final definitelyTrailing =
      !value.isBlock &&
      value.info.canApplyTrailingComments &&
      comments.isNotEmpty;
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
          comments: comments,
          canApplyTrailing: definitelyTrailing,
          offsetFromMargin: value.info.offsetFromMargin,
        )}',
  );
}

/// Dumps an entry to a flow/block map.
DumpedEntry _dumpEntry(
  int entryIndent, {
  required CommentDumper dumper,
  required _KeyStore key,
  required _ValueStore value,
  bool isFlow = false,
}) => key.explicit
    ? _dumpBlockExplicitEntry(dumper, key.info, value, entryIndent, isFlow)
    : _dumpImplicitEntry(dumper, key, value, isFlow);
