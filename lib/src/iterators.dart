import 'dart:async';
import 'dart:collection';

import 'package:fpdart/fpdart.dart';
import 'package:rxdart/subjects.dart';

typedef PullFunction<T> = FutureOr<Option<T>> Function();
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

  late StreamSubscription<T> subscription;
  var complete = false;
  dynamic error;

  void onData(T data) {
    if (puller != null) {
      puller?.complete(some(data));
      puller = null;
    } else {
      queue.add(data);
    }

    subscription.pause();
  }

  void cleanup() {
    complete = true;
    subscription.cancel();
  }

  void onError(dynamic err) {
    error = err;
    puller?.completeError(error);
    puller = null;
    cleanup();
  }

  FutureOr<Option<T>> pull() {
    if (queue.isNotEmpty) {
      final item = queue.removeFirst();
      return some(item);
    }

    if (complete) return none();
    if (error != null) return Future.error(error);
    if (puller != null) return none();

    puller = Completer.sync();
    subscription.resume();
    return puller!.future;
  }

  subscription = stream.listen(onData, onError: onError, onDone: cleanup);
  initialValue.map(queue.add);

  return tuple2(pull, cleanup);
}
