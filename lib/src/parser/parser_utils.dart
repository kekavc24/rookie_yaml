import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/parser/scalars/block/block_scalar.dart';
import 'package:rookie_yaml/src/scanner/grapheme_scanner.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';

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
