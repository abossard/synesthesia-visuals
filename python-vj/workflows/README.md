# ComfyUI Workflows

Place your workflow JSON files here. Export from ComfyUI using:

1. Enable "Dev Mode Options" in ComfyUI Settings
2. Click "Save (API Format)" to export the workflow

The JSON file should contain the node graph in API format.

## Usage in VJ Console

The karaoke engine will:
- Auto-detect workflows in this folder
- Let you select which workflow to use
- Substitute the prompt text into CLIPTextEncode nodes

## Naming Convention

- `default_sdxl.json` - Default SDXL workflow
- `flux_artistic.json` - Flux model for artistic styles
- `fast_lcm.json` - Fast LCM-based generation

The engine will look for nodes with specific class_types:
- `CLIPTextEncode` - For prompt injection
- `CheckpointLoaderSimple` - For model selection
- `SaveImage` - For output retrieval
