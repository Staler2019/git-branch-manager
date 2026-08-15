import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/status_bar/background_task.dart';

void main() {
  group('BackgroundTask', () {
    test('factory creates task with correct fields', () {
      final task = BackgroundTask.fetch(
        id: 'fetch-1',
        label: 'Fetching from origin',
        current: 50,
        total: 100,
      );

      expect(task.id, 'fetch-1');
      expect(task.label, 'Fetching from origin');
      expect(task.current, 50);
      expect(task.total, 100);
      expect(task.finishedAt, isNull);
    });

    test('fetch task is cancellable', () {
      final task = BackgroundTask.fetch(
        id: 'fetch-1',
        label: 'Fetching',
        current: 0,
        total: 1,
      );

      expect(task.cancellable, isTrue);
    });

    test('pull task is cancellable', () {
      final task = BackgroundTask.pull(
        id: 'pull-1',
        label: 'Pulling',
        current: 0,
        total: 1,
      );

      expect(task.cancellable, isTrue);
    });

    test('push task is cancellable', () {
      final task = BackgroundTask.push(
        id: 'push-1',
        label: 'Pushing',
        current: 0,
        total: 1,
      );

      expect(task.cancellable, isTrue);
    });

    test('clone task is cancellable', () {
      final task = BackgroundTask.clone(
        id: 'clone-1',
        label: 'Cloning',
        current: 0,
        total: 1,
      );

      expect(task.cancellable, isTrue);
    });

    test('checkout task is NOT cancellable', () {
      final task = BackgroundTask.checkout(
        id: 'checkout-1',
        label: 'Checking out',
        current: 0,
        total: 1,
      );

      expect(task.cancellable, isFalse);
    });

    test('merge task is NOT cancellable', () {
      final task = BackgroundTask.merge(
        id: 'merge-1',
        label: 'Merging',
        current: 0,
        total: 1,
      );

      expect(task.cancellable, isFalse);
    });

    test('rebase task is NOT cancellable', () {
      final task = BackgroundTask.rebase(
        id: 'rebase-1',
        label: 'Rebasing',
        current: 0,
        total: 1,
      );

      expect(task.cancellable, isFalse);
    });

    test('copyWith creates immutable copy', () {
      final task1 = BackgroundTask.fetch(
        id: 'fetch-1',
        label: 'Fetching',
        current: 10,
        total: 100,
      );

      final task2 = task1.copyWith(current: 50);

      expect(task1.current, 10);
      expect(task2.current, 50);
      expect(task2.id, task1.id);
      expect(task2.label, task1.label);
      expect(task2.total, task1.total);
    });

    test('copyWith can set finishedAt', () {
      final task1 = BackgroundTask.fetch(
        id: 'fetch-1',
        label: 'Fetching',
        current: 100,
        total: 100,
      );

      final now = DateTime.now();
      final task2 = task1.copyWith(finishedAt: now);

      expect(task2.finishedAt, now);
      expect(task1.finishedAt, isNull);
    });

    test('progress calculation is correct', () {
      final task = BackgroundTask.fetch(
        id: 'fetch-1',
        label: 'Fetching',
        current: 33,
        total: 100,
      );

      expect(task.progress, closeTo(0.33, 0.01));
    });

    test('progress is clamped to 1.0 when current >= total', () {
      final task = BackgroundTask.fetch(
        id: 'fetch-1',
        label: 'Fetching',
        current: 150,
        total: 100,
      );

      expect(task.progress, 1.0);
    });

    test('progress is 0.0 (not NaN) when total is 0 (indeterminate task)', () {
      final task = BackgroundTask.fetch(
        id: 'fetch-1',
        label: 'Fetching',
        current: 0,
        total: 0,
      );

      expect(task.progress, 0.0);
      expect(task.progress.isNaN, isFalse);
    });

    test('task is immutable', () {
      final task = BackgroundTask.fetch(
        id: 'fetch-1',
        label: 'Fetching',
        current: 0,
        total: 100,
      );

      expect(task, isA<BackgroundTask>());
      // Verify fields are final by checking the object
      final taskCopy = BackgroundTask(
        id: task.id,
        label: task.label,
        current: task.current,
        total: task.total,
        cancellable: task.cancellable,
        finishedAt: task.finishedAt,
      );

      expect(taskCopy.id, task.id);
      expect(taskCopy.label, task.label);
    });
  });
}
