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

typedef PersistedStreamFactory = ChunkedStreamFactory<T> Function<T>({
  required String key,
  required Map<String, dynamic> Function(T) toJson,
  required T Function(Object?) fromJson,
});

PersistedStreamFactory persistedChunkedStream(
  Storage storage,
) =>
    <T>({
      required key,
      required toJson,
      required fromJson,
    }) {
      final storageKey = 'persistedStreamPuller_$key';

      return (
        Stream<T> stream, {
        int chunkSize = 10,
      }) {
        final initialValue = storage.read(storageKey).flatMap((json) =>
            Option.tryCatch(() => IList.fromJson(jsonDecode(json), fromJson)));

        return chunkedStream(
          stream,
          chunkSize: chunkSize,
          initialValue: initialValue,
        ).doOnData((event) {
          try {
            storage.write(storageKey, jsonEncode(event.toJson(toJson)));
          } catch (_) {}
        });
      };
    };
