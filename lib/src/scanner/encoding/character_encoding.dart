import 'dart:convert';

part 'encoding_utils.dart';

//
// Line breaks

/// `\n`
const lineFeed = 0x0A;

/// `\r`
const carriageReturn = 0x0D;

//
//

//
// Whitespace

/// \t
const tab = 0x09;

/// Normal whitespace
const space = 0x20;

//
//

//
// Indicators

/// Period `.`. When used as a triplet, forms the document end marker
const period = 0x2E;

/// Block sequence entry start `-`.
const blockSequenceEntry = 0x2D;

/// Mapping key start `?`
const mappingKey = 0x3F;

/// Mapping key end, mapping value start `:`
const mappingValue = 0x3A;

/// End of flow collection entry `,`
const flowEntryEnd = 0x2C;

/// Flow sequence start `[`
const flowSequenceStart = 0x5B;

/// Flow sequence end `]`
const flowSequenceEnd = 0x5D;

/// Flow mapping start `{`
const mappingStart = 0x7B;

/// Flow mapping end `}`
const mappingEnd = 0x7D;

/// Comment start `#`
const comment = 0x23;

/// Node's anchor property `&`
const anchor = 0x26;

/// Alias node `*`
const alias = 0x2A;

/// Specifies node tags `!`. Specifically:
///   - Tag handles used in tag directives & properties
///   - Local tags
///   - Non-specific tags for non-plain scalars
const tag = 0x21;

/// Literal block scalar start `|`
const literal = 0x7C;

/// Folded block scalar start `>`
const folded = 0x3E;

/// Single quoted flow scalar start and end `'`
const singleQuote = 0x27;

/// Double quoted flow scalar start and end `"`
const doubleQuote = 0x22;

/// Directive line start `%`
const directive = 0x25;

/// Reserved by YAML for future use `@`
const reservedAtSign = 0x40;

/// Reserved by YAML for future use [`]
const reservedGrave = 0x60;

//
//

//
// Special Escaped characters. Have leading "\"

/// `\0`
const unicodeNull = 0x00;

/// `\a`
const bell = 0x07;

/// `\b`
const backspace = 0x08;

/// `\v`
const verticalTab = 0x0B;

/// `\f`
const formFeed = 0x0C;

/// NEL
const nextLine = 0x85;

/// Line separator
const lineSeparator = 0x2028;

/// Paragraph separator
const paragraphSeparator = 0x2029;

/// `\e`
const asciiEscape = 0x1B;

/// `\/`
const slash = 0x2F;

/// `\\`
const backSlash = 0x5C;

/// Non-breaking space
const nbsp = 0xA0;

//
//
