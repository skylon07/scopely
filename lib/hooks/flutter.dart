import 'package:async_scope/async_scope.dart';
import 'package:flutter/widgets.dart';

mixin StateScoping on State {
  AsyncScope _stateScope = AsyncScope();
  AsyncScope get stateScope => _stateScope;

  @override
  void dispose() {
    _stateScope.cancelAll();
    super.dispose();
  }
}
