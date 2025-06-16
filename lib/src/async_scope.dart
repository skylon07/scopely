import 'dart:async';

import 'package:scopely/src/stream_lifecycle_transformer.dart';

class AsyncScope {
  final _children = <AsyncScope>[];

  AsyncScope([AsyncScope? parent]) {
    parent?._children.add(this);
  }

  final _tasksToCancel = <_CancelableTask>{};
  
  var _isCanceled = false;
  bool get isCanceled => _isCanceled;

  Future<ResultT> bindFuture<ResultT>(Future<ResultT> future) => 
    _bindTask(_FutureTask(this, future));

  Stream<EventT> bindStream<EventT>(Stream<EventT> stream) =>
    _bindTask(_StreamTask(this, stream));

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

  Future<void> catchCancellations(FutureOr<void> Function() body) async {
    return catchAllCancellations(body, shouldBeCaught: (cancelError) => cancelError._owner == this);
  }

  static Future<void> catchAllCancellations(FutureOr<void>? Function() body, {bool Function(TaskCancellationException cancelError)? shouldBeCaught}) async {
    shouldBeCaught ??= (_) => true;

    // you will get stuck awaiting a future that errors in a different zone,
    // so a completer allows us to bridge the error back to the caller
    var completer = Completer();
    runZonedGuarded(
      () async {
        try {
          await body();
          if (!completer.isCompleted) {
            completer.complete();
          }
        } on TaskCancellationException catch(error, stackTrace) {
          var forwardAsError = !shouldBeCaught!(error);
          if (forwardAsError) {
            completer.completeError(error, stackTrace);
          } else {
            completer.complete();
          }
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        }
      },
      (error, stackTrace) {
        var shouldForwardError =
          error is! TaskCancellationException ||
          !shouldBeCaught!(error);
        if (shouldForwardError) {
          Error.throwWithStackTrace(error, stackTrace);
        }
      },
    );
    return completer.future;
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

class TaskCancellationException implements Exception {
  final AsyncScope _owner;
  TaskCancellationException._(this._owner);

  @override
  String toString() => "$TaskCancellationException";
}


extension FutureScoping<ResultT> on Future<ResultT> {
  Future<ResultT> inScope(AsyncScope scope) => scope.bindFuture(this);
}

extension StreamScoping<EventT> on Stream<EventT> {
  Stream<EventT> inScope(AsyncScope scope) => scope.bindStream(this);
}

abstract class _CancelableTask<DelegateT> {
  final AsyncScope owner;
  final DelegateT delegate;

  _CancelableTask(this.owner, this.delegate);

  abstract final DelegateT boundDelegate;
  
  void bind(void Function() signalDelegateDone);
  void cancel();
}

final class _FutureTask<ResultT> extends _CancelableTask<Future<ResultT>> {
  final _boundCompleter = Completer<ResultT>();

  _FutureTask(super.owner, super.delegate);

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
    _attemptComplete(() => _boundCompleter.completeError(TaskCancellationException._(owner)));
  }

  void _attemptComplete(void Function() completionBlock) {
    if (!_boundCompleter.isCompleted) {
      completionBlock();
    }
  }
}

final class _StreamTask<EventT> extends _CancelableTask<Stream<EventT>> {
  _StreamTask(super.owner, super.delegate);

  @override
  late final Stream<EventT> boundDelegate;

  late final _StreamTaskTransformer<EventT> bindingTransformer;

  @override
  void bind(void Function() signalDelegateDone) async {
    bindingTransformer = _StreamTaskTransformer(owner, signalDelegateDone);
    boundDelegate = delegate.transform(bindingTransformer);
  }

  @override
  void cancel() {
    bindingTransformer.taskOnCancel();
  }
}

final class _StreamTaskTransformer<EventT> extends StreamLifecycleTransformer<EventT, EventT> {
  final AsyncScope owner;
  final void Function() signalSourceDone;

  _StreamTaskTransformer(this.owner, this.signalSourceDone);

  StreamSubscription? delegateSubscription;
  late StreamController<EventT> boundController;

  @override
  StreamController<EventT> onBindDestController(Stream<EventT> sourceStream, StreamControllerHandlers handlers, {bool? useSyncControllers}) {
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
      boundController.addError(TaskCancellationException._(owner));
      await boundController.close();
    }
  }
}
