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
  Option<IList<T>> initialValue = const None(),
}) {
  var chunkedStream = stream
      .bufferCount(chunkSize)
      .scan<IList<T>>((acc, chunk, index) => acc.addAll(chunk), IList());

  return initialValue.match(
    (initial) => chunkedStream.startWith(initial).distinct((prev, next) {
      if (prev.length < next.length) return false;
      return prev.sublist(0, next.length) == next;
    }),
    () => chunkedStream,
  );
}

typedef PersistedStreamFactory = Stream<T> Function(Stream<T>) Function<T>({
  required String key,
  required Object? Function(T) toJson,
  required T Function(Object?) fromJson,
});

PersistedStreamFactory persistedStream(
  Storage storage,
) =>
    <T>({
      required key,
      required toJson,
      required fromJson,
    }) {
      final storageKey = 'PullableStreamBuilder_persisted_$key';

      return (Stream<T> stream) {
        final initialValue = storage.read(storageKey).flatMap(
            (json) => Option.tryCatch(() => fromJson(jsonDecode(json))));

        final writeStream = stream.doOnData((event) {
          try {
            storage.write(storageKey, jsonEncode(toJson(event)));
          } catch (_) {}
        });

        return initialValue.match(
          (initial) => writeStream.startWith(initial),
          () => writeStream,
        );
      };
    };

typedef PersistedIListStreamFactory
    = Stream<IList<T>> Function(Stream<IList<T>>) Function<T>({
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
            )(stream);

Stream<IList<T>> accumulatedStream<T>(Stream<IList<T>> stream) =>
    stream.scan<IList<T>>(
      (acc, chunk, index) => acc.addAll(chunk).toIList(),
      IList(),
    );

Stream<IList<T>> accumulatedBehaviourStream<T>(Stream<IList<T>> stream) {
  final subject = BehaviorSubject<IList<T>>(sync: true);
  subject.addStream(accumulatedStream(stream)).whenComplete(subject.close);
  return subject;
}

PersistedIListStreamFactory persistedAccumulatedStream(Storage storage) => <T>({
      required key,
      required toJson,
      required fromJson,
    }) =>
        (Stream<IList<T>> stream) {
          final accStream = accumulatedBehaviourStream(stream);
          return persistedIListStream(storage)<T>(
            key: key,
            toJson: toJson,
            fromJson: fromJson,
          )(accStream);
        };
