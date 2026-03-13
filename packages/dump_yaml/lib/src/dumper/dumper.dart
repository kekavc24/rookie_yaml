extension StringUtils on String {
  /// Applies the node's properties inline. This is usually all scalars and
  /// flow collections.
  String applyInline({String? tag, String? anchor, String? node}) {
    var dumped = node ?? this;

    void apply(String? prop, [String prefix = '']) {
      if (prop == null) return;
      dumped = '$prefix$prop $dumped';
    }

    apply(tag);
    apply(anchor, '&');
    return dumped;
  }
}

/// A YAML string buffer for any [Dumper].
final class YamlStringBuffer {
  /// Creates a [YamlStringBuffer] with the provided [startingIndent]. The
  /// [lineEnding] will be used for the entire document.
  ///
  /// The buffer maintains a [step] that can be used to calculate the
  /// indentation of nested elements. This allows a [Dumper] to emit a uniform
  /// YAML document.
  YamlStringBuffer(int startingIndent, this.step, this.lineEnding)
    : indent = startingIndent;

  /// Current indentation.
  int indent;

  /// Indentation step.
  int step;

  /// Dumper's line ending.
  String lineEnding;

  /// Whether the last write operating included a trailing line break.
  var lastWasLineEnding = false;

  /// Current distance from margin.
  int distanceFromMargin = 0;

  /// Actual buffer with content.
  final _buffer = StringBuffer();

  /// Resets `this` buffer with the [updated] indent and clears the internal
  /// string buffer.
  set reset(int updated) {
    _buffer.clear();
    indent = updated;
    lastWasLineEnding = false;
    distanceFromMargin = 0;
  }

  /// Clears the internal [StringBuffer].
  void clearBuffer() => _buffer.clear();

  /// Moves the imaginary cursor to the next line by writing a [lineEnding].
  void moveToNextLine() {
    if (lastWasLineEnding) return;
    _buffer.write(lineEnding);
    lastWasLineEnding = true;
    distanceFromMargin = 0;
  }

  /// Writes the [content].
  void write(String content) {
    _buffer.write(content);
    distanceFromMargin += content.length;
    lastWasLineEnding = false;
  }

  /// Writes the indent or the number of spaces if [count] is specified.
  void writeSpaceOrIndent([int? count]) => write(' ' * (count ?? indent));

  /// Writes the [content] to the underlying buffer.
  ///
  /// The [preferredIndent] or [indent] is not applied to the first line.
  ///
  /// If [cursorNextLine] is `true`, a [lineEnding] is written only if the
  /// [content] didn't have a trailing line break.
  void writeContent(
    Iterable<String> content, {
    bool cursorNextLine = false,
    int? preferredIndent,
  }) {
    final padding = ' ' * (preferredIndent ?? indent);
    final joined = content
        .take(1)
        .followedBy(content.skip(1).map((l) => l.isEmpty ? l : '$padding$l'))
        .join(lineEnding);

    _buffer.write(joined);

    if (joined.endsWith(lineEnding)) {
      distanceFromMargin = 0;
      lastWasLineEnding = true;
      return;
    }

    lastWasLineEnding = false;

    if (!cursorNextLine) {
      distanceFromMargin += content.lastOrNull?.length ?? 0;
      return;
    }

    moveToNextLine();
  }

  /// Writes the [comments] to the underlying buffer and moves the cursor to
  /// the next line.
  void writeComments(Iterable<String> comments, [int? indent]) {
    if (comments.isEmpty) {
      lastWasLineEnding = false;
      return;
    }

    writeContent(
      comments.map((e) => '#${e.isEmpty ? '' : ' '}$e'),
      cursorNextLine: true,
      preferredIndent: indent,
    );
  }

  @override
  String toString() => _buffer.toString();
}

/// A generic YAML Dumper.
abstract class Dumper<T> {
  /// Dumps a [node].
  void dump(T node);

  /// Dumped string.
  String dumped();

  /// Resets the dumper's internal state.
  void reset();
}
