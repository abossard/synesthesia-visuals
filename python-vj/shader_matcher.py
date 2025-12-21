"""
Shader Matcher - Feature-based shader-to-music matching

Multi-dimensional semantic matching using normalized feature vectors.
Features: energy_score, mood_valence, color_warmth, motion_speed, geometric_score, visual_density

Architecture:
    - ShaderIndexer: ChromaDB sync, LLM analysis orchestration
    - ShaderMatcher: Feature-based matching (from indexed shaders)
    - JSON files are source of truth, ChromaDB is derived index

Audio-Reactive Spec (from MMV pipeline guide):
    Audio Sources:
        - bass: 20-120 Hz, kick/sub (smoothed)
        - lowMid: 120-350 Hz, drum body/synth
        - highs: 2000-6000 Hz, hats/cymbals
        - kickEnv: 40-120 Hz envelope (attack detection)
        - kickPulse: binary 0/1 on kick hits
        - beat4: 4-step counter (0,1,2,3 cycling)
        - energyFast: weighted band mix (realtime)
        - energySlow: 4s averaged energy
        - level: overall loudness
    
    Modulation Types:
        - add: uniform = base + (audio * multiplier)
        - multiply: uniform = base * (1 + audio * multiplier)
        - replace: uniform = audio * multiplier
        - threshold: uniform = 1 if audio > threshold else 0

Usage:
    indexer = ShaderIndexer()
    await indexer.sync()  # JSON → ChromaDB, analyze unanalyzed
    matcher = ShaderMatcher(indexer)
    matches = matcher.match_by_mood("energetic", energy=0.8)
"""

import os
# Suppress huggingface tokenizers parallelism warning (must be before chromadb import)
os.environ["TOKENIZERS_PARALLELISM"] = "false"

import json
import hashlib
import math
import logging
from dataclasses import dataclass, field
from typing import List, Dict, Tuple, Optional, Any
from pathlib import Path

logger = logging.getLogger('shader_matcher')


@dataclass
class ShaderInputs:
    """Input capabilities parsed from ISF header"""
    float_count: int = 0        # MIDI-mappable sliders
    point2d_count: int = 0      # Interactive mouse/touch
    color_count: int = 0        # Color pickers
    bool_count: int = 0         # Toggles
    image_count: int = 0        # Compositing inputs
    has_audio: bool = False     # Native audio reactivity
    input_names: List[str] = field(default_factory=list)
    
    @property
    def is_interactive(self) -> bool:
        return self.point2d_count > 0
    
    @property
    def is_compositable(self) -> bool:
        return self.image_count > 0
    
    @property
    def is_midi_mappable(self) -> bool:
        return self.float_count >= 2
    
    @property
    def is_audio_reactive(self) -> bool:
        return self.has_audio
    
    @property
    def is_autonomous(self) -> bool:
        return self.float_count == 0 and self.point2d_count == 0 and self.image_count == 0
    
    @property
    def total_controls(self) -> int:
        return self.float_count + self.point2d_count + self.color_count + self.bool_count
    
    def get_capabilities(self) -> List[str]:
        caps = []
        if self.is_autonomous:
            caps.append("generator")
        if self.is_interactive:
            caps.append("interactive")
        if self.is_compositable:
            caps.append("compositor")
        if self.is_midi_mappable:
            caps.append("midi-mappable")
        if self.is_audio_reactive:
            caps.append("audio-reactive")
        return caps if caps else ["basic"]
    
    @classmethod
    def from_dict(cls, data: dict) -> 'ShaderInputs':
        return cls(
            float_count=data.get('floatCount', 0),
            point2d_count=data.get('point2DCount', 0),
            color_count=data.get('colorCount', 0),
            bool_count=data.get('boolCount', 0),
            image_count=data.get('imageCount', 0),
            has_audio=data.get('hasAudio', False),
            input_names=data.get('inputNames', [])
        )


# =============================================================================
# AUDIO-REACTIVE SPEC - Typed mappings from MMV pipeline guide
# =============================================================================

class AudioSource:
    """Audio source names matching VJUniverse audio analysis."""
    BASS = "bass"           # 20-120 Hz, kick/sub
    LOW_MID = "lowMid"      # 120-350 Hz, drum body
    HIGHS = "highs"         # 2000-6000 Hz, hats/cymbals
    KICK_ENV = "kickEnv"    # 40-120 Hz envelope
    KICK_PULSE = "kickPulse"  # Binary kick trigger
    BEAT4 = "beat4"         # 4-step counter (0,1,2,3)
    ENERGY_FAST = "energyFast"  # Weighted band mix
    ENERGY_SLOW = "energySlow"  # 4s averaged
    LEVEL = "level"         # Overall loudness
    TREBLE = "treble"       # Alias for highs
    MID = "mid"             # Alias for lowMid


class ModulationType:
    """How audio modulates the uniform value."""
    ADD = "add"             # base + (audio * mult)
    MULTIPLY = "multiply"   # base * (1 + audio * mult)
    REPLACE = "replace"     # audio * mult
    THRESHOLD = "threshold" # 1 if audio > threshold else 0


@dataclass
class UniformAudioBinding:
    """
    Binding between a shader uniform and an audio source.
    
    Example OSC message: /shader/audio_binding scale bass multiply 0.5 0.15
    """
    uniform_name: str           # ISF input name (e.g., "scale", "rate")
    audio_source: str           # AudioSource constant
    modulation_type: str        # ModulationType constant
    multiplier: float = 1.0     # Strength of effect
    smoothing: float = 0.15     # 0=instant, 1=very slow
    base_value: float = 0.5     # Default value when audio is 0
    min_value: float = 0.0      # Clamp minimum
    max_value: float = 1.0      # Clamp maximum
    
    def to_dict(self) -> dict:
        return {
            'uniform': self.uniform_name,
            'source': self.audio_source,
            'modulation': self.modulation_type,
            'multiplier': self.multiplier,
            'smoothing': self.smoothing,
            'baseValue': self.base_value,
            'minValue': self.min_value,
            'maxValue': self.max_value
        }
    
    @classmethod
    def from_dict(cls, data: dict) -> 'UniformAudioBinding':
        return cls(
            uniform_name=data.get('uniform', ''),
            audio_source=data.get('source', AudioSource.LEVEL),
            modulation_type=data.get('modulation', ModulationType.MULTIPLY),
            multiplier=data.get('multiplier', 1.0),
            smoothing=data.get('smoothing', 0.15),
            base_value=data.get('baseValue', 0.5),
            min_value=data.get('minValue', 0.0),
            max_value=data.get('maxValue', 1.0)
        )
    
    def to_osc_args(self) -> List:
        """Convert to flat OSC argument list."""
        return [
            self.uniform_name,
            self.audio_source,
            self.modulation_type,
            self.multiplier,
            self.smoothing,
            self.base_value,
            self.min_value,
            self.max_value
        ]


@dataclass 
class AudioReactiveProfile:
    """
    Complete audio-reactive configuration for a shader.
    
    Stored in .analysis.json under 'audioMapping' key.
    Sent to Processing via OSC when shader loads.
    """
    bindings: List[UniformAudioBinding] = field(default_factory=list)
    song_style: float = 0.5     # 0=bass-focused, 1=highs-focused
    buildup_response: float = 0.5  # How much shader responds to buildup
    drop_intensity: float = 1.0    # Intensity multiplier during drops
    
    def to_dict(self) -> dict:
        return {
            'bindings': [b.to_dict() for b in self.bindings],
            'songStyle': self.song_style,
            'buildupResponse': self.buildup_response,
            'dropIntensity': self.drop_intensity
        }
    
    @classmethod
    def from_dict(cls, data: dict) -> 'AudioReactiveProfile':
        bindings = [UniformAudioBinding.from_dict(b) for b in data.get('bindings', [])]
        return cls(
            bindings=bindings,
            song_style=data.get('songStyle', 0.5),
            buildup_response=data.get('buildupResponse', 0.5),
            drop_intensity=data.get('dropIntensity', 1.0)
        )
    
    def get_binding(self, uniform: str) -> Optional['UniformAudioBinding']:
        """Get binding for a specific uniform."""
        for b in self.bindings:
            if b.uniform_name == uniform:
                return b
        return None


@dataclass
class ShaderFeatures:
    """Shader feature vector for matching"""
    name: str
    path: str
    energy_score: float = 0.5      # 0=calm, 1=intense
    mood_valence: float = 0.0      # -1=dark/sad, 0=neutral, 1=bright/happy
    color_warmth: float = 0.5      # 0=cool, 1=warm
    motion_speed: float = 0.5      # 0=static, 1=fast
    geometric_score: float = 0.5   # 0=organic, 1=geometric
    visual_density: float = 0.5    # 0=minimal, 1=dense
    
    # User rating: 1=BEST, 2=GOOD, 3=NORMAL, 4=MASK, 5=SKIP (0=unrated, treated as 3)
    rating: int = 0
    
    # Input capabilities
    inputs: ShaderInputs = field(default_factory=ShaderInputs)
    
    # Legacy tags for fallback
    mood: str = "unknown"
    colors: List[str] = field(default_factory=list)
    effects: List[str] = field(default_factory=list)
    
    def to_vector(self) -> List[float]:
        """Get feature vector for distance calculations"""
        return [
            self.energy_score,
            self.mood_valence,
            self.color_warmth,
            self.motion_speed,
            self.geometric_score,
            self.visual_density
        ]
    
    @classmethod
    def from_analysis_json(cls, path: str, data: dict) -> 'ShaderFeatures':
        """Load from .analysis.json file"""
        features = data.get('features', {})
        inputs_data = data.get('inputs', {})
        return cls(
            name=data.get('shaderName', Path(path).stem),
            path=path,
            energy_score=features.get('energy_score', 0.5),
            mood_valence=features.get('mood_valence', 0.0),
            color_warmth=features.get('color_warmth', 0.5),
            motion_speed=features.get('motion_speed', 0.5),
            geometric_score=features.get('geometric_score', 0.5),
            visual_density=features.get('visual_density', 0.5),
            rating=data.get('rating', 0),  # 0=unrated, treated as 3
            inputs=ShaderInputs.from_dict(inputs_data),
            mood=data.get('mood', 'unknown'),
            colors=data.get('colors', []),
            effects=data.get('effects', [])
        )
    
    def get_effective_rating(self) -> int:
        """Get effective rating (0=unrated treated as 3)"""
        return self.rating if self.rating > 0 else 3
    
    def is_quality_shader(self) -> bool:
        """Return True if shader is rated 1 (BEST) or 2 (GOOD)"""
        return self.get_effective_rating() in (1, 2)
    
    def is_usable(self) -> bool:
        """Return True if shader is not rated 5 (SKIP)"""
        return self.get_effective_rating() != 5


@dataclass
class SongFeatures:
    """Song feature vector for matching (from audio analysis)"""
    title: str
    artist: str = ""
    energy: float = 0.5            # 0=calm, 1=energetic
    valence: float = 0.0           # -1=sad, 1=happy
    tempo_normalized: float = 0.5  # 0=slow, 1=fast (BPM mapped to 0-1)
    danceability: float = 0.5      # 0=not danceable, 1=very danceable
    acousticness: float = 0.5      # 0=electronic, 1=acoustic
    loudness_normalized: float = 0.5  # 0=quiet, 1=loud
    
    def to_shader_target(self) -> List[float]:
        """Convert song features to shader feature space"""
        return [
            self.energy,                                    # energy_score
            self.valence,                                   # mood_valence
            0.5 + (self.valence * 0.3),                    # color_warmth (happy=warm)
            self.tempo_normalized * 0.7 + self.energy * 0.3,  # motion_speed
            1.0 - self.acousticness,                       # geometric (electronic=geometric)
            self.loudness_normalized * 0.5 + self.energy * 0.5  # visual_density
        ]


def categories_to_song_features(
    categories, 
    track_title: str = "", 
    track_artist: str = "",
    llm_result: Optional[Dict[str, Any]] = None
) -> SongFeatures:
    """
    Convert SongCategories and LLM analysis to SongFeatures for shader matching.
    
    Merges both data sources:
    - categories: SongCategories with mood scores (energetic, calm, happy, etc.)
    - llm_result: Dict with 'keywords' and 'themes' lists from LLM analysis
    
    Maps to normalized feature space:
    - energy: from energetic/calm scores + theme modifiers
    - valence: from happy/sad/dark/uplifting scores + keyword modifiers
    - tempo: estimated from energetic + danceability proxy
    - acousticness: from peaceful/calm vs aggressive/energetic + genre hints
    
    Args:
        categories: SongCategories from AI analysis
        track_title: Song title
        track_artist: Song artist
        llm_result: Optional dict with 'keywords' and 'themes' from LLM
    
    Returns:
        SongFeatures ready for shader matching
    """
    scores = categories.scores if categories else {}
    
    # Extract keywords and themes from LLM result (handle both string and dict items)
    keywords = []
    themes = []
    if llm_result:
        raw_keywords = llm_result.get('keywords', [])
        raw_themes = llm_result.get('themes', [])
        
        # Handle items that might be strings or dicts
        for k in raw_keywords:
            if isinstance(k, str):
                keywords.append(k.lower())
            elif isinstance(k, dict) and 'name' in k:
                keywords.append(str(k['name']).lower())
            elif isinstance(k, dict) and 'keyword' in k:
                keywords.append(str(k['keyword']).lower())
        
        for t in raw_themes:
            if isinstance(t, str):
                themes.append(t.lower())
            elif isinstance(t, dict) and 'name' in t:
                themes.append(str(t['name']).lower())
            elif isinstance(t, dict) and 'theme' in t:
                themes.append(str(t['theme']).lower())
    
    # Theme-based modifiers (boost/reduce based on detected themes)
    theme_energy_mod = 0.0
    theme_valence_mod = 0.0
    theme_acoustic_mod = 0.0
    theme_geometric_mod = 0.0
    
    # High-energy themes
    energy_boost_themes = {'party', 'dance', 'fight', 'battle', 'power', 'rage', 'chaos', 'war', 'rebellion'}
    energy_reduce_themes = {'sleep', 'dream', 'meditation', 'peace', 'rest', 'lullaby', 'quiet'}
    
    # Positive valence themes
    positive_themes = {'love', 'joy', 'celebration', 'freedom', 'hope', 'victory', 'summer', 'sunshine'}
    negative_themes = {'death', 'loss', 'pain', 'grief', 'despair', 'darkness', 'fear', 'loneliness', 'betrayal'}
    
    # Electronic/synthetic vs organic/acoustic themes
    electronic_themes = {'synth', 'electronic', 'digital', 'future', 'cyber', 'robot', 'machine', 'techno'}
    acoustic_themes = {'nature', 'acoustic', 'folk', 'organic', 'earth', 'forest', 'ocean', 'wind'}
    
    # Geometric vs organic visual themes
    geometric_themes = {'city', 'urban', 'geometric', 'abstract', 'digital', 'grid', 'structure', 'architecture'}
    organic_themes = {'nature', 'water', 'fire', 'earth', 'organic', 'flowing', 'waves', 'growth'}
    
    all_text = set(keywords + themes)
    
    for theme in all_text:
        if theme in energy_boost_themes:
            theme_energy_mod += 0.15
        if theme in energy_reduce_themes:
            theme_energy_mod -= 0.15
        if theme in positive_themes:
            theme_valence_mod += 0.1
        if theme in negative_themes:
            theme_valence_mod -= 0.1
        if theme in electronic_themes:
            theme_acoustic_mod -= 0.1
            theme_geometric_mod += 0.1
        if theme in acoustic_themes:
            theme_acoustic_mod += 0.1
            theme_geometric_mod -= 0.1
        if theme in geometric_themes:
            theme_geometric_mod += 0.1
        if theme in organic_themes:
            theme_geometric_mod -= 0.1
    
    # Energy: combine energetic (positive) and calm (negative)
    energetic = scores.get('energetic', 0.0)
    calm = scores.get('calm', 0.0)
    aggressive = scores.get('aggressive', 0.0)
    energy = max(0.0, min(1.0, 0.5 + energetic * 0.5 - calm * 0.4 + aggressive * 0.3 + theme_energy_mod))
    
    # Valence: happy/uplifting (positive) vs sad/dark (negative)
    happy = scores.get('happy', 0.0)
    uplifting = scores.get('uplifting', 0.0)
    romantic = scores.get('romantic', 0.0)
    sad = scores.get('sad', 0.0)
    dark = scores.get('dark', 0.0)
    melancholic = scores.get('nostalgic', 0.0) * 0.5  # Nostalgic is mildly negative
    death = scores.get('death', 0.0)
    
    valence = max(-1.0, min(1.0,
        (happy * 0.4 + uplifting * 0.4 + romantic * 0.2) -
        (sad * 0.4 + dark * 0.3 + melancholic * 0.15 + death * 0.3) +
        theme_valence_mod
    ))
    
    # Tempo proxy: energetic + danceability estimate
    love = scores.get('love', 0.0)
    peaceful = scores.get('peaceful', 0.0)
    tempo = max(0.0, min(1.0, 0.5 + energetic * 0.4 - peaceful * 0.3 - love * 0.1))
    
    # Danceability: energetic + happy, reduced by calm/sad
    danceability = max(0.0, min(1.0, 
        0.4 + energetic * 0.3 + happy * 0.2 - calm * 0.2 - sad * 0.15
    ))
    
    # Acousticness: peaceful/calm vs aggressive/energetic + theme modifiers
    acousticness = max(0.0, min(1.0,
        0.5 + peaceful * 0.3 + calm * 0.2 - aggressive * 0.3 - energetic * 0.2 + theme_acoustic_mod
    ))
    
    # Loudness: aggressive + energetic - peaceful
    loudness = max(0.0, min(1.0,
        0.5 + aggressive * 0.3 + energetic * 0.2 - peaceful * 0.2 - calm * 0.15
    ))
    
    return SongFeatures(
        title=track_title,
        artist=track_artist,
        energy=energy,
        valence=valence,
        tempo_normalized=tempo,
        danceability=danceability,
        acousticness=acousticness,
        loudness_normalized=loudness
    )


class ShaderMatcher:
    """Match shaders to songs using feature vectors"""
    
    FEATURE_WEIGHTS = {
        'energy_score': 1.5,      # Most important
        'mood_valence': 1.3,      # Very important
        'color_warmth': 0.8,
        'motion_speed': 1.0,
        'geometric_score': 0.6,
        'visual_density': 0.8
    }
    
    def __init__(self, shaders_dir: Optional[str] = None):
        self.shaders: List[ShaderFeatures] = []
        self.shaders_dir = shaders_dir
        
        if shaders_dir:
            self.load_shaders(shaders_dir)
    
    def load_shaders(self, shaders_dir: str) -> int:
        """
        Load all shader analyses from directory.
        
        Supports both ISF (.fs) and GLSL (.txt) shaders.
        """
        self.shaders = []
        shaders_path = Path(shaders_dir)
        
        # Find all .analysis.json files
        for analysis_file in shaders_path.rglob("*.analysis.json"):
            try:
                with open(analysis_file, 'r') as f:
                    data = json.load(f)
                
                # Get shader type from analysis or auto-detect
                shader_type = data.get('shaderType', 'isf')
                ext = data.get('extension', '.fs' if shader_type == 'isf' else '.txt')
                
                # Get corresponding shader path
                shader_path = str(analysis_file).replace('.analysis.json', ext)
                if not os.path.exists(shader_path):
                    # Fallback: try other extensions
                    for try_ext in ['.fs', '.txt', '.glsl', '.frag']:
                        try_path = str(analysis_file).replace('.analysis.json', try_ext)
                        if os.path.exists(try_path):
                            shader_path = try_path
                            break
                
                shader = ShaderFeatures.from_analysis_json(shader_path, data)
                self.shaders.append(shader)
                
            except (json.JSONDecodeError, KeyError) as e:
                print(f"Warning: Could not load {analysis_file}: {e}")
        
        print(f"Loaded {len(self.shaders)} shader analyses")
        return len(self.shaders)
    
    def filter_by_capability(
        self,
        require_interactive: bool = False,
        require_compositable: bool = False,
        require_midi: bool = False,
        require_audio: bool = False,
        require_autonomous: bool = False,
        require_quality: bool = False,
        exclude_skip: bool = True
    ) -> List[ShaderFeatures]:
        """
        Filter shaders by input capabilities and rating.
        
        Args:
            require_quality: Only include rating 1 (BEST) or 2 (GOOD) shaders
            exclude_skip: Exclude rating 5 (SKIP) shaders (default True)
        """
        result = []
        for shader in self.shaders:
            # Rating filters
            if exclude_skip and not shader.is_usable():
                continue
            if require_quality and not shader.is_quality_shader():
                continue
            # Capability filters
            if require_interactive and not shader.inputs.is_interactive:
                continue
            if require_compositable and not shader.inputs.is_compositable:
                continue
            if require_midi and not shader.inputs.is_midi_mappable:
                continue
            if require_audio and not shader.inputs.is_audio_reactive:
                continue
            if require_autonomous and not shader.inputs.is_autonomous:
                continue
            result.append(shader)
        return result
    
    def weighted_distance(self, v1: List[float], v2: List[float]) -> float:
        """Calculate weighted Euclidean distance between feature vectors"""
        weights = [
            self.FEATURE_WEIGHTS['energy_score'],
            self.FEATURE_WEIGHTS['mood_valence'],
            self.FEATURE_WEIGHTS['color_warmth'],
            self.FEATURE_WEIGHTS['motion_speed'],
            self.FEATURE_WEIGHTS['geometric_score'],
            self.FEATURE_WEIGHTS['visual_density']
        ]
        
        total = 0.0
        for i in range(min(len(v1), len(v2), len(weights))):
            diff = v1[i] - v2[i]
            total += weights[i] * (diff ** 2)
        
        return math.sqrt(total)
    
    def match_to_features(
        self, 
        target: List[float], 
        top_k: int = 4,
        diversity_penalty: float = 0.3,
        require_quality: bool = True
    ) -> List[Tuple[ShaderFeatures, float]]:
        """
        Find best matching shaders for target feature vector.
        
        Args:
            target: Target feature vector [energy, mood, warmth, motion, geometric, density]
            top_k: Number of shaders to return
            diversity_penalty: Penalty for similar shaders (0=no penalty, 1=max penalty)
            require_quality: Only match rating 1-2 shaders (default True)
        
        Returns:
            List of (shader, score) tuples, sorted by score (lower is better)
        """
        # Filter to usable shaders (exclude rating=5, optionally require quality)
        candidates = self.filter_by_capability(
            require_quality=require_quality,
            exclude_skip=True
        )
        
        if not candidates:
            # Fallback: if no quality shaders, try all usable shaders
            if require_quality:
                candidates = self.filter_by_capability(
                    require_quality=False,
                    exclude_skip=True
                )
        
        if not candidates:
            return []
        
        # Calculate distances
        scored = []
        for shader in candidates:
            dist = self.weighted_distance(shader.to_vector(), target)
            # Boost quality shaders slightly (lower distance = better match)
            if shader.is_quality_shader():
                dist *= 0.9  # 10% bonus for quality shaders
            scored.append((shader, dist))
        
        # Sort by distance
        scored.sort(key=lambda x: x[1])
        
        if diversity_penalty <= 0:
            return scored[:top_k]
        
        # Select with diversity (greedy)
        selected = []
        for shader, dist in scored:
            if len(selected) >= top_k:
                break
            
            # Check diversity against already selected
            penalty = 0.0
            for sel_shader, _ in selected:
                similarity = 1.0 - self.weighted_distance(
                    shader.to_vector(), 
                    sel_shader.to_vector()
                ) / 3.0  # Normalize
                penalty += similarity * diversity_penalty
            
            adjusted_score = dist + penalty
            selected.append((shader, adjusted_score))
        
        return selected
    
    def match_to_song(
        self, 
        song: SongFeatures, 
        top_k: int = 4,
        require_quality: bool = True
    ) -> List[Tuple[ShaderFeatures, float]]:
        """Match shaders to song features (prefers quality shaders by default)"""
        target = song.to_shader_target()
        return self.match_to_features(target, top_k, require_quality=require_quality)
    
    def match_by_mood(
        self, 
        mood: str, 
        energy: float = 0.5,
        top_k: int = 4,
        require_quality: bool = True
    ) -> List[Tuple[ShaderFeatures, float]]:
        """
        Match shaders by mood keyword and energy level.
        Prefers quality (rating 1-2) shaders by default.
        
        Common moods: energetic, calm, dark, bright, psychedelic, 
                      melancholic, aggressive, dreamy, mysterious
        """
        # Map mood keywords to feature targets
        mood_map = {
            'energetic': [0.9, 0.5, 0.6, 0.8, 0.5, 0.7],
            'calm': [0.2, 0.3, 0.4, 0.2, 0.4, 0.3],
            'dark': [0.6, -0.6, 0.3, 0.5, 0.4, 0.6],
            'bright': [0.6, 0.7, 0.7, 0.5, 0.5, 0.5],
            'psychedelic': [0.7, 0.2, 0.5, 0.7, 0.3, 0.8],
            'melancholic': [0.3, -0.5, 0.3, 0.3, 0.4, 0.4],
            'aggressive': [0.95, -0.3, 0.4, 0.9, 0.6, 0.8],
            'dreamy': [0.3, 0.4, 0.5, 0.4, 0.3, 0.5],
            'mysterious': [0.5, -0.2, 0.4, 0.4, 0.5, 0.5],
            'happy': [0.7, 0.8, 0.7, 0.6, 0.4, 0.5],
            'sad': [0.3, -0.7, 0.3, 0.2, 0.4, 0.4],
        }
        
        target = mood_map.get(mood.lower(), [0.5, 0.0, 0.5, 0.5, 0.5, 0.5])
        
        # Adjust energy
        target[0] = energy
        target[3] = target[3] * 0.5 + energy * 0.5  # Motion follows energy
        
        return self.match_to_features(target, top_k, require_quality=require_quality)
    
    def get_stats(self) -> Dict:
        """Get statistics about loaded shaders including rating breakdown"""
        if not self.shaders:
            return {'count': 0}
        
        has_features = sum(1 for s in self.shaders 
                          if s.energy_score != 0.5 or s.mood_valence != 0.0)
        
        # Rating breakdown
        rating_counts = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}
        for s in self.shaders:
            rating_counts[s.get_effective_rating()] += 1
        
        return {
            'count': len(self.shaders),
            'with_features': has_features,
            'without_features': len(self.shaders) - has_features,
            'avg_energy': sum(s.energy_score for s in self.shaders) / len(self.shaders),
            'avg_motion': sum(s.motion_speed for s in self.shaders) / len(self.shaders),
            'rating_best': rating_counts[1],
            'rating_good': rating_counts[2],
            'rating_normal': rating_counts[3],
            'rating_mask': rating_counts[4],
            'rating_skip': rating_counts[5],
            'quality_count': rating_counts[1] + rating_counts[2],
        }


# =============================================================================
# SHADER INDEXER - ChromaDB sync and LLM analysis orchestration
# =============================================================================

class ShaderIndexer:
    """
    Orchestrates shader analysis and ChromaDB indexing.
    
    Source of truth: JSON files (.analysis.json)
    ChromaDB: Derived vector index for fast similarity search
    
    Workflow:
        1. sync() - Scan shaders, sync JSON→ChromaDB
        2. get_unanalyzed() - Find shaders without .analysis.json
        3. analyze_shader() - LLM analysis, writes JSON
    """
    
    # Base shaders directory (parent of isf/ and glsl/)
    DEFAULT_SHADERS_BASE = os.path.join(
        os.path.dirname(__file__),
        '..', 'processing-vj', 'src', 'VJUniverse', 'data', 'shaders'
    )
    
    # Screenshots directory
    DEFAULT_SCREENSHOTS_DIR = os.path.join(
        os.path.dirname(__file__),
        '..', 'processing-vj', 'src', 'VJUniverse', 'data', 'screenshots'
    )
    
    # Shader type configurations: (subfolder, extension, prefix)
    SHADER_TYPES = {
        'isf': ('isf', '.fs', 'isf'),
        'glsl': ('glsl', '.txt', 'glsl'),
    }
    
    # Feature vector dimension names (must match ShaderFeatures order)
    FEATURE_NAMES = [
        'energy_score', 'mood_valence', 'color_warmth',
        'motion_speed', 'geometric_score', 'visual_density'
    ]
    
    def __init__(
        self,
        shaders_dir: Optional[str] = None,
        chromadb_path: Optional[str] = None,
        use_chromadb: bool = True
    ):
        # shaders_dir can be base (containing isf/, glsl/) or a specific type folder
        base_dir = Path(shaders_dir or self.DEFAULT_SHADERS_BASE).resolve()
        
        # Auto-detect: if pointing to isf/ or glsl/, go up one level
        if base_dir.name in ('isf', 'glsl'):
            self.shaders_base = base_dir.parent
        else:
            self.shaders_base = base_dir
        
        # For backwards compatibility, keep shaders_dir pointing to ISF
        self.shaders_dir = self.shaders_base / 'isf'
        self.glsl_dir = self.shaders_base / 'glsl'
        
        # Screenshots directory (sibling to shaders)
        self.screenshots_dir = Path(self.DEFAULT_SCREENSHOTS_DIR).resolve()
        
        self.shaders: Dict[str, ShaderFeatures] = {}  # name → features (prefixed)
        self._chromadb_client = None
        self._collection = None  # Feature vectors collection
        self._text_collection = None  # Text/semantic search collection
        self._use_chromadb = use_chromadb
        
        if use_chromadb:
            self._init_chromadb(chromadb_path)
    
    def _init_chromadb(self, path: Optional[str] = None):
        """Initialize ChromaDB client and collections."""
        try:
            import chromadb
            from chromadb.config import Settings
            
            db_path = path or os.path.join(
                os.path.dirname(__file__), '.chromadb', 'shaders'
            )
            os.makedirs(db_path, exist_ok=True)
            
            self._chromadb_client = chromadb.PersistentClient(
                path=db_path,
                settings=Settings(anonymized_telemetry=False)
            )
            
            # Collection for feature vectors (numeric similarity)
            self._collection = self._chromadb_client.get_or_create_collection(
                name="shader_features",
                metadata={"hnsw:space": "cosine"}
            )
            
            # Collection for semantic text search (uses default embedding)
            self._text_collection = self._chromadb_client.get_or_create_collection(
                name="shader_text",
                metadata={"hnsw:space": "cosine"}
            )
            
            logger.info(f"ChromaDB initialized: {db_path}")
        except ImportError:
            logger.debug("chromadb not installed, using JSON-only mode")
            self._use_chromadb = False
        except Exception as e:
            logger.debug(f"ChromaDB init skipped: {e}")
            self._use_chromadb = False
    
    def scan_shaders(self, use_cache: bool = False) -> Tuple[List[Tuple[Path, str]], List[Tuple[Path, str]]]:
        """
        Scan shader directories for both ISF and GLSL shaders.
        
        Args:
            use_cache: If True and cache exists, return cached results without I/O
        
        Returns:
            (analyzed, unanalyzed) - Lists of (shader_path, shader_type) tuples
            shader_type is 'isf' or 'glsl'
        """
        # Return cached scan if available
        if use_cache and hasattr(self, '_scan_cache') and self._scan_cache:
            return self._scan_cache
        
        analyzed = []
        unanalyzed = []
        
        # Scan ISF shaders (.fs files)
        if self.shaders_dir.exists():
            for shader_file in self.shaders_dir.rglob("*.fs"):
                if shader_file.is_dir():
                    logger.warning(f"Skipping directory with .fs extension: {shader_file}")
                    continue
                if shader_file.stem.endswith('.vs'):
                    continue
                
                analysis_file = shader_file.with_suffix('.analysis.json')
                if analysis_file.exists():
                    analyzed.append((shader_file, 'isf'))
                else:
                    unanalyzed.append((shader_file, 'isf'))
        else:
            logger.warning(f"ISF directory not found: {self.shaders_dir}")
        
        # Scan GLSL shaders (.txt files)
        if self.glsl_dir.exists():
            for shader_file in self.glsl_dir.rglob("*.txt"):
                if shader_file.is_dir():
                    continue
                
                analysis_file = shader_file.with_suffix('.analysis.json')
                if analysis_file.exists():
                    analyzed.append((shader_file, 'glsl'))
                else:
                    unanalyzed.append((shader_file, 'glsl'))
        else:
            logger.debug(f"GLSL directory not found: {self.glsl_dir}")
        
        logger.debug(f"Scanned: {len(analyzed)} analyzed, {len(unanalyzed)} unanalyzed")
        
        # Cache the result
        self._scan_cache = (analyzed, unanalyzed)
        return analyzed, unanalyzed
    
    def sync(self) -> Dict[str, int]:
        """
        Sync JSON analyses to memory (and ChromaDB if enabled).
        
        Returns:
            Stats dict: {loaded, chromadb_synced, text_synced, errors, isf_count, glsl_count}
        """
        stats = {'loaded': 0, 'chromadb_synced': 0, 'text_synced': 0, 'errors': 0, 'isf_count': 0, 'glsl_count': 0}
        self.shaders.clear()
        
        analyzed, _ = self.scan_shaders()
        
        for shader_path, shader_type in analyzed:
            try:
                analysis_path = shader_path.with_suffix('.analysis.json')
                
                # Get base dir for this shader type
                base_dir = self.shaders_dir if shader_type == 'isf' else self.glsl_dir
                
                # Use relative path from type-specific dir as name
                rel_path = shader_path.relative_to(base_dir)
                # Prefixed name: "isf/shadername" or "glsl/shadername"
                name = f"{shader_type}/{str(rel_path.with_suffix('')).replace(chr(92), '/')}"
                
                with open(analysis_path, 'r') as f:
                    data = json.load(f)
                analysis_hash = self._compute_analysis_hash(data)
                
                features = ShaderFeatures.from_analysis_json(str(shader_path), data)
                # Override name with prefixed path-based name
                features.name = name
                self.shaders[name] = features
                features.analysis_hash = analysis_hash  # type: ignore[attr-defined]
                stats['loaded'] += 1
                stats[f'{shader_type}_count'] += 1
                
                # Sync to ChromaDB (feature vectors)
                if self._use_chromadb and self._collection:
                    if self._upsert_to_chromadb(features, analysis_hash):
                        stats['chromadb_synced'] += 1
                
                # Sync to text collection (semantic search)
                if self._use_chromadb and self._text_collection:
                    if self._upsert_text_document(name, data, analysis_hash):
                        stats['text_synced'] += 1
                    
            except Exception as e:
                logger.warning(f"Failed to load {shader_path}: {e}")
                stats['errors'] += 1
        
        logger.info(f"Sync complete: {stats}")
        return stats
    
    def _compute_analysis_hash(self, data: dict) -> str:
        """Compute deterministic hash for analysis JSON content."""
        normalized = json.dumps(data, sort_keys=True, separators=(',', ':'), ensure_ascii=False)
        return hashlib.sha1(normalized.encode('utf-8')).hexdigest()

    def _upsert_to_chromadb(self, features: ShaderFeatures, analysis_hash: str) -> bool:
        """Add or update shader in ChromaDB feature collection.

        Returns True when an upsert occurs, False when existing entry is unchanged.
        """
        if not self._collection:
            return False
        try:
            existing = self._collection.get(ids=[features.name])
        except Exception:
            existing = None

        if existing:
            metadatas = existing.get('metadatas') or []
            if metadatas:
                existing_hash = metadatas[0].get('analysis_hash')
                if existing_hash == analysis_hash:
                    return False
        
        vector = features.to_vector()
        metadata = {
            'path': features.path,
            'mood': features.mood,
            'energy_score': features.energy_score,
            'mood_valence': features.mood_valence,
            'analysis_hash': analysis_hash,
        }
        
        self._collection.upsert(
            ids=[features.name],
            embeddings=[vector],
            metadatas=[metadata]
        )
        return True
    
    def _upsert_text_document(self, name: str, data: dict, analysis_hash: str) -> bool:
        """Add or update shader text document for semantic search.

        Returns True when an upsert occurs, False when existing entry is unchanged.
        """
        if not self._text_collection:
            return False
        try:
            existing = self._text_collection.get(ids=[name])
        except Exception:
            existing = None

        if existing:
            metadatas = existing.get('metadatas') or []
            if metadatas:
                existing_hash = metadatas[0].get('analysis_hash')
                if existing_hash == analysis_hash:
                    return False
        
        # Build searchable document from all text fields
        doc_parts = [
            f"Shader: {name}",
            f"Mood: {data.get('mood', 'unknown')}",
            f"Energy: {data.get('energy', 'medium')}",
            f"Complexity: {data.get('complexity', 'medium')}",
        ]
        
        # Add description
        desc = data.get('description', '')
        if desc:
            doc_parts.append(f"Description: {desc}")
        
        # Add list fields
        colors = data.get('colors', [])
        if colors:
            doc_parts.append(f"Colors: {', '.join(colors)}")
        
        effects = data.get('effects', [])
        if effects:
            doc_parts.append(f"Effects: {', '.join(effects)}")
        
        geometry = data.get('geometry', [])
        if geometry:
            doc_parts.append(f"Geometry: {', '.join(geometry)}")
        
        objects = data.get('objects', [])
        if objects:
            doc_parts.append(f"Objects: {', '.join(objects)}")
        
        # Add input names
        inputs = data.get('inputs', {})
        input_names = inputs.get('inputNames', [])
        if input_names:
            doc_parts.append(f"Controls: {', '.join(input_names)}")
        
        document = ". ".join(doc_parts)
        
        # Store metadata for results
        metadata = {
            'mood': data.get('mood', 'unknown'),
            'energy': data.get('energy', 'medium'),
            'colors': ','.join(data.get('colors', [])),
            'effects': ','.join(data.get('effects', [])),
            'analysis_hash': analysis_hash,
        }
        
        self._text_collection.upsert(
            ids=[name],
            documents=[document],
            metadatas=[metadata]
        )
        return True
    
    def get_unanalyzed(self) -> List[str]:
        """Get list of shader names without analysis (prefixed paths)."""
        _, unanalyzed = self.scan_shaders()
        # Convert paths to prefixed names
        names = []
        for shader_path, shader_type in unanalyzed:
            base_dir = self.shaders_dir if shader_type == 'isf' else self.glsl_dir
            rel_path = shader_path.relative_to(base_dir)
            # Prefixed name: "isf/shadername" or "glsl/shadername"
            name = f"{shader_type}/{str(rel_path.with_suffix('')).replace(chr(92), '/')}"
            names.append(name)
        return names
    
    def get_shader_source(self, name: str) -> Optional[str]:
        """
        Load shader source code by name.
        
        Supports:
        - Prefixed names: 'isf/BitStreamer', 'glsl/acidspace3D'
        - Legacy names (auto-detect): 'BitStreamer' tries ISF then GLSL
        - Subfolder paths: 'isf/subdir/shader'
        """
        # Check for prefix
        if name.startswith('isf/'):
            shader_name = name[4:]  # Remove 'isf/' prefix
            shader_path = self.shaders_dir / f"{shader_name}.fs"
            if shader_path.exists() and not shader_path.is_dir():
                with open(shader_path, 'r') as f:
                    return f.read()
            return None
        
        if name.startswith('glsl/'):
            shader_name = name[5:]  # Remove 'glsl/' prefix
            shader_path = self.glsl_dir / f"{shader_name}.txt"
            if shader_path.exists() and not shader_path.is_dir():
                with open(shader_path, 'r') as f:
                    return f.read()
            return None
        
        # Auto-detect: try ISF first, then GLSL
        # ISF (.fs)
        shader_path = self.shaders_dir / f"{name}.fs"
        if shader_path.exists() and not shader_path.is_dir():
            with open(shader_path, 'r') as f:
                return f.read()
        
        # GLSL (.txt)
        shader_path = self.glsl_dir / f"{name}.txt"
        if shader_path.exists() and not shader_path.is_dir():
            with open(shader_path, 'r') as f:
                return f.read()
        
        return None
    
    def get_screenshot_path(self, name: str) -> Optional[Path]:
        """
        Find screenshot for a shader by name.
        
        Screenshots may be named:
        - {shader_name}.png
        - {shader_name}_{shader_name}.png (ISF naming convention)
        - Without prefix (just the shader name)
        
        Args:
            name: Shader name (may include 'isf/' or 'glsl/' prefix)
        
        Returns:
            Path to screenshot file, or None if not found
        """
        if not self.screenshots_dir.exists():
            return None
        
        # Strip prefix if present
        if name.startswith('isf/') or name.startswith('glsl/'):
            base_name = name.split('/', 1)[1]
        else:
            base_name = name
        
        # Try various naming patterns
        patterns = [
            f"{base_name}.png",
            f"{base_name}_{base_name}.png",  # ISF duplicate naming
            f"{base_name.replace(' ', '')}.png",  # No spaces
            f"{base_name.replace('_', '')}.png",  # No underscores
        ]
        
        for pattern in patterns:
            screenshot_path = self.screenshots_dir / pattern
            if screenshot_path.exists():
                return screenshot_path
        
        # Fuzzy search: find any screenshot that starts with base_name
        for png_file in self.screenshots_dir.glob("*.png"):
            # Normalize both names for comparison
            file_base = png_file.stem.lower().replace('_', '').replace(' ', '').replace('-', '')
            search_base = base_name.lower().replace('_', '').replace(' ', '').replace('-', '')
            
            if file_base.startswith(search_base) or search_base.startswith(file_base):
                return png_file
        
        return None
    
    def parse_isf_inputs(self, source: str) -> ShaderInputs:
        """Parse ISF JSON header to extract input capabilities."""
        # ISF shaders have JSON header between /* and */
        json_start = source.find("/*")
        json_end = source.find("*/")
        
        if json_start < 0 or json_end < 0 or json_end <= json_start:
            return ShaderInputs()  # Not ISF or no header
        
        json_header = source[json_start + 2:json_end].strip()
        
        try:
            # Remove comments (ISF JSON sometimes has // comments)
            lines = []
            for line in json_header.split('\n'):
                # Remove // comments but keep strings intact (simplified)
                comment_pos = line.find('//')
                if comment_pos >= 0:
                    line = line[:comment_pos]
                lines.append(line)
            clean_json = '\n'.join(lines)
            
            isf_data = json.loads(clean_json)
        except json.JSONDecodeError:
            # Try without comment stripping
            try:
                isf_data = json.loads(json_header)
            except json.JSONDecodeError as e:
                logger.debug(f"ISF JSON parse failed: {e}")
                return ShaderInputs()
        
        inputs = ShaderInputs()
        input_names = []
        
        for inp in isf_data.get('INPUTS', []):
            inp_type = inp.get('TYPE', '').lower()
            inp_name = inp.get('NAME', '')
            input_names.append(inp_name)
            
            if inp_type == 'float':
                inputs.float_count += 1
            elif inp_type == 'point2d':
                inputs.point2d_count += 1
            elif inp_type == 'color':
                inputs.color_count += 1
            elif inp_type in ('bool', 'event'):
                inputs.bool_count += 1
            elif inp_type == 'image':
                inputs.image_count += 1
            elif inp_type in ('audio', 'audiofft'):
                inputs.has_audio = True
        
        inputs.input_names = input_names
        return inputs
    
    def parse_glsl_inputs(self, source: str) -> ShaderInputs:
        """
        Parse uniform declarations from plain GLSL shader.
        
        GLSL shaders don't have ISF JSON headers, so we extract
        uniform declarations via regex.
        """
        import re
        
        inputs = ShaderInputs()
        input_names = []
        
        # Pattern: uniform <type> <name>;
        # Handles: uniform float time; uniform vec2 resolution;
        uniform_pattern = re.compile(
            r'uniform\s+(\w+)\s+(\w+)\s*;',
            re.MULTILINE
        )
        
        for match in uniform_pattern.finditer(source):
            uniform_type = match.group(1).lower()
            uniform_name = match.group(2)
            input_names.append(uniform_name)
            
            if uniform_type == 'float':
                inputs.float_count += 1
            elif uniform_type in ('vec2', 'point2d'):
                inputs.point2d_count += 1
            elif uniform_type in ('vec3', 'vec4', 'color'):
                inputs.color_count += 1
            elif uniform_type in ('bool', 'int'):
                inputs.bool_count += 1
            elif uniform_type in ('sampler2d', 'sampler1d'):
                inputs.image_count += 1
        
        inputs.input_names = input_names
        return inputs
    
    def parse_inputs(self, source: str, shader_type: str = 'isf') -> ShaderInputs:
        """
        Parse shader inputs based on shader type.
        
        Args:
            source: Shader source code
            shader_type: 'isf' or 'glsl'
        
        Returns:
            ShaderInputs with parsed capabilities
        """
        if shader_type == 'glsl':
            return self.parse_glsl_inputs(source)
        else:
            return self.parse_isf_inputs(source)
    
    def save_analysis(
        self,
        name: str,
        features: Dict[str, float],
        inputs: ShaderInputs,
        metadata: Dict[str, Any],
        shader_type: str = 'isf'
    ) -> bool:
        """
        Save analysis result to JSON file.
        
        Args:
            name: Shader name (prefixed like 'isf/shader' or unprefixed)
            features: Feature dict {energy_score, mood_valence, ...}
            inputs: Parsed shader inputs
            metadata: Additional fields (mood, colors, description, etc.)
            shader_type: 'isf' or 'glsl'
        
        Returns:
            True if saved successfully
        """
        # Invalidate stats cache when analysis is saved
        self._cached_stats = None
        
        # Handle prefixed names
        if name.startswith('isf/'):
            shader_type = 'isf'
            shader_name = name[4:]
        elif name.startswith('glsl/'):
            shader_type = 'glsl'
            shader_name = name[5:]
        else:
            shader_name = name
        
        # Determine base directory and extension
        if shader_type == 'glsl':
            base_dir = self.glsl_dir
            ext = '.txt'
        else:
            base_dir = self.shaders_dir
            ext = '.fs'
        
        analysis_path = base_dir / f"{shader_name}.analysis.json"
        
        data = {
            'shaderName': name,
            'shaderType': shader_type,
            'extension': ext,
            'analyzedAt': int(os.times().system * 1000),
            'features': features,
            'inputs': {
                'floatCount': inputs.float_count,
                'point2DCount': inputs.point2d_count,
                'colorCount': inputs.color_count,
                'boolCount': inputs.bool_count,
                'imageCount': inputs.image_count,
                'hasAudio': inputs.has_audio,
                'inputNames': inputs.input_names
            },
            **metadata
        }
        
        try:
            with open(analysis_path, 'w') as f:
                json.dump(data, f, indent=2)
            logger.info(f"Saved analysis: {name}")
            return True
        except Exception as e:
            logger.error(f"Failed to save {name}: {e}")
            return False
    
    def save_error(self, name: str, error: str, details: Optional[Dict[str, Any]] = None) -> bool:
        """
        Save analysis error to .error.json file.
        
        This marks a shader as attempted-but-failed so we don't retry forever.
        Delete the .error.json to retry analysis.
        
        Args:
            name: Shader name (prefixed like 'isf/shader' or unprefixed)
            error: Error message
            details: Optional additional error details
        
        Returns:
            True if saved successfully
        """
        import time
        
        # Handle prefixed names (same logic as save_analysis)
        shader_type = 'isf'
        if name.startswith('isf/'):
            shader_type = 'isf'
            shader_name = name[4:]
        elif name.startswith('glsl/'):
            shader_type = 'glsl'
            shader_name = name[5:]
        else:
            shader_name = name
        
        # Determine base directory
        base_dir = self.glsl_dir if shader_type == 'glsl' else self.shaders_dir
        error_path = base_dir / f"{shader_name}.error.json"
        
        data = {
            'shaderName': name,
            'shaderType': shader_type,
            'error': error,
            'failedAt': time.strftime('%Y-%m-%d %H:%M:%S'),
            'timestamp': int(time.time()),
            **(details or {})
        }
        
        try:
            with open(error_path, 'w') as f:
                json.dump(data, f, indent=2)
            logger.warning(f"Saved error for {name}: {error}")
            return True
        except Exception as e:
            logger.error(f"Failed to save error for {name}: {e}")
            return False
    
    def query_similar(
        self,
        target_vector: List[float],
        top_k: int = 5
    ) -> List[Tuple[str, float]]:
        """
        Query ChromaDB for similar shaders.
        
        Args:
            target_vector: 6D feature vector
            top_k: Number of results
        
        Returns:
            List of (shader_name, distance) tuples
        """
        if not self._use_chromadb or not self._collection:
            # Fallback to in-memory search
            return self._query_memory(target_vector, top_k)
        
        try:
            results = self._collection.query(
                query_embeddings=[target_vector],
                n_results=top_k
            )
            
            pairs = []
            ids_list = results.get('ids', [[]])[0]
            distances_list = results.get('distances') or [[]]
            for i, shader_id in enumerate(ids_list):
                distance = distances_list[0][i] if distances_list and len(distances_list[0]) > i else 0.0
                pairs.append((shader_id, distance))
            return pairs
            
        except Exception as e:
            logger.warning(f"ChromaDB query failed: {e}")
            return self._query_memory(target_vector, top_k)
    
    def _query_memory(
        self,
        target: List[float],
        top_k: int
    ) -> List[Tuple[str, float]]:
        """In-memory fallback for similarity search."""
        scored = []
        for name, features in self.shaders.items():
            dist = self._cosine_distance(features.to_vector(), target)
            scored.append((name, dist))
        
        scored.sort(key=lambda x: x[1])
        return scored[:top_k]
    
    @staticmethod
    def _cosine_distance(v1: List[float], v2: List[float]) -> float:
        """Calculate cosine distance (1 - cosine_similarity)."""
        dot = sum(a * b for a, b in zip(v1, v2))
        mag1 = math.sqrt(sum(a * a for a in v1))
        mag2 = math.sqrt(sum(b * b for b in v2))
        
        if mag1 == 0 or mag2 == 0:
            return 1.0  # Max distance
        
        return 1.0 - (dot / (mag1 * mag2))
    
    def get_all_features(self) -> List[ShaderFeatures]:
        """Get all loaded shader features."""
        return list(self.shaders.values())
    
    def text_search(self, query: str, top_k: int = 10) -> List[Tuple[str, float, Dict]]:
        """
        Semantic search for shaders by text query.
        
        Uses ChromaDB's embedding-based search for semantic similarity.
        Falls back to keyword search if ChromaDB unavailable.
        
        Searches across: name, mood, colors, effects, description, geometry, 
                        objects, energy, complexity, inputNames
        
        Args:
            query: Natural language search query (e.g., "colorful waves", "dark psychedelic")
            top_k: Number of results to return
        
        Returns:
            List of (shader_name, distance, features_dict) tuples sorted by relevance
        """
        query = query.strip()
        if not query:
            return []
        
        # Try semantic search via ChromaDB
        if self._use_chromadb and self._text_collection:
            try:
                results = self._text_collection.query(
                    query_texts=[query],
                    n_results=top_k,
                    include=['metadatas', 'distances', 'documents']
                )
                
                output = []
                ids_result = results.get('ids') or [[]]
                distances_result = results.get('distances') or [[]]
                metadatas_result = results.get('metadatas') or [[]]
                
                ids = ids_result[0] if ids_result else []
                distances = distances_result[0] if distances_result else []
                metadatas = metadatas_result[0] if metadatas_result else []
                
                for i, shader_id in enumerate(ids):
                    distance = float(distances[i]) if i < len(distances) else 1.0
                    metadata = metadatas[i] if i < len(metadatas) else {}
                    
                    # Load full features from memory if available
                    colors_val = metadata.get('colors', '') if isinstance(metadata, dict) else ''
                    effects_val = metadata.get('effects', '') if isinstance(metadata, dict) else ''
                    features = {
                        'mood': metadata.get('mood', 'unknown') if isinstance(metadata, dict) else 'unknown',
                        'energy': metadata.get('energy', 'medium') if isinstance(metadata, dict) else 'medium',
                        'colors': str(colors_val).split(',') if colors_val else [],
                        'effects': str(effects_val).split(',') if effects_val else [],
                    }
                    
                    # Add numeric features if shader is in memory
                    if shader_id in self.shaders:
                        sf = self.shaders[shader_id]
                        features['energy_score'] = sf.energy_score
                        features['mood_valence'] = sf.mood_valence
                    
                    output.append((shader_id, distance, features))
                
                return output
                
            except Exception as e:
                logger.warning(f"ChromaDB semantic search failed: {e}, falling back to keyword")
        
        # Fallback: keyword-based search
        return self._keyword_search(query, top_k)
    
    def _keyword_search(self, query: str, top_k: int) -> List[Tuple[str, float, Dict]]:
        """Fallback keyword search when ChromaDB unavailable."""
        query_lower = query.lower()
        results = []
        analyzed, _ = self.scan_shaders()
        
        for shader_path, shader_type in analyzed:
            try:
                # Get prefixed name
                base_dir = self.shaders_dir if shader_type == 'isf' else self.glsl_dir
                rel_path = shader_path.relative_to(base_dir)
                name = f"{shader_type}/{str(rel_path.with_suffix('')).replace(chr(92), '/')}"
                
                analysis_path = shader_path.with_suffix('.analysis.json')
                with open(analysis_path, 'r') as f:
                    data = json.load(f)
                
                # Build searchable text
                searchable_parts = [
                    data.get('shaderName', ''),
                    data.get('mood', ''),
                    data.get('description', ''),
                    data.get('energy', ''),
                    data.get('complexity', ''),
                ]
                searchable_parts.extend(data.get('colors', []))
                searchable_parts.extend(data.get('effects', []))
                searchable_parts.extend(data.get('geometry', []))
                searchable_parts.extend(data.get('objects', []))
                searchable_parts.extend(data.get('inputs', {}).get('inputNames', []))
                
                searchable_text = ' '.join(str(p) for p in searchable_parts).lower()
                
                # Score by occurrence count
                score = 0.0
                for word in query_lower.split():
                    if word in searchable_text:
                        score += searchable_text.count(word)
                        if word in name.lower():
                            score += 3.0
                        if word == data.get('mood', '').lower():
                            score += 2.0
                
                if score > 0:
                    features = {
                        'energy_score': data.get('features', {}).get('energy_score', 0.5),
                        'mood': data.get('mood', 'unknown'),
                        'colors': data.get('colors', []),
                        'effects': data.get('effects', []),
                        'description': data.get('description', '')[:80],
                    }
                    # Convert score to distance (lower = better)
                    results.append((name, 1.0 / (1.0 + score), features))
                    
            except Exception as e:
                logger.debug(f"Failed to search {shader_path}: {e}")
        
        results.sort(key=lambda x: x[1])
        return results[:top_k]
    
    def get_stats(self, use_cache: bool = True) -> Dict[str, Any]:
        """Get indexer statistics.
        
        Args:
            use_cache: If True, return cached stats (fast). If False, rescan directories.
        """
        # Return cached stats if available and cache requested
        if use_cache and hasattr(self, '_cached_stats') and self._cached_stats:
            return self._cached_stats
        
        analyzed, unanalyzed = self.scan_shaders()
        
        self._cached_stats = {
            'shaders_dir': str(self.shaders_dir),
            'total_shaders': len(analyzed) + len(unanalyzed),
            'analyzed': len(analyzed),
            'unanalyzed': len(unanalyzed),
            'loaded_in_memory': len(self.shaders),
            'chromadb_enabled': self._use_chromadb,
            'chromadb_count': self._collection.count() if self._collection else 0
        }
        return self._cached_stats
    
    def invalidate_stats_cache(self):
        """Clear cached stats and scan results to force rescan on next get_stats()."""
        self._cached_stats = None
        self._scan_cache = None


# =============================================================================
# SHADER SELECTOR - Session-aware shader selection with usage tracking
# =============================================================================

@dataclass
class ShaderMatch:
    """Result from shader selection."""
    name: str
    path: str
    score: float           # Lower = better match
    usage_count: int       # Times used this session
    features: ShaderFeatures


class ShaderSelector:
    """
    Session-aware shader selection with usage tracking.
    
    Combines feature-based matching with variety preference:
    - Tracks usage counts during session
    - Penalizes frequently used shaders
    - Uses ChromaDB for fast similarity queries
    
    Usage:
        selector = ShaderSelector(indexer)
        match = selector.select_for_song(song_features)
        if match:
            load_shader(match.name)
    """
    
    # Penalty applied per usage (higher = prefer variety more)
    USAGE_PENALTY = 0.15
    
    def __init__(self, indexer: ShaderIndexer):
        self.indexer = indexer
        self._usage_counts: Dict[str, int] = {}  # shader_name → count
        self._last_selected: Optional[str] = None
        self._warned_shaders: set = set()  # Track warned shaders to avoid spam
    
    def reset_usage(self):
        """Reset usage tracking (e.g., at session start)."""
        self._usage_counts.clear()
        self._last_selected = None
        logger.info("Shader usage counts reset")
    
    def get_usage(self, name: str) -> int:
        """Get usage count for a shader."""
        return self._usage_counts.get(name, 0)
    
    def _record_usage(self, name: str):
        """Record that a shader was selected."""
        self._usage_counts[name] = self._usage_counts.get(name, 0) + 1
        self._last_selected = name
    
    def select_for_song(
        self,
        song_features: SongFeatures,
        top_k: int = 5,
        exclude_last: bool = True,
        require_quality: bool = True
    ) -> Optional[ShaderMatch]:
        """
        Select best shader for a song with variety preference.
        
        Args:
            song_features: Song feature vector
            top_k: Number of candidates to consider
            exclude_last: Skip the last selected shader
            require_quality: Only consider rating 1-2 shaders (default True)
        
        Returns:
            ShaderMatch or None if no shaders available
        """
        target = song_features.to_shader_target()
        
        # Query candidates from ChromaDB
        candidates = self.indexer.query_similar(target, top_k=top_k * 2)
        
        if not candidates:
            logger.warning("No shader candidates found")
            return None
        
        # Score with usage penalty, filter by quality
        scored = []
        for name, distance in candidates:
            # Skip last selected if requested
            if exclude_last and name == self._last_selected:
                continue
            
            # Get features to check rating
            features = self.indexer.shaders.get(name)
            if not features:
                continue
            
            # Filter by rating
            if not features.is_usable():
                continue  # Skip rating=5 (SKIP)
            if require_quality and not features.is_quality_shader():
                continue  # Skip non-quality (rating 3-4)
            
            # Apply usage penalty
            usage = self.get_usage(name)
            penalty = usage * self.USAGE_PENALTY
            adjusted_score = distance + penalty
            
            # Boost quality shaders
            if features.is_quality_shader():
                adjusted_score *= 0.9
            
            scored.append((name, adjusted_score, distance, usage))
        
        if not scored:
            # All excluded, fall back to any candidate
            name, distance = candidates[0]
            scored = [(name, distance, distance, self.get_usage(name))]
        
        # Sort by adjusted score
        scored.sort(key=lambda x: x[1])
        
        # Select best
        best_name, adj_score, orig_dist, usage = scored[0]
        
        # Get features
        features = self.indexer.shaders.get(best_name)
        if not features:
            # Only warn once per shader (not every poll cycle)
            if best_name not in self._warned_shaders:
                logger.warning(f"No features for '{best_name}' - may need re-sync")
                self._warned_shaders.add(best_name)
            return None
        
        # Record usage
        self._record_usage(best_name)
        
        logger.info(f"Selected shader: {best_name} (score={adj_score:.2f}, usage={usage})")
        
        return ShaderMatch(
            name=best_name,
            path=features.path,
            score=adj_score,
            usage_count=usage + 1,  # After increment
            features=features
        )
    
    def select_by_mood(
        self,
        mood: str,
        energy: float = 0.5,
        valence: float = 0.0,
        top_k: int = 5,
        require_quality: bool = True
    ) -> Optional[ShaderMatch]:
        """
        Select shader by mood keyword with variety preference.
        Prefers quality shaders (rating 1-2) by default.
        
        Args:
            mood: Mood keyword (energetic, calm, dark, bright, etc.)
            energy: Energy level 0-1
            valence: Mood valence -1 to 1
            top_k: Number of candidates
            require_quality: Only consider rating 1-2 shaders
        
        Returns:
            ShaderMatch or None
        """
        # Create pseudo song features from mood
        song = SongFeatures(
            title=f"mood_{mood}",
            energy=energy,
            valence=valence,
            tempo_normalized=energy * 0.7,
            danceability=energy,
            acousticness=0.3 if mood in ('calm', 'dreamy', 'melancholic') else 0.7,
            loudness_normalized=energy
        )
        return self.select_for_song(song, top_k=top_k, require_quality=require_quality)
    
    def get_random_shader(self, require_quality: bool = True) -> Optional[ShaderMatch]:
        """
        Get a random shader, preferring quality shaders.
        
        Args:
            require_quality: Only consider rating 1-2 shaders
        
        Returns:
            ShaderMatch or None
        """
        import random
        
        # Filter candidates by rating
        candidates = []
        for name, features in self.indexer.shaders.items():
            if not features.is_usable():
                continue
            if require_quality and not features.is_quality_shader():
                continue
            candidates.append((name, features))
        
        if not candidates:
            # Fallback to all usable shaders
            candidates = [
                (name, features) 
                for name, features in self.indexer.shaders.items()
                if features.is_usable()
            ]
        
        if not candidates:
            return None
        
        name, features = random.choice(candidates)
        usage = self.get_usage(name)
        self._record_usage(name)
        
        return ShaderMatch(
            name=name,
            path=features.path,
            score=0.5,  # Neutral score for random
            usage_count=usage + 1,
            features=features
        )
    
    def get_stats(self) -> Dict[str, Any]:
        """Get selector statistics."""
        total_uses = sum(self._usage_counts.values())
        unique_used = len(self._usage_counts)
        
        return {
            'total_selections': total_uses,
            'unique_shaders_used': unique_used,
            'available_shaders': len(self.indexer.shaders),
            'last_selected': self._last_selected,
            'top_used': sorted(
                self._usage_counts.items(),
                key=lambda x: x[1],
                reverse=True
            )[:5]
        }


# CLI usage
if __name__ == '__main__':
    import sys
    
    logging.basicConfig(level=logging.INFO, format='%(name)s: %(message)s')
    
    # Default path
    shaders_dir = os.path.join(
        os.path.dirname(__file__), 
        '..', 'processing-vj', 'src', 'VJUniverse', 'data', 'shaders', 'isf'
    )
    
    if len(sys.argv) > 1:
        shaders_dir = sys.argv[1]
    
    print("\n=== ShaderIndexer ===")
    indexer = ShaderIndexer(shaders_dir)
    
    # Sync from JSON
    stats = indexer.sync()
    print(f"Sync stats: {stats}")
    
    # Show unanalyzed
    unanalyzed = indexer.get_unanalyzed()
    if unanalyzed:
        print(f"\nUnanalyzed shaders ({len(unanalyzed)}):")
        for name in unanalyzed[:5]:
            print(f"  - {name}")
        if len(unanalyzed) > 5:
            print(f"  ... and {len(unanalyzed) - 5} more")
    
    # Test matcher with indexer data
    print("\n=== ShaderMatcher ===")
    matcher = ShaderMatcher(shaders_dir)
    
    match_stats = matcher.get_stats()
    print(f"Loaded: {match_stats['count']} shaders")
    print(f"  With features: {match_stats.get('with_features', 0)}")
    
    if match_stats['count'] > 0:
        print("\nTest: 'energetic' mood, energy=0.8")
        matches = matcher.match_by_mood('energetic', energy=0.8, top_k=4)
        for shader, score in matches:
            print(f"  {shader.name}: {score:.3f} (energy={shader.energy_score:.2f})")
        
        print("\nTest: 'calm' mood, energy=0.2")
        matches = matcher.match_by_mood('calm', energy=0.2, top_k=4)
        for shader, score in matches:
            print(f"  {shader.name}: {score:.3f} (energy={shader.energy_score:.2f})")
