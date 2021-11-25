import 'package:flutter/widgets.dart';
import 'package:fpdart/fpdart.dart' hide State;
import 'package:pullable_stream_builder/src/iterators.dart';

typedef PullableStreamState<T> = Either<dynamic, Option<T>>;

typedef PullableWidgetBuilder<T> = Widget Function(
  BuildContext,
  PullableStreamState<T>,
  void Function(),
);

@immutable
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

class _PullableStreamBuilderState<T> extends State<PullableStreamBuilder<T>> {
  late final iterator = safeStreamIterator<T>(widget.stream);
  late final iteratorPull = iterator.first;
  late final iteratorCancel = iterator.second;

  PullableStreamState<T> state = Either.right(none());

  @override
  void initState() {
    super.initState();
    _initialDemand(widget.initialDemand);
  }

  void _initialDemand(int remaining) async {
    if (remaining <= 0) return;
    await _demand();
    _initialDemand(remaining - 1);
  }

  Future<void> _demand() => iteratorPull().then((data) {
        data.map((data) {
          setState(() {
            state = Either.right(some(data));
          });
        });
      }, onError: (err) {
        setState(() {
          state = Either.left(err);
        });
      });

  @override
  Widget build(BuildContext context) => widget.builder(context, state, _demand);

  @override
  void dispose() {
    iteratorCancel();
    super.dispose();
  }
}
