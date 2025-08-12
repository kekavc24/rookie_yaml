import 'dart:math';

import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';
import 'package:rookie_yaml/src/parser/scalars/block/block_scalar.dart';
import 'package:rookie_yaml/src/parser/scanner/chunk_scanner.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

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
const _directiveIndicator = Indicator.directive;

const _noDirectives = (
  yamlDirective: null,
  globalTags: <TagHandle, GlobalTag>{},
  reservedDirectives: <ReservedDirective>[],
  hasDirectiveEnd: false,
);

/// A valid `YAML` directive
sealed class Directive {
  /// Name of the directive
  String get name;

  /// Parameters that describe the directive
  List<String> get parameters;
}

/// Parses all [Directive](s) present before the start of a node in a
/// `YAML` document.
Directives parseDirectives(GraphemeScanner scanner) {
  /// Skips line breaks. Returns `true` if we continue parsing directives
  void skipLineBreaks() {
    var char = scanner.charAtCursor;

    while (char is LineBreak) {
      scanner.skipCharAtCursor();
      char = scanner.charAtCursor;
    }
  }

  void throwIfNotSeparation(ReadableChar? char) {
    if (char != null && char is! WhiteSpace) {
      throw FormatException(
        'Expected a separation space but found ${char.string}'
        ' after parsing the directive name',
      );
    }

    scanner.skipWhitespace(skipTabs: true);
    if (scanner.charAtCursor is WhiteSpace) {
      scanner.skipCharAtCursor();
    }
  }

  if (scanner.charAtCursor == _directiveIndicator) {
    final directiveBuffer = StringBuffer();
    YamlDirective? directive;
    final globalDirectives = <TagHandle, GlobalTag>{};
    final reserved = <ReservedDirective>[];

    dirParser:
    while (scanner.canChunkMore) {
      var char = scanner.charAtCursor;

      switch (char) {
        /// Skip line breaks greedily
        case LineBreak _:
          skipLineBreaks();

        // Extract directive
        case _directiveIndicator when scanner.charBeforeCursor is LineBreak?:
          {
            // Buffer
            final ChunkInfo(:charOnExit) = scanner.bufferChunk(
              (c) => directiveBuffer.write(c.string),
              exitIf: (_, curr) =>
                  curr is WhiteSpace ||
                  curr is LineBreak ||
                  !isPrintable(char!),
            );

            if (directiveBuffer.isEmpty) {
              throw const FormatException(
                'Expected at least a printable non-space'
                ' character as the directive name',
              );
            }

            final name = directiveBuffer.toString();

            switch (name) {
              case _yamlDirective:
                {
                  if (directive != null) {
                    throw const FormatException(
                      'A YAML directive can only be declared once per document',
                    );
                  }

                  throwIfNotSeparation(charOnExit);
                  directive = _parseYamlDirective(scanner);
                }

              case _globalTagDirective:
                {
                  throwIfNotSeparation(charOnExit);
                  final tag = _parseGlobalTag(
                    scanner,
                    isDuplicate: globalDirectives.containsKey,
                  );
                  globalDirectives[tag.tagHandle] = tag;
                }

              default:
                {
                  // Reserved directives can have empty parameters
                  if (charOnExit is! LineBreak?) {
                    throwIfNotSeparation(charOnExit);
                  }

                  reserved.add(_parseReservedDirective(name, scanner: scanner));
                }
            }

            char = scanner.charAtCursor;

            // Expect either a line break or whitespace or null
            if (char is! LineBreak?) {
              throwIfNotSeparation(char);
            }

            directiveBuffer.clear();
          }

        /// Directives must see "---" to terminate
        default:
          {
            // Force a "---" check and not "..."
            if (char == Indicator.blockSequenceEntry &&
                checkForDocumentMarkers(scanner, onMissing: (_) {}) ==
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

    /// As long as "%" was seen, we must parse directives and terminate with
    /// the "---" marker
    throw FormatException(
      'Expected a directive end marker but found '
      '"${scanner.charAtCursor?.string}${scanner.peekCharAfterCursor()?.string}'
      '.." as the first two characters',
    );
  }

  return _noDirectives;
}
