// ignore_for_file: depend_on_referenced_packages
// ignore_for_file: uri_does_not_exist
// ignore_for_file: undefined_class
// ignore_for_file: mixin_super_class_constraint_non_interface
// ignore_for_file: undefined_super_member
// ignore_for_file: override_on_non_overriding_member

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
