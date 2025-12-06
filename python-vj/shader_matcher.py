"""
Shader Matcher - Feature-based shader-to-music matching

Multi-dimensional semantic matching using normalized feature vectors.
Features: energy_score, mood_valence, color_warmth, motion_speed, geometric_score, visual_density

Architecture:
    - ShaderIndexer: ChromaDB sync, LLM analysis orchestration
    - ShaderMatcher: Feature-based matching (from indexed shaders)
    - JSON files are source of truth, ChromaDB is derived index

Usage:
    indexer = ShaderIndexer()
    await indexer.sync()  # JSON → ChromaDB, analyze unanalyzed
    matcher = ShaderMatcher(indexer)
    matches = matcher.match_by_mood("energetic", energy=0.8)
"""

import json
import os
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
            inputs=ShaderInputs.from_dict(inputs_data),
            mood=data.get('mood', 'unknown'),
            colors=data.get('colors', []),
            effects=data.get('effects', [])
        )


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
        """Load all shader analyses from directory"""
        self.shaders = []
        shaders_path = Path(shaders_dir)
        
        # Find all .analysis.json files
        for analysis_file in shaders_path.rglob("*.analysis.json"):
            try:
                with open(analysis_file, 'r') as f:
                    data = json.load(f)
                
                # Get corresponding shader path
                shader_path = str(analysis_file).replace('.analysis.json', '.fs')
                if not os.path.exists(shader_path):
                    shader_path = str(analysis_file).replace('.analysis.json', '.glsl')
                
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
        require_autonomous: bool = False
    ) -> List[ShaderFeatures]:
        """Filter shaders by input capabilities"""
        result = []
        for shader in self.shaders:
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
        diversity_penalty: float = 0.3
    ) -> List[Tuple[ShaderFeatures, float]]:
        """
        Find best matching shaders for target feature vector.
        
        Args:
            target: Target feature vector [energy, mood, warmth, motion, geometric, density]
            top_k: Number of shaders to return
            diversity_penalty: Penalty for similar shaders (0=no penalty, 1=max penalty)
        
        Returns:
            List of (shader, score) tuples, sorted by score (lower is better)
        """
        if not self.shaders:
            return []
        
        # Calculate distances
        scored = []
        for shader in self.shaders:
            dist = self.weighted_distance(shader.to_vector(), target)
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
        top_k: int = 4
    ) -> List[Tuple[ShaderFeatures, float]]:
        """Match shaders to song features"""
        target = song.to_shader_target()
        return self.match_to_features(target, top_k)
    
    def match_by_mood(
        self, 
        mood: str, 
        energy: float = 0.5,
        top_k: int = 4
    ) -> List[Tuple[ShaderFeatures, float]]:
        """
        Match shaders by mood keyword and energy level.
        
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
        
        return self.match_to_features(target, top_k)
    
    def get_stats(self) -> Dict:
        """Get statistics about loaded shaders"""
        if not self.shaders:
            return {'count': 0}
        
        has_features = sum(1 for s in self.shaders 
                          if s.energy_score != 0.5 or s.mood_valence != 0.0)
        
        return {
            'count': len(self.shaders),
            'with_features': has_features,
            'without_features': len(self.shaders) - has_features,
            'avg_energy': sum(s.energy_score for s in self.shaders) / len(self.shaders),
            'avg_motion': sum(s.motion_speed for s in self.shaders) / len(self.shaders),
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
    
    # Fixed path to ISF shaders (relative to this file)
    DEFAULT_SHADERS_DIR = os.path.join(
        os.path.dirname(__file__),
        '..', 'processing-vj', 'src', 'VJUniverse', 'data', 'shaders', 'isf'
    )
    
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
        self.shaders_dir = Path(shaders_dir or self.DEFAULT_SHADERS_DIR).resolve()
        self.shaders: Dict[str, ShaderFeatures] = {}  # name → features
        self._chromadb_client = None
        self._collection = None
        self._use_chromadb = use_chromadb
        
        if use_chromadb:
            self._init_chromadb(chromadb_path)
    
    def _init_chromadb(self, path: Optional[str] = None):
        """Initialize ChromaDB client and collection."""
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
            self._collection = self._chromadb_client.get_or_create_collection(
                name="shader_features",
                metadata={"hnsw:space": "cosine"}  # Cosine similarity
            )
            logger.info(f"ChromaDB initialized: {db_path}")
        except ImportError:
            logger.debug("chromadb not installed, using JSON-only mode")
            self._use_chromadb = False
        except Exception as e:
            logger.debug(f"ChromaDB init skipped: {e}")
            self._use_chromadb = False
    
    def scan_shaders(self) -> Tuple[List[str], List[str]]:
        """
        Scan shader directory.
        
        Returns:
            (analyzed, unanalyzed) - Lists of shader names
        """
        analyzed = []
        unanalyzed = []
        
        if not self.shaders_dir.exists():
            logger.error(f"Shaders directory not found: {self.shaders_dir}")
            return [], []
        
        # Find all .fs files (ISF shaders)
        for shader_file in self.shaders_dir.glob("*.fs"):
            name = shader_file.stem
            analysis_file = shader_file.with_suffix('.analysis.json')
            
            if analysis_file.exists():
                analyzed.append(name)
            else:
                unanalyzed.append(name)
        
        logger.info(f"Scanned: {len(analyzed)} analyzed, {len(unanalyzed)} unanalyzed")
        return analyzed, unanalyzed
    
    def sync(self) -> Dict[str, int]:
        """
        Sync JSON analyses to memory (and ChromaDB if enabled).
        
        Returns:
            Stats dict: {loaded, chromadb_synced, errors}
        """
        stats = {'loaded': 0, 'chromadb_synced': 0, 'errors': 0}
        self.shaders.clear()
        
        analyzed, _ = self.scan_shaders()
        
        for name in analyzed:
            try:
                analysis_path = self.shaders_dir / f"{name}.analysis.json"
                shader_path = self.shaders_dir / f"{name}.fs"
                
                with open(analysis_path, 'r') as f:
                    data = json.load(f)
                
                features = ShaderFeatures.from_analysis_json(str(shader_path), data)
                self.shaders[name] = features
                stats['loaded'] += 1
                
                # Sync to ChromaDB
                if self._use_chromadb and self._collection:
                    self._upsert_to_chromadb(features)
                    stats['chromadb_synced'] += 1
                    
            except Exception as e:
                logger.warning(f"Failed to load {name}: {e}")
                stats['errors'] += 1
        
        logger.info(f"Sync complete: {stats}")
        return stats
    
    def _upsert_to_chromadb(self, features: ShaderFeatures):
        """Add or update shader in ChromaDB."""
        if not self._collection:
            return
        
        vector = features.to_vector()
        metadata = {
            'path': features.path,
            'mood': features.mood,
            'energy_score': features.energy_score,
            'mood_valence': features.mood_valence,
        }
        
        self._collection.upsert(
            ids=[features.name],
            embeddings=[vector],
            metadatas=[metadata]
        )
    
    def get_unanalyzed(self) -> List[str]:
        """Get list of shader names without analysis."""
        _, unanalyzed = self.scan_shaders()
        return unanalyzed
    
    def get_shader_source(self, name: str) -> Optional[str]:
        """Load shader source code."""
        shader_path = self.shaders_dir / f"{name}.fs"
        if not shader_path.exists():
            return None
        
        with open(shader_path, 'r') as f:
            return f.read()
    
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
    
    def save_analysis(
        self,
        name: str,
        features: Dict[str, float],
        inputs: ShaderInputs,
        metadata: Dict[str, Any]
    ) -> bool:
        """
        Save analysis result to JSON file.
        
        Args:
            name: Shader name (without extension)
            features: Feature dict {energy_score, mood_valence, ...}
            inputs: Parsed ISF inputs
            metadata: Additional fields (mood, colors, description, etc.)
        
        Returns:
            True if saved successfully
        """
        analysis_path = self.shaders_dir / f"{name}.analysis.json"
        
        data = {
            'shaderName': name,
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
            name: Shader name (without extension)
            error: Error message
            details: Optional additional error details
        
        Returns:
            True if saved successfully
        """
        import time
        error_path = self.shaders_dir / f"{name}.error.json"
        
        data = {
            'shaderName': name,
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
            for i, shader_id in enumerate(results['ids'][0]):
                distance = results['distances'][0][i] if results.get('distances') else 0.0
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
    
    def get_stats(self) -> Dict[str, Any]:
        """Get indexer statistics."""
        analyzed, unanalyzed = self.scan_shaders()
        
        return {
            'shaders_dir': str(self.shaders_dir),
            'total_shaders': len(analyzed) + len(unanalyzed),
            'analyzed': len(analyzed),
            'unanalyzed': len(unanalyzed),
            'loaded_in_memory': len(self.shaders),
            'chromadb_enabled': self._use_chromadb,
            'chromadb_count': self._collection.count() if self._collection else 0
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
