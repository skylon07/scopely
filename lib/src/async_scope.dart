import 'dart:async';

import 'package:async_scope/src/binding_extensions.dart';

// TODO-NOW: refactor similar methods into a CancelableTask
// TODO: implement nesting scopes
class AsyncScope {
  final _cancelTasks = <Object, void Function()>{};
  var _isCanceled = false;

  Future<ResultT> bindFuture<ResultT>(Future<ResultT> future) {
    _throwIfCanceled();

    var boundCompleter = Completer<ResultT>();

    void cancelTask() {
      _runCompletion(
        boundCompleter, 
        () => boundCompleter.completeError(AsyncScopeCancelationException._()), 
        runsDuringCancelation: true,
      );
    }
    _cancelTasks[boundCompleter] = cancelTask;

    _forwardFuture(future, boundCompleter);
    return boundCompleter.future;
  }

  Stream<EventT> bindStream<EventT>(Stream<EventT> stream) {
    _throwIfCanceled();

    late StreamController<EventT> boundController;
    StreamSubscription? currSubscription;

    boundController = StreamController<EventT>(
      onListen: () {
        late StreamSubscription subscription;
        subscription = currSubscription = stream.listen(
          (event) {
            if (!boundController.isClosed) {
              boundController.add(event);
            }
          },
          onError: (error, stackTrace) {
            if (!boundController.isClosed) {
              boundController.addError(error, stackTrace);
            }
          },
          onDone: () {
            _cancelTasks.remove(boundController);
            boundController.close();
          },
          // parent stream is already configured to cancel on error if it needs
          cancelOnError: false, 
        );
        
        void cancelTask() {
          subscription.cancel();
          boundController.close();
        }
        _cancelTasks[boundController] = cancelTask;
      },
      onPause: () => currSubscription?.pause(),
      onResume: () => currSubscription?.resume(),
      onCancel: () async {
        var subscription = currSubscription;
        if (subscription != null) {
          _cancelTasks.remove(boundController);
          await subscription.cancel();
        }
      },
    );

    if (stream.isBroadcast) {
      return boundController.stream.asBroadcastStream();
    } else {
      return boundController.stream;
    }
  }

  void cancelAll() async {
    for (var task in _cancelTasks.values) {
      task();
    }
    _cancelTasks.clear();
    _isCanceled = true;
  }

  void _forwardFuture<ResultT>(Future<ResultT> future, Completer<ResultT> boundCompleter) async {
    try {
      var result = await future;
      _runCompletion(
        boundCompleter, 
        () => boundCompleter.complete(result),
      );
    } catch (error, stackTrace) {
      _runCompletion(
        boundCompleter, 
        () => boundCompleter.completeError(error, stackTrace),
      );
    }
  }

  void _runCompletion(Completer boundCompleter, void Function() completionBlock, {bool runsDuringCancelation = false}) {
    if (!boundCompleter.isCompleted) {
      // prevents modifying tasks list while iterating through it
      if (!runsDuringCancelation) {
        _cancelTasks.remove(boundCompleter);
      }
      completionBlock();
    }
  }

  void _forwardStream<ResultT>(Stream<ResultT> stream, StreamController<ResultT> boundController) async {
    await for (var event in stream.asFutures()) {
      try {
        boundController.add(await event);
      } catch (error,  stackTrace) {
        boundController.addError(error, stackTrace);
      }
    }
  }

  void _addStreamEvent(StreamController boundController, void Function() eventBlock, {bool runsDuringCancelation = false}) {
    if (!)
  }

  void _throwIfCanceled() {
    if (_isCanceled) throw AsyncScopeCanceledError();
  }
}

class AsyncScopeCanceledError extends StateError {
  AsyncScopeCanceledError() : super("AsyncScope has already been canceled");
}

class AsyncScopeCancelationException implements Exception {
  // internal factory constructor ensures a singleton instance is used for all cancelation signals
  factory AsyncScopeCancelationException._() => const AsyncScopeCancelationException._constructConst();

  // class-private constructor; use factory constructor instead
  const AsyncScopeCancelationException._constructConst();

  @override
  String toString() => "AsyncScopeCancelationException";
}





// Using an interface/controller combination enables specific mixins to reuse this logic implicitly.
// If this were a single base mixin, each usage would require explicitly declaring both the mixin and the base,
// which is less desirable. By using an interface instead, specific mixins can be applied without an extra declaration.

/// The base type for all auto-disposing implementations.
/// This type ensures that all the different auto-disposing mixins will implement their
/// respective use cases with the same underlying control logic.
/// 
/// See [EzStreamUtils.disposeWith] for more information why auto-disposing objects are useful.
abstract interface class AutoDisposing {
  abstract final _AutoDisposingController _controller;
}

/// A controller that performs the main logical operations of all auto-disposing instances, namely:
/// - Adding disposal tasks
/// - Removing disposal tasks
/// - Executing all queued disposal tasks
/// 
/// This controller should be used to drive all auto-disposing types that are defined.
/// [AutoDisposing] is the type that enforces this.
final class _AutoDisposingController {
  final _onDisposeTasks = <Object, _AutoDisposeTask>{};
  var _isDisposed = false;

  void autoDispose() {
    for (var task in _onDisposeTasks.values) {
      task();
    }
    _onDisposeTasks.clear();

    _isDisposed = true;
  }

  void addDisposeTask(Object owner, _AutoDisposeTask task) {
    _ensureNotDisposed();
    _onDisposeTasks[owner] = task;
  }

  void removeDisposeTask(Object owner) {
    _ensureNotDisposed();
    _onDisposeTasks.remove(owner);
  }

  void _ensureNotDisposed() {
    if (_isDisposed) throw StateError("Cannot add task; instance already disposed!");
  }
}

/// Provides auto-disposing features to Flutter [State]s.
/// Simply call [EzStreamUtils.disposeWith] on a [Stream] with a [State] using this mixin
/// to have the state automatically manage the necessary cleanup.
mixin StateAutoDisposing<WidgetT extends StatefulWidget> on State<WidgetT> implements AutoDisposing {
  @override
  final _controller = _AutoDisposingController();

  @override
  void dispose() {
    _controller.autoDispose();
    super.dispose();
  }
}

typedef _AutoDisposeTask = void Function();

