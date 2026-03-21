#!/usr/bin/env node

/**
 * ISF Shader Downloader + Categorizer + Catalog Generator
 *
 * Downloads all ISF shaders from editor.isf.video, categorizes them
 * using the GitHub Copilot SDK, takes screenshots with Playwright,
 * and generates a markdown catalog.
 *
 * Usage:
 *   node download.mjs                     # Run all phases
 *   node download.mjs --phase download    # Run specific phase
 *   node download.mjs --username someone  # Different user
 */

import { readFileSync, writeFileSync, existsSync, mkdirSync, readdirSync, renameSync, cpSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const __dirname = dirname(fileURLToPath(import.meta.url));
const STATE_FILE = join(__dirname, ".state.json");
const API_BASE = "https://editor.isf.video/api";
const EDITOR_BASE = "https://editor.isf.video/shaders";

// ---------------------------------------------------------------------------
// CLI args
// ---------------------------------------------------------------------------
const { values: args } = parseArgs({
  options: {
    username: { type: "string", default: "rhythmic-visions" },
    phase: { type: "string", default: "all" },
    help: { type: "boolean", default: false },
  },
});

if (args.help) {
  console.log(`
ISF Shader Downloader

Usage: node download.mjs [options]

Options:
  --username <name>   ISF editor username (default: rhythmic-visions)
  --phase <phase>     Run specific phase: download, categorize, organize, screenshots, catalog, all
  --help              Show this help
`);
  process.exit(0);
}

// ---------------------------------------------------------------------------
// State management (resumability)
// ---------------------------------------------------------------------------
function loadState() {
  if (existsSync(STATE_FILE)) {
    return JSON.parse(readFileSync(STATE_FILE, "utf8"));
  }
  return { shaders: [], categorized: false, organized: false, screenshots: {}, catalogGenerated: false };
}

function saveState(state) {
  writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
}

// ---------------------------------------------------------------------------
// Phase 1: Download shaders from API
// ---------------------------------------------------------------------------
async function phaseDownload(state) {
  console.log("\n━━━ Phase 1: Download ━━━");

  const url = `${API_BASE}/${args.username}/profile`;
  console.log(`Fetching ${url} ...`);

  const res = await fetch(url);
  if (!res.ok) throw new Error(`API error: ${res.status} ${res.statusText}`);
  const profile = await res.json();
  const shaders = profile.shaders || [];
  console.log(`Found ${shaders.length} shaders`);

  const downloadDir = join(__dirname, "_download");
  mkdirSync(downloadDir, { recursive: true });

  let written = 0;
  for (const shader of shaders) {
    const title = shader.title || shader._id;
    const dir = join(downloadDir, title);
    mkdirSync(dir, { recursive: true });

    // Write fragment shader
    if (shader.rawFragmentSource) {
      writeFileSync(join(dir, `${title}.fs`), shader.rawFragmentSource);
    }

    // Write vertex shader
    if (shader.rawVertexSource) {
      writeFileSync(join(dir, `${title}.vs`), shader.rawVertexSource);
    }

    written++;
    if (written % 50 === 0) console.log(`  ... ${written}/${shaders.length}`);
  }

  // Save shader metadata into state
  state.shaders = shaders.map((s) => ({
    id: s._id || s.id,
    title: s.title,
    shaderType: s.shaderType || "unknown",
    description: s.description || "",
    categories: s.publicCategories || [],
    username: s.username,
    forkedFrom: s.forkedFrom || null,
    createdAt: s.createdAt,
    updatedAt: s.updatedAt,
    // AI-generated fields (filled in Phase 2)
    aiCategory: null,
    aiDescription: null,
    aiAudioReactivity: null,
  }));

  saveState(state);
  console.log(`✓ Downloaded ${written} shaders to _download/`);
  return state;
}

// ---------------------------------------------------------------------------
// Phase 2: AI Categorization with Copilot SDK
// ---------------------------------------------------------------------------
async function phaseCategorize(state) {
  console.log("\n━━━ Phase 2: AI Categorization ━━━");

  if (state.categorized) {
    console.log("Already categorized (use --phase categorize to force re-run)");
    if (args.phase === "categorize") state.categorized = false;
    else return state;
  }

  const { CopilotClient, approveAll } = await import("@github/copilot-sdk");

  const client = new CopilotClient();
  await client.start();

  try {
    const downloadDir = join(__dirname, "_download");
    const BATCH_SIZE = 8;
    const shaderBatches = [];

    // Group shaders into batches
    for (let i = 0; i < state.shaders.length; i += BATCH_SIZE) {
      shaderBatches.push(state.shaders.slice(i, i + BATCH_SIZE));
    }

    console.log(`Processing ${state.shaders.length} shaders in ${shaderBatches.length} batches...`);

    // Helper: send one batch in a fresh session and return the response text
    async function classifyBatch(client, batch, batchIdx) {
      const shaderSummaries = batch.map((s, i) => {
        const fsPath = join(downloadDir, s.title, `${s.title}.fs`);
        let source = "";
        if (existsSync(fsPath)) {
          source = readFileSync(fsPath, "utf8");
          if (source.length > 3000) {
            source = source.slice(0, 3000) + "\n// ... (truncated)";
          }
        }
        return `--- Shader ${i}: "${s.title}" (ISF type: ${s.shaderType}) ---\n${source}`;
      });

      const prompt = `Classify these ${batch.length} ISF shaders. Return a JSON array with ${batch.length} objects (one per shader, in order).
Each object must have: "category" ("Layer" or "Effect"), "description" (1-2 sentences of what it looks like visually), "audioReactivity" (object mapping uniform names to audio bands: bass/mid/high/level/bassHits/highHits/beatPhase/bpm).
Return ONLY a valid JSON array, no markdown fences, no explanation.

${shaderSummaries.join("\n\n")}`;

      // Each batch gets a fresh session to avoid event listener accumulation
      const session = await client.createSession({
        model: "claude-sonnet-4",
        onPermissionRequest: approveAll,
        systemMessage: {
          mode: "replace",
          content: `You are a shader classification expert. You analyze ISF (Interactive Shader Format) GLSL shaders and return structured JSON.
For each shader you receive, return a JSON object with:
- "category": "Layer" (generates visuals from math/noise) or "Effect" (modifies/filters an input image)
- "description": 1-2 sentences describing what the shader looks like visually. Be specific and evocative.
- "audioReactivity": object mapping uniform names to suggested audio bands (bass/mid/high/level/bassHits/highHits/beatPhase/bpm)
Return ONLY a valid JSON array with no extra text.`,
        },
      });

      let responseText = "";
      const done = new Promise((resolve) => {
        session.on("assistant.message", (event) => {
          responseText += event.data.content;
        });
        session.on("session.idle", () => resolve());
      });

      await session.send({ prompt });
      await done;
      await session.disconnect();

      return responseText;
    }

    for (let batchIdx = 0; batchIdx < shaderBatches.length; batchIdx++) {
      const batch = shaderBatches[batchIdx];
      console.log(`  Batch ${batchIdx + 1}/${shaderBatches.length} (${batch.length} shaders)...`);

      try {
        const responseText = await classifyBatch(client, batch, batchIdx);

        // Strip markdown fences if present
        let cleaned = responseText.trim();
        if (cleaned.startsWith("```")) {
          cleaned = cleaned.replace(/^```(?:json)?\n?/, "").replace(/\n?```$/, "");
        }
        const results = JSON.parse(cleaned);

        if (Array.isArray(results)) {
          for (let i = 0; i < batch.length && i < results.length; i++) {
            const r = results[i];
            const shaderIdx = batchIdx * BATCH_SIZE + i;
            state.shaders[shaderIdx].aiCategory = r.category || (batch[i].shaderType === "filter" ? "Effect" : "Layer");
            state.shaders[shaderIdx].aiDescription = r.description || "";
            state.shaders[shaderIdx].aiAudioReactivity = r.audioReactivity || {};
          }
        }
      } catch (err) {
        console.warn(`  ⚠ Batch ${batchIdx + 1} failed (${err.message}), using fallback`);
        for (let i = 0; i < batch.length; i++) {
          const shaderIdx = batchIdx * BATCH_SIZE + i;
          const s = state.shaders[shaderIdx];
          const fsPath = join(downloadDir, s.title, `${s.title}.fs`);
          const src = existsSync(fsPath) ? readFileSync(fsPath, "utf8") : "";
          const hasInput = src.includes('"inputImage"') || src.includes("'inputImage'");
          s.aiCategory = hasInput ? "Effect" : "Layer";
          s.aiDescription = s.description || `${s.shaderType} shader`;
          s.aiAudioReactivity = {};
        }
      }

      // Save state after each batch for resumability
      saveState(state);

      // Small delay between batches
      if (batchIdx < shaderBatches.length - 1) {
        await new Promise((r) => setTimeout(r, 500));
      }
    }

    state.categorized = true;
    saveState(state);
    
    const layers = state.shaders.filter((s) => s.aiCategory === "Layer").length;
    const effects = state.shaders.filter((s) => s.aiCategory === "Effect").length;
    console.log(`✓ Categorized: ${layers} Layers, ${effects} Effects`);
  } finally {
    await client.stop();
  }

  return state;
}

// ---------------------------------------------------------------------------
// Phase 3: Organize into Layers/ and Effects/
// ---------------------------------------------------------------------------
async function phaseOrganize(state) {
  console.log("\n━━━ Phase 3: Organize ━━━");

  const downloadDir = join(__dirname, "_download");
  const layersDir = join(__dirname, "Layers");
  const effectsDir = join(__dirname, "Effects");
  mkdirSync(layersDir, { recursive: true });
  mkdirSync(effectsDir, { recursive: true });

  let moved = { Layer: 0, Effect: 0 };

  for (const shader of state.shaders) {
    const srcDir = join(downloadDir, shader.title);
    if (!existsSync(srcDir)) continue;

    const category = shader.aiCategory || "Layer";
    const destDir = join(__dirname, category === "Effect" ? "Effects" : "Layers", shader.title);

    if (existsSync(destDir)) {
      // Already organized
      moved[category]++;
      continue;
    }

    mkdirSync(dirname(destDir), { recursive: true });
    cpSync(srcDir, destDir, { recursive: true });
    moved[category]++;
  }

  state.organized = true;
  saveState(state);
  console.log(`✓ Organized: ${moved.Layer} → Layers/, ${moved.Effect} → Effects/`);
  return state;
}

// ---------------------------------------------------------------------------
// Phase 4: Screenshots with Playwright
// ---------------------------------------------------------------------------
async function phaseScreenshots(state) {
  console.log("\n━━━ Phase 4: Screenshots ━━━");

  const { chromium } = await import("playwright");

  const browser = await chromium.launch({ headless: true });
  const context = await browser.newContext({ viewport: { width: 800, height: 600 } });

  let captured = 0;
  let skipped = 0;
  let failed = 0;

  for (let i = 0; i < state.shaders.length; i++) {
    const shader = state.shaders[i];
    const category = shader.aiCategory === "Effect" ? "Effects" : "Layers";
    const shaderDir = join(__dirname, category, shader.title);
    const screenshotPath = join(shaderDir, "screenshot.jpg");

    if (state.screenshots[shader.id]) {
      skipped++;
      continue;
    }

    if (!existsSync(shaderDir)) {
      console.warn(`  ⚠ Directory not found: ${shaderDir}`);
      failed++;
      continue;
    }

    const url = `${EDITOR_BASE}/${shader.id}`;
    console.log(`  [${i + 1}/${state.shaders.length}] ${shader.title}...`);

    try {
      const page = await context.newPage();
      await page.goto(url, { waitUntil: "networkidle", timeout: 15000 });

      // Wait for the WebGL canvas to render
      await page.waitForTimeout(2500);

      // Try to find and screenshot the canvas element
      const canvas = await page.$("canvas");
      if (canvas) {
        await canvas.screenshot({ path: screenshotPath, type: "jpeg", quality: 85 });
      } else {
        // Fallback: screenshot the main content area
        await page.screenshot({ path: screenshotPath, type: "jpeg", quality: 85, clip: { x: 0, y: 0, width: 800, height: 600 } });
      }

      await page.close();
      state.screenshots[shader.id] = true;
      captured++;

      // Save state periodically
      if (captured % 10 === 0) {
        saveState(state);
        console.log(`    ... saved checkpoint (${captured} captured)`);
      }

      // Rate limiting
      await new Promise((r) => setTimeout(r, 500));
    } catch (err) {
      console.warn(`  ⚠ Failed: ${shader.title} — ${err.message}`);
      failed++;
    }
  }

  await browser.close();
  saveState(state);
  console.log(`✓ Screenshots: ${captured} captured, ${skipped} skipped, ${failed} failed`);
  return state;
}

// ---------------------------------------------------------------------------
// Phase 5: Generate Markdown Catalog
// ---------------------------------------------------------------------------
async function phaseCatalog(state) {
  console.log("\n━━━ Phase 5: Catalog ━━━");

  const layers = state.shaders.filter((s) => s.aiCategory !== "Effect");
  const effects = state.shaders.filter((s) => s.aiCategory === "Effect");

  let md = `# ISF Shader Collection — ${args.username}\n\n`;
  md += `> **${state.shaders.length} shaders** | ${layers.length} Layers | ${effects.length} Effects\n`;
  md += `>\n> Downloaded from [editor.isf.video/u/${args.username}](https://editor.isf.video/u/${args.username})\n\n`;

  md += `## Table of Contents\n\n`;
  md += `- [Layers (${layers.length})](#layers)\n`;
  md += `- [Effects (${effects.length})](#effects)\n\n`;

  // Helper to render a shader entry
  function renderShader(shader, categoryDir) {
    const screenshotRel = `${categoryDir}/${shader.title}/screenshot.jpg`;
    const screenshotExists = existsSync(join(__dirname, categoryDir, shader.title, "screenshot.jpg"));

    let entry = `### ${shader.title}\n\n`;

    if (screenshotExists) {
      entry += `![${shader.title}](${screenshotRel})\n\n`;
    }

    if (shader.aiDescription) {
      entry += `**Description:** ${shader.aiDescription}\n\n`;
    }

    // Parse ISF inputs from the .fs file
    const fsPath = join(__dirname, categoryDir, shader.title, `${shader.title}.fs`);
    if (existsSync(fsPath)) {
      const src = readFileSync(fsPath, "utf8");
      const inputs = parseISFInputs(src);
      if (inputs.length > 0) {
        const inputStr = inputs
          .map((inp) => {
            let desc = `\`${inp.NAME}\` (${inp.TYPE})`;
            if (inp.MIN !== undefined && inp.MAX !== undefined) {
              desc += ` [${inp.MIN}–${inp.MAX}]`;
            }
            if (inp.DEFAULT !== undefined) {
              const def = Array.isArray(inp.DEFAULT) ? `[${inp.DEFAULT.join(", ")}]` : inp.DEFAULT;
              desc += ` default: ${def}`;
            }
            return desc;
          })
          .join(", ");
        entry += `**Inputs:** ${inputStr}\n\n`;
      }
    }

    // Audio reactivity suggestions
    if (shader.aiAudioReactivity && Object.keys(shader.aiAudioReactivity).length > 0) {
      const mappings = Object.entries(shader.aiAudioReactivity)
        .map(([uniform, band]) => `\`${uniform}\` → ${band}`)
        .join(", ");
      entry += `**🎵 Audio Reactivity:** ${mappings}\n\n`;
    }

    // Metadata line
    const meta = [];
    if (shader.categories?.length) meta.push(`Categories: ${shader.categories.join(", ")}`);
    if (shader.username && shader.username !== args.username) meta.push(`by ${shader.username}`);
    if (shader.forkedFrom) meta.push(`forked`);
    if (meta.length) entry += `*${meta.join(" | ")}*\n\n`;

    entry += `---\n\n`;
    return entry;
  }

  // Layers section
  md += `## Layers\n\n`;
  md += `*Generators — produce visuals from math, noise, and algorithms*\n\n`;
  for (const shader of layers.sort((a, b) => a.title.localeCompare(b.title))) {
    md += renderShader(shader, "Layers");
  }

  // Effects section
  md += `## Effects\n\n`;
  md += `*Filters — modify and transform input images*\n\n`;
  for (const shader of effects.sort((a, b) => a.title.localeCompare(b.title))) {
    md += renderShader(shader, "Effects");
  }

  const readmePath = join(__dirname, "README.md");
  writeFileSync(readmePath, md);
  state.catalogGenerated = true;
  saveState(state);
  console.log(`✓ Catalog written to README.md (${(md.length / 1024).toFixed(1)} KB)`);
  return state;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
function parseISFInputs(source) {
  const match = source.match(/\/\*\s*(\{[\s\S]*?\})\s*\*\//);
  if (!match) return [];
  try {
    const json = JSON.parse(match[1]);
    return (json.INPUTS || []).filter((i) => i.NAME !== "inputImage");
  } catch {
    return [];
  }
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
async function main() {
  console.log(`\n🎨 ISF Shader Downloader — ${args.username}`);
  console.log(`   Phase: ${args.phase}\n`);

  let state = loadState();

  const phases = {
    download: phaseDownload,
    categorize: phaseCategorize,
    organize: phaseOrganize,
    screenshots: phaseScreenshots,
    catalog: phaseCatalog,
  };

  if (args.phase === "all") {
    for (const [name, fn] of Object.entries(phases)) {
      state = await fn(state);
    }
  } else if (phases[args.phase]) {
    state = await phases[args.phase](state);
  } else {
    console.error(`Unknown phase: ${args.phase}`);
    console.error(`Valid phases: ${Object.keys(phases).join(", ")}, all`);
    process.exit(1);
  }

  console.log("\n✅ Done!\n");
}

main().catch((err) => {
  console.error("Fatal error:", err);
  process.exit(1);
});
