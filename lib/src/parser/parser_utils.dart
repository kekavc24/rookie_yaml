import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/scalars/block/block_scalar.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';

/// A non-existent indent level for block(-like) scalars (`plain`, `literal`,
/// `folded`) that are affected by indent changes. Indicates that the said
/// scalar was parsed successfully without an indent change.
const seamlessIndentMarker = -2;

typedef PreScalar = ({
  /// Buffered content
  String content,

  /// [Scalar]'s scalarstyle
  ScalarStyle scalarStyle,

  /// Fixed indent used to parse the scalar.
  ///
  /// It should be noted that the indent for a flow scalar
  /// ([ScalarStyle.doubleQuoted], [ScalarStyle.singleQuoted]
  /// and [ScalarStyle.plain]) may be an approximate indent since indent serves
  /// no purpose in a flow scalar. Ergo, this [scalarIndent] may refer to the
  /// minimum indent used to determine its structure if its parent flow
  /// collection ([Sequence] or [Mapping]) is nested within a collection
  ///
  /// If the scalar is a direct child of a block key or block list then its
  /// indent is fixed based on the parent. However, for [ScalarStyle.folded]
  /// and [ScalarStyle.literal], this indent may be greater than that suggested
  /// by the parent since YAML allows block scalars to define their own
  /// indentation using the indentation indicator (`+`) in the block header.
  /// Additionally, YAML recommends the parser to infer the indent based
  /// on the first non-empty line's indentatio. This indent can be end up being
  /// equal to or greater than the indent recommended by the parent.
  int scalarIndent,

  /// Document marker type encountered
  DocumentMarker docMarkerType,

  /// Indicates whether any linebreak was ever seen while parsing.
  ///
  /// `NOTE`: This is a helper to prevent a redundant scan on the
  /// [parsedContent] as the line break may have already been seen while parsing
  /// the content and folded
  bool hasLineBreak,

  /// Indicates if the actual formatted content itself has a line break.
  ///
  /// Do not confuse this with `hasLineBreak`. Some scalars fold line breaks
  /// which are never written to the buffer. Specifically,
  /// [ScalarStyle.doubleQuoted] allow line breaks to be escaped. In this case,
  /// the string may be concantenated without ever folding the line break to a
  /// space. This information may be crucial to how we infer the kind
  /// (Dart type) since most (, if not all,) types are inline.
  bool wroteLineBreak,

  /// Returns `true` for block(-like) styles, that is, `plain`, `literal` and
  /// `folded` if an indent change triggered the end of its parsing
  bool indentDidChange,

  /// Indent after complete parsing of the scalar. This will usually
  /// default to `-2` for quoted styles.
  ///
  /// Block(-like) styles, that is, `plain`, `literal` and `folded`, that rely
  /// on indentation to convey content may provide a different value when
  /// [indentDidChange] is `true`.
  int indentOnExit,

  /// End offset of the scalar (exclusive)
  RuneOffset end,
});

/// Skips any comments and linebreaks until a character that can be parsed
/// is encountered. Returns `null` if no indent was found.
///
/// Leading white spaces when this function is called are ignored. This
/// function treats them as separation space including tabs.
///
/// You must provide either [comments] or an [onParseComment] [Function]
int? skipToParsableChar(
  GraphemeScanner scanner, {
  List<YamlComment>? comments,
  void Function(YamlComment comment)? onParseComment,
}) {
  assert(
    comments != null || onParseComment != null,
    'Missing handler/buffer to use when a comment is parsed',
  );

  int? indent;
  var isLeading = true;

  void addComment(YamlComment comment) =>
      comments != null ? comments.add(comment) : onParseComment!(comment);

  while (scanner.canChunkMore) {
    switch (scanner.charAtCursor) {
      /// If the first character is a leading whitespace, ignore. There
      /// is no need treating it as indent
      case space || tab when isLeading:
        {
          scanner.skipWhitespace(skipTabs: true);
          scanner.skipCharAtCursor();
        }

      // Each line break triggers implicit indent inference
      case int char when char.isLineBreak():
        {
          skipCrIfPossible(char, scanner: scanner);

          // Only spaces. Tabs are not considered indent
          indent = scanner.skipWhitespace().length;
          scanner.skipCharAtCursor();
          isLeading = false;
        }

      case comment:
        {
          final (:onExit, :comment) = parseComment(scanner);
          addComment(comment);

          if (onExit.sourceEnded) return null;
          indent = null; // Guarantees a recheck to indent
        }

      // We found the first parsable character
      default:
        return indent;
    }
  }

  return indent;
}

/// A function to easily create a [TypeResolverTag] on demand
typedef ResolverCreator = TypeResolverTag Function(NodeTag tag);

/// A wrapper class used to define a [TagShorthand] that the parser associates
/// with a [TypeResolverTag] to infer the kind for a [YamlSourceNode] or
/// [String] content from [Scalar] to valid output [O].
///
/// {@category resolvers}
final class Resolver<I, O> {
  Resolver._(this.target, this.creator);

  /// Suffix associated with a [TypeResolverTag]
  final TagShorthand target;

  /// Function to create a [TypeResolverTag] once a matching suffix is
  /// encountered
  final ResolverCreator creator;

  /// Creates a [ContentResolver] as its [TypeResolverTag]
  Resolver.content(
    TagShorthand tag, {
    required O? Function(String input) contentResolver,
    required String Function(O input) toYamlSafe,
  }) : this._(
         tag,
         (tag) => ContentResolver(
           tag,
           resolver: contentResolver,
           toYamlSafe: (s) => toYamlSafe(s as O),
         ),
       );

  /// Creates a [NodeResolver] as its [TypeResolverTag]
  Resolver.node(
    TagShorthand tag, {
    required O Function(YamlSourceNode input) resolver,
  }) : this._(tag, (tag) => NodeResolver(tag, resolver: resolver));
}
