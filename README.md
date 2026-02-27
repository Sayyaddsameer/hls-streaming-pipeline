# HLS Adaptive Bitrate Streaming Pipeline

A fully containerized video processing pipeline that transcodes a source MP4 file into **HLS (HTTP Live Streaming)** adaptive bitrate content using **FFmpeg**, and serves it via **Nginx** over HTTP with proper CORS headers and MIME types.

---

## Features

- **Three quality renditions**: 1080p (5 Mbps), 720p (2.5 Mbps), 480p (800 kbps)
- **6-second segments** — good balance of startup latency and overhead
- **Idempotent processing** — skips re-encoding if output already exists
- **Fully Dockerized** — one command to build and run everything
- **CORS-enabled** Nginx server for browser-based playback
- **Correct MIME types** for `.m3u8`, `.ts`, `.mpd`, `.m4s`
- **Structured HLS output**: master playlist + per-resolution variant playlists

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) (v20+)
- [Docker Compose](https://docs.docker.com/compose/install/) (v2+)
- ~10 GB free disk space for source video and generated segments
- (Optional) [VLC](https://www.videolan.org/vlc/) for local playback testing

---

## Project Structure

```
hls-streaming-pipeline/
├── process.sh              # FFmpeg transcoding script (generates HLS renditions)
├── docker-compose.yml      # Orchestrates processor + web server containers
├── Dockerfile.nginx        # Builds the custom Nginx image
├── nginx.conf              # Nginx config: CORS headers + HLS/DASH MIME types
├── .env.example            # Sample environment variables (copy to .env)
├── .gitignore
├── README.md
├── video/
│   ├── README.txt          # Instructions for downloading source.mp4
│   └── source.mp4          # ← Place your source video here (gitignored)
└── media/                  # ← Gitignored; created at runtime by Docker
    └── output/
        ├── master.m3u8     # Top-level HLS master playlist
        ├── 1080/
        │   ├── stream.m3u8 # 1080p variant playlist
        │   └── seg*.ts     # 6-second video segments
        ├── 720/
        │   ├── stream.m3u8 # 720p variant playlist
        │   └── seg*.ts
        └── 480/
            ├── stream.m3u8 # 480p variant playlist
            └── seg*.ts
```

---

## Quick Start

### Step 1: Clone the repository

```bash
git clone <repository-url>
cd hls-streaming-pipeline
```

### Step 2: Download the source video

Download the **Big Buck Bunny 1080p** test video and place it in the `video/` directory:

```bash
# Linux / macOS / WSL
curl -L https://download.blender.org/demo/movies/BBB/bbb_sunflower_1080p_30fps_normal.mp4 \
     -o video/source.mp4

# Windows PowerShell
Invoke-WebRequest -Uri "https://download.blender.org/demo/movies/BBB/bbb_sunflower_1080p_30fps_normal.mp4" `
                  -OutFile "video\source.mp4"
```

> **Note**: The file is ~356 MB. Ensure you have a stable internet connection.

You can also use any other MP4 file — just rename it to `source.mp4` and place it in the `video/` directory.

### Step 3: (Optional) Configure environment variables

```bash
cp .env.example .env
# Edit .env to customize segment duration, output path, or host port
```

### Step 4: Run the pipeline

```bash
docker-compose up --build
```

This will:
1. Pull the `jrottenberg/ffmpeg:4.4-alpine` image
2. Run `process.sh` to transcode `video/source.mp4` into HLS segments
3. Build and start the Nginx server to serve the output

> **Note**: Initial transcoding takes **10–30 minutes** depending on your CPU. Subsequent runs are instant (idempotent).

---

## Master Playlist URL

Once `docker-compose up` completes and the server is healthy, access the stream at:

```
http://localhost:8080/media/output/master.m3u8
```

Individual variant playlists are also accessible:

| Quality | URL |
|---------|-----|
| **Master** | `http://localhost:8080/media/output/master.m3u8` |
| **1080p** | `http://localhost:8080/media/output/1080/stream.m3u8` |
| **720p**  | `http://localhost:8080/media/output/720/stream.m3u8`  |
| **480p**  | `http://localhost:8080/media/output/480/stream.m3u8`  |

---

## Testing Playback

### Option 1: VLC Player (Desktop)

1. Open **VLC** → `Media` → `Open Network Stream...`
2. Enter: `http://localhost:8080/media/output/master.m3u8`
3. Click **Play**

### Option 2: HLS.js Web Player (Browser)

1. Go to [https://hls-js.netlify.app/demo/](https://hls-js.netlify.app/demo/)
2. Paste the master playlist URL: `http://localhost:8080/media/output/master.m3u8`
3. Click **Load**

### Option 3: curl (Verification)

```bash
# Check master playlist
curl -v http://localhost:8080/media/output/master.m3u8

# Check a variant playlist
curl -v http://localhost:8080/media/output/720/stream.m3u8

# Check a segment file (use -o NUL on Windows, -o /dev/null on Linux/macOS)
curl -v http://localhost:8080/media/output/480/seg000.ts -o NUL
```

---

## Output Directory Structure

After running, the `media/output/` directory will contain:

```
media/output/
├── master.m3u8          ← Master playlist (references all renditions)
├── 1080/
│   ├── stream.m3u8      ← 1080p variant playlist
│   ├── seg000.ts
│   ├── seg001.ts
│   └── ...
├── 720/
│   ├── stream.m3u8      ← 720p variant playlist
│   ├── seg000.ts
│   └── ...
└── 480/
    ├── stream.m3u8      ← 480p variant playlist
    ├── seg000.ts
    └── ...
```

---

## Bitrate Ladder

| Rendition | Resolution | Video Bitrate | Audio Bitrate | Total      |
|-----------|------------|---------------|---------------|------------|
| 1080p     | 1920×1080  | 5,000 kbps    | 192 kbps      | ~5.2 Mbps  |
| 720p      | 1280×720   | 2,500 kbps    | 128 kbps      | ~2.6 Mbps  |
| 480p      | 854×480    | 800 kbps      | 96 kbps       | ~0.9 Mbps  |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Docker Compose                                                  │
│                                                                  │
│  ┌────────────────────────┐      ┌───────────────────────────┐  │
│  │  processor (FFmpeg)    │      │  web_server (Nginx)       │  │
│  │                        │      │                           │  │
│  │  source.mp4 ──────────►│      │  master.m3u8              │  │
│  │       │                │      │  1080/stream.m3u8 + *.ts  │  │
│  │       ▼ FFmpeg         │      │  720/stream.m3u8 + *.ts   │  │
│  │  process.sh            │─────►│  480/stream.m3u8 + *.ts   │  │
│  │  (Transcodes to HLS)   │      │                           │  │
│  │                        │(vol) │  Port 8080 → HTTP         │  │
│  └────────────────────────┘      └───────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                                              │
                               ┌──────────────┘
                               ▼
                    http://localhost:8080/
                    media/output/master.m3u8
```

---

## Configuration

All configuration is done through environment variables. Copy `.env.example` to `.env` to customize:

| Variable | Default | Description |
|----------|---------|-------------|
| `SOURCE_VIDEO` | `/app/video/source.mp4` | Path to input video (inside container) |
| `OUTPUT_DIR` | `/app/media/output` | HLS output directory (inside container) |
| `SEGMENT_DURATION` | `6` | Duration of each `.ts` segment in seconds |
| `HOST_PORT` | `8080` | Host port for the Nginx web server |

---

## Stopping the Pipeline

```bash
# Stop containers (keeps generated files in media/)
docker-compose down
```

To force re-transcoding, delete the generated output and re-run:
```bash
# Linux / macOS / WSL
docker-compose down && rm -rf media/output/ && docker-compose up

# Windows PowerShell
docker-compose down; Remove-Item -Recurse -Force media\output; docker-compose up
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| `source.mp4 not found` | Download the file to `video/source.mp4` (see Step 2) |
| Transcoding seems stuck | It takes 10–30 min for a 1080p file; check `docker logs` for progress |
| CORS errors in browser | Ensure the nginx.conf is being used (check `docker-compose build --no-cache`) |
| Port 8080 in use | Set `HOST_PORT=8081` in `.env` and restart |
| `master.m3u8` returns 404 | Wait for transcoding to complete; check `docker-compose logs processor` |

---

## License

This project uses [Big Buck Bunny](https://peach.blender.org/) as its test video, licensed under the [Creative Commons Attribution 3.0 license](https://creativecommons.org/licenses/by/3.0/).
