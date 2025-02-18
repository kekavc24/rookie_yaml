/// Indicates the context for a yaml stream being parsed/produced
enum YamlContext {
  /// Within a block style context
  blockIN,

  /// Outside a block style context
  blockOUT,

  /// Within a block key context.
  blockKEY,

  /// Within a flow style context
  flowIN,

  /// Outside a flow style context
  flowOUT,

  /// Within a flow key context
  flowKEY,
}
