import 'dart:math';

import 'package:collection/collection.dart';
import 'package:rookie_yaml/src/parser/parser_utils.dart';
import 'package:rookie_yaml/src/scanner/source_iterator.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';
import 'package:rookie_yaml/src/schema/yaml_comment.dart';

part 'directive_utils.dart';
part 'global_tag.dart';
part 'node_tag.dart';
part 'reserved_directive.dart';
part 'resolver_tag.dart';
part 'tag.dart';
part 'tag_handle.dart';
part 'tag_shorthand.dart';
part 'verbatim_tag.dart';
part 'yaml_directive.dart';

/// Denotes all YAML directives declared before a yaml document is parsed.
///
/// See: https://yaml.org/spec/1.2.2/#68-directives
typedef Directives = ({
  YamlDirective? yamlDirective,
  List<ReservedDirective> reservedDirectives,
  Map<TagHandle, GlobalTag<dynamic>> globalTags,
  bool hasDirectiveEnd,
});

/// `%` character
const _directiveIndicator = directive;

const _noDirectives = (
  yamlDirective: null,
  globalTags: <TagHandle, GlobalTag>{},
  reservedDirectives: <ReservedDirective>[],
  hasDirectiveEnd: false,
);

/// A valid `YAML` directive
///
/// {@category yaml_docs}
sealed class Directive {
  /// Name of the directive
  String get name;

  /// Parameters that describe the directive
  List<String> get parameters;
}

/// Parses all [Directive]s present before the start of a node in a `YAML`
/// document.
Directives parseDirectives(
  SourceIterator iterator, {
  required void Function(YamlComment comment) onParseComment,
  required void Function(String message) warningLogger,
}) {
  void throwIfNotSeparation(int? char) {
    if (!iteratedIsEOF(char) && !char!.isWhiteSpace()) {
      throwWithSingleOffset(
        iterator,
        message: 'Expected a separation space after parsing the directive name',
        offset: iterator.currentLineInfo.current,
      );
    }

    skipWhitespace(iterator, skipTabs: true);
    if (iterator.current case space || tab) {
      iterator.nextChar();
    }
  }

  if (iterator.current == _directiveIndicator) {
    final directiveBuffer = StringBuffer();
    YamlDirective? directive;
    final globalDirectives = <TagHandle, GlobalTag>{};
    final reserved = <ReservedDirective>[];

    dirParser:
    while (!iterator.isEOF) {
      var char = iterator.current;

      switch (char) {
        /// Skip line breaks greedily
        case lineFeed || carriageReturn || comment:
          {
            // Directives must start with "%". Never indented.
            // [skipToParsableChar] will ensure all comments and empty lines
            // are skipped
            if (_skipToNextNonEmptyLine(iterator, onParseComment)) {
              continue extractor;
            }

            char = iterator.current;
            continue terminator;
          }

        // Extract directive
        extractor:
        case _directiveIndicator
            when iterator.before.isNullOr((c) => c.isLineBreak()):
          {
            // Buffer
            final OnChunk(:charOnExit) = iterateAndChunk(
              iterator,
              onChar: directiveBuffer.writeCharCode,
              exitIf: (_, curr) =>
                  curr.isWhiteSpace() ||
                  curr.isLineBreak() ||
                  !curr.isPrintable(),
            );

            if (directiveBuffer.isEmpty) {
              throwForCurrentLine(
                iterator,
                message:
                    'Expected at least a printable non-space'
                    ' character as the directive name',
              );
            }

            final name = directiveBuffer.toString();

            switch (name) {
              case _yamlDirective:
                {
                  if (directive != null) {
                    throwForCurrentLine(
                      iterator,
                      message:
                          'A YAML directive can only be declared once per '
                          'document',
                    );
                  }

                  throwIfNotSeparation(charOnExit);
                  directive = _parseYamlDirective(iterator, warningLogger);
                }

              case _globalTagDirective:
                {
                  throwIfNotSeparation(charOnExit);
                  final tag = _parseGlobalTag(
                    iterator,
                    isDuplicate: globalDirectives.containsKey,
                  );
                  globalDirectives[tag.tagHandle] = tag;
                }

              default:
                {
                  // Reserved directives can have empty parameters
                  if (charOnExit != null && !charOnExit.isLineBreak()) {
                    throwIfNotSeparation(charOnExit);
                  }

                  reserved.add(
                    _parseReservedDirective(
                      name,
                      iterator: iterator,
                    ),
                  );
                }
            }

            char = iterator.current;

            // Expect either a line break or whitespace or null or a comment
            if (!iteratedIsEOF(char) &&
                !char.isLineBreak() &&
                char != comment) {
              throwIfNotSeparation(char);
            }

            directiveBuffer.clear();
          }

        // Directives must see "---" to terminate
        terminator:
        default:
          {
            // Force a "---" check and not "..."
            if (char == blockSequenceEntry &&
                checkForDocumentMarkers(iterator, onMissing: (_) {}) ==
                    DocumentMarker.directiveEnd) {
              return (
                yamlDirective: directive,
                globalTags: globalDirectives,
                reservedDirectives: reserved,
                hasDirectiveEnd: true,
              );
            }

            break dirParser;
          }
      }
    }

    // As long as "%" was seen, we must parse directives and terminate with the
    // "---" marker
    throwForCurrentLine(
      iterator,
      message: 'Expected a directives end marker after the last directive',
    );
  }

  return _noDirectives;
}
