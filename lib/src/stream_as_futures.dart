import 'dart:async';

import 'package:scopely/scopely.dart';


/// An extension that provides an [asFutures] transformation method for [Stream]s.
extension StreamAsFutures<EventT> on Stream<EventT> {
  /// Returns a stream that wraps every result in its own [Future]. This can be used
  /// to improve exception handling in `await for` loops.
  /// 
  /// For example, let's say events are being received from a stream like this:
  /// 
  /// ```dart
  /// await for (var event in stream) {
  ///   // ...
  /// }
  /// ```
  /// 
  /// If the stream never sends errors, then you're good to go! However, if the stream
  /// *does* emit errors, there's no way to catch them without breaking out of the loop.
  /// 
  /// ```dart
  /// try {
  ///   await for (var event in stream) {
  ///     try {
  ///       // process `event`...
  ///     } catch (errorInsideLoop) {
  ///       // uh oh! this only catches errors from processing `event` *after*
  ///       // it was emitted, not errors emitted from the stream itself!
  ///     }
  ///   }
  /// } catch (errorOutsideLoop) {
  ///   // this catches errors from the stream, but it's outside the loop!
  /// }
  /// ```
  /// 
  /// Doesn't it feel like you *should* be able to do this? Well, look no further!
  /// This is exactly the problem this method was designed to solve!
  /// 
  /// ```dart
  /// try {
  ///   await for (var eventFuture in stream.asFutures()) {
  ///     try {
  ///       var event = await eventFuture;
  ///       // process `event`...
  ///     } on Exception catch (errorInsideLoop) {
  ///       // nice! this catches errors emitted from the stream now!
  ///     }
  ///   }
  /// } on Error catch (errorOutsideLoop) {
  ///   // this can catch its own set of errors that should still break the loop
  /// }
  /// ```
  Stream<Future<EventT>> asFutures() => transform(_AsFuturesTransformer());
}

/// A [StreamLifecycleTransformer] that facilitates transforming stream errors into
/// successful emissions of failed futures.
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
