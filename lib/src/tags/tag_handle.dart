import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';
import 'package:rookie_yaml/src/scanner/chunk_scanner.dart';

const _indicator = Indicator.tag;

enum TagHandleVariant {
  primary('!'),

  secondary('!!'),

  named('');

  const TagHandleVariant(this._handle);

  final String _handle;
}

final class TagHandle {
  TagHandle._(this.handleVariant, String? handle)
    : handle = handle ?? handleVariant._handle;

  TagHandle.primary() : this._(TagHandleVariant.primary, null);

  TagHandle.secondary() : this._(TagHandleVariant.secondary, null);

  factory TagHandle.named(String name) {
    assert(name.isNotEmpty, 'Name cannot be empty!');

    var modded = name;
    final pattern = _indicator.string;

    if (!name.startsWith(pattern)) modded = '$pattern$modded';
    if (!name.endsWith(pattern)) modded = '$modded$pattern';
    return TagHandle._(TagHandleVariant.named, modded);
  }

  final TagHandleVariant handleVariant;

  final String handle;

  @override
  String toString() => handle;

  @override
  bool operator ==(Object other) =>
      other is TagHandle &&
      other.handleVariant == handleVariant &&
      other.handle == handle;

  @override
  int get hashCode => Object.hashAll([handleVariant, handle]);
}

TagHandle parseTagHandle(ChunkScanner scanner) {
  scanner.skipWhitespace(skipTabs: true); // Tabs are separation spaces
  scanner.skipCharAtCursor(); // Move to handle

  var char = scanner.charAtCursor;

  final indicatorStr = _indicator.string;

  // All tag handles must start with the indicator
  if (char == null || char != _indicator) {
    throw FormatException(
      'Expected a $indicatorStr but found '
      '${char?.string ?? 'nothing'}',
    );
  }

  TagHandle tagHandle;

  switch (scanner.peekCharAfterCursor()) {
    // Just a single `!`
    case WhiteSpace _:
      tagHandle = TagHandle.primary();

    /// For secondary tags, parse as secondary. Let caller handle the "mess" or
    /// "success" that may follow.
    ///
    /// "Success" -> whitespace
    /// "Mess" -> throw if not whitespace
    case _indicator:
      scanner.skipCharAtCursor(); // Present in tag handle object
      tagHandle = TagHandle.secondary();

    // Strictly expect a named tag handle if not primary/secondary
    default:
      {
        // Prefer setting the leading and trailing "!"
        final namedBuffer = StringBuffer(indicatorStr);

        final ChunkInfo(:charOnExit) = scanner.bufferChunk(
          namedBuffer,
          exitIf: (_, curr) => !isAlphaNumeric(char),
        );

        if (charOnExit != _indicator) {
          final bufferVal = namedBuffer.toString();

          throw FormatException(
            'Invalid named tag handle format. '
            'Expected !$bufferVal! but found $bufferVal<${charOnExit?.string}>',
          );
        }

        namedBuffer.write(indicatorStr); // Trailing "!"
        tagHandle = TagHandle.named(namedBuffer.toString());
      }
  }

  scanner.skipCharAtCursor();
  return tagHandle;
}
