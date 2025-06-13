import 'dart:async';

import 'package:scopely/scopely.dart';

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

extension StreamAsFutures<EventT> on Stream<EventT> {
  Stream<Future<EventT>> asFutures() => transform(_AsFuturesTransformer());
}

final class _AsFuturesTransformer<EventT> extends StreamLifecycleTransformer<EventT, Future<EventT>> {
  @override
  void sourceOnData(TransformerContext<EventT, Future<EventT>> context, EventT event) {
    context.destController.add(Future.value(event));
  }

  @override
  void sourceOnError(TransformerContext<EventT, Future<EventT>> context, Object error, StackTrace stackTrace) async {
    var completer = Completer<EventT>();
    context.destController.add(completer.future);
    completer.completeError(error, stackTrace);
  }
}
