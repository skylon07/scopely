import 'dart:async';

import 'package:scopely/scopely.dart';
import 'package:test/test.dart';

void main() {
  group("AsyncScope", () {
    late AsyncScope scope;
    
    setUp(() {
      scope = AsyncScope();
    });

    tearDown(() {
      scope.cancelAll();
    });

    // first group since the success of all the other tests depends on this working properly
    // (tests will fail if cancellation errors aren't caught correctly)
    group("cancellation handling", () {
      test("catches cancellation exceptions from its own scope", () async {
        expect(() async {
          await scope.catchCancellations(() async {
            scope.bindFuture(Future.value());
            scope.cancelAll();
          });
        }, returnsNormally);
      });

      test("does not catch cancellation exceptions from another scope", () async {
        var scope2 = AsyncScope();

        expect(() async {
          await scope.catchCancellations(() async {
            var future = scope2.bindFuture(Future.value());
            scope2.cancelAll();
            await future;
          });
        }, throwsA(isA<TaskCancelationException>()));
      });

      test("catches cancellation exceptions from all scopes (when using the static method)", () async {
        var scope2 = AsyncScope();

        expect(() async {
          await AsyncScope.catchAllCancellations(() async {
            var future1 = scope.bindFuture(Future.value());
            var future2 = scope2.bindFuture(Future.value());
            scope.cancelAll();
            scope2.cancelAll();
            await Future.wait([future1, future2]);
          });
        }, returnsNormally);
      });

      test("completes when the async task completes", () async {
        var completer1 = Completer();
        var completer2 = Completer();
        var completer3 = Completer();

        var catchFuture = scope.catchCancellations(() async {
          await completer1.future;
          await completer2.future;
          await completer3.future;
        });

        completer1.complete();
        completer2.complete();
        completer3.complete();

        expect(catchFuture, completes);
      });

      test("completes normally when an async (future) task is canceled", () async {
        var completer = Completer();

        var catchFuture = scope.catchCancellations(() async {
          await scope.bindFuture(completer.future);
        });
        var catchFutureCompletedNormally = false;
        var catchFutureCompletedError = false;
        catchFuture
          .then((_) => catchFutureCompletedNormally = true)
          .catchError((_) => catchFutureCompletedError = true);;

        scope.cancelAll();

        // cancellations should not be handled synchronously
        expect(catchFutureCompletedNormally, false);

        await Future.delayed(Duration.zero);
        
        expect(catchFutureCompletedNormally, true);
        expect(catchFutureCompletedError, false);
      });

      test("completes normally when an async (stream) task is canceled", () async {
        var controller = StreamController();

        var catchFuture = scope.catchCancellations(() async {
          await for (var data in scope.bindStream(controller.stream)) {
            // just ignore data
          }
        });
        var catchFutureCompletedNormally = false;
        var catchFutureCompletedError = false;
        catchFuture
          .then((_) => catchFutureCompletedNormally = true)
          .catchError((_) => catchFutureCompletedError = true);

        scope.cancelAll();

        // cancellations should not be handled synchronously
        expect(catchFutureCompletedNormally, false);

        await Future.delayed(Duration.zero);
        
        expect(catchFutureCompletedNormally, true);
        expect(catchFutureCompletedError, false);
      });

      test("forwards non-cancellation asynchronous/future errors through its own future", () async {
        var catchFuture = scope.catchCancellations(() async {
          var completer = Completer();
          completer.completeError("forward this");
          
          await completer.future;
        });

        expect(() async {
          await catchFuture;
        }, throwsA("forward this"));
      });

      test("forwards non-cancellation stream errors through its own future when stream is part of the future stack", () async {
        var catchFuture = scope.catchCancellations(() async {
          var controller = StreamController();
          controller.addError("forward this");

          await for (var _ in controller.stream) {}
        });

        expect(() async {
          await catchFuture;
        }, throwsA("forward this"));
      });

      test("forwards non-cancellation stream errors through its own future when stream is handled manually", () async {
        var uncaughtErrors = [];
        await runZonedGuarded(
          () async {
            var catchFuture = scope.catchCancellations(() async {
              var controller = StreamController();
              controller.addError("forward this");

              controller.stream.listen(null);
              await Future.delayed(Duration.zero);
            });

            await catchFuture;
          },
          (error, stackTrace) {
            uncaughtErrors.add(error);
          },
        );

        expect(uncaughtErrors, ["forward this"]);
      });
    });

    group("from its future-related behaviors", () {
      late Completer completer;

      setUp(() {
        completer = Completer();
      });

      test("can bind futures to itself", () async {
        var boundFuture = scope.bindFuture(completer.future);
        completer.complete(5);

        expect(await boundFuture, 5);
      });

      test("can cancel future asynchronous processing", () async {
        var completer1 = Completer();
        var completer2 = Completer();
        var completer3 = Completer();
        var taskResults = [];
        
        completeThenWaitInOrder([completer1, completer2, completer3]);
        await runTasksToCancel(
          scopeToCancel: scope, 
          cancelDelayer: completer2,
          tasks: [
            runFutureTask(
              scope: scope, 
              delayers: [completer1, completer3], 
              resultsList: taskResults,
            ),
          ],
        );

        expect(taskResults, [1, 2]);
      });
    });

    group("from its stream-related behaviors", () {
      late StreamController controller;
      
      setUp(() {  
        controller = StreamController();
      });

      test("can bind streams to itself", () async {
        var boundStream = scope.bindStream(controller.stream);
        controller.add(1);
        controller.add(2);
        controller.add(3);
        controller.close();

        expect(await boundStream.toList(), [1, 2, 3]);
      });

      test("can cancel streams prematurely", () async {
        var completer1 = Completer();
        var completer2 = Completer();
        var completer3 = Completer();
        var taskResults = [];

        completeThenWaitInOrder([completer1, completer2, completer3]);
        await runTasksToCancel(
          scopeToCancel: scope, 
          cancelDelayer: completer2,
          tasks: [
            runStreamTask(
              scope: scope,
              delayers: [completer1, completer3],
              resultsList: taskResults,
            ),
          ],
        );

        expect(taskResults, [1, 2]);
      });

      test("throws when listening to a stream bound to a single-subscription stream that is already listened to", () async {
        controller.stream.listen(null);

        expect(
          () => scope.catchCancellations(
            () => scope.bindStream(controller.stream)
          ),
          returnsNormally,
        );

        expect(
          () => scope.catchCancellations(
            () => scope.bindStream(controller.stream).listen(null)
          ),
          throwsStateError,
        );
      });
    });

    group("from its parent-child relationships", () {
      test("will cancel children scopes when canceled", () async {
        var completer1 = Completer();
        var completer2 = Completer();
        var completer3 = Completer();
        var child1 = AsyncScope(scope);
        var child2 = AsyncScope(scope);
        var task1Results = [];
        var task2Results = [];

        completeThenWaitInOrder([completer1, completer2, completer3]);
        await runTasksToCancel(
          scopeToCancel: scope, 
          cancelDelayer: completer2,
          tasks: [
            runFutureTask(
              scope: child1, 
              delayers: [completer1, completer3], 
              resultsList: task1Results,
            ),
            runStreamTask(
              scope: child2, 
              delayers: [completer1, completer3], 
              resultsList: task2Results,
            ),
          ],
        );

        expect(task1Results, [1, 2]);
        expect(task2Results, [1, 2]);
        expect(scope.isCanceled, true);
        expect(child1.isCanceled, true);
        expect(child2.isCanceled, true);
      });

      test("will not cancel parent scopes when canceled", () async {
        var completer1 = Completer();
        var completer2 = Completer();
        var completer3 = Completer();
        var child1 = AsyncScope(scope);
        var taskResults = [];

        completeThenWaitInOrder([completer1, completer2, completer3]);
        await runTasksToCancel(
          scopeToCancel: child1,
          cancelDelayer: completer2,
          tasks: [
            runFutureTask(
              scope: scope,
              delayers: [completer1, completer3],
              resultsList: taskResults,
            ),
          ],
        );

        expect(taskResults, [1, 2]);
        expect(scope.isCanceled, false);
        expect(child1.isCanceled, true);
      });
    });

    test("throws when attempting to bind after being canceled", () async {
      expect(scope.isCanceled, false);
      expect(
        () => scope.catchCancellations(
          () => scope.bindFuture(Future.value())
        ),
        returnsNormally,
      );

      scope.cancelAll();
      
      expect(scope.isCanceled, true);
      expect(
        () => scope.catchCancellations(
          () => scope.bindFuture(Future.value())
        ),
        throwsA(isA<AsyncScopeCanceledError>()),
      );
    });

    test("can bind/cancel independently of other scopes", () async {
      var scope2 = AsyncScope();
      var child3 = AsyncScope();
      var completer = Completer();

      var future1 = scope.bindFuture(completer.future);
      var future2 = scope2.bindFuture(completer.future);
      var future3 = child3.bindFuture(future1);

      scope.cancelAll();

      completer.complete();

      expect(future1, throwsA(isA<TaskCancelationException>()));
      expect(future2, completes);
      expect(future3, throwsA(isA<TaskCancelationException>()));
    });
  });

  group("scoping extensions", () {
    test("can scope futures by binding them to an AsyncScope", () async {

    });

    test("can scope streams by binding them to an AsyncScope", () async {

    });
  });
}

final mainZone = Zone.current;
void runWithFreshZone(void Function() body) {

}

Future<void> runFutureTask({
  required AsyncScope scope, 
  required List<Completer> delayers,
  required List resultsList,
}) async {
  Future<void> asyncTask() async {
    for (var (idx, delayer) in delayers.indexed) {
      resultsList.add(idx + 1);
      await delayer.future;
    }
  }
  
  await scope.catchCancellations(asyncTask);
}

Future<void> runStreamTask({
  required AsyncScope scope, 
  required List<Completer> delayers,
  required List resultsList,
}) async {
  Future<void> asyncTask() async {
    var stream = () async* {
      for (var (idx, delayer) in delayers.indexed) {
        yield idx + 1;
        await delayer.future;
      }
    }();

    await for (var data in scope.bindStream(stream)) {
      resultsList.add(data);
    }
  }

  await scope.catchCancellations(asyncTask);
}

Future<void> runTasksToCancel({
  required AsyncScope scopeToCancel,
  required Completer cancelDelayer,
  required List<Future> tasks,
}) async {
  Future<void> cancelScopeAfterDelay() async {
    await cancelDelayer.future;
    scopeToCancel.cancelAll();
  }

  await Future.wait([
    ...tasks,
    cancelScopeAfterDelay(),
  ]);
}

Future<void> completeThenWaitInOrder(List<Completer> delayers) async {
  for (var delayer in delayers) {
    delayer.complete();
    await Future.delayed(Duration.zero);
  }
}
