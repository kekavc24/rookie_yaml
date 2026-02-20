part of 'directives.dart';

const _versionSeparator = period;

const _pinnedMajor = 1;

/// `YAML` version that is used to implement the current `YamlParser` version.
///
/// Must support this and all lower versions.
///
/// {@category yaml_docs}
final parserVersion = YamlDirective.ofVersion(_pinnedMajor, 2);

/// `YAML` version directive
const _yamlDirective = 'YAML';

/// Specifies the version a `YAML` document conforms to.
///
/// {@category yaml_docs}
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
  Never Function(String message) onMajorMismatch,
) {
  final sourceVersion = '$parsedMajor.$parsedMinor';
  final YamlDirective(:minor, :version) = parserVersion;

  /// Major versions are incompatible
  /// https://yaml.org/spec/1.2.2/#681-yaml-directives
  if (parsedMajor != _pinnedMajor) {
    onMajorMismatch(
      'Unsupported YAML version requested. Current parser version is $version',
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
  SourceIterator iterator,
  void Function(String message) logger,
) {
  final formattedVersion = <int>[];

  // Track state of converting string to number
  const versionReset = -1;

  int? lastChar;
  var version = versionReset;

  versionBuilder:
  while (!iterator.isEOF) {
    final char = iterator.current;

    switch (char) {
      case lineFeed || carriageReturn || space || tab:
        break versionBuilder;

      case _ when char.isDigit():
        version = (max(version, 0) * 10) + (char - asciiZero);

      case _versionSeparator:
        {
          // We must not see the separator if we have no integers
          if (lastChar == null) {
            throwWithSingleOffset(
              iterator,
              message: 'A YAML directive cannot start with a version separator',
              offset: iterator.currentLineInfo.current,
            );
          } else if (lastChar == _versionSeparator) {
            throwWithApproximateRange(
              iterator,
              message:
                  'A YAML directive cannot have consecutive version separators',
              current: iterator.currentLineInfo.current,
              charCountBefore: 1, // Highlight previous version separator
            );
          }

          formattedVersion.add(version);
          version = versionReset;
        }

      default:
        throwWithSingleOffset(
          iterator,
          message:
              'A YAML version directive can only have digits separated by'
              ' a "."',
          offset: iterator.currentLineInfo.current,
        );
    }

    lastChar = char;
    iterator.nextChar();
  }

  if (version != versionReset) {
    formattedVersion.add(version);
  }

  if (formattedVersion.length != 2 || lastChar == _versionSeparator) {
    throwForCurrentLine(
      iterator,
      message:
          'A YAML version directive can only have 2 integers separated by "."',
    );
  }

  return _verifyYamlVersion(
    formattedVersion[0],
    formattedVersion[1],
    logger,
    (m) => throwForCurrentLine(iterator, message: m),
  );
}
