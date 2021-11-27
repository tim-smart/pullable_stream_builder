import 'dart:async';
import 'dart:collection';

import 'package:fpdart/fpdart.dart';
import 'package:rxdart/subjects.dart';

typedef PullResult<T> = Either<Future<Option<T>>, Option<T>>;
typedef PullFunction<T> = PullResult<T> Function();
typedef StreamIteratorTuple<T> = Tuple2<PullFunction<T>, void Function()>;

StreamIteratorTuple<T> streamIterator<T>(
  Stream<T> stream, {
  Option<T> initialValue = const None(),
}) {
  if (stream is BehaviorSubject<T> && stream.hasValue) {
    return streamIterator(stream.skip(1), initialValue: optionOf(stream.value));
  }

  final queue = Queue<T>();
  Completer<Option<T>>? puller;

  StreamSubscription<T>? subscription;
  var complete = false;
  dynamic error;

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
      return Either.right(some(item));
    }

    if (error != null) return Either.left(Future.error(error));
    if (complete) return Either.right(none());
    if (puller != null) return Either.right(none());

    resume();

    puller = Completer.sync();
    return Either.left(puller!.future);
  }

  initialValue.map(queue.add);

  return tuple2(pull, cleanup);
}
