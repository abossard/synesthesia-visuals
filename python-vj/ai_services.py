#!/usr/bin/env python3
"""
AI Services - LLM analysis, categorization, and image generation

Deep modules hiding AI complexity behind simple interfaces.
All services gracefully degrade if backends are unavailable.
"""

import os
import re
import json
import time
import uuid
import logging
import requests
from pathlib import Path
from typing import Optional, Dict, Any, List
from domain import sanitize_cache_filename, STOP_WORDS, SongCategories
from infrastructure import ServiceHealth, Config

logger = logging.getLogger('karaoke')


# =============================================================================
# LLM ANALYZER - Deep module for AI-powered lyrics analysis
# =============================================================================

class LLMAnalyzer:
    """
    AI-powered lyrics analysis using OpenAI or local LM Studio.
    
    Deep module interface:
        analyze_lyrics(lyrics, artist, title) -> Dict
        analyze_shader(shader_name, shader_source) -> Dict
        generate_image_prompt(artist, title, keywords, themes) -> str
    
    Hides: Multi-backend LLM (OpenAI/LM Studio), caching, fallback logic
    """
    
    LM_STUDIO_URL = "http://localhost:1234"
    
    def __init__(self, cache_dir: Optional[Path] = None):
        self._cache_dir = (cache_dir or Config.APP_DATA_DIR) / "llm_cache"
        self._cache_dir.mkdir(parents=True, exist_ok=True)
        self._openai_client = None
        self._lmstudio_model = None
        self._health = ServiceHealth("LLM")
        self._backend = "none"
        self._init_backend()
    
    def analyze_lyrics(self, lyrics: str, artist: str, title: str) -> Dict[str, Any]:
        """Analyze lyrics, extract refrain/keywords/themes. Returns dict with 'refrain_lines', 'keywords', 'themes'."""
        cache_file = self._cache_dir / f"{sanitize_cache_filename(artist, title)}.json"
        
        # Check cache
        if cache_file.exists():
            try:
                data = json.loads(cache_file.read_text())
                data['cached'] = True
                return data
            except Exception:
                pass
        
        # Try LLM
        self._try_reconnect()
        if self._health.available:
            result = self._analyze_with_llm(lyrics, artist, title)
            if result:
                cache_file.write_text(json.dumps(result, indent=2))
                result['cached'] = False
                return result
        
        # Fallback
        return self._basic_analysis(lyrics)
    
    def generate_image_prompt(self, artist: str, title: str, keywords: List[str], themes: List[str]) -> str:
        """Generate image prompt for AI image generation."""
        self._try_reconnect()
        
        if not self._health.available:
            return self._basic_image_prompt(artist, title, keywords, themes)
        
        prompt = f"""Create a visual prompt for '{title}' by {artist}. Keywords: {', '.join(keywords[:5])}. Themes: {', '.join(themes[:3])}. Style: cinematic, abstract, high-contrast VJ visuals."""
        
        try:
            if self._backend == "openai":
                response = self._openai_client.chat.completions.create(
                    model="gpt-3.5-turbo",
                    messages=[{"role": "user", "content": prompt}],
                    max_tokens=150
                )
                return response.choices[0].message.content.strip()
            elif self._backend == "lmstudio":
                resp = requests.post(f"{self.LM_STUDIO_URL}/v1/chat/completions",
                    json={
                        "model": self._lmstudio_model,
                        "messages": [{"role": "user", "content": prompt}],
                        "max_tokens": 150
                    },
                    timeout=30)
                if resp.status_code == 200:
                    return resp.json().get('choices', [{}])[0].get('message', {}).get('content', '').strip()
        except Exception as e:
            logger.debug(f"Image prompt generation error: {e}")
        
        return self._basic_image_prompt(artist, title, keywords, themes)
    
    def analyze_shader(self, shader_name: str, shader_source: str, timeout: int = 300) -> Dict[str, Any]:
        """
        Analyze GLSL shader source for VJ music visualization matching.
        
        Args:
            shader_name: Name of the shader
            shader_source: GLSL source code
            timeout: Request timeout in seconds (default 300s = 5 min for large shaders)
        
        Returns dict with:
            - mood: str (energetic|calm|dark|bright|psychedelic|...)
            - colors: List[str]
            - effects: List[str]
            - description: str
            - features: Dict[str, float] (energy_score, mood_valence, etc.)
            - error: str (only present if analysis failed)
        """
        self._try_reconnect()
        
        if not self._health.available:
            logger.debug("LLM not available for shader analysis")
            return {'error': 'LLM not available', 'shader_name': shader_name}
        
        prompt = self._build_shader_analysis_prompt(shader_name, shader_source)
        
        try:
            if self._backend == "openai":
                response = self._openai_client.chat.completions.create(
                    model="gpt-3.5-turbo",
                    messages=[{"role": "user", "content": prompt}],
                    max_tokens=800,
                    timeout=timeout
                )
                content = response.choices[0].message.content
            elif self._backend == "lmstudio":
                resp = requests.post(f"{self.LM_STUDIO_URL}/v1/chat/completions",
                    json={
                        "model": self._lmstudio_model,
                        "messages": [{"role": "user", "content": prompt}],
                        "max_tokens": 800
                    },
                    timeout=timeout)  # Long timeout for large shaders
                if resp.status_code == 200:
                    content = resp.json().get('choices', [{}])[0].get('message', {}).get('content', '')
                else:
                    error_msg = f"LLM returned status {resp.status_code}: {resp.text[:200]}"
                    logger.warning(f"Shader analysis failed: {error_msg}")
                    return {'error': error_msg, 'shader_name': shader_name}
            else:
                return {'error': 'No LLM backend configured', 'shader_name': shader_name}
            
            # Parse JSON from response
            if content:
                result = self._parse_shader_analysis(content)
                if result:
                    return result
                else:
                    return {'error': f'Failed to parse LLM response: {content[:200]}...', 'shader_name': shader_name}
                
        except requests.exceptions.Timeout as e:
            error_msg = f"Request timeout after {timeout}s"
            logger.warning(f"Shader analysis timeout for {shader_name}: {error_msg}")
            return {'error': error_msg, 'shader_name': shader_name}
        except Exception as e:
            error_msg = str(e)
            logger.warning(f"Shader analysis error for {shader_name}: {error_msg}")
            self._health.mark_unavailable(error_msg)
            return {'error': error_msg, 'shader_name': shader_name}
        
        return {'error': 'Unknown error', 'shader_name': shader_name}
    
    def _build_shader_analysis_prompt(self, shader_name: str, source: str) -> str:
        """Build prompt for shader analysis with GLSL pattern guidance and audio mapping."""
        # Smart truncation for large shaders - preserve header and key parts
        max_len = 8000
        if len(source) > max_len:
            # Try to preserve ISF header (JSON at top) and main function
            header_end = source.find('*/')
            main_start = source.find('void main')
            if main_start < 0:
                main_start = source.find('vec4 main')
            
            if header_end > 0 and main_start > 0:
                # Keep header + ... + main function area
                header = source[:header_end + 2]
                remaining = max_len - len(header) - 100
                main_section = source[main_start:main_start + remaining]
                truncated = f"{header}\n\n// ... ({len(source) - max_len} chars omitted) ...\n\n{main_section}"
            else:
                # Simple truncation with note
                truncated = source[:max_len] + f"\n// ... (truncated, {len(source) - max_len} chars omitted)"
        else:
            truncated = source
        
        # Extract ISF input names from header for audio mapping hints
        input_names = []
        try:
            if '/*' in source and '*/' in source:
                json_start = source.find('/*') + 2
                json_end = source.find('*/')
                isf_json = source[json_start:json_end].strip()
                import json as json_module
                isf_header = json_module.loads(isf_json)
                for inp in isf_header.get('INPUTS', []):
                    name = inp.get('NAME', '')
                    inp_type = inp.get('TYPE', '')
                    if name and inp_type in ('float', 'long', 'bool'):
                        input_names.append(f"{name} ({inp_type})")
        except:
            pass
        
        inputs_hint = ", ".join(input_names) if input_names else "None detected"
        
        return f"""Analyze this GLSL shader for VJ music visualization matching.

Shader name: {shader_name}
Detected ISF inputs: {inputs_hint}

Source code:
```glsl
{truncated}
```

SCORING GUIDE - Look for these GLSL patterns:

energy_score (0.0-1.0):
  HIGH (0.7-1.0): TIME*fast_multiplier (>2.0), sin/cos with high freq, feedback loops, many iterations
  MEDIUM (0.3-0.7): TIME*moderate (0.5-2.0), smooth animations, gradual changes
  LOW (0.0-0.3): TIME*slow (<0.5), static patterns, no animation, still images

mood_valence (-1.0 to 1.0):
  POSITIVE (+0.5 to +1.0): bright colors, saturation boost, bloom/glow, rainbows, warm tones
  NEUTRAL (-0.3 to +0.3): balanced palettes, grayscale, neutral processing
  NEGATIVE (-1.0 to -0.5): dark themes, desaturation, noise/distortion, glitch, vignette, shadows

color_warmth (0.0-1.0):
  WARM (0.7-1.0): red/orange/yellow dominant, vec3(1,0.5,0), fire palettes
  NEUTRAL (0.3-0.7): purple/white/mixed, balanced RGB
  COOL (0.0-0.3): blue/cyan/green dominant, vec3(0,0.5,1), water/ice palettes

motion_speed (0.0-1.0):
  FAST (0.7-1.0): TIME*5+, rapid UV scrolling, high-freq sin/cos, particle velocity
  MEDIUM (0.3-0.7): TIME*1-3, moderate rotation/translation
  SLOW (0.0-0.3): TIME*0.1-0.5, subtle drift, nearly static, slow morphing

geometric_score (0.0-1.0):
  GEOMETRIC (0.7-1.0): step(), mod(), floor(), grid patterns, sharp edges, polygons, voronoi
  MIXED (0.3-0.7): combination of smooth and sharp, soft-edged shapes
  ORGANIC (0.0-0.3): smoothstep(), noise(), fbm(), fluid simulations, clouds, soft gradients

visual_density (0.0-1.0):
  DENSE (0.7-1.0): many loop iterations (>20), layered effects, complex fbm, particle systems
  MEDIUM (0.3-0.7): moderate complexity, 5-20 iterations, some layering
  MINIMAL (0.0-0.3): simple math, few operations, clean output, <5 iterations

AUDIO MAPPING - Map shader uniforms to audio sources for music reactivity.

Available audio sources (all normalized 0-1):
  bass: 20-120 Hz, responds to kick drums and sub-bass
  lowMid: 120-350 Hz, responds to drum body and low synths
  mid: 350-2000 Hz, responds to vocals and instruments
  highs: 2000-6000 Hz, responds to hi-hats and cymbals
  kickEnv: kick drum envelope (fast attack, slow decay)
  kickPulse: binary 1 on kick hit, 0 otherwise
  beat4: cycles 0→0.33→0.66→1 every 4 beats
  energyFast: weighted band mix (realtime energy)
  energySlow: 4-second averaged energy (buildup detection)
  level: overall loudness

Modulation types:
  add: uniform = baseValue + (audio * multiplier)
  multiply: uniform = baseValue * (1 + audio * multiplier)
  replace: uniform = audio * multiplier
  threshold: uniform = 1 if audio > multiplier else 0

For each ISF input uniform, suggest optimal audio binding based on:
- "scale/zoom" params → bass or kickEnv (pulse with kick)
- "rate/speed" params → energyFast or mid (vary with energy)
- "color/hue" params → beat4 or energySlow (gradual shifts)
- "intensity/brightness" → level or energyFast
- "warp/distortion" → bass or kickEnv (punch on kicks)

Respond with ONLY valid JSON:
{{
  "mood": "<one word: energetic|calm|dark|bright|psychedelic|mysterious|chaotic|peaceful|aggressive|dreamy>",
  "colors": ["<dominant color>", "<secondary color>"],
  "geometry": ["<shape type>"],
  "objects": ["<visual element>"],
  "effects": ["<visual effect>"],
  "energy": "<low|medium|high>",
  "complexity": "<simple|medium|complex>",
  "description": "<one sentence description>",
  "features": {{
    "energy_score": <float>,
    "mood_valence": <float>,
    "color_warmth": <float>,
    "motion_speed": <float>,
    "geometric_score": <float>,
    "visual_density": <float>
  }},
  "audioMapping": {{
    "songStyle": <0.0-1.0: 0=bass-focused, 1=highs-focused>,
    "bindings": [
      {{
        "uniform": "<ISF input name>",
        "source": "<audio source name>",
        "modulation": "<add|multiply|replace|threshold>",
        "multiplier": <float: effect strength>,
        "smoothing": <0.0-1.0: 0=instant, 0.9=very smooth>,
        "baseValue": <float: value when audio is 0>,
        "minValue": <float: clamp minimum>,
        "maxValue": <float: clamp maximum>
      }}
    ]
  }}
}}

JSON response:"""
    
    def _parse_shader_analysis(self, content: str) -> Optional[Dict[str, Any]]:
        """Parse shader analysis JSON from LLM response."""
        try:
            # Find JSON in response
            start, end = content.find('{'), content.rfind('}')
            if start >= 0 and end > start:
                return json.loads(content[start:end+1])
        except json.JSONDecodeError as e:
            logger.debug(f"Failed to parse shader analysis JSON: {e}")
        return None
    
    @property
    def is_available(self) -> bool:
        return self._health.available
    
    @property
    def backend_info(self) -> str:
        if self._backend == "openai":
            return "OpenAI"
        elif self._backend == "lmstudio":
            return f"LM Studio ({self._lmstudio_model})"
        return "Basic (no LLM)"
    
    # Private implementation
    
    def _init_backend(self):
        """Initialize best available backend."""
        # Try OpenAI
        openai_key = os.environ.get('OPENAI_API_KEY', '')
        if openai_key:
            try:
                import openai
                self._openai_client = openai.OpenAI(api_key=openai_key)
                self._openai_client.models.list()
                self._health.mark_available("OpenAI")
                self._backend = "openai"
                logger.info("LLM: ✓ OpenAI")
                return
            except Exception:
                pass
        
        # Try LM Studio (OpenAI-compatible API)
        try:
            resp = requests.get(f"{self.LM_STUDIO_URL}/v1/models", timeout=2)
            if resp.status_code == 200:
                models = resp.json().get('data', [])
                if models:
                    self._lmstudio_model = models[0].get('id', 'local-model')
                    self._health.mark_available(f"LM Studio ({self._lmstudio_model})")
                    self._backend = "lmstudio"
                    logger.info(f"LLM: ✓ LM Studio ({self._lmstudio_model})")
                    return
        except Exception:
            pass
        
        logger.info("LLM: using basic analysis (no AI)")
    
    def _try_reconnect(self):
        if not self._health.available and self._health.should_retry:
            self._init_backend()
    
    def _analyze_with_llm(self, lyrics: str, artist: str, title: str) -> Optional[Dict]:
        prompt = f"""Analyze lyrics for "{title}" by {artist}. Extract JSON with:
{{"refrain_lines": ["repeated chorus lines"], "keywords": ["5-10 key words"], "themes": ["2-3 themes"]}}

Lyrics: {lyrics[:2000]}"""
        
        try:
            if self._backend == "openai":
                response = self._openai_client.chat.completions.create(
                    model="gpt-3.5-turbo",
                    messages=[{"role": "user", "content": prompt}],
                    max_tokens=400
                )
                content = response.choices[0].message.content
            elif self._backend == "lmstudio":
                resp = requests.post(f"{self.LM_STUDIO_URL}/v1/chat/completions",
                    json={
                        "model": self._lmstudio_model,
                        "messages": [{"role": "user", "content": prompt}],
                        "max_tokens": 400
                    },
                    timeout=60)
                if resp.status_code == 200:
                    content = resp.json().get('choices', [{}])[0].get('message', {}).get('content', '')
                else:
                    content = None
            else:
                return None
            
            # Parse JSON from response
            if content:
                start, end = content.find('{'), content.rfind('}')
                if start >= 0 and end > start:
                    return json.loads(content[start:end+1])
        except Exception as e:
            self._health.mark_unavailable(str(e))
        
        return None
    
    def _basic_analysis(self, lyrics: str) -> Dict:
        """Fallback without LLM."""
        lines = [line.strip() for line in lyrics.split('\n') if line.strip()]
        counts = {}
        for line in lines:
            key = re.sub(r'[^\w\s]', '', line.lower())
            counts[key] = counts.get(key, 0) + 1
        
        refrain = [line for line in lines if counts.get(re.sub(r'[^\w\s]', '', line.lower()), 0) >= 2]
        
        # Keywords
        words = re.findall(r'\b[a-zA-Z]+\b', lyrics.lower())
        word_counts = {}
        for w in words:
            if w not in STOP_WORDS and len(w) > 3:
                word_counts[w] = word_counts.get(w, 0) + 1
        keywords = sorted(word_counts, key=lambda x: word_counts[x], reverse=True)[:10]
        
        return {'refrain_lines': list(set(refrain))[:5], 'keywords': keywords, 'themes': [], 'cached': False}
    
    def _basic_image_prompt(self, artist: str, title: str, keywords: List[str], themes: List[str]) -> str:
        kw = ', '.join(keywords[:5]) if keywords else 'music, rhythm'
        return f"Abstract visualization for '{title}' by {artist}. Elements: {kw}. Cinematic, high-contrast VJ visuals, dark background."


# =============================================================================
# SONG CATEGORIZER - Deep module for mood/theme classification
# =============================================================================

class SongCategorizer:
    """
    AI-powered song categorization by mood and theme.
    
    Deep module interface:
        categorize(artist, title, lyrics) -> SongCategories
    
    Hides: LLM prompting, keyword matching, caching
    """
    
    CATEGORIES = ['dark', 'happy', 'sad', 'energetic', 'calm', 'love', 'death',
                  'romantic', 'aggressive', 'peaceful', 'nostalgic', 'uplifting']
    
    def __init__(self, llm: Optional[LLMAnalyzer] = None, cache_dir: Optional[Path] = None):
        self._llm = llm
        self._cache_dir = (cache_dir or Config.APP_DATA_DIR) / "categorization_cache"
        self._cache_dir.mkdir(parents=True, exist_ok=True)
    
    def categorize(self, artist: str, title: str, lyrics: Optional[str] = None, album: Optional[str] = None) -> SongCategories:
        """Categorize song by mood/theme. Returns SongCategories with scores."""
        cache_file = self._cache_dir / f"{sanitize_cache_filename(artist, title)}.json"
        
        # Check cache
        if cache_file.exists():
            try:
                data = json.loads(cache_file.read_text())
                return SongCategories(
                    scores=data.get('categories', {}),
                    primary_mood=data.get('primary_mood', '')
                )
            except Exception:
                pass
        
        # Try LLM
        if self._llm and self._llm.is_available and lyrics:
            result = self._categorize_with_llm(artist, title, lyrics)
            if result:
                cache_file.write_text(json.dumps({
                    'categories': result.get_dict(),
                    'primary_mood': result.primary_mood
                }))
                return result
        
        # Fallback
        result = self._categorize_basic(artist, title, lyrics)
        cache_file.write_text(json.dumps({
            'categories': result.get_dict(),
            'primary_mood': result.primary_mood
        }))
        return result
    
    @property
    def is_available(self) -> bool:
        return self._llm is not None and self._llm.is_available
    
    # Private implementation
    
    def _categorize_with_llm(self, artist: str, title: str, lyrics: str) -> Optional[SongCategories]:
        prompt = f"""Rate song "{title}" by {artist} on these categories (0.0-1.0):
{', '.join(self.CATEGORIES)}

Lyrics: {lyrics[:1500]}

Return JSON: {{"dark": 0.8, "energetic": 0.3, ...}}"""
        
        try:
            if self._llm._backend == "openai":
                response = self._llm._openai_client.chat.completions.create(
                    model="gpt-3.5-turbo",
                    messages=[{"role": "user", "content": prompt}],
                    max_tokens=300
                )
                content = response.choices[0].message.content
            elif self._llm._backend == "lmstudio":
                resp = requests.post(f"{LLMAnalyzer.LM_STUDIO_URL}/v1/chat/completions",
                    json={
                        "model": self._llm._lmstudio_model,
                        "messages": [{"role": "user", "content": prompt}],
                        "max_tokens": 300
                    },
                    timeout=60)
                if resp.status_code == 200:
                    content = resp.json().get('choices', [{}])[0].get('message', {}).get('content', '')
                else:
                    content = None
            else:
                return None
            
            if content:
                start, end = content.find('{'), content.rfind('}')
                if start >= 0:
                    scores = json.loads(content[start:end+1])
                    # Find primary mood (highest scoring category)
                    primary = max(scores.items(), key=lambda x: x[1])[0] if scores else ""
                    return SongCategories(scores=scores, primary_mood=primary)
        except Exception:
            pass
        
        return None
    
    def _categorize_basic(self, artist: str, title: str, lyrics: Optional[str]) -> SongCategories:
        """Keyword-based fallback."""
        scores = {cat: 0.1 for cat in self.CATEGORIES}
        
        if lyrics:
            text = (title + ' ' + lyrics).lower()
            if any(w in text for w in ['dark', 'death', 'shadow', 'night']):
                scores['dark'] = 0.7
            if any(w in text for w in ['happy', 'joy', 'smile', 'laugh']):
                scores['happy'] = 0.7
            if any(w in text for w in ['sad', 'cry', 'tear', 'pain']):
                scores['sad'] = 0.7
            if any(w in text for w in ['love', 'heart', 'kiss']):
                scores['love'] = 0.7
        
        # Find primary mood
        primary = max(scores.items(), key=lambda x: x[1])[0] if scores else "neutral"
        return SongCategories(scores=scores, primary_mood=primary)


# =============================================================================
# COMFYUI GENERATOR - Deep module for AI image generation
# =============================================================================

class ComfyUIGenerator:
    """
    Generates images using local ComfyUI.
    
    Deep module interface:
        generate_image(prompt, artist, title) -> Optional[Path]
    
    Hides: ComfyUI REST API, workflow management, polling, caching
    """
    
    COMFYUI_URL = "http://127.0.0.1:8188"
    
    def __init__(self, output_dir: Optional[Path] = None, enabled: Optional[bool] = None):
        self._enabled = enabled if enabled is not None else Config.COMFYUI_ENABLED
        self._output_dir = output_dir or (Config.APP_DATA_DIR / "generated_images")
        self._output_dir.mkdir(parents=True, exist_ok=True)
        self._health = ServiceHealth("ComfyUI")
        if self._enabled:
            self._check_connection()
    
    def generate_image(self, prompt: str, artist: str, title: str, width: int = 1024, height: int = 1024) -> Optional[Path]:
        """Generate image for song. Returns path to PNG or None."""
        if not self._enabled:
            return None
        
        # Check cache
        output_path = self._output_dir / f"{sanitize_cache_filename(artist, title)}.png"
        if output_path.exists():
            logger.debug(f"Using cached image: {output_path.name}")
            return output_path
        
        # Check ComfyUI availability
        if not self._health.available:
            self._try_reconnect()
            if not self._health.available:
                return None
        
        # Generate
        try:
            workflow = self._build_simple_workflow(prompt, width, height)
            prompt_id = str(uuid.uuid4())
            
            resp = requests.post(f"{self.COMFYUI_URL}/prompt",
                json={"prompt": workflow, "client_id": prompt_id},
                timeout=10)
            
            if resp.status_code == 200:
                result = self._wait_for_image(prompt_id, output_path)
                if result:
                    logger.info(f"Generated image: {output_path.name}")
                return result
        except Exception as e:
            self._health.mark_unavailable(str(e))
            logger.debug(f"ComfyUI generation error: {e}")
        
        return None
    
    def get_cached_image(self, artist: str, title: str) -> Optional[Path]:
        """Check if cached image exists."""
        path = self._output_dir / f"{sanitize_cache_filename(artist, title)}.png"
        return path if path.exists() else None
    
    @property
    def is_available(self) -> bool:
        return self._enabled and self._health.available
    
    # Private implementation
    
    def _check_connection(self):
        try:
            resp = requests.get(f"{self.COMFYUI_URL}/system_stats", timeout=2)
            if resp.status_code == 200:
                self._health.mark_available("Connected")
                logger.info("ComfyUI: ✓ connected")
            else:
                self._health.mark_unavailable("Not responding")
        except Exception:
            self._health.mark_unavailable("Not running")
    
    def _try_reconnect(self):
        if self._health.should_retry:
            self._check_connection()
    
    def _build_simple_workflow(self, prompt: str, width: int, height: int) -> Dict:
        """Build minimal SDXL workflow."""
        return {
            "3": {"inputs": {"seed": int(time.time()), "steps": 20, "cfg": 7, "sampler_name": "euler",
                           "scheduler": "normal", "denoise": 1, "model": ["4", 0], "positive": ["6", 0],
                           "negative": ["7", 0], "latent_image": ["5", 0]}, "class_type": "KSampler"},
            "4": {"inputs": {"ckpt_name": "sd_xl_base_1.0.safetensors"}, "class_type": "CheckpointLoaderSimple"},
            "5": {"inputs": {"width": width, "height": height, "batch_size": 1}, "class_type": "EmptyLatentImage"},
            "6": {"inputs": {"text": prompt + " black background, high contrast", "clip": ["4", 1]}, "class_type": "CLIPTextEncode"},
            "7": {"inputs": {"text": "busy background, low contrast", "clip": ["4", 1]}, "class_type": "CLIPTextEncode"},
            "8": {"inputs": {"samples": ["3", 0], "vae": ["4", 2]}, "class_type": "VAEDecode"},
            "9": {"inputs": {"filename_prefix": "karaoke", "images": ["8", 0]}, "class_type": "SaveImage"}
        }
    
    def _wait_for_image(self, prompt_id: str, output_path: Path, timeout: int = 60) -> Optional[Path]:
        """Poll for completion and download."""
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                resp = requests.get(f"{self.COMFYUI_URL}/history/{prompt_id}", timeout=5)
                if resp.status_code == 200:
                    history = resp.json().get(prompt_id, {})
                    if history.get('status', {}).get('completed'):
                        # Get output filename
                        outputs = history.get('outputs', {})
                        for node_output in outputs.values():
                            if 'images' in node_output:
                                img_info = node_output['images'][0]
                                subfolder = img_info.get('subfolder', '')
                                return self._download_image(img_info['filename'], subfolder, output_path)
            except Exception:
                pass
            time.sleep(2)
        return None
    
    def _download_image(self, filename: str, subfolder: str, output_path: Path) -> Optional[Path]:
        """Download generated image."""
        try:
            params = {"filename": filename}
            if subfolder:
                params["subfolder"] = subfolder
            resp = requests.get(f"{self.COMFYUI_URL}/view", params=params, timeout=10)
            if resp.status_code == 200:
                output_path.write_bytes(resp.content)
                return output_path
        except Exception:
            pass
        return None
