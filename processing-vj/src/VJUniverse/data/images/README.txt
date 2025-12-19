ImageTile Example Images
========================

Drop images here to use with the ImageTile.

Supported formats: .jpg .jpeg .png .gif .tif .tiff .bmp

Usage:
- Press 'i' in VJUniverse to load this folder
- Images cycle on beat (configurable via /image/beat OSC)
- Crossfade transitions between images

OSC Control:
- /image/folder /path/to/folder  - Load a different folder
- /image/beat 4                  - Change every 4 beats (1=every beat, 0=manual)
- /image/fade 500                - Crossfade duration in ms
- /image/fit contain             - "contain" (show all) or "cover" (fill, crop)
