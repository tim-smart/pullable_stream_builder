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

  Widget build(
    BuildContext context,
    PullableStreamState<T> state,
    VoidCallback pull,
  ) =>
      builder(context, state, pull);
}

class _PullableStreamBuilderState<T> extends State<PullableStreamBuilder<T>> {
  SafeStreamIterator<T>? iterator;
  Future<Option<T>> Function() get iteratorPull => iterator!.first;
  VoidCallback get iteratorCancel => iterator!.second;

  PullableStreamState<T> state = Either.right(none());

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
    iterator = safeStreamIterator(widget.stream);
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
  Widget build(BuildContext context) => widget.build(context, state, _demand);

  @override
  void dispose() {
    iteratorCancel();
    super.dispose();
  }
}
