#!/bin/bash
# =============================================================================
# process.sh — HLS Adaptive Bitrate Streaming Pipeline
#
# Transcodes the source video into three HLS renditions (1080p, 720p, 480p)
# and generates a master playlist. Idempotent: skips processing if output
# already exists.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (can be overridden via environment variables)
# ---------------------------------------------------------------------------
SOURCE_VIDEO="${SOURCE_VIDEO:-/app/video/source.mp4}"
OUTPUT_DIR="${OUTPUT_DIR:-/app/media/output}"
SEGMENT_DURATION="${SEGMENT_DURATION:-6}"      # seconds per .ts segment
SEGMENT_FILENAME="seg%03d.ts"                  # e.g. seg000.ts, seg001.ts

# ---------------------------------------------------------------------------
# Idempotency check — skip if master playlist already exists
# ---------------------------------------------------------------------------
MASTER_PLAYLIST="${OUTPUT_DIR}/master.m3u8"

if [ -f "${MASTER_PLAYLIST}" ]; then
    echo "[INFO] Output already exists at ${MASTER_PLAYLIST}. Skipping processing."
    echo "[INFO] Delete '${OUTPUT_DIR}' to force re-encoding."
    exit 0
fi

# ---------------------------------------------------------------------------
# Validate source file
# ---------------------------------------------------------------------------
if [ ! -f "${SOURCE_VIDEO}" ]; then
    echo "[ERROR] Source video not found: ${SOURCE_VIDEO}"
    echo "[ERROR] Please place your source video at: ${SOURCE_VIDEO}"
    exit 1
fi

echo "[INFO] Starting HLS transcoding pipeline..."
echo "[INFO] Source : ${SOURCE_VIDEO}"
echo "[INFO] Output : ${OUTPUT_DIR}"
echo "[INFO] Segment: ${SEGMENT_DURATION}s"

# ---------------------------------------------------------------------------
# Create output directories for each rendition
# ---------------------------------------------------------------------------
mkdir -p "${OUTPUT_DIR}/1080"
mkdir -p "${OUTPUT_DIR}/720"
mkdir -p "${OUTPUT_DIR}/480"

# ---------------------------------------------------------------------------
# Step 1: Transcode all three renditions with a single FFmpeg pass
#
# Bitrate ladder:
#   1080p — 5000k video + 192k audio  (≈ 5.2 Mbps)
#    720p — 2500k video + 128k audio  (≈ 2.6 Mbps)
#    480p —  800k video +  96k audio  (≈  0.9 Mbps)
#
# Each rendition is output to its own directory with:
#   - HLS segmenter (hls muxer)
#   - Fixed segment duration
#   - Segment filename pattern
# ---------------------------------------------------------------------------

echo "[INFO] Running FFmpeg transcode (this may take a while)..."

ffmpeg -y \
    -i "${SOURCE_VIDEO}" \
    \
    -filter_complex \
        "[0:v]split=3[v1080][v720][v480]; \
         [v1080]scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2[out1080]; \
         [v720]scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2[out720]; \
         [v480]scale=854:480:force_original_aspect_ratio=decrease,pad=854:480:(ow-iw)/2:(oh-ih)/2[out480]" \
    \
    -map "[out1080]" -map 0:a? \
        -c:v:0 libx264 -preset fast -crf 22 \
        -b:v:0 5000k -maxrate:v:0 5350k -bufsize:v:0 7500k \
        -c:a:0 aac -b:a:0 192k -ar 48000 \
        -f hls \
        -hls_time "${SEGMENT_DURATION}" \
        -hls_list_size 0 \
        -hls_segment_type mpegts \
        -hls_segment_filename "${OUTPUT_DIR}/1080/${SEGMENT_FILENAME}" \
        -hls_flags independent_segments \
        "${OUTPUT_DIR}/1080/stream.m3u8" \
    \
    -map "[out720]" -map 0:a? \
        -c:v:1 libx264 -preset fast -crf 23 \
        -b:v:1 2500k -maxrate:v:1 2675k -bufsize:v:1 3750k \
        -c:a:1 aac -b:a:1 128k -ar 48000 \
        -f hls \
        -hls_time "${SEGMENT_DURATION}" \
        -hls_list_size 0 \
        -hls_segment_type mpegts \
        -hls_segment_filename "${OUTPUT_DIR}/720/${SEGMENT_FILENAME}" \
        -hls_flags independent_segments \
        "${OUTPUT_DIR}/720/stream.m3u8" \
    \
    -map "[out480]" -map 0:a? \
        -c:v:2 libx264 -preset fast -crf 24 \
        -b:v:2 800k -maxrate:v:2 856k -bufsize:v:2 1200k \
        -c:a:2 aac -b:a:2 96k -ar 48000 \
        -f hls \
        -hls_time "${SEGMENT_DURATION}" \
        -hls_list_size 0 \
        -hls_segment_type mpegts \
        -hls_segment_filename "${OUTPUT_DIR}/480/${SEGMENT_FILENAME}" \
        -hls_flags independent_segments \
        "${OUTPUT_DIR}/480/stream.m3u8"

echo "[INFO] FFmpeg transcoding complete."

# ---------------------------------------------------------------------------
# Step 2: Generate the master playlist (master.m3u8)
#
# The master playlist tells the player about all available quality levels.
# BANDWIDTH values below are in bits-per-second (video + audio combined).
# ---------------------------------------------------------------------------

echo "[INFO] Generating master playlist: ${MASTER_PLAYLIST}"

cat > "${MASTER_PLAYLIST}" << 'EOF'
#EXTM3U
#EXT-X-VERSION:3

#EXT-X-STREAM-INF:BANDWIDTH=5192000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2",NAME="1080p"
1080/stream.m3u8

#EXT-X-STREAM-INF:BANDWIDTH=2628000,RESOLUTION=1280x720,CODECS="avc1.64001f,mp4a.40.2",NAME="720p"
720/stream.m3u8

#EXT-X-STREAM-INF:BANDWIDTH=896000,RESOLUTION=854x480,CODECS="avc1.64001e,mp4a.40.2",NAME="480p"
480/stream.m3u8
EOF

echo "[INFO] Master playlist written to: ${MASTER_PLAYLIST}"
echo ""
echo "============================================================"
echo "  HLS pipeline complete!"
echo "  Master playlist: ${OUTPUT_DIR}/master.m3u8"
echo "  Renditions     : 1080p, 720p, 480p"
echo "  Segment length : ${SEGMENT_DURATION}s"
echo "============================================================"
