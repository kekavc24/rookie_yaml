import 'dart:math';

import 'package:characters/characters.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rookie_yaml/src/parser/scalars/block/block_scalar.dart';
import 'package:rookie_yaml/src/scanner/chunk_scanner.dart';
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
const _directiveIndicator = directive;

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

    while (char.isNotNullAnd((c) => c.isLineBreak())) {
      scanner.skipCharAtCursor();
      char = scanner.charAtCursor;
    }
  }

  void throwIfNotSeparation(int? char) {
    if (char != null && !char.isWhiteSpace()) {
      throw FormatException(
        'Expected a separation space but found ${char.asString()}'
        ' after parsing the directive name',
      );
    }

    scanner.skipWhitespace(skipTabs: true);
    if (scanner.charAtCursor case space || tab) {
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
        /// TODO: Comments in directives >> hug left side?
        case lineFeed || carriageReturn:
          skipLineBreaks();

        // Extract directive
        case _directiveIndicator
            when scanner.charBeforeCursor.isNullOr((c) => c.isLineBreak()):
          {
            // Buffer
            final ChunkInfo(:charOnExit) = scanner.bufferChunk(
              (c) => directiveBuffer.writeCharCode(c),
              exitIf: (_, curr) =>
                  curr.isWhiteSpace() ||
                  curr.isLineBreak() ||
                  !curr.isPrintable(),
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
                  if (charOnExit != null && !charOnExit.isLineBreak()) {
                    throwIfNotSeparation(charOnExit);
                  }

                  reserved.add(_parseReservedDirective(name, scanner: scanner));
                }
            }

            char = scanner.charAtCursor;

            // Expect either a line break or whitespace or null
            if (char != null && !char.isLineBreak()) {
              throwIfNotSeparation(char);
            }

            directiveBuffer.clear();
          }

        /// Directives must see "---" to terminate
        default:
          {
            // Force a "---" check and not "..."
            if (char == blockSequenceEntry &&
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
      '"${scanner.charAtCursor?.asString()}'
      '${scanner.peekCharAfterCursor()?.asString()}'
      '.." as the first two characters',
    );
  }

  return _noDirectives;
}
