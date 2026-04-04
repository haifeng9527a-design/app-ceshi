import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentViewController = flutterViewController

    // PC 端布局需要宽度 >= 1100，启动时设为 1280x800，最小 1100x700
    let defaultFrame = CGRect(x: 200, y: 200, width: 1280, height: 800)
    self.setFrame(defaultFrame, display: true)
    self.minSize = NSSize(width: 1100, height: 700)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
