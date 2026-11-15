---
name: motioneyes-visual-analysis
description: Pixel-based motion and UI change analysis from frame sequences or screenshots using computer vision and visual comparison. Use when `.transition` or visual effects are not observable via MotionEyes logs, when you only have screenshots/video, when you need regression diffs across builds, or when you need to summarize on-screen changes without instrumentation. Do not use when MotionEyes traces are available and you need precise timing/values; use `motioneyes-animation-debug` instead.
---

# MotionEyes Visual Analysis

## Overview

Analyze UI motion by comparing frames directly. This skill produces annotated images plus a JSON summary of motion signals (translation, scale, rotation, opacity, color) and changed regions. It complements MotionEyes traces when instrumentation is unavailable or insufficient.

## Use With the Other MotionEyes Skill

- Use `motioneyes-animation-debug` when you can instrument the app and need precise timing or value traces.
- Use this skill when you only have pixels or when `.transition` and similar effects do not surface in MotionEyes logs.

## Inputs

Use one of these inputs:

- **Frames directory** with sequential image files (PNG/JPG).
- **Video file** captured from the simulator (preferred). Frames are extracted at `--fps`.
- **macOS window capture** using `screencapture` with a window id.

## Workflow

Follow this order:

1. Capture or gather frames for the target animation.
2. Normalize frames (same size, consistent crop).
3. Run baseline analysis with `--trim` to generate frames, diffs, and keyframes.
4. Interpret motion using grid artifacts first (`grid/` + `sprite/`, plus `diff_grid/` when needed) for coordinate-indexed reading across frames.
5. If grid overlays obscure subtle visual details, fall back to non-grid artifacts (`frames/` + `diff/`) for verification.
6. Escalate from keyframe pairs to neighboring pairs and then `--all-pairs` only when confidence is low or anomalies are suspected.
7. Select key frames (start/mid/end + top delta frames) for summary.
8. Write `analysis.json` and `summary.md`.
9. If validating the skill itself, optionally generate an HTML report with `--report`.
10. Use `--trim-threshold` and `--trim-relative` tuning if the animation is subtle.

## Artifact Decision Matrix

Use this matrix to choose which artifacts to rely on.

| Goal | `frames/` | `grid/` | `diff/` | `diff_grid/` | `sprite/` | Pair scope |
| --- | --- | --- | --- | --- | --- | --- |
| Fast first pass (unknown issue) | Optional | Yes | Yes | Optional | Yes | Keyframe pairs |
| On-screen coordinate pinpointing ("where?") | Optional | Yes | Optional | Optional | Yes | Keyframe pairs |
| Pixel-change inspection ("what changed?") | Yes | Optional | Yes | Optional | Optional | Keyframe pairs |
| Timing/story summary | Optional | Yes | Optional | No | Yes | Keyframe pairs |
| Flicker / dropped-frame suspicion | Yes | Yes | Yes | Optional | Yes | All pairs |
| Regression verification across builds | Yes | Yes | Yes | Optional | Optional | All pairs |
| Visual design/polish review | Yes | No | Optional | No | Optional | Keyframe pairs |

## Claim-Evidence Contract

Every conclusion in `summary.md` must cite evidence explicitly.

- Do not infer motion from `diff/` alone. Pair each diff with `frame_n` and `frame_n+1`.
- For each major claim, cite at least:
  - frame pair index (for example `pair 12->13`)
  - artifact types used (`frames`, `diff`, optionally `grid` or `diff_grid`)
  - confidence score (`0.0-1.0`)
- Prefer coordinate-indexed references from `grid/` or `sprite/` when available.
- If confidence is below `0.7`, do not finalize. Escalate pair coverage first.
- If `diff` indicates change but frame context is ambiguous, mark as uncertain and inspect neighboring pairs.

## Pair Scope and Escalation

Use this escalation order:

1. Start with keyframe-rendered pairs (default behavior).
2. If uncertain, inspect local neighborhood around a suspect pair (`i-1`, `i`, `i+1`).
3. If still uncertain, or for flicker/regression work, rerun with `--all-pairs`.

Pair selection intent:

- Adjacent pairs: continuity and timing transitions.
- First vs last frame: net displacement/scale/rotation.
- Top-delta pairs: highest visible change moments.
- All pairs: exhaustive validation and anomaly hunting.

## Frame Capture

### Simulator (preferred)

- Use Xcode's built-in MCP server to run the app and RocketSim or `simctl` to capture the relevant visual sequence.
- Record only the animation window you care about (for example, 1.0s).
- For precise start timing, use the capture script with motion gating so frames only begin once pixels change.

Example flow:

1. Build and run the demo app.
2. Trigger the animation.
3. Capture frames with motion gating.
4. Run analysis using `--frames-dir`.

Motion-gated capture (simulator):

```bash
python3 scripts/capture_sim_frames.py \
  --sim-id <SIM_ID> \
  --output-dir /path/to/frames_raw \
  --fps 15 \
  --frame-count 45 \
  --gate-threshold 4.0 \
  --gate-consecutive 1
```

### macOS window capture

- Use `scripts/analyze_sequence.py --source macos --window-id <id> --duration <seconds> --fps <fps>`.
- The script uses `screencapture` on the specified window id.

### Pre-captured frames

- Place images in a folder named `frames/`.
- Run analysis using `--frames-dir`.

## Pairwise Diffs

- Diff images are generated between **consecutive frames** (frame _n_ vs _n+1_).
- By default, only keyframe pairs are rendered. Use `--all-pairs` to render every pair.
- Use `--diff-grid` to overlay the alphanumeric grid on diff images for faster coordinate pinpointing.
- Use `--grid-theme auto|light|dark` to ensure the grid is readable on dark or light backgrounds.
- Treat diff output as a **change detector**, not standalone semantic truth.

## Keyframe Selection

- Always analyze **all frames** for metrics.
- Summarize using **start**, **mid**, **end**, and the **top 2 delta frames**.
- If the sequence is very short (<=3 frames), include all frames.

## Outputs

The analyzer writes to the `--output` directory:

- `analysis.json`: machine-readable metrics.
- `summary.md`: short human summary.
- `frames/`: normalized frames.
- `grid/`: frames with alphanumeric grid overlay.
- `diff/`: absolute diff images.
- `diff_grid/`: diff images with grid overlay (when `--diff-grid` is enabled).
- `sprite/`: keyframe sprite sheet (grid-overlaid by default, raw only when `--no-grid` is used).

Interpretation guidance:

- Start with grid artifacts (`grid/` + `sprite/`) for coordinate-indexed motion interpretation.
- Add `diff_grid/` when you need pairwise change maps with coordinate labels.
- If overlays obscure subtle visual details, fall back to non-grid `frames/` + `diff/`.

## Scripts

Primary entrypoint:

```bash
python3 scripts/analyze_sequence.py --video /path/to/capture.mp4 --fps 15 --duration 1.0 --output /path/to/report
```

If the capture includes idle time before/after the animation, add `--trim` to auto-detect the motion window.

Recommended profiles:

```bash
# Default summary + coordinate-indexed artifacts
python3 scripts/analyze_sequence.py --video /path/to/capture.mp4 --fps 15 --duration 1.0 --trim --diff-grid --output /path/to/report

# Deep investigation for flicker/regression
python3 scripts/analyze_sequence.py --video /path/to/capture.mp4 --fps 15 --duration 1.0 --trim --diff-grid --all-pairs --output /path/to/report

# Clean visual review (no overlay)
python3 scripts/analyze_sequence.py --video /path/to/capture.mp4 --fps 15 --duration 1.0 --trim --no-grid --output /path/to/report
```

See `scripts/analyze_sequence.py --help` for all flags.

## Dependencies

Create a local venv and install dependencies:

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Reference

Load these references when needed:

- `references/motion-analysis-techniques.md`
- `references/report-schema.md`
- `references/grid-overlay-notes.md`
