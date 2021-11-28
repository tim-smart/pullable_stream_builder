import 'dart:async';
import 'dart:collection';

import 'package:fpdart/fpdart.dart';
import 'package:rxdart/rxdart.dart';

/// tuple2<optionOf(chunk), hasMore>
typedef PullData<T> = Tuple2<Option<T>, bool>;
typedef PullResult<T> = Either<Future<PullData<T>>, PullData<T>>;
typedef PullFunction<T> = PullResult<T> Function();
typedef StreamIteratorTuple<T> = Tuple2<PullFunction<T>, void Function()>;

StreamIteratorTuple<T> streamIterator<T>(
  Stream<T> stream, {
  Option<T> initialValue = const None(),
}) {
  if (stream is ValueStream<T> && stream.hasValue) {
    return streamIterator(stream.skip(1), initialValue: optionOf(stream.value));
  }

  final queue = Queue<T>();
  Completer<Option<T>>? puller;

  StreamSubscription<T>? subscription;
  var complete = false;
  dynamic error;

  bool hasMore() => !complete || error == null;

  PullResult<T> noData() => Either.right(Tuple2(const None(), hasMore()));
  PullResult<T> syncData(T data) => Either.right(Tuple2(Some(data), hasMore()));
  PullResult<T> asyncData(Future<Option<T>> data) =>
      Either.left(data.then((data) => Tuple2(data, hasMore())));
  PullResult<T> withError(dynamic err) => Either.left(Future.error(err));

  void onData(T data) {
    if (puller != null) {
      puller?.complete(some(data));
      puller = null;
    } else {
      queue.add(data);
    }

    subscription!.pause();
  }

  void cleanup() {
    complete = true;
    subscription?.cancel();

    puller?.complete(none());
    puller = null;
  }

  void onError(dynamic err) {
    error = err;
    puller?.completeError(error);
    puller = null;
    cleanup();
  }

  void resume() {
    if (subscription == null) {
      subscription = stream.listen(onData, onError: onError, onDone: cleanup);
    } else {
      subscription!.resume();
    }
  }

  PullResult<T> pull() {
    if (queue.isNotEmpty) {
      final item = queue.removeFirst();
      return syncData(item);
    }

    if (error != null) return withError(error);
    if (complete) return noData();
    if (puller != null) return noData();

    resume();

    puller = Completer.sync();
    return asyncData(puller!.future);
  }

  initialValue.map(queue.add);

  return tuple2(pull, cleanup);
}
