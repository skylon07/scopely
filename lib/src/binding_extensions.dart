import 'package:async_scope/async_scope.dart';

extension FutureScoping<ResultT> on Future<ResultT> {
  Future<ResultT> bindToScope(AsyncScope scope) => scope.bindFuture(this);
}

extension StreamScoping<EventT> on Stream<EventT> {
  Stream<EventT> bindToScope(AsyncScope scope) => scope.bindStream(this);
}
