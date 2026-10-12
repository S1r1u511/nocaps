# Community assets

Drop community art here, one folder per community. The folder name is the community **id**: lowercase,
no spaces (e.g. `shiba`, `penguin`, `rocket`). The same id is used for the community's data resources
under `data/communities/<id>/`.

## Folder layout

```text
assets/communities/<id>/
├── mascot.png            # the community mascot (required)
├── mascot_claimed.png    # optional: alternate art once the cap is claimed
├── cap_side.png          # optional: cap in flight (falls back to the default cap)
├── cap_center.png        # optional: cap sitting on the head (falls back to the default cap)
└── background/           # optional: theme layers (falls back to the default background)
    ├── sky.png
    ├── midground.png
    └── ground.png
```

A community with no cap art uses the shared `data/caps/default_cap.tres`. A community with no
background uses the shared default background.

## Format and sizes

- Format: **PNG**, RGBA, transparent background. No white/opaque backdrop, no baked shadow box.
- **Mascot:** `512 × 512`. Character centered, vertically filling ~80–90% of the canvas, feet near the
  bottom. Keep consistent framing across mascots so cap fit stays predictable.
- **Caps:** `256 × 256`. Cap centered and filling most of the width. `cap_side` faces the direction of
  flight; `cap_center` is the seated form.
- **Background:** either a single full-screen `backdrop` image (portrait `1080 × 1920`; cover-cropped,
  static) or tiling parallax layers: `sky` `1080 × 1920`, `midground` `1080 × 720`, `ground` `1080 × 420`.
- Parallax layers are **scaled to the viewport width**, so author them 1080 px wide (1.5× the 720 px
  design) for crispness; height scales with width. They tile horizontally, so keep left/right edges
  seamless. Position them with `y_offset` (or `align_bottom` for ground/midground).

## How it is used

The mascot's opaque bounds (not the full canvas) are the reference for cap fit and the head landing
band, so transparent padding does not affect fit. Tuning is done in the Godot editor with the Mascot
Fit Tool (`tools/mascot_fit_tool.tscn`); no code change is needed to fit a new mascot.

See `docs/09_COMMUNITY_SYSTEM_HANDOFF.md` and `docs/08_VISUALS_HANDOFF.md`.
