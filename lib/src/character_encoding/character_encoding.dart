import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

//import 'package:characters/characters.dart';

part 'indicator_characters.dart';
part 'spacing_characters.dart';
part 'non_printable_characters.dart';
part 'char_utils.dart';

/// A single human readable character referred to as a "grapheme cluster".
abstract interface class ReadableChar {
  factory ReadableChar.scanned(String char) {
    final _GraphemeWrapper(:unicode) = _GraphemeWrapper(char);
    return _delimiterMap[unicode] ?? GraphemeChar._(unicode, char);
  }

  /// String representing the character
  String get string;

  /// Unicode value of the character
  int get unicode;
}

/// A single grapheme cluster obtained from a string.
///
/// See [Characters].
@immutable
final class GraphemeChar implements ReadableChar {
  const GraphemeChar._(this.unicode, this.string);

  /// Wraps a unicode value
  GraphemeChar.fromUnicode(int unicode)
    : this._(unicode, String.fromCharCode(unicode));

  /// Byte order mark
  GraphemeChar.unicodeBOM() : this.fromUnicode(unicodeBomCharacterRune);

  @override
  final int unicode;

  @override
  final String string;

  @override
  bool operator ==(Object other) {
    return other is ReadableChar &&
        other.unicode == unicode &&
        other.string == string;
  }

  @override
  String toString() => string;

  @override
  int get hashCode => Object.hashAll([unicode, string]);
}

/// A "no-cost" read-only wrapper type that still allows access to the wrapped
/// string. Guarantees this is a single grapheme cluster
/// (human readable character).
extension type _GraphemeWrapper(String char) {
  /// Underlying string
  String get value => char;

  /// Unicode value as an `int`
  int get unicode => char.isEmpty ? 0 : char.runes.first;
}

/// A raw representation for any [ReadableChar]
extension RawString on ReadableChar {
  /// Returns a raw representation of string as a `32-bit` unicode value
  String get raw {
    const prefix = r'\u';

    // Emit a sequence of utf-16 raw strings
    return string.codeUnits
        .map((unit) => '$prefix${unit.toRadixString(16).padLeft(4, '0')}')
        .join();
  }
}

/// Convenient map of all character encodings that are somewhat special
final _delimiterMap = UnmodifiableMapView(
  Map.fromEntries(
    <List<ReadableChar>>[
      Indicator.values,
      SpecialEscaped.values,
      LineBreak.values,
      WhiteSpace.values,
    ].flattened.map((m) => MapEntry(m.unicode, m)),
  ),
);
