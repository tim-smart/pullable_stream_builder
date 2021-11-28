import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:pullable_stream_builder/src/iterators.dart';

typedef PullableStreamState<T> = Either<dynamic, Tuple2<Option<T>, bool>>;

typedef PullableWidgetBuilder<T> = Widget Function(
  BuildContext,
  PullableStreamState<T>,
  void Function(),
);

class PullableStreamBuilder<T> extends StatefulWidget {
  const PullableStreamBuilder({
    Key? key,
    required this.stream,
    required this.builder,
    this.initialDemand = 1,
  }) : super(key: key);

  final Stream<T> stream;
  final PullableWidgetBuilder<T> builder;
  final int initialDemand;

  @override
  _PullableStreamBuilderState<T> createState() =>
      _PullableStreamBuilderState<T>();
}

R withPullableValue<T, R>(
  PullableStreamState<T> value, {
  required R Function(dynamic) error,
  required R Function(T, bool) data,
  required R Function() loading,
}) =>
    value.match(error, (s) => s.first.match((v) => data(v, s.second), loading));

class _PullableStreamBuilderState<T> extends State<PullableStreamBuilder<T>> {
  StreamIteratorTuple<T>? iterator;
  PullFunction<T> get iteratorPull => iterator!.first;
  VoidCallback get iteratorCancel => iterator!.second;

  PullableStreamState<T> state = Either.right(tuple2(none(), true));

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant PullableStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.stream != widget.stream) {
      _subscribe();
    }
  }

  void _subscribe() {
    if (iterator != null) iteratorCancel();
    iterator = streamIterator(widget.stream);
    _initialDemand(widget.initialDemand);
  }

  void _initialDemand(int remaining) {
    if (remaining <= 0) return;
    _demand().then((_) => _initialDemand(remaining - 1));
  }

  Future<void> _demand() => iteratorPull().match(
        (future) => future.then(_handleData),
        (o) {
          _handleData(o);
          return Future.sync(() {});
        },
      );

  void _handleData(PullData<T> data) {
    data.first.map((value) {
      setState(() {
        state = Either.right(tuple2(some(value), data.second));
      });
    });
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, state, () => Future.microtask(_demand));

  @override
  void dispose() {
    iteratorCancel();
    super.dispose();
  }
}
