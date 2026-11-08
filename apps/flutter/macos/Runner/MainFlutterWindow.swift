import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()

    placeOnVisibleScreen()
  }

  /// The window of the bundle has to be visible on a screen of the machine.
  ///
  /// The frame of the storyboard is a fixed rectangle of the screen the
  /// bundle was generated for. On a smaller display the window opens above
  /// the visible area and the operator sees nothing at all. When the frame
  /// touches no visible screen, the window is placed in the centre of the
  /// visible frame of the main screen and fitted into it.
  private func placeOnVisibleScreen() {
    let visibleFrames = NSScreen.screens.map { $0.visibleFrame }
    let visible = visibleFrames.contains(where: { $0.intersects(frame) })
    report("frames=\(visibleFrames) window=\(frame) visible=\(visible)")
    if visible {
      return
    }
    guard let screen = NSScreen.main ?? NSScreen.screens.first else {
      report("no screen of the machine")
      return
    }
    let visibleFrame = screen.visibleFrame
    var target = frame
    target.size.width = min(target.size.width, visibleFrame.width)
    target.size.height = min(target.size.height, visibleFrame.height)
    target.origin.x = visibleFrame.midX - target.width / 2
    target.origin.y = visibleFrame.midY - target.height / 2
    setFrame(target, display: true)
    report("placed=\(frame)")
  }

  /// One line of the placement of the window on the standard error of the
  /// bundle. The operator sees the window; the log says where it came.
  private func report(_ message: String) {
    FileHandle.standardError.write(("OIP-WINDOW " + message + "\n").data(using: .utf8)!)
  }
}
