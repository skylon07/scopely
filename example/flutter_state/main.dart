import 'package:scopely/src/async_scope.dart';

import 'my_state.dart';

void main() {
  // (just prevents cancellation exceptions from polluting the console)
  AsyncScope.catchAllCancellations(() async {
    runApp();
  });
}

/// A mock version of Flutter's `runApp()` function.
/// This just pretends to perform normal internal Flutter operations over time.
/// 
/// The order of events happens as follows:
/// - fakeFetch() is called
/// - state disposes/scope is canceled
/// - fakeFetch() returns (unavoidable unless you bind the internal future to the scope)
/// - (fakeStore() *would be called* if not already canceled)
/// - (fakeStore() *would return* if not already canceled)
void runApp() async {
  // simulate Flutter's internal actions by creating a state...
  var state = MyState();

  // ...initializing it...
  state.initState();

  // ...then disposing it some time later
  await Future.delayed(Duration(seconds: 1));
  state.dispose();
}
