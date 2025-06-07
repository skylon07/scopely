import 'dart:async';
import 'package:meta/meta.dart';

extension StreamUtils<EventT> on Stream<EventT> {
  Stream<ForwardT> forwardingStream<ForwardT>(StreamLifecycleHooks<EventT, ForwardT> hooks) {
    StreamController<ForwardT> destController;
    if (isBroadcast) {
      destController = StreamController.broadcast(
        onListen: hooks.destOnListen,
        onCancel: hooks.destOnCancel,
      );
    } else {
      destController = StreamController(
        onListen: hooks.destOnListen,
        onPause: hooks.destOnPause,
        onResume: hooks.destOnResume,
        onCancel: hooks.destOnCancel,
      );
    }

    hooks._initialize(stream: this, destController: destController);

    return destController.stream;
  }

  Stream<Future<EventT>> asFutures() => forwardingStream(_AsFuturesLifecycleHooks());   
}

// TODO: modify and use this docstring for asFutures()
  /// Creates a new stream that listens to this one, transforming all events into [Future]s
  /// that can be used intuitively in `await for` loops.
  /// 
  /// In other words, the futures emitted by the resulting stream can be used similar to
  /// the callback parameters available from [Stream.listen]:
  /// ```dart
  /// try {
  ///   await for (var eventFuture in stream.asFutures()) {
  ///     try {
  ///       // event received, like `listen(onData: ...)`
  ///       var event = await eventFuture
  ///     } catch (error) {
  ///       // error received, like `listen(onError: ...)`
  ///     }
  ///   }
  ///   // stream closed, like `listen(onDone: ...)`
  /// } catch (error) {
  ///   // error thrown when calling `stream.listen()`,
  ///   // or like `listen(onError: ..., cancelOnError: true)`
  ///   // if there's no inner `try` block
  /// }
  /// ```


abstract base class StreamLifecycleHooks<EventT, ForwardT> {
  late final Stream<EventT> _sourceStream;
  Stream<EventT> get sourceStream => _sourceStream;

  StreamSubscription? _sourceSubscription;
  StreamSubscription? get sourceSubscription => _sourceSubscription;

  late final StreamController<ForwardT> _destController;
  StreamController<ForwardT> get destController => _destController;

  bool _initialized = false;

  void _initialize({
    required Stream<EventT> stream, 
    required StreamController<ForwardT> destController
  }) {
    if (_initialized) throw StateError("Hooks have already been used");

    this._sourceStream = stream;
    this._destController = destController;

    _initialized = true;
  }

  @mustCallSuper
  void destOnListen() {
    // TODO: should they be able to override the listen()?
    //  if so, _subscription never gets set!
    _sourceSubscription = _sourceStream.listen(
      sourceOnData,
      onError: sourceOnError,
      onDone: sourceOnDone,
      // canceling on error is usually not wanted;
      // even if it was, it can be implemented in the onError override
      cancelOnError: false, 
    );
  }

  FutureOr<void> destOnCancel() async {
    await _sourceSubscription?.cancel();
    _sourceSubscription = null;
    if (!_sourceStream.isBroadcast) {
      _destController.close();
    }
  }

  void destOnPause() => _sourceSubscription?.pause();

  void destOnResume() => _sourceSubscription?.resume();

  // can't give a default implementation because
  // there's no way to create a ForwardT instance
  void sourceOnData(EventT event); 

  void sourceOnError(Object error, StackTrace stackTrace) {
    _destController.addError(error, stackTrace);
  }

  void sourceOnDone() {
    _destController.close();
  }
}


final class _AsFuturesLifecycleHooks<EventT> extends StreamLifecycleHooks<EventT, Future<EventT>> {
  @override
  void destOnListen() {
    try {
      super.destOnListen();
    } catch (error, stackTrace) {
      _destController.addError(error, stackTrace);
      _destController.close();
    }
  }

  @override
  void sourceOnData(EventT event) {
    _destController.add(Future.value(event));
  }

  @override
  void sourceOnError(Object error, StackTrace stackTrace) {
    _destController.add(Future.error(error, stackTrace));
  }
}
