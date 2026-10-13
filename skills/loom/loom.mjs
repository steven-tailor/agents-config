#!/usr/bin/env node
// Turn a Loom share link into files a model can read cheaply:
// video, transcript with timecodes, scene-change frames, contact sheet.
// Usage: loom.mjs fetch <loom-url> [outdir]   (default outdir: ~/loom/<video-id>)
//        loom.mjs strip <outdir> <x:y:w:h> [scale-width]  (crop one region from every frame, tile into strip.png)
import { execFileSync } from "node:child_process";
import { mkdirSync, writeFileSync, readdirSync, existsSync, statSync } from "node:fs";
import { homedir } from "node:os";
import { join, basename } from "node:path";

const [cmd, ...rest] = process.argv.slice(2);
const die = (m) => { console.error(m); process.exit(1); };
const run = (bin, args, opts = {}) => execFileSync(bin, args, { stdio: ["ignore", "pipe", "pipe"], ...opts }).toString();

const videoId = (url) => {
  const m = /loom\.com\/(?:share|embed)\/([0-9a-f]{32})/.exec(url) ?? /^([0-9a-f]{32})$/.exec(url);
  if (!m) die(`Not a Loom share link: ${url}`);
  return m[1];
};

const json = async (res) => { if (!res.ok) die(`${res.url}: HTTP ${res.status}`); return res.json(); };

const fetchVideo = async (id) => {
  const res = await fetch(`https://www.loom.com/api/campaigns/sessions/${id}/transcoded-url`, {
    method: "POST", headers: { "content-type": "application/json" }, body: "{}",
  });
  const { url } = await json(res);
  if (!url) die("Loom returned no video URL (private video? try yt-dlp)");
  return Buffer.from(await (await fetch(url)).arrayBuffer());
};

const fetchCaptions = async (id) => {
  const query = `query FetchVideoTranscript($videoId: ID!, $password: String) {
    fetchVideoTranscript(videoId: $videoId, password: $password) {
      ... on VideoTranscriptDetails { captions_source_url language }
      ... on GenericError { message } } }`;
  const res = await fetch("https://www.loom.com/graphql", {
    method: "POST",
    headers: { "content-type": "application/json", "x-loom-request-source": "loom_web_2" },
    body: JSON.stringify({ operationName: "FetchVideoTranscript", variables: { videoId: id, password: null }, query }),
  });
  const data = (await json(res)).data?.fetchVideoTranscript;
  if (!data?.captions_source_url) return null;
  return (await fetch(data.captions_source_url)).text();
};

const vttToText = (vtt) => {
  const out = []; let t = null;
  for (const line of vtt.split("\n")) {
    const m = /^(\d+):(\d+):(\d+)\.\d+ -->/.exec(line);
    if (m) { t = +m[1] * 3600 + +m[2] * 60 + +m[3]; continue; }
    const s = line.replace(/<\/?v[^>]*>/g, "").trim();
    if (s && !/^\d+$/.test(s) && s !== "WEBVTT") out.push(`[${t}s] ${s}`);
  }
  return out.join("\n");
};

const probe = (file) => {
  const [w, h, fps, dur] = run("ffprobe", ["-v", "error", "-select_streams", "v:0", "-show_entries",
    "stream=width,height,r_frame_rate:format=duration", "-of", "csv=p=0", file]).trim().split(/[\n,]/);
  const [n, d] = fps.split("/").map(Number);
  return { width: +w, height: +h, fps: n / (d || 1), duration: +dur };
};

const extractFrames = (file, dir, { fps, width }) => {
  mkdirSync(join(dir, "raw"), { recursive: true });
  // A frame at every scene change, and at least one every 10 s.
  run("ffmpeg", ["-v", "error", "-y", "-i", file, "-vf",
    "select='gt(scene,0.2)+isnan(prev_selected_t)+gte(t-prev_selected_t,10)'",
    "-vsync", "vfr", "-frame_pts", "1", join(dir, "raw", "f_%08d.png")]);
  mkdirSync(join(dir, "frames"), { recursive: true });
  const scale = Math.min(width, 2000);
  const frames = [];
  for (const f of readdirSync(join(dir, "raw")).sort()) {
    const t = (parseInt(f.slice(2, 10), 10) / fps).toFixed(1);
    const name = `t${t.padStart(6, "0")}s.png`;
    // The timecode is burned into the top-right corner so any crop or tile stays attributable.
    run("ffmpeg", ["-v", "error", "-y", "-i", join(dir, "raw", f), "-vf",
      `scale=${scale}:-1,drawtext=text='${name.slice(0, -4)}':x=w-150:y=6:fontsize=22:fontcolor=red:box=1:boxcolor=white@0.7`,
      join(dir, "frames", name)]);
    frames.push({ file: name, t: +t });
  }
  run("rm", ["-rf", join(dir, "raw")]);
  return frames;
};

const contactSheet = (dir, frames) => {
  const cols = 3, rows = Math.ceil(frames.length / cols);
  run("ffmpeg", ["-v", "error", "-y", "-pattern_type", "glob", "-i", join(dir, "frames", "*.png"), "-vf",
    `scale=660:-1,tile=${cols}x${rows}`,
    "-frames:v", "1", join(dir, "sheet.png")]);
};

if (cmd === "fetch") {
  const [url, outArg] = rest;
  if (!url) die("Usage: loom.mjs fetch <loom-url> [outdir]");
  const id = videoId(url);
  const dir = outArg ?? join(homedir(), "loom", id);
  mkdirSync(dir, { recursive: true });
  const video = join(dir, "video.mp4");
  if (!existsSync(video) || statSync(video).size === 0) writeFileSync(video, await fetchVideo(id));
  const info = probe(video);
  const vtt = await fetchCaptions(id);
  if (vtt) { writeFileSync(join(dir, "captions.vtt"), vtt); writeFileSync(join(dir, "transcript.txt"), vttToText(vtt) + "\n"); }
  const frames = extractFrames(video, dir, info);
  contactSheet(dir, frames);
  writeFileSync(join(dir, "index.json"), JSON.stringify({ id, url, ...info, transcript: !!vtt, frames }, null, 2) + "\n");
  console.log(`${dir}\n${info.width}x${info.height}, ${Math.round(info.duration)}s, ${frames.length} frames, transcript: ${vtt ? "yes" : "no (run whisper or watch without it)"}`);
  console.log(`Read ${join(dir, "transcript.txt")} and ${join(dir, "sheet.png")} first.`);
} else if (cmd === "strip") {
  const [dir, region, scaleArg] = rest;
  if (!dir || !region) die("Usage: loom.mjs strip <outdir> <x:y:w:h> [scale-width]");
  const [x, y, w, h] = region.split(":").map(Number);
  const scale = Number(scaleArg ?? 1000);
  const frames = readdirSync(join(dir, "frames")).filter((f) => f.endsWith(".png")).sort();
  mkdirSync(join(dir, "strip"), { recursive: true });
  for (const f of frames) {
    run("ffmpeg", ["-v", "error", "-y", "-i", join(dir, "frames", f), "-vf",
      `crop=${w}:${h}:${x}:${y},scale=${scale}:-1,drawtext=text='${basename(f, ".png")}':x=w-150:y=6:fontsize=22:fontcolor=red:box=1:boxcolor=white@0.7`,
      join(dir, "strip", f)]);
  }
  const cols = w > h * 3 ? 1 : 2;
  run("ffmpeg", ["-v", "error", "-y", "-pattern_type", "glob", "-i", join(dir, "strip", "*.png"), "-vf",
    `tile=${cols}x${Math.ceil(frames.length / cols)}`, "-frames:v", "1", join(dir, "strip.png")]);
  run("rm", ["-rf", join(dir, "strip")]);
  console.log(join(dir, "strip.png"));
} else die("Usage: loom.mjs fetch <loom-url> [outdir] | strip <outdir> <x:y:w:h> [scale-width]");
