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

  GraphemeChar.wrap(String string)
    : this._(_GraphemeWrapper(string).unicode, string);

  const GraphemeChar.raw(String string, int unicode) : this._(unicode, string);

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
final delimiterMap = UnmodifiableMapView(_generateSpecialMap());

Map<int, ReadableChar> _generateSpecialMap() {
  final special = <int, ReadableChar>{};

  for (final indicator in Indicator.values) {
    special[indicator.unicode] = indicator;
  }

  for (final escaped in SpecialEscaped.values) {
    special[escaped.unicode] = escaped;
  }

  for (final linebreak in LineBreak.values) {
    special[linebreak.unicode] = linebreak;
  }

  for (final space in WhiteSpace.values) {
    special[space.unicode] = space;
  }

  return special;
}
