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

/// Generic [List]
///
/// {@category schema}
final sequenceTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'seq');

/// Generic [String]
///
/// {@category schema}
final stringTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'str');

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

//
// ** Dart Tags **
//

/// [Uri] tag
///
/// {@category schema}
final uriTag = TagShorthand.fromTagUri(_defaultYamlHandle, 'uri');

/// Any [TagShorthand] that resolves to a [Scalar]
///
/// {@category schema}
final scalarTags = {
  stringTag,
  nullTag,
  booleanTag,
  integerTag,
  floatTag,
  uriTag,
};

/// Checks if a [tag] is valid tag in the yaml schema. A yaml tag uses the
/// [TagHandleVariant.secondary] handle
///
/// {@category schema}
bool isYamlTag(TagShorthand tag) =>
    tag == mappingTag || tag == sequenceTag || scalarTags.contains(tag);
