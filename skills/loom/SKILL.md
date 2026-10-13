---
name: loom
description: Read a Loom video as transcript plus a few screenshots. Use whenever a task or message links loom.com.
---

# Loom

The script `loom.mjs` sits next to this file (`~/.claude/skills/loom/` for Claude Code, `~/.codex/skills/loom/` for Codex). Needs node 20+ and ffmpeg.

```bash
node ~/.claude/skills/loom/loom.mjs fetch <loom-url>
```

Writes `~/loom/<id>/`: `transcript.txt` with `[Ns]` timecodes, `frames/` (one per scene change, timecode burned in), `sheet.png` (all frames tiled), `video.mp4`. Public share links need no login; if it fails, ask for another link.

Images are expensive. Read in this order and stop when the task is clear:

1. `transcript.txt`: the claim, the steps, the ask.
2. `sheet.png`: which screens appear and when. Layout only, text is unreadable.
3. For exact text (URLs, IDs, versions, numbers), one strip per region instead of full frames:
   `node ~/.claude/skills/loom/loom.mjs strip ~/loom/<id> <x:y:w:h> [width]` crops that region (coordinates in `frames/` scale) from every frame into `strip.png`. Address bar plus the panel you care about is usually enough.
4. Single `frames/` files only for the two or three moments that matter.

Report in English, "said" and "seen" kept apart, with timecodes; copy IDs exactly and mark unreadable text as unreadable. Say whether anything was verified against data. Videos show customer names and call transcripts: keep them inside company tools.
