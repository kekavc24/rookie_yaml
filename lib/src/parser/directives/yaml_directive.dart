part of 'directives.dart';

const _versionSeparator = period;

/// `YAML` version that is used to implement the current `YamlParser` version.
///
/// Must support this and all lower versions.
const _version = [1, 2];
final parserVersion = YamlDirective._(
  version: _version.join(_versionSeparator.asString()),
  formatted: _version,
);

/// `YAML` version directive
const _yamlDirective = 'YAML';

/// Specifies the version a `YAML` document conforms to.
final class YamlDirective extends ReservedDirective {
  YamlDirective._({required String version, required List<int> formatted})
    : _formatted = formatted,
      super(name: _yamlDirective, parameters: [version]);

  /// Creates a directive from a version.
  ///
  /// [version] should be 2 integers separated by a `.`
  YamlDirective.ofVersion(String version)
    : this._(version: version, formatted: _formatVersionParameter(version));

  final List<int> _formatted;
}

/// Checks if the current version is supported by our parser.
({bool isSupported, bool shouldWarn}) checkVersion(YamlDirective directive) {
  final [currentMajor, currentMin] = parserVersion._formatted;
  final [parsedMajor, parsedMin] = directive._formatted;

  final isSupported = currentMajor >= parsedMajor;

  return (
    isSupported: isSupported,
    shouldWarn: !isSupported || (isSupported && parsedMin > currentMin),
  );
}

/// Formats a version to individual integers denoting the version
List<int> _formatVersionParameter(String version) {
  void throwException(String violator) {
    final message = violator.isEmpty ? 'nothing' : violator;
    throw FormatException('Expected an integer but found "$message"');
  }

  final formatted = version.split(_versionSeparator.asString());

  if (formatted.length != 2) {
    throw FormatException(
      'Invalid YAML version format. '
      'The version must have only 2 integers separated by a '
      '"${_versionSeparator.asString()}"',
    );
  }

  return formatted.map((v) {
    final parsed = int.tryParse(v);

    if (parsed == null) {
      throwException(v);
    }

    return parsed!;
  }).toList();
}

/// Parses a [YamlDirective] version number
YamlDirective _parseYamlDirective(GraphemeScanner scanner) {
  final versionBuffer = StringBuffer();

  final formattedVersion = <int>[];

  // Track state of converting string to number
  const versionReset = -1;

  int? lastChar;
  var version = versionReset;

  const prefix = 'Invalid YAML version format. ';

  versionBuilder:
  while (scanner.canChunkMore) {
    final char = scanner.charAtCursor!;

    switch (char) {
      case lineFeed || carriageReturn || space || tab:
        break versionBuilder;

      case _ when char.isDigit():
        version = (max(version, 0) * 10) + (char - asciiZero);

      case _versionSeparator:
        {
          // We must not see the separator if we have no integers
          if (lastChar == null) {
            throw FormatException(
              '$prefix'
              'Version cannot start with a "${_versionSeparator.asString()}"',
            );
          } else if (lastChar == _versionSeparator) {
            throw FormatException(
              '$prefix'
              'Version cannot have consecutive '
              '"${_versionSeparator.asString()}" characters',
            );
          }

          formattedVersion.add(version);
          version = versionReset;
        }

      default:
        throw FormatException(
          'Invalid "${char.asString()}" character in YAML version. '
          'Only digits separated by "${_versionSeparator.asString()}"'
          ' characters are allowed.',
        );
    }

    versionBuffer.writeCharCode(char);
    lastChar = char;
    scanner.skipCharAtCursor();
  }

  if (version != versionReset) {
    formattedVersion.add(version);
  }

  if (formattedVersion.length != 2 || lastChar == _versionSeparator) {
    throw FormatException(
      '$prefix'
      'A YAML version must have only 2 integers separated by '
      '"${_versionSeparator.asString()}"',
    );
  }

  return YamlDirective._(
    version: versionBuffer.toString(),
    formatted: formattedVersion,
  );
}
