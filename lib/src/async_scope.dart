import 'dart:async';

import 'package:scopely/src/stream_lifecycle_transformer.dart';

class AsyncScope {
  final _children = <AsyncScope>[];

  AsyncScope([AsyncScope? parent]) {
    parent?._children.add(this);
  }

  final _tasksToCancel = <_CancelableTask>{};
  var _isCanceled = false;

  Future<ResultT> bindFuture<ResultT>(Future<ResultT> future) => 
    _bindTask(_FutureTask(future));

  Stream<EventT> bindStream<EventT>(Stream<EventT> stream) =>
    _bindTask(_StreamTask(stream));

  void cancelAll() async {
    for (var task in _tasksToCancel) {
      task.cancel();
    }
    _tasksToCancel.clear();

    for (var childScope in _children) {
      childScope.cancelAll();
    }

    _isCanceled = true;
  }

  DelegateT _bindTask<DelegateT>(_CancelableTask<DelegateT> task) {
    _throwIfCanceled();

    _tasksToCancel.add(task);
    
    void onDelegateDone() {
      _tasksToCancel.remove(task);
    }
    task.bind(onDelegateDone);
    return task.boundDelegate;
  }

  void _throwIfCanceled() {
    if (_isCanceled) throw AsyncScopeCanceledError();
  }
}


class AsyncScopeCanceledError extends StateError {
  AsyncScopeCanceledError() : super("AsyncScope has already been canceled");
}

class AsyncTaskCancelationException implements Exception {
  // internal factory constructor ensures a singleton instance is used for all cancelation signals
  factory AsyncTaskCancelationException._() => const AsyncTaskCancelationException._constructConst();

  // class-private constructor; use factory constructor instead
  const AsyncTaskCancelationException._constructConst();

  @override
  String toString() => "AsyncScopeCancelationException";
}


extension FutureScoping<ResultT> on Future<ResultT> {
  Future<ResultT> inScope(AsyncScope scope) => scope.bindFuture(this);
}

extension StreamScoping<EventT> on Stream<EventT> {
  Stream<EventT> inScope(AsyncScope scope) => scope.bindStream(this);
}


abstract class _CancelableTask<DelegateT> {
  final DelegateT delegate;

  _CancelableTask(this.delegate);

  abstract final DelegateT boundDelegate;
  
  void bind(void Function() signalDelegateDone);
  void cancel();
}

final class _FutureTask<ResultT> extends _CancelableTask<Future<ResultT>> {
  final _boundCompleter = Completer<ResultT>();

  _FutureTask(super.delegate);

  @override
  late Future<ResultT> boundDelegate = _boundCompleter.future;

  @override
  void bind(void Function() signalDelegateDone) async {
    try {
      var result = await delegate;
      _attemptComplete(() => _boundCompleter.complete(result));
    } catch (error, stackTrace) {
      _attemptComplete(() => _boundCompleter.completeError(error, stackTrace));
    } finally {
      signalDelegateDone();
    }
  }

  @override
  void cancel() {
    _attemptComplete(() => _boundCompleter.completeError(AsyncTaskCancelationException._()));
  }

  void _attemptComplete(void Function() completionBlock) {
    if (!_boundCompleter.isCompleted) {
      completionBlock();
    }
  }
}

final class _StreamTask<EventT> extends _CancelableTask<Stream<EventT>> {
  _StreamTask(super.delegate);

  @override
  late final Stream<EventT> boundDelegate;

  late final _StreamTaskTransformer<EventT> bindingTransformer;

  @override
  void bind(void Function() signalDelegateDone) async {
    bindingTransformer = _StreamTaskTransformer(signalDelegateDone);
    boundDelegate = delegate.transform(bindingTransformer);
  }

  @override
  void cancel() {
    bindingTransformer.taskOnCancel();
  }
}

final class _StreamTaskTransformer<EventT> extends StreamLifecycleTransformer<EventT, EventT> {
  final void Function() signalSourceDone;

  _StreamTaskTransformer(this.signalSourceDone);

  StreamSubscription? delegateSubscription;
  late StreamController<EventT> boundController;

  @override
  StreamController<EventT> onBindDestController(Stream<EventT> sourceStream, StreamControllerHandlers handlers) {
    var controller = super.onBindDestController(sourceStream, handlers);
    boundController = controller;
    return controller;
  }

  @override
  StreamSubscription<EventT>? destOnListen(TransformerContext<EventT, EventT> context) {
    var subscription = super.destOnListen(context);
    delegateSubscription = subscription;
    return subscription;
  }

  @override
  FutureOr<StreamSubscription<EventT>?> destOnCancel(TransformerContext<EventT, EventT> context) async {
    var subscription = await super.destOnCancel(context);
    if (!context.sourceStream.isBroadcast) {
      signalSourceDone();
    }
    delegateSubscription = subscription;
    return subscription;
  }

  @override
  void sourceOnData(TransformerContext<EventT, EventT> context, EventT event) {
    context.destController.add(event);
  }

  @override
  FutureOr<void> sourceOnDone(TransformerContext<EventT, EventT> context) async {
    await super.sourceOnDone(context);
    signalSourceDone();
  }

  void taskOnCancel() async {
    await delegateSubscription?.cancel();

    if (!boundController.isClosed) {
      boundController.addError(AsyncTaskCancelationException._());
      await boundController.close();
    }
  }
}
