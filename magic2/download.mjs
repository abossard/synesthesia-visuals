#!/usr/bin/env node

/**
 * ISF Shader Downloader
 *
 * Downloads ISF shaders from editor.isf.video, categorizes with Copilot SDK,
 * downloads Cloudinary thumbnails, and generates a markdown catalog.
 *
 * Output:
 *   magic2/Layers/*.fs        — generator shaders
 *   magic2/Effects/*.fs       — filter/effect shaders
 *   magic2/screenshots/*.jpg  — Cloudinary thumbnails
 *   magic2/README.md          — catalog
 *
 * Usage:
 *   node download.mjs                        # Run all
 *   node download.mjs --phase download       # Just fetch API + write .fs
 *   node download.mjs --phase categorize     # Re-run AI categorization
 *   node download.mjs --phase screenshots    # Re-download thumbnails
 *   node download.mjs --phase catalog        # Re-generate README
 */

import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { parseArgs } from "node:util";

const __dirname = dirname(fileURLToPath(import.meta.url));
const STATE_FILE = join(__dirname, ".state.json");
const API_BASE = "https://editor.isf.video/api";
const CLOUDINARY = "https://res.cloudinary.com/hrlz5rsqo/image/upload";
const LAYERS_DIR = join(__dirname, "Layers");
const EFFECTS_DIR = join(__dirname, "Effects");
const SCREENSHOTS_DIR = join(__dirname, "screenshots");

const { values: args } = parseArgs({
  options: {
    username: { type: "string", default: "rhythmic-visions" },
    phase: { type: "string", default: "all" },
    help: { type: "boolean", default: false },
  },
});

if (args.help) {
  console.log("Usage: node download.mjs [--username NAME] [--phase download|categorize|screenshots|catalog|all]");
  process.exit(0);
}

// -- State -------------------------------------------------------------------
function loadState() {
  if (existsSync(STATE_FILE)) return JSON.parse(readFileSync(STATE_FILE, "utf8"));
  return { shaders: [], categorized: false };
}
function saveState(s) { writeFileSync(STATE_FILE, JSON.stringify(s, null, 2)); }

// -- Phase 1: Download -------------------------------------------------------
async function phaseDownload(state) {
  console.log("\n━━━ Phase 1: Download ━━━");
  const res = await fetch(`${API_BASE}/${args.username}/profile`);
  if (!res.ok) throw new Error(`API ${res.status}`);
  const { shaders } = await res.json();
  console.log(`Fetched ${shaders.length} shaders`);

  // Deduplicate by title (keep last)
  const byTitle = new Map();
  for (const s of shaders) byTitle.set(s.title, s);
  const unique = [...byTitle.values()];
  console.log(`${unique.length} unique (${shaders.length - unique.length} duplicates)`);

  state.shaders = unique.map((s) => ({
    id: s._id || s.id,
    title: s.title,
    shaderType: s.shaderType || "unknown",
    description: s.description || "",
    categories: s.publicCategories || [],
    username: s.username,
    forkedFrom: s.forkedFrom || null,
    thumbnailId: s.thumbnailCloudinaryId || null,
    rawFragmentSource: s.rawFragmentSource || "",
    aiCategory: null,
    aiDescription: null,
    aiAudioReactivity: null,
  }));

  saveState(state);
  console.log(`✓ ${unique.length} shaders ready`);
  return state;
}

// -- Phase 2: AI Categorization -----------------------------------------------
async function phaseCategorize(state) {
  console.log("\n━━━ Phase 2: AI Categorization ━━━");
  if (state.categorized && args.phase !== "categorize") {
    console.log("Already done, skipping");
    return state;
  }

  const { CopilotClient, approveAll } = await import("@github/copilot-sdk");
  const client = new CopilotClient();
  await client.start();

  try {
    const BATCH = 8;
    const nBatches = Math.ceil(state.shaders.length / BATCH);
    console.log(`${state.shaders.length} shaders in ${nBatches} batches...`);

    for (let bi = 0; bi < nBatches; bi++) {
      const batch = state.shaders.slice(bi * BATCH, (bi + 1) * BATCH);
      console.log(`  Batch ${bi + 1}/${nBatches}...`);

      const summaries = batch.map((s, i) => {
        let src = s.rawFragmentSource;
        if (src.length > 3000) src = src.slice(0, 3000) + "\n// ...truncated";
        return `--- Shader ${i}: "${s.title}" (type: ${s.shaderType}) ---\n${src}`;
      });

      const prompt = `Classify these ${batch.length} ISF shaders. Return a JSON array of ${batch.length} objects (in order).
Each: {"category":"Layer"|"Effect","description":"1-2 evocative sentences","audioReactivity":{"uniformName":"bass|mid|high|level|bassHits|highHits|beatPhase|bpm"}}
ONLY valid JSON array, no markdown fences.

${summaries.join("\n\n")}`;

      try {
        const session = await client.createSession({
          model: "claude-sonnet-4",
          onPermissionRequest: approveAll,
          systemMessage: { mode: "replace", content: "You classify ISF GLSL shaders. Return only valid JSON arrays." },
        });
        let text = "";
        const done = new Promise((r) => {
          session.on("assistant.message", (e) => { text += e.data.content; });
          session.on("session.idle", () => r());
        });
        await session.send({ prompt });
        await done;
        await session.disconnect();

        let cleaned = text.trim();
        if (cleaned.startsWith("```")) cleaned = cleaned.replace(/^```(?:json)?\n?/, "").replace(/\n?```$/, "");
        const results = JSON.parse(cleaned);
        for (let i = 0; i < batch.length && i < results.length; i++) {
          const idx = bi * BATCH + i;
          state.shaders[idx].aiCategory = results[i].category === "Effect" ? "Effect" : "Layer";
          state.shaders[idx].aiDescription = results[i].description || "";
          state.shaders[idx].aiAudioReactivity = results[i].audioReactivity || {};
        }
      } catch (err) {
        console.warn(`  ⚠ Batch ${bi + 1} failed: ${err.message}, fallback`);
        for (let i = 0; i < batch.length; i++) {
          const idx = bi * BATCH + i;
          const s = state.shaders[idx];
          const hasInput = s.rawFragmentSource.includes('"inputImage"');
          s.aiCategory = hasInput ? "Effect" : "Layer";
          s.aiDescription = s.description || `${s.shaderType} shader`;
          s.aiAudioReactivity = {};
        }
      }
      saveState(state);
      if (bi < nBatches - 1) await new Promise((r) => setTimeout(r, 500));
    }

    state.categorized = true;
    saveState(state);

    // Write .fs files
    mkdirSync(LAYERS_DIR, { recursive: true });
    mkdirSync(EFFECTS_DIR, { recursive: true });
    for (const s of state.shaders) {
      if (!s.rawFragmentSource) continue;
      const dir = s.aiCategory === "Effect" ? EFFECTS_DIR : LAYERS_DIR;
      writeFileSync(join(dir, `${s.title}.fs`), s.rawFragmentSource);
    }

    const nL = state.shaders.filter((s) => s.aiCategory !== "Effect").length;
    const nE = state.shaders.filter((s) => s.aiCategory === "Effect").length;
    console.log(`✓ ${nL} Layers, ${nE} Effects — .fs files written`);
  } finally {
    await client.stop();
  }
  return state;
}

// -- Phase 3: Download Cloudinary thumbnails (parallel) -----------------------
async function phaseScreenshots(state) {
  console.log("\n━━━ Phase 3: Download Thumbnails ━━━");
  mkdirSync(SCREENSHOTS_DIR, { recursive: true });

  const toDownload = state.shaders.filter((s) => s.thumbnailId && !existsSync(join(SCREENSHOTS_DIR, `${s.title}.jpg`)));
  console.log(`${toDownload.length} thumbnails to download (${state.shaders.length - toDownload.length} already exist)`);

  const CONCURRENCY = 20;
  let done = 0, failed = 0;

  async function download(shader) {
    const url = `${CLOUDINARY}/${shader.thumbnailId}.jpg`;
    const path = join(SCREENSHOTS_DIR, `${shader.title}.jpg`);
    try {
      const res = await fetch(url);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const buf = Buffer.from(await res.arrayBuffer());
      writeFileSync(path, buf);
      done++;
    } catch {
      failed++;
    }
  }

  // Process in parallel batches
  for (let i = 0; i < toDownload.length; i += CONCURRENCY) {
    const batch = toDownload.slice(i, i + CONCURRENCY);
    await Promise.all(batch.map(download));
    if (done % 50 === 0 && done > 0) console.log(`  ... ${done} downloaded`);
  }

  console.log(`✓ ${done} thumbnails downloaded, ${failed} failed`);
  return state;
}

// -- Phase 4: Generate README.md catalog --------------------------------------
async function phaseCatalog(state) {
  console.log("\n━━━ Phase 4: Catalog ━━━");

  const layers = state.shaders.filter((s) => s.aiCategory !== "Effect");
  const effects = state.shaders.filter((s) => s.aiCategory === "Effect");

  let md = `# ISF Shader Collection — ${args.username}\n\n`;
  md += `> **${state.shaders.length} shaders** | ${layers.length} Layers | ${effects.length} Effects\n`;
  md += `> Downloaded from [editor.isf.video/u/${args.username}](https://editor.isf.video/u/${args.username})\n\n`;
  md += `## Table of Contents\n\n- [Layers (${layers.length})](#layers)\n- [Effects (${effects.length})](#effects)\n\n`;

  function entry(s) {
    const hasImg = existsSync(join(SCREENSHOTS_DIR, `${s.title}.jpg`));
    const imgPath = `screenshots/${encodeURIComponent(s.title)}.jpg`;
    let o = `### ${s.title}\n\n`;
    if (hasImg) o += `![${s.title}](${imgPath})\n\n`;
    if (s.aiDescription) o += `**Description:** ${s.aiDescription}\n\n`;

    const inputs = parseISFInputs(s.rawFragmentSource);
    if (inputs.length) {
      o += `**Inputs:** ${inputs.map((i) => {
        let d = `\`${i.NAME}\` (${i.TYPE})`;
        if (i.MIN !== undefined && i.MAX !== undefined) d += ` [${i.MIN}–${i.MAX}]`;
        return d;
      }).join(", ")}\n\n`;
    }

    if (s.aiAudioReactivity && Object.keys(s.aiAudioReactivity).length) {
      o += `**🎵 Audio:** ${Object.entries(s.aiAudioReactivity).map(([u, b]) => `\`${u}\`→${b}`).join(", ")}\n\n`;
    }

    return o + `---\n\n`;
  }

  md += `## Layers\n\n*Generators — produce visuals from math, noise, and algorithms*\n\n`;
  for (const s of layers.sort((a, b) => a.title.localeCompare(b.title))) md += entry(s);

  md += `## Effects\n\n*Filters — modify and transform input images*\n\n`;
  for (const s of effects.sort((a, b) => a.title.localeCompare(b.title))) md += entry(s);

  writeFileSync(join(__dirname, "README.md"), md);
  console.log(`✓ README.md (${(md.length / 1024).toFixed(1)} KB)`);
  return state;
}

// -- Helpers ------------------------------------------------------------------
function parseISFInputs(src) {
  const m = (src || "").match(/\/\*\s*(\{[\s\S]*?\})\s*\*\//);
  if (!m) return [];
  try { return (JSON.parse(m[1]).INPUTS || []).filter((i) => i.NAME !== "inputImage"); } catch { return []; }
}

// -- Main ---------------------------------------------------------------------
const phases = { download: phaseDownload, categorize: phaseCategorize, screenshots: phaseScreenshots, catalog: phaseCatalog };
let state = loadState();
console.log(`\n🎨 ISF Shader Downloader — ${args.username} (phase: ${args.phase})\n`);

if (args.phase === "all") {
  for (const fn of Object.values(phases)) state = await fn(state);
} else if (phases[args.phase]) {
  state = await phases[args.phase](state);
} else {
  console.error(`Unknown phase. Valid: ${Object.keys(phases).join(", ")}, all`);
  process.exit(1);
}
console.log("\n✅ Done!\n");
