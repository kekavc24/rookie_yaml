import 'package:rookie_yaml/src/parser/directives/directives.dart';
import 'package:rookie_yaml/src/schema/nodes/yaml_node.dart';

/// Default `YAML` uri prefix
const _yamlPrefix = 'tag:yaml.org,2002:';

/// Default handle for the global `YAML` tag.
///
/// See [_yamlPrefix]
final _defaultYamlHandle = TagHandle.secondary();

/// `YAML` global tag
///
/// ```text
/// %TAG !! tag:yaml.org,2002:
/// ```
///
/// {@category schema}
final yamlGlobalTag = GlobalTag.fromTagUri(_defaultYamlHandle, _yamlPrefix);

/// Generic [Map]
///
/// {@category schema}
final mappingTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'map');

/// Generic ordered [Map]
///
/// {@category schema}
final orderedMappingTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'omap');

/// Generic [List]
///
/// {@category schema}
final sequenceTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'seq');

/// Generic [String]
///
/// {@category schema}
final stringTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'str');

/// Generic [Set]
///
/// {@category schema}
final setTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'set');

//
// ** JSON SCHEMA TAGS **
// This schema is supported by YAML out of the box.
//

/// `JSON` `null`
///
/// {@category schema}
final nullTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'null');

/// `JSON` [bool]
///
/// {@category schema}
final booleanTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'bool');

/// `JSON` [int]
///
/// {@category schema}
final integerTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'int');

/// `JSON` [double]
///
/// {@category schema}
final floatTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'float');

/// Any [TagShorthand] that resolves to a [Scalar]
///
/// {@category schema}
final scalarTags = {};

/// Whether a [tag] is a valid [Map] or [Mapping] tag.
///
/// {@category schema}
bool isYamlMapTag(TagShorthand tag) =>
    tag == mappingTag || tag == orderedMappingTag;

/// Whether a [tag] is a valid [List] or [Set] or [Sequence] tag.
///
/// {@category schema}
bool isYamlSequenceTag(TagShorthand tag) => tag == sequenceTag || tag == setTag;

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
