# yaml_dart

A collection of `Dart` packages that help you to interact with YAML and the features it supports in the official [spec](https://yaml.org/spec/1.2.2/).

> [!IMPORTANT]
> Supports YAML 1.2+ features. Earlier versions are supported but parsing is done with YAML 1.2+ grammar rules.
>
> By default, all empty documents are treated as `null` and never excluded when loaded. This compromise has resulted in a lower pass rate (`89.05%`) when running the official [YAML Test Suite](https://github.com/yaml/yaml-test-suite) in `package:rookie_yaml` :)

## Packages

| Package | Description | Version |
| --------| ----------- | ------- |
| [rookie_yaml](packages/rookie_yaml/) | A loader and dumper for YAML. | [![pub package](https://img.shields.io/pub/v/rookie_yaml.svg)](https://pub.dev/packages/rookie_yaml) |

## Contributions

Visit [CONTRIBUTING.md](CONTRIBUTING.md) for more information.
