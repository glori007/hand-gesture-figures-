# Hand Geometry Sculptor

A gesture-driven visual environment where the hands are the only interface — no mouse, no keyboard, no controller. Point, shape, and move your fingers in front of a webcam to spawn 3D geometric shapes, rotate and scale them, cycle through colours, and destroy them.

<!-- Add a demo GIF or screenshot here -->

**Course:** Music and Multimedia Streaming over the Internet — Politecnico di Torino (A.Y. 2025/2026)
**Author:** Glorian Bici (s325248)
**Instructors:** Cristina Rottondi, Leonardo Severi, Massimiliano Zanoni
**Stack:** Python · MediaPipe · Wekinator · Processing · OBS · mediamtx

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Gesture Classes](#gesture-classes)
- [Repository Structure](#repository-structure)
- [Setup](#setup)
- [Running the Project](#running-the-project)
- [OBS Configuration](#obs-configuration)
- [Viewing the Stream](#viewing-the-stream)
- [mediamtx Configuration](#mediamtx-configuration)
- [Design Notes](#design-notes)

## Overview

The idea started from a simple question: what if the machine could learn to read the geometry of a hand rather than being told a fixed set of rules? Instead of writing "if fingers are closed, do X," a classifier is trained on examples of each gesture in Wekinator, which works out the boundaries between them on its own.

Three independent processes talk to each other exclusively through **OSC** messages:

1. A **Python sensing layer** (MediaPipe) extracts 120 hand-landmark features per frame and streams them to Wekinator.
2. **Wekinator** classifies the current gesture and sends a single integer to Processing.
3. **Processing** renders the resulting 3D shapes.

Two additional continuous streams — rotation delta and zoom scale — bypass Wekinator and go straight to Processing for smooth, real-time manipulation. The final output is broadcast as a live HLS stream via OBS and a self-hosted mediamtx server, viewable in any browser on the local network.

## Architecture

Each layer below is a separate process; OSC is the only channel through which they exchange data.

| Component | Tool | OSC Address | Port | Direction |
|---|---|---|---|---|
| Sensing | Python / MediaPipe | `/wek/inputs` (120 floats) | 6448 | → Wekinator |
| Sensing | Python / MediaPipe | `/shape/rotate` (2 floats) | 12000 | → Processing |
| Sensing | Python / MediaPipe | `/shape/zoom` (1 float) | 12000 | → Processing |
| ML Mediation | Wekinator | `/gesture/event` (1 int) | 12000 | → Processing |
| Rendering | Processing | — (consumer) | 12000 | RECEIVE |
| Streaming | OBS + mediamtx | RTMP / HLS | 1935 / 8888 | → Browser |

### Sensing — `sensing.py`

MediaPipe Hands detects up to two hands per frame. For each hand, 20 landmarks are expressed as a displacement from the wrist (landmark 0) — 60 values per hand (dx, dy, dz), giving a 120-dimensional vector with two hands. Single-hand frames are zero-padded so the input size stays fixed for Wekinator.

Two signals go straight to Processing without passing through Wekinator:
- **`/shape/rotate`** — delta position of the index fingertip, used for inertial rotation
- **`/shape/zoom`** — wrist-to-middle-knuckle distance, used as a proximity scale

When a hand moves too fast (velocity above 0.045 normalised units), both streams are suppressed to avoid injecting noise into the renderer.

### ML Mediation — Wekinator

A KNN classifier takes the 120-dimensional input and outputs a single integer identifying the current gesture. Eleven classes were trained, each recorded with roughly 30 example frames while holding the gesture steady in front of the camera.

### Rendering — `HandGeometry.pde`

The Processing sketch listens on port 12000 for all three OSC message types at once. The classified gesture integer triggers discrete events (shape spawning, erase, colour toggle), while the rotation delta and zoom scalar drive continuous, frame-by-frame manipulation. Shapes live in a 3D `P3D` scene and support spawn animations, inertial rotation with friction decay, HSB colour cycling, and a dissolve-erase effect.

A 500 ms debounce gate filters out momentary classification noise — a gesture has to be held consistently before it fires. The continuous rotation and zoom streams run through a leaky-bucket score filter so brief frame drops don't stutter the motion.

### Streaming — OBS + mediamtx

OBS captures the Processing window and pushes it to a locally running mediamtx server over RTMP. mediamtx re-serves the feed as Low-Latency HLS on port 8888 — viewable by any browser on the local network, no plugin or external service needed.

## Gesture Classes

| # | Gesture | Effect |
|---|---|---|
| 1 | Idle / no hand visible | No action |
| 2 | Closed fist | Freeze rotation |
| 3 | Index finger pointing up | Enable inertial rotation |
| 4 | Rock sign (index + pinky extended) | Start HSB colour cycling |
| 5 | Love sign (index + pinky + thumb extended) | Stop colour cycling |
| 6 | Open palm swipe | Dissolve and erase shape |
| 7 | Sphere (both hands cupped facing each other) | Spawn sphere |
| 8 | Cube (thumbs connected, fingers outline three faces) | Spawn cube |
| 9 | Triangle (index fingers and thumbs form a triangle) | Spawn pyramid |
| 10 | Goggles (hands form circles in front of eyes) | Spawn torus |
| 11 | Two-hand close proximity | Activate zoom mode |

## Repository Structure

```
.
├── sensing.py                  # Python sensing script
├── requirements.txt            # Python dependency list
├── HandGeometry.pde            # Processing rendering sketch
├── WekinatorProject2.wekproj   # Trained Wekinator classifier
├── mediamtx (+ mediamtx.yml)   # Self-hosted HLS media server
└── player.html                 # Browser page for viewing the live stream
```

## Setup

**Python 3.9–3.11 is required** — mediapipe 0.10.x does not run on Python 3.12+.

```bash
pip install -r requirements.txt
```

`requirements.txt`:
```
mediapipe==0.10.14
opencv-python==4.10.0.84
python-osc==1.8.3
numpy==1.26.4
```

**Processing** needs the `oscP5` library: *Sketch → Import Library → Add Library*, then search for `oscP5`.

## Running the Project

Start components in this order so every OSC listener is ready before data arrives:

| Step | Component | Action |
|---|---|---|
| 1 | mediamtx | `cd` into the mediamtx folder, run `./mediamtx` |
| 2 | Processing | Open `HandGeometry.pde` and click Run |
| 3 | Wekinator | Open `WekinatorProject2.wekproj` and click Run |
| 4 | Python | `python3 sensing.py` |
| 5 | OBS | Select the Processing window as source, click Start Streaming |
| 6 | Browser | Open `http://localhost:8888/live/stream/index.m3u8` |

## OBS Configuration

Covers both macOS (used to build this project) and Windows, since the two differ slightly in encoder options and permissions.

### Stream settings

`OBS → Settings → Stream` → Service: **Custom...**

- Server: `rtmp://127.0.0.1/live`
- Stream key: `stream`

Use `127.0.0.1` rather than `localhost` — it avoids an IPv6 resolution issue that can prevent OBS from connecting on some systems.

### Output settings

Switch Output Mode to **Advanced** (the keyframe interval option is hidden in Simple mode).

- **Keyframe Interval: 1 s** — the most important setting for Low-Latency HLS. mediamtx needs a new IDR frame every second to cut segments cleanly; without it, segments drift and the browser either buffers indefinitely or plays with much higher latency.
- **Bitrate:** 2500 Kbps

### Encoder

- **macOS:** Apple VT H264 Hardware Encoder — offloads encoding to the media engine, keeping CPU usage low while `sensing.py` and Processing also run locally. Software x264 caused segments to stall intermittently, likely from CPU contention.
- **Windows:** NVENC H264 on NVIDIA GPUs, AMD HW H264 on AMD cards, or x264 if neither is present — Windows tends to have less CPU contention than macOS at the same load, so software encoding is less likely to cause issues.

### Window capture and canvas size

Add the Processing window as a **Window Capture** source. If the preview shows a zoomed-in crop rather than the full sketch, right-click the source → *Transform → Fit to Screen*. Set the OBS canvas resolution to **1280×720** under `Settings → Video` to match the sketch dimensions.

### macOS screen recording permission

OBS needs explicit screen recording permission or the capture shows a black rectangle: `System Settings → Privacy & Security → Screen & System Audio Recording`, enable OBS, then **fully restart OBS** — toggling the permission while OBS is open has no effect.

## Viewing the Stream

Once OBS is streaming and the mediamtx terminal shows the stream as available and online, the feed is live.

### Same machine

```
http://localhost:8888/live/stream/index.m3u8
```

Works regardless of network. Safari plays it natively; Chrome and Firefox need the provided `player.html`, which uses hls.js.

### Another device on the same Wi-Fi

Find the host machine's local IP:

```bash
ipconfig getifaddr en0   # macOS / Linux
ipconfig                 # Windows — look for IPv4 Address
```

Then open on the other device:

```
http://192.168.x.x:8888/live/stream/index.m3u8
```

If the connection is refused, port 8888 is likely blocked by the firewall — allow `mediamtx` through it (macOS: *Network → Firewall → Options*; Windows: Windows Defender Firewall), or disable the firewall temporarily for a quick demo.

### iPhone via personal hotspot

Connecting the host Mac to the iPhone's personal hotspot (rather than router Wi-Fi) worked well for demos — the Mac's hotspot-client IP is usually `172.20.10.2` (confirm with `ipconfig getifaddr en0`). Opening `http://172.20.10.2:8888/live/stream/index.m3u8` in Safari on the iPhone then works with no extra configuration.

Latency over hotspot dropped from the ~6 s default to ~3–4 s by:
- switching `hlsVariant` to `lowLatency`
- setting `hlsSegmentDuration` to `1s` and `hlsPartDuration` to `200ms`
- setting a 1 s OBS keyframe interval with the Apple hardware encoder

On the same machine, latency with the same settings is ~1–2 s. Getting below 3 s on iOS Safari would need HTTPS on mediamtx, since Low-Latency HLS relies on HTTP/2 push for partial segments and iOS Safari only allows that over a secure connection — out of scope for a local demo.

## mediamtx Configuration

Relevant section of `mediamtx.yml`:

```yaml
hlsAddress: :8888
hlsVariant: lowLatency
hlsSegmentDuration: 1s
hlsPartDuration: 200ms
hlsAlwaysRemux: true
hlsAllowOrigins: ['*']
```

`hlsAlwaysRemux: true` keeps the HLS muxer alive even when no viewer is connected, so the stream is ready instantly when someone opens the browser page, rather than waiting for mediamtx to spin up a new muxer on the first request.

## Design Notes

No rule was written for what a rock sign or a sphere shape looks like — Wekinator learned the boundaries from examples instead. The model has no concept of "hands" or "geometry," only distances in a 120-dimensional space, and that turned out to be enough.

The OSC-based separation between layers paid off in debugging: the rendering sketch can be swapped out entirely without touching `sensing.py`, and the Wekinator model can be retrained from scratch without the renderer knowing anything changed. The same pipeline could become something different with an afternoon of retraining — a different set of gestures, outputs mapped to sound instead of shapes — without the architecture needing an opinion about what it's for.

---

*Politecnico di Torino — Music and Multimedia Streaming over the Internet — A.Y. 2025/2026*
