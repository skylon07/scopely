import 'package:scopely/scopely.dart';

void main() {
  // (just prevents cancellation exceptions from polluting the console;
  // you can do the same in a real Flutter app)
  AsyncScope.catchAllCancellations(() async {
    runApp();
  });
}

//  -- example user Flutter code --

/// An example of how to tie an [AsyncScope] to a Flutter `State`.
/// This class holds all the magic of automating task cleanup.
/// As you can see, it's pretty minimal!
mixin StateScope on State {
  final scope = AsyncScope();

  @override
  void dispose() {
    print("-- scope canceling all tasks");
    scope.cancelAll();
    print("-- scope tasks canceled");
    super.dispose();
  }
}

/// An example implementation of a custom state *with* the [AsyncScope] mixed in.
/// At this point, everything is handled behind the scenes. All you'd need to do
/// is bind your async tasks to the [scope]!
class MyState extends State with StateScope {
  final notifier = MyChangeNotifier();

  @override
  void initState() {
    // notice this is fire-and-forget...
    // (not bound to the scope, although it could be)
    fakeFetchAndStore();

    // scopes also work with other patterns that might need manual cleanup
    void fakeListener() {};
    print("  adding notifier listeners...");
    notifier.addListener(fakeListener);
    scope.addCancelListener(() {
      print("-- cancelling listener");
      notifier.removeListener(fakeListener);
    });

    super.initState();
  }

  Future<void> fakeFetchAndStore() async {
    // `inScope()` makes it very easy to take existing async code
    // and bind it to this state's scope
    print("before fakeFetch()");
    var data = await fakeFetch().inScope(scope);
    print("after fakeFetch()");
    
    // this won't ever run; the state was already disposed in `main()`!
    print("before fakeStore()");
    await fakeStore(data).inScope(scope);
    print("after fakeStore()");
  }

  Future<String> fakeFetch() async {
    print("  fakeFetch(): starting...   (scope canceled? ${scope.isCanceled})");  // this WILL be printed
    await Future.delayed(Duration(seconds: 2));
    // runs even though the scope was canceled;
    // this would NOT happen if the above delay was also bound to the scope
    print("  fakeFetch(): returning     (scope canceled? ${scope.isCanceled})");  // this WILL be printed
    return "very important data!";
  }

  Future<void> fakeStore(String data) async {
    print("  fakeStore(): starting...");  // this will NOT be printed
    await Future.delayed(Duration(seconds: 2));
    print("  fakeStore(): returning");    // this will NOT be printed
  }
}

//  -- mocked flutter internals --

/// A type representing Flutter's `State` type.
class State {
  void initState() {}

  /// Cleans up this [State]. Flutter normally calls this method for you,
  /// however in this example we call it manually to simulate this behavior.
  void dispose() {}
}

/// Represents a custom Flutter `ChangeNotifier` or something of the like.
/// This just demonstrates how [AsyncScope] is compatible with the "listener pattern".
class MyChangeNotifier {
  void addListener(void Function() callback) {}
  void removeListener(void Function() callback) {}
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
