import 'package:flutter/widgets.dart';
import 'package:state_notifier/state_notifier.dart';

typedef StateWidgetBuilder<T> = Widget Function(BuildContext context, T state);

final class NotifierView<T> extends StatefulWidget {
  const NotifierView({
    required this.notifier,
    required this.builder,
    super.key,
  });

  final StateNotifier<T> notifier;
  final StateWidgetBuilder<T> builder;

  @override
  State<NotifierView<T>> createState() => _NotifierViewState<T>();
}

final class _NotifierViewState<T> extends State<NotifierView<T>> {
  late T _state;
  late RemoveListener _removeListener;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(NotifierView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.notifier, widget.notifier)) {
      _removeListener();
      _subscribe();
    }
  }

  void _subscribe() {
    var first = true;
    _removeListener = widget.notifier.addListener((state) {
      if (first) {
        _state = state;
        first = false;
      } else if (mounted) {
        setState(() => _state = state);
      }
    });
  }

  @override
  void dispose() {
    _removeListener();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _state);
}
