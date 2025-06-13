import 'dart:async';

import 'package:scopely/scopely.dart';
import 'package:test/test.dart';

void main() {
  late StreamController<int> controller;
  late List futureResults;
  late List futureErrors;
  late List errors;

  setUp(() {
    controller = StreamController();
    futureResults = [];
    futureErrors = [];
    errors = [];

    controller.stream.asFutures().listen(
      (future) async {
        try {
          futureResults.add(await future);
        } catch (error) {
          futureErrors.add(error);
        }
      },
      onError: (error, stackTrace) => errors.add((error, stackTrace)),
    );
  });

  tearDown(() {
    controller.close();
  });

  test("forwards data from the original stream", () async {
    controller.add(1);
    controller.add(2);
    controller.add(3);
    await Future.delayed(Duration.zero);

    expect(futureResults, [1, 2, 3]);
  });

  test("forwards errors as failed futures instead of error events", () async {
    controller.addError("fake error");
    await Future.delayed(Duration.zero);
    
    expect(futureResults, []);
    expect(futureErrors, ["fake error"]);
    expect(errors, []);
  });

  test("respects single-subscription stream listening contract", () async {
    expect(() {
      // setup listened to the stream already, so do it again
      controller.stream.asFutures().listen(null);
    }, throwsStateError);
  });
}
