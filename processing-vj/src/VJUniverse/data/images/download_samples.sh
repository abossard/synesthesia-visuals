#!/bin/bash
# Download sample images for VJUniverse ImageTile testing
# Uses Lorem Picsum (free, no API key needed)

OUTPUT_DIR="$(dirname "$0")"
cd "$OUTPUT_DIR"

echo "Downloading sample images to: $OUTPUT_DIR"

# Abstract/VJ-friendly images from Lorem Picsum
# Using specific image IDs for consistent, visually cohesive results

# Neon/dark abstract images (good for VJ)
curl -sL "https://picsum.photos/id/1025/1920/1080" -o "01_wolf.jpg"
curl -sL "https://picsum.photos/id/1036/1920/1080" -o "02_water.jpg"
curl -sL "https://picsum.photos/id/1043/1920/1080" -o "03_road.jpg"
curl -sL "https://picsum.photos/id/1051/1920/1080" -o "04_lake.jpg"
curl -sL "https://picsum.photos/id/1057/1920/1080" -o "05_tunnel.jpg"
curl -sL "https://picsum.photos/id/1067/1920/1080" -o "06_night_city.jpg"
curl -sL "https://picsum.photos/id/1073/1920/1080" -o "07_fire.jpg"
curl -sL "https://picsum.photos/id/110/1920/1080" -o "08_clock.jpg"

echo ""
echo "Downloaded $(ls -1 *.jpg 2>/dev/null | wc -l | tr -d ' ') images"
echo "Press 'i' in VJUniverse to load them!"
