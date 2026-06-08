// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camerax;

import android.content.Context;
import android.hardware.camera2.CameraCharacteristics;
import android.hardware.camera2.CameraManager;
import android.hardware.camera2.CaptureRequest;
import android.util.Log;
import android.util.Range;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.annotation.OptIn;
import androidx.camera.camera2.interop.Camera2Interop;
import androidx.camera.camera2.interop.ExperimentalCamera2Interop;
import androidx.camera.video.VideoCapture;
import androidx.camera.video.VideoOutput;
import java.util.ArrayList;
import java.util.List;

/**
 * ProxyApi implementation for {@link VideoCapture}. This class may handle instantiating native
 * object instances that are attached to a Dart instance or handle method calls on the associated
 * native class or an instance of that class.
 */
class VideoCaptureProxyApi extends PigeonApiVideoCapture {
  VideoCaptureProxyApi(@NonNull ProxyApiRegistrar pigeonRegistrar) {
    super(pigeonRegistrar);
  }

  // Range<?> is defined as Range<Integer> in pigeon.
  @SuppressWarnings("unchecked")
  @OptIn(markerClass = ExperimentalCamera2Interop.class)
  @NonNull
  @Override
  public VideoCapture<?> withOutput(
      @NonNull VideoOutput videoOutput, @Nullable Range<?> targetFpsRange) {
    VideoCapture.Builder<VideoOutput> builder = new VideoCapture.Builder<>(videoOutput);

    // Eğer Dart tarafı açıkça bir FPS aralığı verdiyse ona saygı duy.
    // Aksi halde, video kaydında AE'nin ~30fps'e kilitlenip loş ortamda
    // görüntüyü karartmasını engellemek için ESNEK bir düşük-ışık aralığı
    // (örn. [15,30]) seçeriz. Böylece iyi ışıkta 30fps (akıcı), loş ışıkta
    // AE alt sınıra düşüp pozlamayı uzatarak görüntüyü aydınlatır.
    Range<Integer> appliedRange = (Range<Integer>) targetFpsRange;
    if (appliedRange == null) {
      Context context = null;
      try {
        context = ((ProxyApiRegistrar) getPigeonRegistrar()).getContext();
      } catch (Exception e) {
        // yoksay
      }
      appliedRange = computeLowLightFpsRange(context);
    }

    if (appliedRange != null) {
      Camera2Interop.Extender<VideoCapture<VideoOutput>> extender =
          new Camera2Interop.Extender<>(builder);
      extender.setCaptureRequestOption(
          CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, appliedRange);
    }

    return builder.build();
  }

  /**
   * Cihazdaki TÜM kameraların desteklediği AE hedef FPS aralıkları arasından, loş ortam için en
   * iyisini seçer: üst sınırı akıcı kayıt için yeterli (>=24), alt sınırı en düşük olan aralık.
   * Her kamerada desteklenen bir aralık seçilir ki session bozulmasın. Uygun aralık yoksa null
   * döner (mevcut davranış korunur).
   */
  @Nullable
  private static Range<Integer> computeLowLightFpsRange(@Nullable Context context) {
    if (context == null) return null;
    try {
      CameraManager cm = (CameraManager) context.getSystemService(Context.CAMERA_SERVICE);
      if (cm == null) return null;

      String[] ids = cm.getCameraIdList();
      if (ids.length == 0) return null;

      // İlk kameranın aralıklarını aday listesi yap.
      List<Range<Integer>> candidates = new ArrayList<>();
      Range<Integer>[] firstRanges =
          cm.getCameraCharacteristics(ids[0])
              .get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES);
      if (firstRanges == null) return null;
      for (Range<Integer> r : firstRanges) candidates.add(r);

      // Yalnızca tüm kameralarda da bulunan aralıkları tut (kesişim).
      for (int i = 1; i < ids.length; i++) {
        Range<Integer>[] ranges =
            cm.getCameraCharacteristics(ids[i])
                .get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES);
        if (ranges == null) continue;
        List<Range<Integer>> intersection = new ArrayList<>();
        for (Range<Integer> r : candidates) {
          for (Range<Integer> other : ranges) {
            if (r.equals(other)) {
              intersection.add(r);
              break;
            }
          }
        }
        candidates = intersection;
      }

      // En iyi loş-ışık aralığını seç: üst >= 24, alt sınırı en küçük; eşitse üstü en büyük.
      Range<Integer> best = null;
      for (Range<Integer> r : candidates) {
        if (r.getUpper() < 24) continue;
        if (best == null
            || r.getLower() < best.getLower()
            || (r.getLower().equals(best.getLower()) && r.getUpper() > best.getUpper())) {
          best = r;
        }
      }
      return best;
    } catch (Exception e) {
      Log.w("VideoCaptureProxyApi", "AE fps range hesaplanamadı: " + e.getMessage());
      return null;
    }
  }

  @NonNull
  @Override
  public VideoOutput getOutput(VideoCapture<?> pigeonInstance) {
    return pigeonInstance.getOutput();
  }

  @Override
  public void setTargetRotation(VideoCapture<?> pigeonInstance, long rotation) {
    pigeonInstance.setTargetRotation((int) rotation);
  }
}
