part of 'directives.dart';

abstract interface class _Tag {
  TagHandle get tagHandle;

  String get prefix;
}

abstract interface class _ResolvedTag extends _Tag {
  String get verbatim;
}

sealed class SpecificTag<T> implements _Tag {
  SpecificTag._(this.tagHandle, this.content);

  SpecificTag.fromLocalTag(TagHandle tagHandle, LocalTag tag)
    : this._(tagHandle, tag as T);

  SpecificTag.fromString(TagHandle tagHandle, String uri)
    : this._(tagHandle, uri as T);

  @override
  final TagHandle tagHandle;

  final T content;
}

final class NonSpecificTag implements _Tag {
  @override
  TagHandle get tagHandle => TagHandle.primary();

  @override
  String get prefix => tagHandle.handle;
}
