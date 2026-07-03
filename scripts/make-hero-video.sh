#!/usr/bin/env bash
#
# Cuts the hero intro video from the raw screen recording:
# title card -> full desktop (parallel sessions) -> zoom to the menu bar
# (red alert, panel) -> resolution -> end card, with timed text overlays.
#
# Input:  docs/media/hero-raw.mov  (4K screen recording, see the timing
#         constants below — adjust them after re-recording)
# Output: docs/media/hero.mp4      (1920x1080, 30 fps, ~30 s, no audio)
#
# Usage: scripts/make-hero-video.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAW="$ROOT/docs/media/hero-raw.mov"
OUT="$ROOT/docs/media/hero.mp4"
CARDS="$ROOT/build/video-cards"

[ -f "$RAW" ] || { echo "missing $RAW" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg required (brew install ffmpeg)" >&2; exit 1; }

mkdir -p "$CARDS"
xcrun swift "$ROOT/scripts/video-cards.swift" "$CARDS"

# --- Timings in the raw recording (seconds) -----------------------------------
ACT1_START=0.6    # calm: sessions working, panel browse (full frame)
ACT1_END=9.8
ACT2_START=9.8    # icon flips red, badge, panel shows "Needs input" (zoomed)
ACT2_END=14.0
CLICK_START=14.0  # click the session row -> Antigravity jumps to front
CLICK_END=18.5    # (full frame — the window switch is the point)
ACT3_START=19.0   # resumed: back to yellow, then all done (zoomed)
ACT3_END=25.7

# Top-right crop of the 3852x2168 source: menu bar icon + panel, 16:9.
CROP="crop=1600:900:2252:0"

ffmpeg -y -v error \
  -loop 1 -t 2.8 -i "$CARDS/card-title.png" \
  -i "$RAW" \
  -loop 1 -t 3.4 -i "$CARDS/card-end.png" \
  -i "$CARDS/ov-parallel.png" \
  -i "$CARDS/ov-red.png" \
  -i "$CARDS/ov-answer.png" \
  -i "$CARDS/ov-features.png" \
  -i "$CARDS/ov-click.png" \
  -filter_complex "
    [3:v]scale=1920:1080[ov1];
    [4:v]scale=1920:1080[ov2];
    [5:v]scale=1920:1080[ov3];
    [6:v]scale=1920:1080[ov4];
    [7:v]scale=1920:1080[ov5];
    [0:v]fps=30,scale=1920:1080,format=yuv420p,
        fade=t=in:st=0:d=0.5,fade=t=out:st=2.3:d=0.5[title];
    [1:v]trim=start=$ACT1_START:end=$ACT1_END,setpts=PTS-STARTPTS,fps=30,
        scale=1920:1080:flags=lanczos[act1base];
    [act1base][ov1]overlay=0:0:eof_action=repeat:enable='between(t,0.8,8.6)',format=yuv420p[act1];
    [1:v]trim=start=$ACT2_START:end=$ACT2_END,setpts=PTS-STARTPTS,fps=30,
        $CROP,scale=1920:1080:flags=lanczos[act2base];
    [act2base][ov2]overlay=0:0:eof_action=repeat:enable='between(t,0.5,3.9)',format=yuv420p[act2];
    [1:v]trim=start=$CLICK_START:end=$CLICK_END,setpts=PTS-STARTPTS,fps=30,
        scale=1920:1080:flags=lanczos[clickbase];
    [clickbase][ov5]overlay=0:0:eof_action=repeat:enable='between(t,0.4,4.2)',format=yuv420p[click];
    [1:v]trim=start=$ACT3_START:end=$ACT3_END,setpts=PTS-STARTPTS,fps=30,
        $CROP,scale=1920:1080:flags=lanczos[act3base];
    [act3base][ov4]overlay=0:0:eof_action=repeat:enable='between(t,0.5,2.7)'[act3mid];
    [act3mid][ov3]overlay=0:0:eof_action=repeat:enable='between(t,3.0,6.2)',format=yuv420p[act3];
    [2:v]fps=30,scale=1920:1080,format=yuv420p,
        fade=t=in:st=0:d=0.4,fade=t=out:st=2.7:d=0.7[end];
    [title][act1][act2][click][act3][end]concat=n=6:v=1:a=0,format=yuv420p[out]
  " \
  -map "[out]" -an -c:v libx264 -preset slow -crf 20 -movflags +faststart "$OUT"

echo ""
echo "Wrote $OUT"
ffprobe -v error -show_entries format=duration,size -of default=noprint_wrappers=1 "$OUT"

# README hero GIF: red alert (zoom), the click-to-focus window switch, and
# the resolution act — palette-optimized, well under GitHub's size comfort.
GIF="$ROOT/docs/media/hero.gif"
ffmpeg -y -v error -ss 12.0 -to 27.2 -i "$OUT" \
  -filter_complex "[0:v]fps=12,scale=900:-2:flags=lanczos,split[g1][g2];[g1]palettegen=stats_mode=diff[pal];[g2][pal]paletteuse=dither=bayer:bayer_scale=4" \
  "$GIF"
echo "Wrote $GIF ($(du -h "$GIF" | cut -f1))"
