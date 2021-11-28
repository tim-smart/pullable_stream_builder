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

typedef PersistedStreamFactory = ValueStream<T> Function(Stream<T>)
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

final _cache = <String, dynamic>{};

Option<T> Function() _readCache<T>(
  Storage storage,
  String key,
  T Function(Object?) fromJson,
) =>
    () {
      if (_cache.containsKey(key)) return _cache[key];

      final data = storage
          .read(key)
          .flatMap((json) => Option.tryCatch(() => fromJson(jsonDecode(json))));
      _cache[key] = data;
      return data;
    };

void Function(T) _writeCache<T>(
  Storage storage,
  String key,
  Object? Function(T) toJson,
) =>
    (value) {
      try {
        storage.write(key, jsonEncode(toJson(value)));
      } catch (_) {}
      _cache[key] = some(value);
    };

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
      final read = _readCache(storage, storageKey, fromJson);
      final write = _writeCache(storage, storageKey, toJson);

      return (Stream<T> stream) {
        final initialValue = read();

        stream = initialValue.match(
          (prev) => stream.skipWhile(
              (next) => (skipPredicate ?? defaultSkipPredicate)(prev, next)),
          () => stream,
        );

        final writeStream = stream.doOnData(write);

        return initialValue.match<ValueStream<T>>(
          (initial) => writeStream.publishValueSeeded(initial),
          () => writeStream.publishValue(),
        );
      };
    };

typedef PersistedIListStreamFactory
    = ValueStream<IList<T>> Function(Stream<IList<T>>) Function<T>({
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

ValueStream<IList<T>> accumulatedValueStream<T>(Stream<IList<T>> stream) =>
    accumulatedStream(stream).publishValue();

PersistedIListStreamFactory persistedAccumulatedStream(Storage storage) => <T>({
      required key,
      required toJson,
      required fromJson,
    }) =>
        (Stream<IList<T>> stream) => persistedIListStream(storage)<T>(
              key: key,
              toJson: toJson,
              fromJson: fromJson,
            )(accumulatedStream(stream));

Stream<R> Function(ValueStream<T>) transformedValueStream<T, R>(
  R Function(T) predicate,
) =>
    (stream) {
      final mappedStream = stream.map(predicate);

      return optionOf(stream.valueOrNull).map(predicate).match(
            (initial) => mappedStream.publishValueSeeded(initial),
            () => mappedStream,
          );
    };

class ResourceStreamState<T, Acc> {
  const ResourceStreamState({
    required this.acc,
    required this.chunk,
    required this.hasMore,
  });

  final Acc acc;
  final List<T> chunk;
  final bool hasMore;
}

Stream<T> resourceStream<T, Acc>({
  required FutureOr<Acc> Function() init,
  required Future<ResourceStreamState<T, Acc>> Function(
    ResourceStreamState<T, Acc> state,
  )
      process,
  void Function(Acc)? cleanup,
}) async* {
  var state = ResourceStreamState<T, Acc>(
    acc: await init(),
    chunk: [],
    hasMore: true,
  );

  while (state.hasMore) {
    state = await process(state);

    for (final item in state.chunk) {
      yield item;
    }
  }

  if (cleanup != null) {
    cleanup(state.acc);
  }
}
