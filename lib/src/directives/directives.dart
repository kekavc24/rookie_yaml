import 'dart:math';

import 'package:collection/collection.dart';

import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/chunk_scanner.dart';

part 'global_tag.dart';
part 'reserved_directive.dart';
part 'tag.dart';
part 'local_tag.dart';
part 'parsed_tag.dart';
part 'tag_handle.dart';
part 'verbatim_tag.dart';
part 'yaml_directive.dart';
part 'directive_utils.dart';

typedef Directives =
    ({
      YamlDirective directive,
      List<ReservedDirective> reservedDirectives,
      Map<TagHandle, GlobalTag> globalTags,
    });

const _directiveIndicator = Indicator.directive;

abstract interface class _Directive {
  String get name;

  List<String> get parameters;
}

Directives parseDirectives(
  ChunkScanner scanner, {
  Map<TagHandle, GlobalTag>? existingGlobalDirectives,
}) {
  YamlDirective? directive;
  final globalDirectives = existingGlobalDirectives ?? {};
  final reserved = <ReservedDirective>[];

  /// Closure to validate global tag handles
  bool isDuplicate(TagHandle handle) => globalDirectives.containsKey(handle);

  /// Skips line breaks. Returns `true` if we continue parsing directives
  bool skipLineBreaks() {
    var char = scanner.charAtCursor;

    while (char is LineBreak) {
      scanner.skipCharAtCursor();
      char = scanner.charAtCursor;
    }

    return char == _directiveIndicator;
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

    dirParser:
    while (scanner.canChunkMore) {
      var char = scanner.charAtCursor;

      switch (char) {
        /// Skip line breaks greedily
        case LineBreak _:
          {
            if (skipLineBreaks()) {
              continue dirParser;
            }

            break dirParser;
          }

        // Extract directive
        case _directiveIndicator:
          {
            // Buffer
            final ChunkInfo(:charOnExit) = scanner.bufferChunk(
              directiveBuffer,
              exitIf:
                  (_, curr) =>
                      curr is WhiteSpace ||
                      curr is LineBreak ||
                      !isPrintable(char!),
            );

            if (directiveBuffer.isEmpty) {
              throw FormatException(
                'Expected at least a printable non-space'
                ' character as the directive name',
              );
            }

            final name = directiveBuffer.toString();

            if (name == _yamlDirective) {
              if (directive != null) {
                throw FormatException(
                  'A YAML directive can only be declared once per document',
                );
              }

              throwIfNotSeparation(charOnExit);
              directive = _parseYamlDirective(scanner);
            } else if (name == _globalTagDirective) {
              throwIfNotSeparation(charOnExit);
              final tag = _parseGlobalTag(scanner, isDuplicate: isDuplicate);
              globalDirectives[tag.tagHandle] = tag;
            } else {
              if (charOnExit is! LineBreak) {
                throwIfNotSeparation(charOnExit);
              }
              reserved.add(_parseReservedDirective(name, scanner: scanner));
            }

            char = scanner.charAtCursor;

            // Expect either a line break or whitespace or null
            if (char is! LineBreak?) {
              throwIfNotSeparation(char);
            }

            directiveBuffer.clear();
          }

        /// Either the current character is whitespace or a character that
        /// indicates start of the root of the document
        default:
          if (scanner.charBeforeCursor is LineBreak) {
            break dirParser;
          }

          throw FormatException('Expected a "%" indicator or line break');
      }
    }
  }

  return (
    directive: directive ?? _parserVersion,
    globalTags: globalDirectives,
    reservedDirectives: reserved,
  );
}
