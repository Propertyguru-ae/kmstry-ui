"""Build shared startup artwork with the original bold, shadowed wordmark.

First run tool/export_startup_wordmark.dart on an iOS simulator. Pass its PNG
directory with --wordmark-dir once. Then --check verifies generated assets.
The original source symbol is retained. No fonts are copied or redistributed.
"""

import argparse
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
MASTERS = ROOT / "tool/brand"


def compose(symbol_source, wordmark):
    canvas = Image.new("RGBA", symbol_source.size)
    # Only the symbol is reused; old thin lettering is discarded.
    region = (0, 0, symbol_source.width, round(symbol_source.height * 0.45))
    canvas.paste(symbol_source.crop(region), (0, 0))
    canvas.alpha_composite(wordmark.resize(canvas.size, Image.Resampling.LANCZOS))
    return canvas


def verify_or_save(path, expected, check):
    if not check:
        expected.save(path)
    actual = Image.open(path).convert("RGBA")
    if actual.size != expected.size or actual.tobytes() != expected.tobytes():
        raise ValueError(f"Unexpected startup artwork: {path}")
    print(f"OK {path.relative_to(ROOT)} {actual.size}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--wordmark-dir", type=Path)
    args = parser.parse_args()
    if args.wordmark_dir:
        if args.check:
            parser.error("--check cannot install master artwork")
        MASTERS.mkdir(exist_ok=True)
        for name in ("light", "dark"):
            source = args.wordmark_dir / f"{name}.png"
            im = Image.open(source)
            if im.size != (1356, 1808) or im.mode != "RGBA":
                raise ValueError("Expected transparent 4x Flutter wordmark")
            (MASTERS / f"wordmark_{name}.png").write_bytes(source.read_bytes())
    words = {
        name: Image.open(MASTERS / f"wordmark_{name}.png").convert("RGBA")
        for name in ("light", "dark")
    }
    original = Image.open(ROOT / "assets/images/native_splash_logo.png").convert("RGBA")
    for name in words:
        verify_or_save(
            ROOT / f"assets/images/native_splash_logo_{name}.png",
            compose(original, words[name]), args.check,
        )
    ios = ROOT / "ios/Runner/Assets.xcassets/LaunchBrandAppearance.imageset"
    pairs = []
    for scale in ("", "@2x", "@3x"):
        pairs.append((ios / f"LaunchImage{scale}.png", ios / f"LaunchImageDark{scale}.png"))
    android = ROOT / "android/app/src/main/res"
    for density in ("mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi"):
        pairs.append((android / f"drawable-{density}/splash.png",
                      android / f"drawable-night-{density}/splash.png"))
    for light, dark in pairs:
        # Preserve each native density's existing symbol pixels exactly.
        existing = Image.open(dark).convert("RGBA")
        for name, path in (("light", light), ("dark", dark)):
            verify_or_save(path, compose(existing, words[name]), args.check)
    for name, native in (("light", "LaunchImage@3x.png"), ("dark", "LaunchImageDark@3x.png")):
        target = ROOT / f"assets/images/startup_brand_{name}.png"
        source = (ios / native).read_bytes()
        if not args.check:
            target.write_bytes(source)
        if target.read_bytes() != source:
            raise ValueError(f"Flutter/native artwork differs: {target}")
        print(f"OK Flutter/native {name} artwork is byte-identical")


if __name__ == "__main__":
    main()
