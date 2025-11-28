import Cocoa
import FlutterMacOS
import AVFoundation

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    // Request microphone permission (macOS)
    AVCaptureDevice.requestAccess(for: .audio) { granted in
      if granted {
        print("Microphone permission granted")
      } else {
        print("Microphone permission denied")
      }
    }
  }
  
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
