part of 'dumping.dart';

const _maxImplicitLength = 1024;

bool _useNodeStyleDefault(ScalarStyle? style, String content) =>
    style == null ||
    style == ScalarStyle.plain &&
        (content.startsWith('#') || content.trim().length != content.length);

/// Validates and optionally overrides a [ScalarStyle] based on its [NodeStyle].
///
/// [parentNodeStyle] defaults to [NodeStyle.flow] when `null`.
///
/// If [current] is `null`, [parentNodeStyle] is used to determine the
/// [ScalarStyle]. Defaults to [ScalarStyle.doubleQuoted] in [NodeStyle.flow]
/// and [ScalarStyle.literal] in [NodeStyle.block].
///
/// If current is [ScalarStyle.plain], the [ScalarStyle] defaults to the
/// [parentNodeStyle] if it has leading or trailing whitespaces (line breaks
/// included).
ScalarStyle _defaultStyle(
  ScalarStyle? current, {
  required NodeStyle? parentNodeStyle,
  required String content,
}) {
  var useDefault = _useNodeStyleDefault(current, content);

  /// Ensure global style matches the scalar style. Block styles are never
  /// used in flow styles but the opposite is possible. YAML prefers plain style
  /// but double quoted guarantees compatibility.
  ///
  /// Plain styles never have any leading/trailing whitespaces.
  if ((parentNodeStyle ?? current?.nodeStyle ?? NodeStyle.flow) ==
      NodeStyle.flow) {
    return (current?.nodeStyle != NodeStyle.flow || useDefault)
        ? ScalarStyle.doubleQuoted
        : current!;
  }

  return useDefault ? ScalarStyle.literal : current!;
}

/// Dumps a [Scalar] or any `Dart` object by calling its `toString` method.
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
  ScalarStyle? dumpingStyle,
  NodeStyle? parentNodeStyle,
}) {
  assert(
    dumpingStyle != null || parentNodeStyle != null,
    'Unable to dump a node with no style. Expected a ScalarStyle or NodeStyle '
    'to be provided',
  );

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

  // TODO: Register tag information
  final style = _defaultStyle(
    switch (scalar) {
      Scalar(:final scalarStyle) => scalarStyle,
      _ => dumpingStyle,
    },
    parentNodeStyle: parentNodeStyle,
    content: content,
  );

  var preferExplicit = false;

  switch (style) {
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

    case ScalarStyle.literal || ScalarStyle.folded:
      {
        /// Leading spaces may be problematic. We can know the indentation level
        /// from here.
        if (content.startsWith(' ')) {
          continue doubleQuoted;
        }

        final isBlockFolded = style == ScalarStyle.folded;

        content = _joinScalar(
          isBlockFolded
              ? unfoldBlockFolded(_splitBlockString(content))
              : _splitBlockString(content),
          indent: indent,
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

    // Strictly yaml's double quoted style.
    doubleQuoted:
    default:
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
  }
}
