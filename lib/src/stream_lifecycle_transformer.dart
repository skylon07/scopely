import 'dart:async';

typedef TransformerContext<SourceT, DestT> = ({
  Stream<SourceT> sourceStream, 
  StreamSubscription<SourceT>? sourceSubscription,
  StreamController<DestT> destController
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

    void onListen() {
      sourceSubscription = destOnListen(compileContext());
    }

    FutureOr<void> onCancel() async {
      sourceSubscription = await destOnCancel(compileContext());
    }

    void onPause() {
      destOnPause(compileContext());
    }

    void onResume() {
      destOnResume(compileContext());
    }

    if (sourceStream.isBroadcast) {
      destController = StreamController.broadcast(
        onListen: onListen,
        onCancel: onCancel,
      );
    } else {
      destController = StreamController(
        onListen: onListen,
        onPause: onPause,
        onResume: onResume,
        onCancel: onCancel,
      );
    }

    onBind(compileContext());

    return destController.stream;
  }
  
  @override
  StreamTransformer<RS, RT> cast<RS, RT>() =>
    StreamTransformer.castFrom<SourceT, DestT, RS, RT>(this);

  void onBind(TransformerContext<SourceT, DestT> context) {}

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
    if (!context.sourceStream.isBroadcast) {
      context.destController.close();
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

  void sourceOnDone(TransformerContext<SourceT, DestT> context) {
    context.destController.close();
  }
}
