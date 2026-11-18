import Cocoa

/// Lets AppKit resize the window while the Flutter surface keeps its current
/// size. Apply the resulting size after AppKit leaves live event tracking.
final class DeferredContentResize {
  private weak var content: NSView?
  private var originalSize: NSSize?
  private var generation = 0

  func begin(in view: NSView) {
    generation += 1
    // A second drag can begin before the first completion has run. Keep the
    // size the children still have and invalidate the queued completion.
    guard originalSize == nil, view.autoresizesSubviews else { return }
    content = view
    originalSize = view.bounds.size
    view.autoresizesSubviews = false
  }

  func end() {
    guard originalSize != nil else { return }
    let finishedGeneration = generation
    RunLoop.main.perform(inModes: [.default]) { [weak self] in
      guard let self, self.generation == finishedGeneration,
            let previousSize = self.originalSize else { return }
      self.originalSize = nil
      guard let view = self.content else { return }
      self.content = nil
      view.autoresizesSubviews = true
      if view.bounds.size != previousSize {
        view.resizeSubviews(withOldSize: previousSize)
      }
    }
  }
}
