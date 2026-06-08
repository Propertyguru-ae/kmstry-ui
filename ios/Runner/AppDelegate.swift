import Flutter
import UIKit
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GMSServices.provideAPIKey("AIzaSyAW_tmPFyMqvhpZn9Fieq2iUXxX3we-F70")
    GeneratedPluginRegistrant.register(with: self)

    // window, super.application içinde kurulduğu için önce onu çağırıyoruz.
    let launchResult = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    // Native video aynalama kanalı (front camera mirror, re-encode yok).
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "app/video_mirror",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "mirror",
              let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
          result(FlutterMethodNotImplemented)
          return
        }
        VideoMirror.mirror(inputPath: path) { res in
          DispatchQueue.main.async {
            switch res {
            case .success(let outPath):
              result(outPath)
            case .failure(let error):
              result(FlutterError(
                code: "MIRROR_FAILED",
                message: error.localizedDescription,
                details: nil
              ))
            }
          }
        }
      }
    }

    return launchResult
  }
}
