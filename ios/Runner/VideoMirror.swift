import Foundation
import AVFoundation

/// Ön kamera videosunu YENİDEN KODLAMADAN yatay aynalar.
///
/// Yöntem (Instagram/pro uygulamaların yaptığı): video track'in
/// `preferredTransform`'una yatay-flip matrisi eklenir ve dosya
/// `AVAssetExportPresetPassthrough` ile remux edilir. Kareler yeniden
/// sıkıştırılmaz → ~anlık, kalite kaybı yok.
enum VideoMirror {

  static func mirror(inputPath: String, completion: @escaping (Result<String, Error>) -> Void) {
    let inputURL = URL(fileURLWithPath: inputPath)
    let asset = AVURLAsset(url: inputURL)

    guard let videoTrack = asset.tracks(withMediaType: .video).first else {
      completion(.failure(MirrorError.noVideoTrack))
      return
    }

    let composition = AVMutableComposition()
    guard let compVideoTrack = composition.addMutableTrack(
      withMediaType: .video,
      preferredTrackID: kCMPersistentTrackID_Invalid
    ) else {
      completion(.failure(MirrorError.compositionFailed))
      return
    }

    let timeRange = CMTimeRange(start: .zero, duration: asset.duration)

    do {
      try compVideoTrack.insertTimeRange(timeRange, of: videoTrack, at: .zero)
    } catch {
      completion(.failure(error))
      return
    }

    // Ses varsa olduğu gibi taşı.
    if let audioTrack = asset.tracks(withMediaType: .audio).first,
       let compAudioTrack = composition.addMutableTrack(
        withMediaType: .audio,
        preferredTrackID: kCMPersistentTrackID_Invalid
       ) {
      try? compAudioTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
    }

    // Sensör (natural) uzayında yatay flip → sonra orijinal yönlendirme uygulanır.
    // Böylece görüntülenen kare yatay aynalanır, dönüş bozulmaz.
    let naturalSize = videoTrack.naturalSize
    let flip = CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: naturalSize.width, ty: 0)
    compVideoTrack.preferredTransform = flip.concatenating(videoTrack.preferredTransform)

    let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("\(Int(Date().timeIntervalSince1970 * 1000))_m.mp4")

    guard let export = AVAssetExportSession(
      asset: composition,
      presetName: AVAssetExportPresetPassthrough
    ) else {
      completion(.failure(MirrorError.exportInitFailed))
      return
    }

    export.outputURL = outputURL
    export.outputFileType = .mp4
    export.shouldOptimizeForNetworkUse = true

    export.exportAsynchronously {
      switch export.status {
      case .completed:
        completion(.success(outputURL.path))
      case .failed, .cancelled:
        completion(.failure(export.error ?? MirrorError.exportFailed))
      default:
        completion(.failure(MirrorError.exportFailed))
      }
    }
  }

  enum MirrorError: Error {
    case noVideoTrack
    case compositionFailed
    case exportInitFailed
    case exportFailed
  }
}
