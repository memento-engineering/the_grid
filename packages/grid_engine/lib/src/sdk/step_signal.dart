/// What an observed runtime or protocol event means to a process step.
enum StepSignal {
  /// No cursor transition.
  none,

  /// A daemon is ready and remains live.
  ready,

  /// The step completed successfully.
  complete,

  /// The step failed and routes to supervision.
  failed,
}
