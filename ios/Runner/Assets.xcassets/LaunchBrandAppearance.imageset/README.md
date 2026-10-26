# Launch Screen Assets

Light and Dark variants share the same symbol and layout. The original Continue
screen's bold system lettering and blue shadow are rendered once by the local
`tool/export_startup_wordmark.dart` tool and composited into every native density.
`tool/prepare_splash_light.py --check` verifies the generated artwork. Flutter
uses the exact same @3x PNGs, so there is no font or position jump at startup.

The active asset is `LaunchBrandAppearance`, referenced by
`Base.lproj/LaunchScreenBrand.storyboard`. `Info.plist` and the Xcode project
must keep that storyboard name in sync. These names replace the old launch
resources so an installed app can stop reusing the previous white-on-light
launch image. Do not change them on every build.

`flutter_native_splash` defaults to `LaunchImage` and `LaunchScreen`; if running
that generator, preserve the custom active bindings and rerun the appearance
tests. Changing only the unused default resources will not update the splash.
