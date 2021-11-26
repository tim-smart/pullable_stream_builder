import 'dart:async';
import 'dart:convert';

import 'package:fast_immutable_collections/fast_immutable_collections.dart'
    hide Tuple2;
import 'package:fpdart/fpdart.dart';
import 'package:pullable_stream_builder/src/storage.dart';
import 'package:rxdart/rxdart.dart';

typedef ChunkedStreamFactory<T> = Stream<IList<T>> Function(
  Stream<T> stream, {
  int chunkSize,
});

Stream<IList<T>> chunkedStream<T>(
  Stream<T> stream, {
  int chunkSize = 10,
}) =>
    stream
        .bufferCount(chunkSize)
        .scan<IList<T>>((acc, chunk, index) => acc.addAll(chunk), IList());

typedef PersistedStreamFactory = BehaviorSubject<T> Function(Stream<T>)
    Function<T>({
  required String key,
  required Object? Function(T) toJson,
  required T Function(Object?) fromJson,
  bool Function(T prev, T next)? skipPredicate,
});

bool defaultSkipPredicate<T>(T prev, T next) => prev == next;
bool iListSkipPredicate<T>(IList<T> prev, IList<T> next) {
  final prevLength = prev.length;
  final nextLength = next.length;

  if (prevLength == nextLength) {
    return prev == next;
  } else if (prevLength < nextLength) {
    return false;
  }

  return prev.sublist(0, nextLength) == next;
}

PersistedStreamFactory persistedStream(
  Storage storage,
) =>
    <T>({
      required key,
      required toJson,
      required fromJson,
      skipPredicate,
    }) {
      final storageKey = 'PullableStreamBuilder_$key';

      return (Stream<T> stream) {
        final initialValue = storage.read(storageKey).flatMap(
            (json) => Option.tryCatch(() => fromJson(jsonDecode(json))));

        final subject = initialValue.match<BehaviorSubject<T>>(
          (initial) => BehaviorSubject.seeded(initial, sync: true),
          () => BehaviorSubject(sync: true),
        );

        stream = initialValue.match(
          (prev) => stream.skipWhile(
              (next) => (skipPredicate ?? defaultSkipPredicate)(prev, next)),
          () => stream,
        );

        final writeStream = stream.doOnData((event) {
          try {
            storage.write(storageKey, jsonEncode(toJson(event)));
          } catch (_) {}
        });

        subject.addStream(writeStream).whenComplete(subject.close);

        return subject;
      };
    };

typedef PersistedIListStreamFactory
    = BehaviorSubject<IList<T>> Function(Stream<IList<T>>) Function<T>({
  required String key,
  required Object? Function(T) toJson,
  required T Function(Object?) fromJson,
});

PersistedIListStreamFactory persistedIListStream(Storage storage) => <T>({
      required key,
      required toJson,
      required fromJson,
    }) =>
        (stream) => persistedStream(storage)<IList<T>>(
              key: key,
              toJson: (val) => val.toJson(toJson),
              fromJson: (json) => IList.fromJson(json, fromJson),
              skipPredicate: iListSkipPredicate,
            )(stream);

Stream<IList<T>> accumulatedStream<T>(Stream<IList<T>> stream) =>
    stream.scan<IList<T>>(
      (acc, chunk, index) => acc.addAll(chunk).toIList(),
      IList(),
    );

BehaviorSubject<IList<T>> accumulatedBehaviourStream<T>(
  Stream<IList<T>> stream,
) {
  final accStream = accumulatedStream(stream);
  final subject = BehaviorSubject<IList<T>>();
  subject.addStream(accStream).whenComplete(subject.close);
  return subject;
}

PersistedIListStreamFactory persistedAccumulatedStream(Storage storage) => <T>({
      required key,
      required toJson,
      required fromJson,
    }) =>
        (Stream<IList<T>> stream) {
          final accStream = accumulatedStream(stream);
          return persistedIListStream(storage)<T>(
            key: key,
            toJson: toJson,
            fromJson: fromJson,
          )(accStream);
        };

BehaviorSubject<R> Function(BehaviorSubject<T>)
    transformedBehaviorSubject<T, R>(R Function(T) predicate) => (subject) {
          final newSubject = optionOf(subject.valueOrNull).map(predicate).match(
                (initial) => BehaviorSubject.seeded(initial),
                () => BehaviorSubject<R>(),
              );

          newSubject
              .addStream(
                  (subject.hasValue ? subject.skip(1) : subject).map(predicate))
              .whenComplete(newSubject.close);

          return newSubject;
        };
