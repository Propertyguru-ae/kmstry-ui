import Flutter
import UIKit
import GoogleMaps
import AVKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var volumeShutterChannel: FlutterMethodChannel?
  private var captureEventInteraction: AnyObject?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    guard let mapsApiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String,
          mapsApiKey.hasPrefix("AIza"),
          !mapsApiKey.contains("$(") else {
      fatalError(
        "Missing iOS Google Maps API key. Copy " +
        "ios/Flutter/GoogleMaps.xcconfig.example to GoogleMaps.xcconfig and set GOOGLE_MAPS_API_KEY."
      )
    }
    GMSServices.provideAPIKey(mapsApiKey)
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

      let shutterChannel = FlutterMethodChannel(
        name: "app/volume_shutter",
        binaryMessenger: controller.binaryMessenger
      )
      volumeShutterChannel = shutterChannel

      if #available(iOS 17.2, *) {
        let interaction = AVCaptureEventInteraction { [weak self] event in
          if event.phase == .ended {
            self?.volumeShutterChannel?.invokeMethod("onVolumeShutter", arguments: nil)
          }
        }
        interaction.isEnabled = false
        controller.view.addInteraction(interaction)
        captureEventInteraction = interaction

        shutterChannel.setMethodCallHandler { [weak interaction] call, result in
          guard call.method == "setEnabled" else {
            result(FlutterMethodNotImplemented)
            return
          }
          interaction?.isEnabled = (call.arguments as? Bool) ?? false
          result(nil)
        }
      } else {
        shutterChannel.setMethodCallHandler { call, result in
          guard call.method == "setEnabled" else {
            result(FlutterMethodNotImplemented)
            return
          }
          // Older iOS versions keep the normal volume-button behavior.
          result(nil)
        }
      }
    }

    return launchResult
  }
}
