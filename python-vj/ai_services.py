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
    AI-powered lyrics analysis using OpenAI or local Ollama.
    
    Deep module interface:
        analyze_lyrics(lyrics, artist, title) -> Dict
        generate_image_prompt(artist, title, keywords, themes) -> str
    
    Hides: Multi-backend LLM (OpenAI/Ollama), caching, fallback logic
    """
    
    PREFERRED_MODELS = ['llama3.2', 'llama3.1', 'mistral', 'deepseek-r1', 'llama2']
    OLLAMA_URL = "http://localhost:11434"
    
    def __init__(self, cache_dir: Optional[Path] = None):
        self._cache_dir = (cache_dir or Config.APP_DATA_DIR) / "llm_cache"
        self._cache_dir.mkdir(parents=True, exist_ok=True)
        self._openai_client = None
        self._ollama_model = None
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
            elif self._backend == "ollama":
                resp = requests.post(f"{self.OLLAMA_URL}/api/generate",
                    json={"model": self._ollama_model, "prompt": prompt, "stream": False},
                    timeout=30)
                if resp.status_code == 200:
                    return resp.json().get('response', '').strip()
        except Exception as e:
            logger.debug(f"Image prompt generation error: {e}")
        
        return self._basic_image_prompt(artist, title, keywords, themes)
    
    @property
    def is_available(self) -> bool:
        return self._health.available
    
    @property
    def backend_info(self) -> str:
        if self._backend == "openai":
            return "OpenAI"
        elif self._backend == "ollama":
            return f"Ollama ({self._ollama_model})"
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
        
        # Try Ollama
        try:
            resp = requests.get(f"{self.OLLAMA_URL}/api/tags", timeout=2)
            if resp.status_code == 200:
                models = [m.get('name', '').split(':')[0] for m in resp.json().get('models', [])]
                for preferred in self.PREFERRED_MODELS:
                    if preferred in models:
                        self._ollama_model = preferred
                        break
                if self._ollama_model:
                    self._health.mark_available(f"Ollama ({self._ollama_model})")
                    self._backend = "ollama"
                    logger.info(f"LLM: ✓ Ollama ({self._ollama_model})")
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
            elif self._backend == "ollama":
                resp = requests.post(f"{self.OLLAMA_URL}/api/generate",
                    json={"model": self._ollama_model, "prompt": prompt, "stream": False},
                    timeout=30)
                content = resp.json().get('response', '') if resp.status_code == 200 else None
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
            elif self._llm._backend == "ollama":
                resp = requests.post(f"{LLMAnalyzer.OLLAMA_URL}/api/generate",
                    json={"model": self._llm._ollama_model, "prompt": prompt, "stream": False},
                    timeout=30)
                content = resp.json().get('response', '') if resp.status_code == 200 else None
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
