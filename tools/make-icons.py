"""
Every launcher icon, from the one mark the academy already owns.

    python tools/make-icons.py

---------------------------------------------------------------------------
WHY THE MARK IS NOT SHIPPED AS-IS.

`mobile/assets/brand/mark.png` is the tree whose canopy is half a brain, drawn
on transparency. That is right on the sign-in screen, which has a known pale
background and room around it. A launcher icon has neither: Android composites
it against whatever wallpaper the person chose, and a transparent PNG there is
a tree floating on a photograph of their children.

So the icon is the mark centred on the brand's own pale wash, inset far enough
that Android's round and squircle masks cut background rather than branches.
The mark's drawn content sits at (55, 10)-(331, 384) inside its 384 square —
off-centre and touching the bottom edge — so it is cropped to its content first
and recentred, or every icon would sit low and left.

---------------------------------------------------------------------------
WHAT IS GENERATED.

  mipmap-*/ic_launcher.png          the legacy square, five densities
  mipmap-*/ic_launcher_foreground.png   the mark alone, for the adaptive icon
  values/ic_launcher_background.xml     its flat background colour
  mipmap-anydpi-v26/ic_launcher.xml     the adaptive icon itself

Adaptive icons matter from Android 8 on: the launcher masks the foreground and
background separately, and an app that ships only the legacy square gets a
white or grey plate around it on most phones.
"""

import pathlib

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
MARK = ROOT / "mobile/assets/brand/mark.png"
RES = ROOT / "mobile/android/app/src/main/res"

# --color-brand-soft from web/app/globals.css: the pale teal the dashboard
# already uses behind the mark.
BACKGROUND = (234, 244, 243, 255)
BACKGROUND_HEX = "#EAF4F3"

# Legacy icon sizes, and the adaptive foreground sizes beside them. The
# adaptive canvas is larger because the launcher crops it: only the middle two
# thirds is guaranteed visible, so the mark is drawn into that safe circle.
DENSITIES = {
    "mdpi": (48, 108),
    "hdpi": (72, 162),
    "xhdpi": (96, 216),
    "xxhdpi": (144, 324),
    "xxxhdpi": (192, 432),
}

SUPERSAMPLE = 4


def trimmed_mark() -> Image.Image:
    """The mark cropped to its own ink and padded back to a square."""
    mark = Image.open(MARK).convert("RGBA")
    box = mark.getchannel("A").getbbox()
    if box is None:
        raise SystemExit("the mark is empty")

    content = mark.crop(box)
    side = max(content.size)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(
        content,
        ((side - content.width) // 2, (side - content.height) // 2),
        content,
    )
    return square


def render(mark: Image.Image, size: int, inset: float, background) -> Image.Image:
    """The mark at `inset` of the canvas, over `background` or transparency."""
    big = size * SUPERSAMPLE
    canvas = Image.new("RGBA", (big, big), background or (0, 0, 0, 0))

    drawn = int(big * inset)
    scaled = mark.resize((drawn, drawn), Image.LANCZOS)
    offset = (big - drawn) // 2
    canvas.paste(scaled, (offset, offset), scaled)

    return canvas.resize((size, size), Image.LANCZOS)


def main() -> None:
    mark = trimmed_mark()

    for density, (legacy, adaptive) in DENSITIES.items():
        folder = RES / f"mipmap-{density}"
        folder.mkdir(parents=True, exist_ok=True)

        # 0.72 on the legacy square: enough air that the round mask on older
        # launchers does not clip the canopy.
        render(mark, legacy, 0.72, BACKGROUND).save(folder / "ic_launcher.png")

        # 0.46 on the adaptive foreground: its safe zone is the middle 66%,
        # and the mark has to sit inside that however the launcher masks it.
        render(mark, adaptive, 0.46, None).save(folder / "ic_launcher_foreground.png")

        print(f"  mipmap-{density:<8} {legacy}px  +  {adaptive}px adaptive")

    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(parents=True, exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@color/ic_launcher_background" />\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground" />\n'
        "</adaptive-icon>\n",
        encoding="utf-8",
    )

    values = RES / "values"
    values.mkdir(parents=True, exist_ok=True)
    (values / "ic_launcher_background.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        "<resources>\n"
        f'    <color name="ic_launcher_background">{BACKGROUND_HEX}</color>\n'
        "</resources>\n",
        encoding="utf-8",
    )

    store = ROOT / "apk"
    store.mkdir(exist_ok=True)

    # The 512 Play listing icon. The store shows it on white, so it keeps the
    # same wash rather than going transparent.
    render(mark, 512, 0.72, BACKGROUND).convert("RGB").save(store / "play-icon-512.png")

    feature_graphic(store / "play-feature-1024x500.png")

    print("\n  mipmap-anydpi-v26/ic_launcher.xml   adaptive icon")
    print("  values/ic_launcher_background.xml   background colour")
    print("  apk/play-icon-512.png               Play listing icon")


def feature_graphic(path) -> None:
    """
    The 1024x500 banner at the top of the Play listing.

    The full logo, not the mark: this is the one place in the listing with room
    for the academy's name, and a banner carrying only a tree says nothing a
    passer-by can read. It sits left of centre because Play crops this image
    differently on different surfaces and the middle is the only region that
    survives every crop — a mark pushed to an edge gets cut off in half of them.

    No text is drawn on top. Play overlays the app's own name and icon on this
    banner in several places, and a banner that repeats them reads as a mistake.
    """
    width, height = 1024, 500
    big = SUPERSAMPLE

    canvas = Image.new("RGB", (width * big, height * big), BACKGROUND[:3])

    logo = Image.open(ROOT / "mobile/assets/brand/logo.png").convert("RGBA")
    box = logo.getchannel("A").getbbox()
    if box:
        logo = logo.crop(box)

    # 68% of the banner's height, which leaves the wordmark legible at the
    # sizes Play actually renders this at.
    target = int(height * big * 0.68)
    scale = target / logo.height
    logo = logo.resize((int(logo.width * scale), target), Image.LANCZOS)

    canvas.paste(logo, ((width * big - logo.width) // 2, (height * big - logo.height) // 2), logo)
    canvas.resize((width, height), Image.LANCZOS).save(path)


if __name__ == "__main__":
    main()
