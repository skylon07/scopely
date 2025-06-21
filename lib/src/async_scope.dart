import 'dart:async';

import 'package:scopely/src/stream_lifecycle_transformer.dart';

/// A collection of asynchronous tasks exposed as native futures/streams that can be
/// canceled at any time.
/// 
/// Scopes require no arguments to construct and can be used in a variety of application architectures.
/// You can create as many as you want (optionally under a parent scope), bind tasks to them
/// via [bindFuture] and [bindStream], and cancel them at any time with [cancelAll].
/// It's a good idea to use [catchCancellations]/[catchAllCancellations] as well,
/// to avoid producing uncaught errors from exceptions thrown internally to cancel asynchronous tasks.
/// 
/// [AsyncScope] was designed with custom lifecycles in mind. They seamlessly integrate
/// into whatever architecture you might already have. For example, to integrate [AsyncScope]
/// into your Flutter `State`s, you could create a simple mixin
/// 
/// ```dart
/// import 'package:flutter/widgets.dart';
/// 
/// mixin StateScoping on State {
///   final scope = AsyncScope();
/// 
///   @override
///   void dispose() {
///     scope.cancelAll();
///     super.dispose();
///   }
/// }
/// ```
/// 
/// which is very straightforward to use, even if you're refactoring existing code!
/// 
/// ```dart
/// class _MyState extends State<MyWidget> with StateScoping {
///   String data = "";
/// 
///   @override
///   void initState() {
///     super.initState();
/// 
///     // `scope` provided by the mixin
///     scope.bindStream(someStream).listen((data) {
///       // can use `data` with confidence this `State` is still active!
///     });
///   }
/// 
///   @override
///   Widget build(BuildContext context) {
///     return TextButton(
///       onPressed: () async {
///         // existing code can simply add `.inScope(scope)`
///         // to become cancelable!
///         var data = await someFetch().inScope(scope);
/// 
///         // you don't even have to check `mounted`; the scope's futures/streams
///         // guarantee `mounted == true` if it is canceled in `dispose()`
///         setState(() => this.data = data);
///       },
///       child: Text(data),
///     );
///   }
/// }
/// ```
/// 
/// One caveat: canceling a scope may result in several [TaskCancellationException]s being thrown.
/// Although harmless, they will appear as uncaught errors unless manually caught.
/// You may decide to use [catchCancellations] or [catchAllCancellations] to cleanly
/// filter these errors out. The quickest way to do this universally is to wrap
/// the entire body of `main()` with [catchAllCancellations], or just `runApp()`
/// if you're using Flutter. 
/// 
/// See [bindFuture] and [bindStream] for more details on how their respective tasks
/// are canceled and the behaviors you can expect from cancellations.
class AsyncScope {
  final _children = <AsyncScope>[];

  AsyncScope([AsyncScope? parent]) {
    parent?._children.add(this);
  }

  final _tasksToCancel = <_CancelableTask>{};
  
  var _isCanceled = false;
  /// Returns if this scope was canceled, either by its parent or from calling
  /// [cancelAll] manually.
  /// 
  /// Binding asynchronous tasks (by calling [FutureScoping.inScope], etc) when the scope is canceled
  /// will result in a state error. This property is provided to guard against these situations.
  bool get isCanceled => _isCanceled;

  /// Takes the given [future] and returns a new "bound" future equivalent to the original.
  /// Awaiting bound futures allow for cancelable tasks to be constructed.
  /// 
  /// In Dart, [Future]s are not built to be cancelable operations. It would be a mistake
  /// to assume this function is capable of changing this behavior. Rather, this function
  /// *circumvents* this behavior by throwing an internal [TaskCancellationException]
  /// which enables scopes to "cancel" their bound futures.
  /// 
  /// ### What this means
  /// Asynchronous processes waiting for bound futures to complete
  /// will halt processing if the scope is canceled. For example...
  /// 
  /// ```dart
  /// Future<int> fetchInt() async {
  ///   await Future.delayed(Duration(seconds: 5));
  ///   return 5;
  /// }
  /// 
  /// void someAsyncTask() async {
  ///   var result = await fetchInt().inScope(scope);
  ///   print(result + 10);
  /// }
  /// ```
  /// 
  /// If `someAsyncTask()` is called, but the scope is canceled before `fetchInt()` completes,
  /// the line `print(result + 10);` will never run.
  /// 
  /// ### What this *does not* mean
  /// Canceling tasks won't stop their internal logic or prevent side effects;
  /// their underlying futures will still run to completion (that is, `fetchInt()`
  /// will still finish after 5 seconds). Cancellation only prevents downstream logic
  /// from observing or using the result.
  ///
  /// This is a limitation of the language itself. *True* cancellation would require
  /// language-level support or a custom async system (not `Future`/`Stream`-based)
  /// used consistently across your project. Instead, [AsyncScope] intends to provide
  /// a simple and lightweight API, one that
  /// - works with Dart's native `async`/`await` syntaxes
  /// - can integrate easily with existing libraries and async workflows
  /// - can be adopted incrementally
  Future<ResultT> bindFuture<ResultT>(Future<ResultT> future) => 
    _bindTask(_FutureTask(this, future));

  /// Takes the given [stream] and returns a new "bound" stream equivalent to the original.
  /// Awaiting or listening to bound streams allows for cancelable tasks to be constructed.
  /// 
  /// The resulting stream behaves identically to [stream], except that it is bound to the scope.
  /// This means if [stream] is a broadcast stream, then the bound stream will be too.
  /// If [stream] emits data or error events, so will the bound stream. Modifying subscriptions
  /// returned from the bound stream will work just as they would if the subscriptions
  /// were on [stream] itself.
  /// 
  /// Canceling streams follows a pattern similar to futures (see [bindFuture]).
  /// More specifically, [AsyncScope] throws [TaskCancellationException]s to signal 
  /// a premature halt. This results in the stream emitting an error event, then a done event.
  /// Immediately when `scope.cancelAll()` is called, no more data/error events 
  /// will be processed by the stream, aside from the cancellation exception itself.
  /// 
  /// Similar to [bindFuture], canceling a bound stream doesn't guarantee the underlying stream
  /// will stop. However, this is only true for broadcast streams. If [stream]
  /// is a single-subscription stream, then cancelling the bound stream actually *does*
  /// cause it to stop. Even so, it is better to rely on [bindStream] directly whenever possible,
  /// even inside chains of single-subscription streams, because it provides the
  /// same cancellation behavior regardless of the underlying stream's type
  /// (in other words, swapping out streams won't break the cancellation logic).
  Stream<EventT> bindStream<EventT>(Stream<EventT> stream) =>
    _bindTask(_StreamTask(this, stream));

  /// Adds a callback [onCancel] to run when this scope is canceled. Once registered,
  /// the callback should not be invoked directly. Doing so might result in the callback
  /// being run more times than expected. To run [onCancel] early, using the returned
  /// [CancelListener.cancelEarly] method instead.
  CancelListener addCancelListener(void Function() onCancel) =>
    _bindTask(_CustomCancelableTask(this, onCancel));

  /// Cancels all tasks bound to this scope immediately and synchronously.
  /// 
  /// Any futures from [bindFuture] or streams from [bindStream] are tracked by this scope.
  /// Calling this function causes all of them to immediately throw a [TaskCancellationException].
  /// This exception prevents them from continuing their execution.
  /// 
  /// Although most errors/events in Dart are handled asynchronously, this cancellation
  /// operation is an exception (pun absolutely intended). [cancelAll] *intentionally*
  /// violates an "async contract" that Dart normally promises by performing cancellation tasks 
  /// *synchronously*. As an example, normally async code like:
  /// 
  /// ```dart
  /// someFuture.then((_) => print(2));
  /// print(1);
  /// ```
  /// 
  /// will print:
  /// 
  /// ```
  /// 1
  /// 2
  /// ```
  /// 
  /// However, if [cancelAll] were to follow this pattern, then tasks *could* (although unlikely)
  /// still run after the scope is canceled. This would prevent [AsyncScope]'s intended
  /// lifecycle behavior from being equivalent to some other lifecycle (like a Flutter `State`;
  /// if it's disposed, the scope should not run tasks). So instead, [cancelAll]
  /// works synchronously to provide a much stronger lifecycle contract at the cost of 
  /// *technically* providing "invalid" async behavior. What this really means is code like:
  /// 
  /// ```dart
  /// scope.bindFuture(someFuture).catchError((_) => print(2));
  /// scope.cancelAll();
  /// print(1);
  /// ```
  /// 
  /// will print:
  /// 
  /// ```
  /// 2
  /// 1
  /// ```
  /// 
  /// In practice though, this almost certainly won't cause you any issues.
  /// It's very easy to avoid situations like this: just make sure
  /// [cancelAll] is never called synchronously after [bindFuture] or [bindStream],
  /// and all the expected async behaviors are preserved.
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

  /// Equivalent to [catchAllCancellations], but only filters [TaskCancellationException]s
  /// thrown by this scope. Cancellation exceptions thrown from other scopes will be rethrown
  /// just like normal uncaught exceptions.
  Future<void> catchCancellations(FutureOr<void> Function() body) async {
    return catchAllCancellations(body, shouldBeCaught: (cancelError) => cancelError._owner == this);
  }

  /// Runs [body] in a try-catch-like construct that filters out [TaskCancellationException]s.
  /// Useful for guarding against uncaught errors in your program.
  /// 
  /// [AsyncScope]s throw exceptions to cancel their asynchronous tasks. While this leads to
  /// very powerful and predictable behavior, the downside is that it generates a lot of uncaught exceptions.
  /// Even though these are usually harmless (they are always caught asynchronously),
  /// they might feel noisy or unwanted during development.
  /// 
  /// Fortunately, [catchAllCancellations] makes the cleanup easy. It is logically
  /// very similar to this code:
  /// 
  /// ```dart
  /// try {
  ///   await asyncOperation().inScope(scope);
  /// } on TaskCancellationException catch (_) {
  ///   // absorb it
  /// } catch (error) {
  ///   rethrow error;
  /// }
  /// ```
  /// 
  /// Internally, [Zone]s are used to facilitate intercepting all uncaught exceptions.
  /// Although this shouldn't affect your code at all, this might be useful to know
  /// if you're doing advanced error handling.
  /// 
  /// Additionally, [shouldBeCaught] is an optional argument that can be provided
  /// to selectively catch or rethrow particular [TaskCancellationException]s.
  /// This is mainly useful for individual scopes internally when you call
  /// [catchCancellations] on them.
  /// 
  /// This method returns a future that completes normally (without errors)
  /// when [body] completes or a [TaskCancellationException] is caught.
  /// If [body] throws an error, the future will complete with the same error.
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


/// An error indicating a call was made to bind a task to an [AsyncScope] 
/// after the scope had already canceled.
class AsyncScopeCanceledError extends StateError {
  AsyncScopeCanceledError() : super("AsyncScope has already been canceled");
}

/// An error thrown internally by [AsyncScope] to facilitate canceling async tasks.
/// 
/// While triggered by a call to [AsyncScope.cancelAll], this exception is actually
/// thrown by the bound [Future]s and [Stream]s returned by the [AsyncScope].
/// 
/// This exception does not indicate an error in your code. If you're noticing it
/// as an uncaught exception during development, consider using [AsyncScope.catchCancellations]
/// or [AsyncScope.catchAllCancellations] to handle it more gracefully.
class TaskCancellationException implements Exception {
  final AsyncScope _owner;
  TaskCancellationException._(this._owner);

  @override
  String toString() => "$TaskCancellationException";
}


extension FutureScoping<ResultT> on Future<ResultT> {
  /// Binds this future to a [scope].
  /// 
  /// This is a convenience method for [AsyncScope.bindFuture] that reads better
  /// in many cases. For example, the following are equivalent:
  /// 
  /// ```dart
  /// await scope.bindFuture(someAsyncTask());
  /// await someAsyncTask().inScope(scope);
  /// ```
  Future<ResultT> inScope(AsyncScope scope) => scope.bindFuture(this);
}

extension StreamScoping<EventT> on Stream<EventT> {
  /// Binds this stream to a [scope].
  /// 
  /// This is a convenience method for [AsyncScope.bindStream] that reads better
  /// in many cases. For example, the following are equivalent:
  /// 
  /// ```dart
  /// await for (var data in scope.bindStream(someStream)) {
  ///   // ...
  /// }
  /// 
  /// await for (var data in someStream.inScope(scope)) {
  ///   // ...
  /// }
  /// ```
  Stream<EventT> inScope(AsyncScope scope) => scope.bindStream(this);
}

abstract class _CancelableTask<DelegateT> {
  final AsyncScope owner;

  _CancelableTask(this.owner);

  abstract final DelegateT boundDelegate;
  
  void bind(void Function() signalDelegateDone);
  void cancel();
}

final class _FutureTask<ResultT> extends _CancelableTask<Future<ResultT>> {
  // a sync controller must be used to prevent this race condition:
  // - The task waits for the delegate, which completes
  // - The completion of the bound future is scheduled in the next microtask (should run now instead!)
  // - The scope cancels
  // - The completion runs in a now invalid state (should have run earlier!)
  final _boundCompleter = Completer<ResultT>.sync();

  final Future<ResultT> _delegate;

  _FutureTask(super.owner, this._delegate);

  @override
  late Future<ResultT> boundDelegate = _boundCompleter.future;

  @override
  void bind(void Function() signalDelegateDone) async {
    try {
      var result = await _delegate;
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
  final Stream<EventT> _delegate;

  _StreamTask(super.owner, this._delegate);

  @override
  late final Stream<EventT> boundDelegate = _delegate.transform(bindingTransformer);

  late final _StreamTaskTransformer<EventT> bindingTransformer;

  @override
  void bind(void Function() signalDelegateDone) async {
    bindingTransformer = _StreamTaskTransformer(owner, signalDelegateDone);
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
    var controller = super.onBindDestController(sourceStream, handlers, useSyncControllers: true);
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

/// A handle to a manually added cancellation task allowing you to cancel it early.
class CancelListener {
  final AsyncScope _scope;
  final void Function() _cancelEarly;

  CancelListener(this._scope, this._cancelEarly);

  var _hasCanceledEarly = false;

  /// Performs the cancellation early and removes it from the scope's pending cancellation tasks.
  /// 
  /// Calling this method ensures the bound cancellation callback will only be run once,
  /// and not again if the underlying [AsyncScope] cancels (or is already canceled).
  /// Canceling early has no effect on the underlying scope or its other cancellation tasks.
  void cancelEarly() {
    if (!_scope._isCanceled && !_hasCanceledEarly) {
      _hasCanceledEarly = true;
      _cancelEarly();
    }
  }
}

class _CustomCancelableTask extends _CancelableTask<CancelListener> {
  final void Function() _onCancel;

  _CustomCancelableTask(super.owner, this._onCancel);

  @override
  late final CancelListener boundDelegate;

  @override
  void bind(void Function() signalDelegateDone) {
    boundDelegate = CancelListener(owner, () {
      signalDelegateDone();
      _onCancel();
    });
  }

  @override
  void cancel() {
    _onCancel();
  }
}
