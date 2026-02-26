import 'package:rookie_yaml/src/parser/directives/directives.dart';

/// Default `YAML` uri prefix
const _yamlPrefix = 'tag:yaml.org,2002:';

/// Default handle for the global `YAML` tag.
///
/// See [_yamlPrefix]
final defaultYamlHandle = TagHandle.secondary();

/// `YAML` global tag
///
/// ```text
/// %TAG !! tag:yaml.org,2002:
/// ```
///
/// {@category schema}
final yamlGlobalTag = GlobalTag.fromTagUri(defaultYamlHandle, _yamlPrefix);

/// Generic [Map]
///
/// {@category schema}
final mappingTag = TagShorthand.fromTagUri(defaultYamlHandle, 'map');

/// Generic ordered [Map]
///
/// {@category schema}
final orderedMappingTag = TagShorthand.fromTagUri(defaultYamlHandle, 'omap');

/// Generic [List]
///
/// {@category schema}
final sequenceTag = TagShorthand.fromTagUri(defaultYamlHandle, 'seq');

/// Generic [String]
///
/// {@category schema}
final stringTag = TagShorthand.fromTagUri(defaultYamlHandle, 'str');

/// Generic [Set]
///
/// {@category schema}
final setTag = TagShorthand.fromTagUri(defaultYamlHandle, 'set');

//
// ** JSON SCHEMA TAGS **
// This schema is supported by YAML out of the box.
//

/// `JSON` `null`
///
/// {@category schema}
final nullTag = TagShorthand.fromTagUri(defaultYamlHandle, 'null');

/// `JSON` [bool]
///
/// {@category schema}
final booleanTag = TagShorthand.fromTagUri(defaultYamlHandle, 'bool');

/// `JSON` [int]
///
/// {@category schema}
final integerTag = TagShorthand.fromTagUri(defaultYamlHandle, 'int');

/// `JSON` [double]
///
/// {@category schema}
final floatTag = TagShorthand.fromTagUri(defaultYamlHandle, 'float');

/// Whether a [tag] can be used as both a [Sequence] and [Mapping] tag.
bool _canBeSequenceOrMap(TagShorthand tag) =>
    tag == orderedMappingTag || tag == setTag;

/// Whether a [tag] is a valid [Map] or [Mapping] tag.
///
/// {@category schema}
bool isYamlMapTag(TagShorthand tag) =>
    tag == mappingTag || _canBeSequenceOrMap(tag);

/// Whether a [tag] is a valid [List] or [Set] or [Sequence] tag.
///
/// {@category schema}
bool isYamlSequenceTag(TagShorthand tag) =>
    tag == sequenceTag || _canBeSequenceOrMap(tag);

/// Whether a [tag] is a valid [Scalar] tag.
///
/// {@category schema}
bool isYamlScalarTag(TagShorthand tag) =>
    tag == stringTag ||
    tag == nullTag ||
    tag == booleanTag ||
    tag == integerTag ||
    tag == floatTag;

/// Whether a [tag] is valid tag in the yaml schema. A yaml tag uses the
/// [TagHandleVariant.secondary] handle.
///
/// {@category schema}
bool isYamlTag(TagShorthand tag) =>
    isYamlMapTag(tag) || isYamlSequenceTag(tag) || isYamlScalarTag(tag);
