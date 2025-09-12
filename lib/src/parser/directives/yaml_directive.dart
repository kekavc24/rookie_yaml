part of 'directives.dart';

const _versionSeparator = period;

const _pinnedMajor = 1;

/// `YAML` version that is used to implement the current `YamlParser` version.
///
/// Must support this and all lower versions.
final parserVersion = YamlDirective.ofVersion(_pinnedMajor, 2);

/// `YAML` version directive
const _yamlDirective = 'YAML';

/// Specifies the version a `YAML` document conforms to.
final class YamlDirective extends ReservedDirective {
  YamlDirective._(this.major, this.minor, String version)
    : super(name: _yamlDirective, parameters: [version]);

  /// Creates a yaml directive from the [major] and [minor] versions joined
  /// with a period.
  YamlDirective.ofVersion(int major, int minor)
    : this._(major, minor, '$major.$minor');

  /// `YAML` major version
  final int major;

  /// `YAML` minor version
  final int minor;

  /// Returns `true` if the current [major] version is supported by the
  /// parser.
  ///
  /// Differing [minor] versions of the same [major] version may be supported
  /// based on the `YAML` features used. Lower versions may have unsupported
  /// features. Higher versions may introduce new or modify existing behaviour.
  bool get isSupported => _pinnedMajor >= major;

  /// Returns the actual version
  String get version => parameters.first;
}

/// Returns a [YamlDirective] after verifying if the [parsedMajor] and
/// [parsedMinor] are supported by the current [parserVersion].
YamlDirective _verifyYamlVersion(
  int parsedMajor,
  int parsedMinor,
  void Function(String message) logger,
) {
  final sourceVersion = '$parsedMajor.$parsedMinor';
  final YamlDirective(:minor, :version) = parserVersion;

  /// Major versions are incompatible
  /// https://yaml.org/spec/1.2.2/#681-yaml-directives
  if (parsedMajor != _pinnedMajor) {
    throw FormatException(
      'Unsupported YAML version requested.\n'
      '\tSource string version: $sourceVersion\n'
      '\tParser version: $version',
    );
  }

  if (parsedMinor != minor) {
    logger(
      'YamlParser only supports YAML version "$version". Found YAML version '
      '"$sourceVersion" which may have unsupported features.',
    );
  }

  return YamlDirective._(parsedMajor, parsedMinor, sourceVersion);
}

/// Parses a [YamlDirective] version number
YamlDirective _parseYamlDirective(
  GraphemeScanner scanner,
  void Function(String message) logger,
) {
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
      '"${_versionSeparator.asString()}" but found: %YAML '
      '${formattedVersion.join('.')}',
    );
  }

  return _verifyYamlVersion(formattedVersion[0], formattedVersion[1], logger);
}
