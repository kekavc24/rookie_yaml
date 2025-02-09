import 'package:rookie_yaml/src/character_encoding/character_encoding.dart';
import 'package:rookie_yaml/src/yaml_nodes/node.dart';
import 'package:rookie_yaml/src/yaml_nodes/node_styles.dart';

enum NextParseTarget {
  wildcard,

  startFlowSequence,

  nextBlockEntry,

  nextFlowEntry,

  endFlowSequence,

  startBlockSequence,

  startFlowMap,

  startFlowValue,

  endFlowMap;

  static NextParseTarget checkTarget(ReadableChar? char) {
    return switch (char) {
      Indicator.mappingStart => NextParseTarget.startFlowMap,
      Indicator.mappingEnd => NextParseTarget.endFlowMap,
      Indicator.flowSequenceStart => NextParseTarget.startFlowSequence,
      Indicator.flowSequenceEnd => NextParseTarget.endFlowSequence,
      (Indicator.flowEntryEnd || Indicator.mappingKey) =>
        NextParseTarget.nextFlowEntry,
      Indicator.blockSequenceEntry => NextParseTarget.nextBlockEntry,
      Indicator.mappingValue => NextParseTarget.startFlowValue,
      _ => NextParseTarget.wildcard,
    };
  }
}

/// Represents a return type for styles that use indent to denote their
/// structure. Typically (but not limited to), [ScalarStyle.plain]. This also
/// includes [ScalarStyle.literal] and [ScalarStyle.folded].
///
/// While `YAML` explicitly differentiates these styles based on their
/// [NodeStyle], it should be noted both [ScalarStyle.literal] and
/// [ScalarStyle.folded] are `plain` styles that use explicit indicators to
/// differentiate them for [ScalarStyle.plain] and qualify them as `block
/// scalar` styles.
typedef PlainStyleInfo = ({
  NextParseTarget parseTarget,
  Scalar? scalar,
  int? indentOnExit,
});
