part of '../parser/yaml_parser.dart';

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
final yamlGlobalTag = GlobalTag.fromTagUri(_defaultYamlHandle, _yamlPrefix);

/// Generic mapping
final mappingTag = LocalTag.fromTagUri(_defaultYamlHandle, 'map');

/// Generic sequence
final sequenceTag = LocalTag.fromTagUri(_defaultYamlHandle, 'seq');

/// Generic string
final stringTag = LocalTag.fromTagUri(_defaultYamlHandle, 'str');

//
// ** JSON SCHEMA TAGS **
// This schema is supported by YAML out of the box.
//

/// `JSON` null
final nullTag = LocalTag.fromTagUri(_defaultYamlHandle, 'null');

/// `JSON` boolean
final booleanTag = LocalTag.fromTagUri(_defaultYamlHandle, 'bool');

/// `JSON` integer
final integerTag = LocalTag.fromTagUri(_defaultYamlHandle, 'int');

/// `JSON` floating point
final floatTag = LocalTag.fromTagUri(_defaultYamlHandle, 'float');

/// YAML scalar tags
final yamlScalarTags = [stringTag, nullTag, booleanTag, integerTag, floatTag];
