import Cocoa

final class Surface: NSView {
  var sizes: [NSSize] = []

  override func setFrameSize(_ size: NSSize) {
    if frame.size != size { sizes.append(size) }
    super.setFrameSize(size)
  }
}

@main
struct DeferredContentResizeTest {
  static func main() {
    let initial = NSSize(width: 800, height: 600)
    let frame = NSRect(origin: .zero, size: initial)
    let content = NSView(frame: frame)
    let surface = Surface(frame: frame)
    surface.autoresizingMask = [.width, .height]
    content.addSubview(surface)
    let resize = DeferredContentResize()

    for increment in 1...20 {
      let before = surface.frame.size
      let expected = NSSize(width: 800 + 11 * increment, height: 600 - 3 * increment)
      surface.sizes.removeAll()
      resize.begin(in: content)
      content.setFrameSize(NSSize(width: expected.width - 4, height: expected.height + 5))
      content.setFrameSize(expected)
      precondition(surface.frame.size == before && surface.sizes.isEmpty)
      resize.end()
      precondition(surface.frame.size == before)
      RunLoop.main.run(until: Date().addingTimeInterval(0.01))
      precondition(content.autoresizesSubviews && surface.sizes == [expected])
    }

    let before = surface.frame.size
    let expected = NSSize(width: 930, height: 510)
    surface.sizes.removeAll()
    resize.begin(in: content)
    content.setFrameSize(NSSize(width: 1000, height: 540))
    resize.end()
    resize.begin(in: content)
    content.setFrameSize(expected)
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    precondition(surface.frame.size == before && surface.sizes.isEmpty)
    resize.end()
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    precondition(surface.sizes == [expected])

    surface.sizes.removeAll()
    resize.begin(in: content)
    resize.end()
    RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    precondition(content.autoresizesSubviews && surface.sizes.isEmpty)
    content.setFrameSize(initial)
    precondition(surface.sizes == [initial])
    print("20 deferred AppKit resizes, queued completion, no-op and immediate resize passed")
  }
}
