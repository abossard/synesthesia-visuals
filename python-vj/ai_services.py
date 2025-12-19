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
    
    def analyze_shader(
        self, 
        shader_name: str, 
        shader_source: str, 
        screenshot_path: Optional[str] = None,
        timeout: int = 300
    ) -> Dict[str, Any]:
        """
        Analyze GLSL shader source (and optionally screenshot) for VJ music visualization matching.
        
        Args:
            shader_name: Name of the shader
            shader_source: GLSL source code
            screenshot_path: Optional path to PNG screenshot for visual analysis
            timeout: Request timeout in seconds (default 300s = 5 min for large shaders)
        
        Returns dict with:
            - mood: str (energetic|calm|dark|bright|psychedelic|...)
            - colors: List[str]
            - effects: List[str]
            - description: str
            - features: Dict[str, float] (energy_score, mood_valence, etc.)
            - screenshot: Dict (visual analysis if screenshot provided)
            - error: str (only present if analysis failed)
        """
        self._try_reconnect()
        
        if not self._health.available:
            logger.debug("LLM not available for shader analysis")
            return {'error': 'LLM not available', 'shader_name': shader_name}
        
        # If screenshot available, use combined vision+code analysis
        if screenshot_path:
            result = self._analyze_with_screenshot(shader_name, shader_source, screenshot_path, timeout)
            if result and 'error' not in result:
                return result
            # Fall back to code-only analysis if vision fails
            logger.debug(f"Vision analysis failed, falling back to code-only: {result.get('error', '')}")
        
        # Code-only analysis
        prompt = self._build_shader_analysis_prompt(shader_name, shader_source)
        
        try:
            if self._backend == "openai":
                response = self._openai_client.chat.completions.create(
                    model="gpt-3.5-turbo",
                    messages=[{"role": "user", "content": prompt}],
                    max_tokens=1200,
                    timeout=timeout
                )
                content = response.choices[0].message.content
            elif self._backend == "lmstudio":
                resp = requests.post(f"{self.LM_STUDIO_URL}/v1/chat/completions",
                    json={
                        "model": self._lmstudio_model,
                        "messages": [{"role": "user", "content": prompt}],
                        "max_tokens": 1200
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
    
    def _analyze_with_screenshot(
        self,
        shader_name: str,
        shader_source: str,
        screenshot_path: str,
        timeout: int
    ) -> Dict[str, Any]:
        """
        Combined analysis using both shader code and screenshot image.
        
        This is the most accurate analysis as it sees actual visual output.
        """
        import base64
        from pathlib import Path
        
        # Read and encode image
        try:
            img_path = Path(screenshot_path)
            if not img_path.exists():
                return {'error': f'Screenshot not found: {screenshot_path}'}
            
            with open(img_path, 'rb') as f:
                image_data = base64.b64encode(f.read()).decode('utf-8')
            
            mime_type = 'image/png' if img_path.suffix.lower() == '.png' else 'image/jpeg'
        except Exception as e:
            return {'error': f'Failed to read screenshot: {e}'}
        
        prompt = self._build_combined_analysis_prompt(shader_name, shader_source)
        
        try:
            if self._backend == "openai":
                response = self._openai_client.chat.completions.create(
                    model="gpt-4o-mini",  # Vision-capable model
                    messages=[{
                        "role": "user",
                        "content": [
                            {"type": "text", "text": prompt},
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": f"data:{mime_type};base64,{image_data}",
                                    "detail": "low"
                                }
                            }
                        ]
                    }],
                    max_tokens=1200,
                    timeout=timeout
                )
                content = response.choices[0].message.content
                
            elif self._backend == "lmstudio":
                resp = requests.post(f"{self.LM_STUDIO_URL}/v1/chat/completions",
                    json={
                        "model": self._lmstudio_model,
                        "messages": [{
                            "role": "user",
                            "content": [
                                {"type": "text", "text": prompt},
                                {
                                    "type": "image_url",
                                    "image_url": {"url": f"data:{mime_type};base64,{image_data}"}
                                }
                            ]
                        }],
                        "max_tokens": 1200
                    },
                    timeout=timeout)
                
                if resp.status_code == 200:
                    content = resp.json().get('choices', [{}])[0].get('message', {}).get('content', '')
                else:
                    return {'error': 'Vision not supported by LM Studio model'}
            else:
                return {'error': 'No vision-capable backend'}
            
            if content:
                result = self._parse_shader_analysis(content)
                if result:
                    result['has_screenshot'] = True
                    return result
                    
        except Exception as e:
            logger.debug(f"Vision analysis failed: {e}")
            return {'error': str(e)}
        
        return {'error': 'Vision analysis failed'}
    
    def _build_combined_analysis_prompt(self, shader_name: str, source: str) -> str:
        """Build prompt for combined code + screenshot analysis."""
        # Truncate source more aggressively since we have the image
        max_len = 4000
        if len(source) > max_len:
            source = source[:max_len] + "\n// ... (truncated)"
        
        return f"""Analyze this shader using BOTH the code AND the screenshot image.

Shader: {shader_name}

The IMAGE shows the actual visual output - use it to determine:
- Actual colors (what you SEE, not what code suggests)
- Visual patterns and shapes
- Brightness and contrast
- Perceived motion/energy

Code (for context):
```glsl
{source}
```

IMPORTANT: The screenshot is the SOURCE OF TRUTH for visual properties.
Keep response SHORT. Output ONLY valid JSON, no markdown.

{{
  "mood": "<energetic|calm|dark|bright|psychedelic|mysterious|chaotic|peaceful|aggressive|dreamy>",
  "colors": ["<actual colors from image>"],
  "geometry": ["<shapes you see>"],
  "objects": ["<visual elements>"],
  "effects": ["<visual effects>"],
  "energy": "<low|medium|high>",
  "complexity": "<simple|medium|complex>",
  "description": "<15 words describing what you SEE in the image>",
  "features": {{
    "energy_score": <0.0-1.0 based on visual intensity>,
    "mood_valence": <-1.0 to 1.0: dark=-1, bright=+1>,
    "color_warmth": <0.0-1.0: cool blues=0, warm reds=1>,
    "motion_speed": <0.0-1.0 based on perceived motion>,
    "geometric_score": <0.0-1.0: organic=0, geometric=1>,
    "visual_density": <0.0-1.0: minimal=0, dense=1>
  }},
  "screenshot": {{
    "dominant_colors": ["<top 3 colors from image>"],
    "visual_patterns": ["<stripes|spirals|grids|particles|waves|etc>"],
    "brightness": <0.0-1.0>,
    "contrast": <0.0-1.0>,
    "colorfulness": <0.0-1.0>
  }},
  "audioMapping": {{
    "primarySource": "<bass|mid|highs|kickEnv|energyFast|level>",
    "songStyle": <0.0-1.0>
  }}
}}

JSON:"""
    
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

AUDIO MAPPING - Suggest best audio source for this shader's primary parameter.
Audio sources: bass, mid, highs, kickEnv, beat4, energyFast, level

IMPORTANT: Keep response SHORT. Output ONLY valid JSON, no markdown fences.

{{
  "mood": "<energetic|calm|dark|bright|psychedelic|mysterious|chaotic|peaceful|aggressive|dreamy>",
  "colors": ["<color1>", "<color2>"],
  "geometry": ["<shape>"],
  "objects": ["<element>"],
  "effects": ["<effect>"],
  "energy": "<low|medium|high>",
  "complexity": "<simple|medium|complex>",
  "description": "<15 words max>",
  "features": {{
    "energy_score": <0.0-1.0>,
    "mood_valence": <-1.0 to 1.0>,
    "color_warmth": <0.0-1.0>,
    "motion_speed": <0.0-1.0>,
    "geometric_score": <0.0-1.0>,
    "visual_density": <0.0-1.0>
  }},
  "audioMapping": {{
    "primarySource": "<best audio source for this shader>",
    "songStyle": <0.0-1.0>
  }}
}}

JSON:"""
    
    # Required fields for valid shader analysis
    REQUIRED_FIELDS = {'mood', 'colors', 'effects', 'energy', 'description', 'features'}
    REQUIRED_FEATURES = {'energy_score', 'mood_valence', 'color_warmth', 'motion_speed', 'geometric_score', 'visual_density'}
    
    def _parse_shader_analysis(self, content: str) -> Optional[Dict[str, Any]]:
        """Parse shader analysis JSON from LLM response. Returns None if invalid or incomplete."""
        try:
            # Strip markdown code fences if present
            cleaned = content.strip()
            if cleaned.startswith('```'):
                # Remove opening fence (```json or ```)
                first_newline = cleaned.find('\n')
                if first_newline > 0:
                    cleaned = cleaned[first_newline + 1:]
                # Remove closing fence
                if cleaned.rstrip().endswith('```'):
                    cleaned = cleaned.rstrip()[:-3].rstrip()
            
            # Find JSON in response
            start = cleaned.find('{')
            end = cleaned.rfind('}')
            
            if start >= 0 and end > start:
                json_str = cleaned[start:end+1]
                result = json.loads(json_str)
                
                # Validate required fields
                missing = self.REQUIRED_FIELDS - set(result.keys())
                if missing:
                    logger.warning(f"Missing required fields: {missing}")
                    return None
                
                # Validate features dict
                features = result.get('features', {})
                if not isinstance(features, dict):
                    logger.warning("'features' is not a dict")
                    return None
                
                missing_features = self.REQUIRED_FEATURES - set(features.keys())
                if missing_features:
                    logger.warning(f"Missing required features: {missing_features}")
                    return None
                
                return result
            
            # No valid JSON found
            logger.warning(f"No valid JSON found in LLM response: {content[:200]}...")
            return None
                    
        except json.JSONDecodeError as e:
            logger.warning(f"Failed to parse shader analysis JSON: {e}")
            return None
    
    def analyze_screenshot(self, shader_name: str, screenshot_path: str, timeout: int = 60) -> Dict[str, Any]:
        """
        Analyze shader screenshot using vision-capable LLM.
        
        This provides visual analysis that complements code analysis:
        - Actual colors visible in the output
        - Visual patterns and shapes
        - Perceived mood and energy from the image
        - Description of what the shader looks like
        
        Args:
            shader_name: Name of the shader
            screenshot_path: Path to PNG screenshot file
            timeout: Request timeout in seconds
        
        Returns dict with:
            - visual_mood: str (energetic|calm|dark|bright|psychedelic|...)
            - dominant_colors: List[str] (actual colors seen)
            - visual_patterns: List[str] (stripes, spirals, particles, etc.)
            - visual_description: str (what it looks like)
            - visual_features: Dict[str, float] (scores from image)
            - error: str (only if analysis failed)
        """
        self._try_reconnect()
        
        if not self._health.available:
            return {'error': 'LLM not available', 'shader_name': shader_name}
        
        # Read and encode image as base64
        try:
            import base64
            from pathlib import Path
            
            img_path = Path(screenshot_path)
            if not img_path.exists():
                return {'error': f'Screenshot not found: {screenshot_path}', 'shader_name': shader_name}
            
            with open(img_path, 'rb') as f:
                image_data = base64.b64encode(f.read()).decode('utf-8')
            
            # Determine mime type
            suffix = img_path.suffix.lower()
            mime_type = 'image/png' if suffix == '.png' else 'image/jpeg'
            
        except Exception as e:
            return {'error': f'Failed to read screenshot: {e}', 'shader_name': shader_name}
        
        prompt = self._build_screenshot_analysis_prompt(shader_name)
        
        try:
            if self._backend == "openai":
                response = self._openai_client.chat.completions.create(
                    model="gpt-4o-mini",  # Vision-capable model
                    messages=[{
                        "role": "user",
                        "content": [
                            {"type": "text", "text": prompt},
                            {
                                "type": "image_url",
                                "image_url": {
                                    "url": f"data:{mime_type};base64,{image_data}",
                                    "detail": "low"  # Use low detail for faster/cheaper analysis
                                }
                            }
                        ]
                    }],
                    max_tokens=800,
                    timeout=timeout
                )
                content = response.choices[0].message.content
                
            elif self._backend == "lmstudio":
                # LM Studio with vision model (if available)
                resp = requests.post(f"{self.LM_STUDIO_URL}/v1/chat/completions",
                    json={
                        "model": self._lmstudio_model,
                        "messages": [{
                            "role": "user",
                            "content": [
                                {"type": "text", "text": prompt},
                                {
                                    "type": "image_url",
                                    "image_url": {
                                        "url": f"data:{mime_type};base64,{image_data}"
                                    }
                                }
                            ]
                        }],
                        "max_tokens": 800
                    },
                    timeout=timeout)
                
                if resp.status_code == 200:
                    content = resp.json().get('choices', [{}])[0].get('message', {}).get('content', '')
                else:
                    # Vision might not be supported - return graceful error
                    return {'error': f'Vision not supported by LM Studio model', 'shader_name': shader_name}
            else:
                return {'error': 'No vision-capable backend', 'shader_name': shader_name}
            
            # Parse response
            if content:
                result = self._parse_screenshot_analysis(content)
                if result:
                    return result
                else:
                    return {'error': f'Failed to parse vision response', 'shader_name': shader_name}
                    
        except Exception as e:
            logger.warning(f"Screenshot analysis error for {shader_name}: {e}")
            return {'error': str(e), 'shader_name': shader_name}
        
        return {'error': 'Unknown error', 'shader_name': shader_name}
    
    def _build_screenshot_analysis_prompt(self, shader_name: str) -> str:
        """Build prompt for screenshot/image analysis."""
        return f"""Analyze this shader screenshot for VJ music visualization matching.

Shader: {shader_name}

Look at the IMAGE and describe what you SEE. Focus on:
1. Actual colors visible (not guessed from code)
2. Visual patterns (spirals, grids, particles, waves, etc.)
3. Overall mood/feeling the image conveys
4. Brightness and contrast levels
5. Motion impression (does it look fast/slow/static?)

IMPORTANT: Keep response SHORT. Output ONLY valid JSON, no markdown.

{{
  "visual_mood": "<energetic|calm|dark|bright|psychedelic|mysterious|chaotic|peaceful|aggressive|dreamy>",
  "dominant_colors": ["<color1>", "<color2>", "<color3>"],
  "visual_patterns": ["<pattern1>", "<pattern2>"],
  "visual_objects": ["<what you see: tunnels, fractals, shapes, etc>"],
  "visual_description": "<15 words max describing what it looks like>",
  "visual_features": {{
    "brightness": <0.0-1.0: 0=very dark, 1=very bright>,
    "contrast": <0.0-1.0: 0=flat, 1=high contrast>,
    "colorfulness": <0.0-1.0: 0=monochrome, 1=rainbow>,
    "complexity": <0.0-1.0: 0=simple, 1=intricate>,
    "perceived_motion": <0.0-1.0: 0=static, 1=fast movement>
  }}
}}

JSON:"""
    
    def _parse_screenshot_analysis(self, content: str) -> Optional[Dict[str, Any]]:
        """Parse screenshot analysis JSON from LLM response."""
        try:
            cleaned = content.strip()
            if cleaned.startswith('```'):
                first_newline = cleaned.find('\n')
                if first_newline > 0:
                    cleaned = cleaned[first_newline + 1:]
                if cleaned.rstrip().endswith('```'):
                    cleaned = cleaned.rstrip()[:-3].rstrip()
            
            start = cleaned.find('{')
            end = cleaned.rfind('}')
            
            if start >= 0 and end > start:
                json_str = cleaned[start:end+1]
                result = json.loads(json_str)
                
                # Validate required fields
                required = {'visual_mood', 'dominant_colors', 'visual_description', 'visual_features'}
                if not required.issubset(set(result.keys())):
                    logger.warning(f"Screenshot analysis missing fields: {required - set(result.keys())}")
                    return None
                
                return result
            
            return None
        except json.JSONDecodeError as e:
            logger.warning(f"Failed to parse screenshot analysis JSON: {e}")
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

