/// Prevents late asynchronous responses from replacing newer UI state.
///
/// Call [begin] when starting a request and check [isCurrent] before applying
/// its result. [invalidate] makes all outstanding request tokens stale.
class LatestRequestGuard {
  int _generation = 0;

  int begin() => ++_generation;

  bool isCurrent(int token) => token == _generation;

  void invalidate() {
    _generation++;
  }
}
