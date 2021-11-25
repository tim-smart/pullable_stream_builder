import 'dart:async';

import 'package:fpdart/fpdart.dart';

typedef PullResult<T> = Future<Tuple2<Option<T>, bool>>;
typedef PullFunction<T> = PullResult<T> Function();

typedef StreamIteratorTuple<T> = Tuple2<PullFunction<T>, void Function()>;

StreamIteratorTuple<T> streamIterator<T>(Stream<T> stream) {
  final iterator = StreamIterator(stream);

  Future<Tuple2<Option<T>, bool>> pull() async {
    final available = await iterator.moveNext();
    return tuple2(available ? some(iterator.current) : none(), available);
  }

  return tuple2(pull, iterator.cancel);
}

typedef SafePullResult<T> = Future<Option<T>>;
typedef SafePullFunction<T> = SafePullResult<T> Function();
typedef SafeStreamIterator<T> = Tuple2<SafePullFunction<T>, void Function()>;

/// Ensures only one running pull operation at a time
SafeStreamIterator<T> safeStreamIterator<T>(Stream<T> stream) {
  var pulling = false;
  var complete = false;
  dynamic error;

  final iterator = streamIterator(stream);
  final pull = iterator.first;
  final cancel = iterator.second;

  Future<Option<T>> safePull() async {
    if (error != null) {
      throw error;
    } else if (complete || pulling) {
      return none();
    }

    pulling = true;

    try {
      final result = await pull();
      final data = result.first;
      final hasMore = result.second;

      complete = !hasMore;
      pulling = false;

      return data;
    } catch (err) {
      error = err;
      rethrow;
    }
  }

  return tuple2(safePull, cancel);
}
