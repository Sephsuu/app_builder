# Salin artwork and offline fonts

`LANDPAGElogo.png` and `tagalogHeader.png` are the supplied originals, unchanged.
The logo uses its original aspect ratio. The Tagalog widget clips only the PNG's
transparent padding in layout; the original image file is not cropped or edited.

The supplied character originals were `AFRO.jpg` and `BABAE.jpg` (240×324), not
SVGs. At the user's explicit follow-up request on 10 October 2026, `AFRO.svg` and
`BABAE.svg` were traced from those JPEGs. The originals remain here unchanged;
these SVGs are derivatives, not recovered original vector files.

Conversion used VTracer 0.6.15 (Python package; generator reports engine 0.6.12):
black threshold 150, two-color tracing, spline paths, speckle filter 2, color
precision 2, corner threshold 60, length threshold 3, splice threshold 45 and
path precision 2. The exterior background is transparent. White areas inside
the open-bottom bust/arm contours are retained as skin and clothing. Each SVG
viewBox includes the visible artwork with four source pixels of padding. Paths
use black/white fills and translation transforms; there are no embedded rasters,
external references, fonts, masks or filters. Fine details are limited by the
resolution of the original JPEGs.

Both fonts are the official variable TrueType files from Google Fonts, downloaded
10 October 2026. They are bundled in `pubspec.yaml` and do not make runtime
network requests. Corresponding SIL Open Font Licenses are included and bundled.

- [Inter source](https://github.com/google/fonts/tree/main/ofl/inter)
- [Plus Jakarta Sans source](https://github.com/google/fonts/tree/main/ofl/plusjakartasans)

SHA-256:

| File | SHA-256 |
|---|---|
| LANDPAGElogo.png | 0510729609724786713d53c597d547ec8809a8b027eb408a1b77ebca0c372d46 |
| tagalogHeader.png | dd0e4a9fa50cd37591c6217041f43c00e41f7c7d3cbc480b52e533b8a7de40c8 |
| AFRO.jpg | 27fbd93f54c653a548606e1ed63bb6dbbd454c87a1e27867f9ca995fee4260b0 |
| BABAE.jpg | 751429284ad78c1d336b22c174be5b703a0adde48bd84deffaee60ed83950a68 |
| fonts/Inter.ttf | 29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031 |
| fonts/PlusJakartaSans.ttf | 89b3fb38aa0d275d7a731d0d817a4f1622b316b4d7fbdedcf02ee9099ff68bc8 |
