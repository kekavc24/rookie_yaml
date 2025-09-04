part of 'yaml_node.dart';

/// Any value that is not a [Sequence] or [Mapping].
///
/// For equality, a scalar uses the inferred value [T] for maximum
/// compatibility with `Dart` objects that can be scalars.
final class Scalar<T> extends YamlSourceNode {
  Scalar(
    this._type, {
    required this.scalarStyle,
    required this.tag,
    required this.anchorOrAlias,
    required this.start,
    required this.end,
  });

  /// Type inferred from the scalar's content
  final ScalarValue<T> _type;

  /// Style used to serialize the scalar. Can be degenerated to a `block` or
  /// `flow` too.
  final ScalarStyle scalarStyle;

  /// A native value represented by the parsed scalar.
  T get value => _type.value;

  @override
  final ResolvedTag? tag;

  @override
  final String? anchorOrAlias;

  @override
  final SourceLocation start;

  @override
  final SourceLocation end;

  @override
  NodeStyle get nodeStyle => scalarStyle._nodeStyle;

  @override
  bool operator ==(Object other) => other == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => _type.toString();
}

const _maxImplicitLength = 1024;

/// Dumps a [Scalar] or an object by calling its `toString` method.
///
/// [dumpingStyle] will always default to [ScalarStyle.doubleQuoted] if
/// [jsonCompatible] is `true`. In this case, the string is normalized and any
/// escaped characters are "nerfed".
///
/// If the [scalar] is an actual [Scalar] object, its [ScalarStyle] takes
/// precedence. Otherwise, defaults to [dumpingStyle]. However, the
/// [dumpingStyle]'s [NodeStyle] must be compatible with the [parentNodeStyle]
/// if present, that is, [NodeStyle.block] accepts both `block` and `flow`
/// styles while [NodeStyle.flow] accepts only `flow` styles. If incompatible,
/// [dumpingStyle] defaults to YAML's [ScalarStyle.doubleQuoted].
///
/// If multiline, each line (excluding the leading line) is padded with the
/// [indent] provided.
({bool explicitIfKey, String encodedScalar}) _dumpScalar<T>(
  T scalar, {
  required int indent,
  bool jsonCompatible = false,
  ScalarStyle dumpingStyle = ScalarStyle.doubleQuoted,
  NodeStyle? parentNodeStyle,
}) {
  var content = scalar.toString(); // Scalars are always strings

  /// Default to double quoted for json compatibility and normalize all
  /// escaped characters and escape the (") quote
  if (jsonCompatible) {
    content = String.fromCharCodes(
      content.codeUnits
          .map(
            (c) => c.normalizeEscapedChars(
              includeTab: true,
              includeLineBreaks: true,
            ),
          )
          .flattened,
    );

    return (
      explicitIfKey: content.length > _maxImplicitLength,
      encodedScalar: '"$content"',
    );
  }

  var style = switch (scalar) {
    Scalar(:final scalarStyle) => scalarStyle,
    _ => dumpingStyle,
  };

  /// Ensure global style matches the scalar style. Block styles are never
  /// used in flow styles but the opposite is possible. YAML prefers plain style
  /// but double quoted guarantees compatibility.
  ///
  /// Plain styles never have any leading/trailing whitespaces.
  style =
      (parentNodeStyle != null && style._nodeStyle != parentNodeStyle) ||
          (style == ScalarStyle.plain &&
              trimYamlWhitespace(content).length != content.length)
      ? ScalarStyle.doubleQuoted
      : style;

  var preferExplicit = false;

  switch (style) {
    // Strictly yaml's double quoted style.
    case ScalarStyle.doubleQuoted:
      {
        final (dqIndent, string) = _joinScalar(
          unfoldDoubleQuoted(
            splitLazyChecked(
              content,
              replacer: (_, c) => c.normalizeEscapedChars(
                includeTab: false,
                includeLineBreaks: false,
              ),
              lineOnSplit: () => preferExplicit = true,
            ),
          ),
          indent: indent,
        );

        return (
          explicitIfKey: preferExplicit || string.length > _maxImplicitLength,
          encodedScalar: '"$string${string.endsWith('\n') ? dqIndent : ''}"',
        );
      }

    // All characters must be printable!
    case ScalarStyle.singleQuoted:
      {
        final (sqIndent, string) = _joinScalar(
          unfoldNormal(
            splitLazyChecked(
              content,
              replacer: (index, char) sync* {
                if (!char.isPrintable()) {
                  throw FormatException(
                    'Non-printable character cannot be encoded as single '
                    'quoted',
                    content,
                    index,
                  );
                } else if (char == singleQuote) {
                  yield char; // Escape single quote with itself
                }

                yield char;
              },
              lineOnSplit: () => preferExplicit = true,
            ),
          ),
          indent: indent,
        );

        return (
          explicitIfKey: preferExplicit || string.length > _maxImplicitLength,
          encodedScalar: "'$string${string.endsWith('\n') ? sqIndent : ''}'",
        );
      }

    /// Normalize every character that is not a tab or linebreak.
    /// See: https://yaml.org/spec/1.2.2/#733-plain-style:~:text=The%20plain%20(unquoted)%20style%20has%20no%20identifying%20indicators%20and%20provides%20no%20form%20of%20escaping
    case ScalarStyle.plain:
      {
        final (_, plain) = _joinScalar(
          unfoldNormal(
            splitLazyChecked(
              content,
              replacer: (_, c) => c.normalizeEscapedChars(
                includeTab: false,
                includeLineBreaks: false,
                includeDoubleQuote: false,
                includeSlashes: false,
              ),
              lineOnSplit: () => preferExplicit = true,
            ),
          ),
          indent: indent,
        );

        return (
          explicitIfKey: preferExplicit || plain.length > _maxImplicitLength,
          encodedScalar: plain,
        );
      }

    // Block styles. Always explicit if it's a key.
    default:
      {
        var indentIndicator = 0;
        var blockIndent = indent;

        /// Both literal and folded styles infer indent from the first
        /// non-empty line. We need to ensure that line is parsed "as-is"
        /// without resorting to double quoted.
        ///
        /// We can limit a parser to a specific indent using an indent
        /// indicator.
        if (content.startsWith(' ')) {
          ++indentIndicator; // Must be 1-9.
          ++blockIndent; // Cheat whichever parser parses.
        }

        final isBlockFolded = style == ScalarStyle.folded;

        content = _joinScalar(
          isBlockFolded
              ? unfoldBlockFolded(_splitBlockString(content))
              : _splitBlockString(content),
          indent: blockIndent,
          includeFirst: true,
        ).$2;

        /// Preserve the block scalar content info from being affected by
        /// trailing line breaks
        final chomping = content.endsWith('\n')
            ? ChompingIndicator.keep.indicator
            : ChompingIndicator.strip.indicator;

        return (
          explicitIfKey: true,
          encodedScalar:
              '${isBlockFolded ? folded.asString() : literal.asString()}'
              '${indentIndicator == 0 ? '' : indentIndicator}'
              '$chomping'
              /// Never append a header line break if [ScalarStyle.folded] and
              /// unfolded string has a leading line feed.
              ///
              /// The header line break is folded if the first line is empty or
              /// it is just a linebreak. It is always discarded as long as no
              /// characters have been written to the buffer a parser is using
              /// to write characters of this folded block scalar.
              '${!isBlockFolded || !content.startsWith('\n') ? '\n' : ''}'
              '$content',
        );
      }
  }
}
