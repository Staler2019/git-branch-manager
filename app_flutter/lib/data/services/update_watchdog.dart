import 'dart:io';

/// The watchdog, running on its own isolate -- which is the entire point.
///
/// [Future.timeout] cannot bound synchronous work on the isolate that is
/// doing it: the `Timer` it arms needs the very event loop the blocking call
/// is holding. Measured on this repository's Dart 3.12.2: `.timeout(100ms)`
/// around a future whose body synchronously sleeps three seconds reports
/// `completed after 3009ms` and never fires. `closeNativeSession()` is
/// exactly that shape -- a synchronous FFI `gbm_session_close` whose C++
/// destructor blocks in `operations_->drain()` until the operation worker
/// goes idle -- so the deadline has to be enforced from somewhere the main
/// isolate cannot stall. A spawned isolate has its own event loop on its own
/// OS thread, and `exit()` from it terminates the whole VM (measured: the
/// process ended with the watchdog's code while the main isolate was 30
/// seconds into a synchronous sleep).
///
/// `sleep` rather than a `Timer` so nothing depends on this isolate having a
/// live event-loop reason to stay alive.
void updateWatchdogEntryPoint(int milliseconds) {
  sleep(Duration(milliseconds: milliseconds));
  exit(0);
}
