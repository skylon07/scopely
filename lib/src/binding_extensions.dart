import 'package:async_scope/async_scope.dart';

extension FutureScoping<ResultT> on Future<ResultT> {
  Future<ResultT> bindToScope(AsyncScope scope) => scope.bindFuture(this);
}

extension StreamScoping<EventT> on Stream<EventT> {
  Stream<EventT> bindToScope(AsyncScope scope) => scope.bindStream(this);

  Stream<Future<EventT>> asFutures() {
    return Stream.multi((controller) {
      try {
        var subscription = listen(
          (event) => controller.add(Future.value(event)),
          onError: (error, stackTrace) => controller.add(Future.error(error, stackTrace)),
          onDone: () => controller.close(),
          cancelOnError: false, // otherwise, `await for` would always break on the first error!
        );
        controller.onCancel = () => subscription.cancel();
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
        controller.close();
      }
    });
  }
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