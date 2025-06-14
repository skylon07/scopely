import 'dart:async';

import 'package:scopely/src/merge_streams.dart';

typedef TransformerContext<SourceT, DestT> = ({
  Stream<SourceT> sourceStream, 
  StreamSubscription<SourceT>? sourceSubscription,
  StreamController<DestT> destController
});

typedef StreamControllerHandlers = ({
  void Function() listen,
  FutureOr<void> Function() cancel,
  void Function() pause,
  void Function() resume,
});

/// A [StreamTransformer] that provides an alternative but equivalent interface to [StreamController]s.
/// Instances are intended to be passed to [Stream.transform].
/// 
/// Although [StreamController]s are very powerful tools for fine-grain control over streams,
/// they are an extremely verbose interface, and simple tweaks to a stream's lifecycle
/// can require a large amount of boilerplate. This class abstracts as much of that boilerplate
/// as possible, leaving you with only one implementation requirement: forwarding stream data events.
/// 
/// Like [StreamTransformer]s in general, this class is conceptually just a function transforming a
/// "source stream" into a "destination stream". This class is meant to be extended and contains
/// various "hooks" that can be overridden, representing pieces of this "transformation function".
/// These overridable hook methods are:
/// - [onBindDestController]
/// - [destOnListen]
/// - [destOnCancel]
/// - [destOnPause]
/// - [destOnResume]
/// - [sourceOnData] (required)
/// - [sourceOnError]
/// - [sourceOnDone]
/// 
/// This provides everything you'll need to implement a [StreamController]-based algorithm,
/// but without most of the headache. Override any hooks you need or want to. Most are provided
/// with a `context` object providing references to the source stream, the current subscription,
/// and the destination stream's controller. If you don't override anything, this transformer
/// will forward all cancel/pause/etc signals and act just like the given source stream,
/// including single-subscription stream behaviors. If you *do* override a hook but
/// still want default behavior, use `super` to call into the base method implementation.
/// If you want to *completely replace* a hook's behavior, simply *don't* call `super`.
/// However, exercise caution when replacing the `destOn...()` hooks, as you will almost certainly
/// want to utilize their default behavior, even though it is not a requirement to.
/// Make *sure* you know what you're doing if you decide not to use `super.destOn...()`.
abstract base class StreamLifecycleTransformer<SourceT, DestT> implements StreamTransformer<SourceT, DestT> {
  @override
  Stream<DestT> bind(Stream<SourceT> sourceStream) {
    StreamSubscription<SourceT>? sourceSubscription;
    late StreamController<DestT> destController;

    TransformerContext<SourceT, DestT> compileContext() => (
      sourceStream: sourceStream, 
      destController: destController,
      sourceSubscription: sourceSubscription,
    );

    Object? listenError;
    StackTrace? listenErrorTrace;
    void listen() {
      try {
        sourceSubscription = destOnListen(compileContext());
      } catch (error, stackTrace) {
        if (_shouldHandleListenErrorSynchronously(error)) {
          listenError = error;
          listenErrorTrace = stackTrace;
        } else {
          rethrow;
        }
      }
    }

    FutureOr<void> cancel() async {
      sourceSubscription = await destOnCancel(compileContext());
    }

    void pause() {
      destOnPause(compileContext());
    }

    void resume() {
      destOnResume(compileContext());
    }

    destController = onBindDestController(
      sourceStream, (
      listen: listen,
      cancel: cancel,
      pause: pause,
      resume: resume,
    ));

    return _ListenProxyStream(destController.stream, () => (listenError, listenErrorTrace));
  }
  
  @override
  StreamTransformer<RS, RT> cast<RS, RT>() =>
    StreamTransformer.castFrom<SourceT, DestT, RS, RT>(this);

  /// An overridable hook called when the [StreamController] responsible for the 
  /// overall transformation is created.
  /// 
  /// Generally speaking, this method's default behavior (creating a new controller)
  /// should not be replaced. A notable exception is to reuse the same controller across
  /// multiple streams/transformers. However, returning a custom controller from this method
  /// comes with subtle implications that, if not well understood, can be very hard to debug.
  /// For this reason, [mergeStreams] is provided to safely handle transforming multiple streams
  /// from a shared controller, which ultimately overrides this method so you don't have to.
  /// 
  /// Should you choose pain and suffering and decide to replace this method anyway,
  /// study the default implementations of this class carefully. There are nuances to how this
  /// method is treated semantically. For example, the returned controller's stream 
  /// should not be listened to directly, as it is wrapped with a lifecycle-aware stream
  /// which is returned by this transformer.
  StreamController<DestT> onBindDestController(Stream<SourceT> sourceStream, StreamControllerHandlers handlers) {
    if (sourceStream.isBroadcast) {
      return StreamController.broadcast(
        onListen: handlers.listen,
        onCancel: handlers.cancel,
      );
    } else {
      return StreamController(
        onListen: handlers.listen,
        onPause: handlers.pause,
        onResume: handlers.resume,
        onCancel: handlers.cancel,
      );
    }
  }

  /// An overridable hook called when the destination stream is listened to.
  /// 
  /// Like all `destOn...()` hooks, you should be careful if you decide to replace this hook's behavior.
  /// [destOnListen] *especially* needs some extra care since it is responsible for connecting
  /// many other pieces of this transformer together.
  /// 
  /// This hook should return the [StreamSubscription] obtained from listening to the source stream,
  /// or `null` if the source stream was not listened to. This hook is also responsible for
  /// setting up callbacks to [sourceOnData], [sourceOnError], and [sourceOnDone].
  /// 
  /// Returning an incorrect subscription value may lead to unexpected results
  /// when reading the subscription from `context` later.
  StreamSubscription<SourceT>? destOnListen(TransformerContext<SourceT, DestT> context) {
    return context.sourceStream.listen(
      (event) => sourceOnData(context, event),
      onError: (error, stackTrace) => sourceOnError(context, error, stackTrace),
      onDone: () => sourceOnDone(context),
      // not canceling on errors is usually what's wanted;
      // even if it's not, it can be easily implemented in the onError override
      cancelOnError: false, 
    );
  }

  /// An overridable hook called when the destination stream's subscription is canceled.
  /// 
  /// Like all `destOn...()` hooks, you should be careful if you decide to replace this hook's behavior.
  /// 
  /// This hook should asynchronously `await` any necessary `cancel()` or `close()` operations,
  /// then return either `null` to signal a successful cancelation, or `context.sourceSubscription`
  /// if a cancelation did not occur and the subscription is still active. By default,
  /// the subscription is always canceled, and the destination stream's controller is only closed
  /// if the source stream is a single-subscription stream.
  /// 
  /// Returning an incorrect subscription value may lead to unexpected results
  /// when reading the subscription from `context` later.
  /// 
  /// It's also worth noting [SafeClosing.closeIfNeeded] is provided as a more await-friendly alternative
  /// to [StreamController.close].
  FutureOr<StreamSubscription<SourceT>?> destOnCancel(TransformerContext<SourceT, DestT> context) async {
    await context.sourceSubscription?.cancel();
    // broadcast streams shouldn't be closed because more listeners could come later
    if (!context.sourceStream.isBroadcast) {
      await context.destController.closeIfNeeded();
    }
    return null;
  }

  /// An overridable hook called when the destination stream's subscription is actually paused.
  /// (This is *not necessarily* the same as "every time [StreamSubscription.pause] is called".)
  /// 
  /// Like all `destOn...()` hooks, you should be careful if you decide to replace this hook's behavior.
  /// 
  /// For most circumstances, this hook should just attempt to forward the "pause" signal
  /// to the source stream through `context.sourceSubscription`.
  void destOnPause(TransformerContext<SourceT, DestT> context) => context.sourceSubscription?.pause();

  /// An overridable hook called when the destination stream's subscription is actually resumed.
  /// (This is *not necessarily* the same as "every time [StreamSubscription.resume] is called".)
  /// 
  /// Like all `destOn...()` hooks, you should be careful if you decide to replace this hook's behavior.
  /// 
  /// For most circumstances, this hook should just attempt to forward the "resume" signal
  /// to the source stream through `context.sourceSubscription`.
  void destOnResume(TransformerContext<SourceT, DestT> context) => context.sourceSubscription?.resume();

  /// An overridable hook called when the source stream produces a new [event].
  /// 
  /// This hook does not have a default implementation, and therefore subclasses
  /// are required to implement it. You have full control over what events (if any)
  /// are emitted through the destination stream via `context.destController`.
  /// For example, forwarding the event unmodified can be done with
  /// ```dart
  /// context.destController.add(event);
  /// ```
  void sourceOnData(TransformerContext<SourceT, DestT> context, SourceT event); 

  /// An overridable hook called when the source stream produces a new [error] event.
  /// 
  /// Similar to [sourceOnData], you have full control over what events (if any) are emitted
  /// through the destination stream via `context.destController`. 
  /// For example, forwarding the event unmodified can be done with
  /// ```dart
  /// context.destController.add(event);
  /// ```
  void sourceOnError(TransformerContext<SourceT, DestT> context, Object error, StackTrace stackTrace) {
    context.destController.addError(error, stackTrace);
  }

  /// An overridable hook called when the source stream has finished and produced a "done" event.
  /// 
  /// This hook is responsible for performing any needed cleanup, including closing
  /// the destination stream's controller (ie `context.destController.close()`).
  /// 
  /// It's also worth noting [SafeClosing.closeIfNeeded] is provided as a more await-friendly alternative
  /// to [StreamController.close].
  FutureOr<void> sourceOnDone(TransformerContext<SourceT, DestT> context) async {
    await context.destController.closeIfNeeded();
  }
}

/// A convenience extension providing [closeIfNeeded] as an alternative to [StreamController.close].
extension SafeClosing on StreamController {
  /// Attempts to close this controller via [StreamController.close].
  /// If the controller is already closed, this function is a no-op
  /// (unlike the default for `.close()`).
  Future<void> closeIfNeeded() async {
    // awaiting a close() after it's already closed will hang forever
    if (!isClosed) {
      await close();
    }
  }
}

/// A proxy stream that wraps [listen] with some extra error-handling logic.
/// 
/// By default, the `onListen()` callback provided to stream controllers is executed
/// in a guarded zone. This zone will treat all thrown errors as uncaught exceptions.
/// This is by design, because even though `onListen()` runs synchronously, it's treated like
/// any other "event handler" in the asynchronous framework. However, this poses an issue
/// for [StreamLifecycleTransformer], since conceptually it should behave just as its source stream
/// when left unmodified. This includes the behavior of throwing [StateError]s when a
/// single-subscription stream is listened to multiple times. This class facilitates
/// filtering and forwarding these errors when [listen] is called.
class _ListenProxyStream<EventT> extends Stream<EventT> {
  final Stream<EventT> sourceStream;
  final (Object?, StackTrace?) Function() sourceListenErrorProvider;
  _ListenProxyStream(this.sourceStream, this.sourceListenErrorProvider);

  @override
  StreamSubscription<EventT> listen(
    void Function(EventT event)? onData, {
    Function? onError, 
    void Function()? onDone, 
    bool? cancelOnError,
  }) {
    var subscription = sourceStream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
    
    var (error, stackTrace) = sourceListenErrorProvider();
    var sourceListenDidError = error != null;
    if (sourceListenDidError) {
      if (stackTrace != null) {
        Error.throwWithStackTrace(error, stackTrace);
      } else {
        throw error;
      }
    }

    return subscription;
  }
}

/// A helper function that decides when an error should be thrown by a [_ListenProxyStream].
bool _shouldHandleListenErrorSynchronously(Object error) {
  var isDuplicateListenerError = 
    error is StateError &&
    error.message == "Stream has already been listened to.";
  
  return isDuplicateListenerError;
}
