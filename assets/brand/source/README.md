# NOCAPS app icon — sources

- `nocaps_icon_master_1024.png` — the icon at full native quality (use this for anything ≤1024).
- `nocaps_icon_master_2048.png` — upscaled for large prints/posters (slightly softer).
- `layer_sky_2048.png` (softened) + `layer_mascot_2048.png` (mascot + soft glow) — the two layers, so the icon can be rebuilt or re-cropped at any size.
- `mascot_original.png` — the untouched mascot art.

Recipe (at 1024): sky = background02.png crop (0,731)–(941,1672), Gaussian blur 4px.
Mascot (cropped to its visible pixels) width 686px, centered, top at 252px, using its own black linework (no extra outline).
Soft glow behind mascot: color #3C236E, 45% opacity, 18px blur, 8px down.

Android files live one folder up (`assets/brand/`): icon_512/192, adaptive foreground/background/monochrome 432
(108dp; key art stays inside the central 264px circle), dev/preview variants with badges/tints.
The mascot is raster art, so there is no true vector (SVG) version — that would need the mascot redrawn as vector.
This folder has a .gdignore so Godot doesn't import it into builds.
