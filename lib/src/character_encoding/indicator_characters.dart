part of 'character_encoding.dart';

/// Characters that have special meaning in YAML, usually a structural change.
enum Indicator implements ReadableChar {
  /// Block sequence entry start `-`.
  blockSequenceEntry(0x2D),

  /// Mapping key start `?`
  mappingKey(0x3F),

  /// Mapping key end, mapping value start `:`
  mappingValue(0x3A),

  /// End of flow collection entry `,`
  flowEntryEnd(0x2C),

  /// Flow sequence start `[`
  flowSequenceStart(0x5B),

  /// Flow sequence end `]`
  flowSequenceEnd(0x5D),

  /// Flow mapping start `{`
  mappingStart(0x7B),

  /// Flow mapping end `}`
  mappingEnd(0x7D),

  /// Comment start `#`
  comment(0x23),

  /// Node's anchor property `&`
  anchor(0x26),

  /// Alias node `*`
  alias(0x2A),

  /// Specifies node tags `!`. Specifically:
  ///   - Tag handles used in tag directives & properties
  ///   - Local tags
  ///   - Non-specific tags for non-plain scalars
  tag(0x21),

  /// Literal block scalar start `|`
  literal(0x7C),

  /// Folded block scalar start `>`
  folded(0x3E),

  /// Single quoted flow scalar start and end `'`
  singleQuote(0x27),

  /// Double quoted flow scalar start and end `"`
  doubleQuote(0x22),

  /// Directive line start `%`
  directive(0x25),

  /// Reserved by YAML for future use `@`
  reservedAtSign(0x40),

  /// Reserved by YAML for future use [`]
  reservedGrave(0x60);

  const Indicator(this.unicode);

  @override
  final int unicode;

  @override
  String get string => String.fromCharCode(unicode);
}
