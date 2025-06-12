import 'dart:async';

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

  FutureOr<StreamSubscription<SourceT>?> destOnCancel(TransformerContext<SourceT, DestT> context) async {
    await context.sourceSubscription?.cancel();
    // broadcast streams shouldn't be closed because more listeners could come later
    if (!context.sourceStream.isBroadcast) {
      await context.destController.closeIfNeeded();
    }
    return null;
  }

  void destOnPause(TransformerContext<SourceT, DestT> context) => context.sourceSubscription?.pause();

  void destOnResume(TransformerContext<SourceT, DestT> context) => context.sourceSubscription?.resume();

  // can't give a default implementation because
  // there's no way to create a DestT event instance
  void sourceOnData(TransformerContext<SourceT, DestT> context, SourceT event); 

  void sourceOnError(TransformerContext<SourceT, DestT> context, Object error, StackTrace stackTrace) {
    context.destController.addError(error, stackTrace);
  }

  FutureOr<void> sourceOnDone(TransformerContext<SourceT, DestT> context) async {
    await context.destController.closeIfNeeded();
  }
}

extension SafeClosing on StreamController {
  Future<void> closeIfNeeded() async {
    // awaiting a close() after it's already closed will hang forever
    if (!isClosed) {
      await close();
    }
  }
}

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

bool _shouldHandleListenErrorSynchronously(Object error) {
  var isDuplicateListenerError = 
    error is StateError &&
    error.message == "Stream has already been listened to.";
  
  return isDuplicateListenerError;
}
