"""Shader analysis background worker service."""

import logging
import threading
import time
from typing import List, Optional

logger = logging.getLogger('vj_console.shader_analysis')


class ShaderAnalysisWorker:
    """
    Background worker that analyzes unanalyzed shaders using LLM.

    Scans once on start, then processes the queue. Does NOT continuously re-scan.
    Call rescan() to refresh the queue if new shaders are added.
    """

    MAX_RECENT = 10  # Keep last N analyses for display

    def __init__(self, indexer, llm_analyzer):
        self.indexer = indexer
        self.llm = llm_analyzer
        self._thread: Optional[threading.Thread] = None
        self._running = False
        self._paused = True  # Start paused, user must press 'p' to begin
        self._lock = threading.Lock()
        self._queue: List[str] = []  # Queue of shader names to analyze
        self._scanned = False
        self._recent: List[dict] = []  # Recent analysis results for UI

        # Status for UI
        self.status = {
            'running': False,
            'paused': True,
            'current_shader': '',
            'progress': 0,
            'total': 0,
            'analyzed': 0,
            'errors': 0,
            'last_error': '',
            'queue': [],
            'recent': []
        }

    def start(self):
        """Start the analysis worker thread."""
        if self._thread and self._thread.is_alive():
            return

        self._running = True
        self._thread = threading.Thread(target=self._run, daemon=True, name="ShaderAnalysis")
        self._thread.start()
        logger.info("Shader analysis worker started")

    def stop(self):
        """Stop the worker thread."""
        self._running = False
        if self._thread:
            self._thread.join(timeout=2.0)
        logger.info("Shader analysis worker stopped")

    def toggle_pause(self):
        """Toggle pause state."""
        with self._lock:
            self._paused = not self._paused
            self.status['paused'] = self._paused
            logger.info(f"Shader analysis {'paused' if self._paused else 'resumed'}")

    def rescan(self):
        """Rescan for unanalyzed shaders and rebuild queue."""
        with self._lock:
            self._queue = self.indexer.get_unanalyzed()
            self.status['total'] = len(self._queue) + self.status['analyzed']
            self.status['queue'] = self._queue[:5]
            logger.info(f"Rescanned: {len(self._queue)} shaders in queue")

    def is_paused(self) -> bool:
        return self._paused

    def _run(self):
        """Main worker loop - scans once, then processes queue."""
        # Initial scan (once)
        if not self._scanned:
            with self._lock:
                self._queue = self.indexer.get_unanalyzed()
                self.status['total'] = len(self._queue)
                self.status['queue'] = self._queue[:5]
                self._scanned = True
                logger.info(f"Initial scan: {len(self._queue)} unanalyzed shaders")

        while self._running:
            # Check if paused
            if self._paused:
                self.status['running'] = False
                time.sleep(0.5)
                continue

            # Check if queue is empty
            with self._lock:
                if not self._queue:
                    self.status['running'] = False
                    self.status['current_shader'] = ''
                    # Don't rescan - just wait. User can press 'r' to rescan.
                    time.sleep(1.0)
                    continue

                # Get next shader from queue
                shader_name = self._queue[0]

            self.status['running'] = True
            self.status['current_shader'] = shader_name
            self.status['queue'] = self._queue[:5]

            try:
                # Get shader source
                source = self.indexer.get_shader_source(shader_name)
                if not source:
                    logger.warning(f"Could not read shader: {shader_name}")
                    self.status['errors'] += 1
                    self.status['last_error'] = f"Could not read {shader_name}"
                    # Remove from queue even on error
                    with self._lock:
                        if shader_name in self._queue:
                            self._queue.remove(shader_name)
                    continue

                # Check for screenshot (most significant for analysis)
                screenshot_path = self.indexer.get_screenshot_path(shader_name)
                screenshot_str = str(screenshot_path) if screenshot_path else None

                # Analyze with LLM (includes screenshot if available)
                if screenshot_path:
                    logger.info(f"Analyzing shader with screenshot: {shader_name}")
                else:
                    logger.info(f"Analyzing shader (no screenshot): {shader_name}")

                result = self.llm.analyze_shader(shader_name, source, screenshot_path=screenshot_str)

                if result and 'error' not in result:
                    # Parse ISF inputs
                    inputs = self.indexer.parse_isf_inputs(source)

                    # Extract features
                    features = result.get('features', {})

                    # Extract audio mapping
                    audio_mapping = result.get('audioMapping', {})

                    # Build metadata dict
                    metadata = {
                        'mood': result.get('mood', 'unknown'),
                        'colors': result.get('colors', []),
                        'effects': result.get('effects', []),
                        'description': result.get('description', ''),
                        'geometry': result.get('geometry', []),
                        'objects': result.get('objects', []),
                        'energy': result.get('energy', 'medium'),
                        'complexity': result.get('complexity', 'medium'),
                        'audioMapping': audio_mapping,
                        'has_screenshot': result.get('has_screenshot', False)
                    }

                    # Include screenshot analysis data if present
                    if 'screenshot' in result:
                        metadata['screenshot'] = result['screenshot']

                    # Save analysis
                    success = self.indexer.save_analysis(
                        shader_name,
                        features,
                        inputs,
                        metadata
                    )

                    if success:
                        self.status['analyzed'] += 1
                        self.status['progress'] = self.status['analyzed']

                        # Track recent analysis for UI
                        with self._lock:
                            self._recent.insert(0, {
                                'name': shader_name,
                                'mood': result.get('mood', '?'),
                                'energy': result.get('energy', '?'),
                                'colors': result.get('colors', [])[:2],
                                'features': features,
                                'has_screenshot': result.get('has_screenshot', False)
                            })
                            self._recent = self._recent[:self.MAX_RECENT]
                            self.status['recent'] = self._recent.copy()

                        # Sync to ChromaDB
                        self.indexer.sync()
                        logger.info(f"Analyzed and saved: {shader_name}")
                    else:
                        self.status['errors'] += 1
                        self.status['last_error'] = f"Failed to save {shader_name}"
                else:
                    # Save error file
                    error_msg = result.get('error', 'Unknown error') if result else 'No result'
                    self.indexer.save_error(shader_name, error_msg, {'result': result})
                    self.status['errors'] += 1
                    self.status['last_error'] = f"{shader_name}: {error_msg[:50]}"
                    logger.warning(f"Analysis failed for {shader_name}: {error_msg}")

            except Exception as e:
                error_msg = str(e)
                self.indexer.save_error(shader_name, error_msg)
                self.status['errors'] += 1
                self.status['last_error'] = f"{shader_name}: {error_msg[:50]}"
                logger.exception(f"Error analyzing {shader_name}: {e}")

            # Remove processed shader from queue
            with self._lock:
                if shader_name in self._queue:
                    self._queue.remove(shader_name)

            # Small delay between analyses to avoid overwhelming LLM
            time.sleep(1.0)

        self.status['running'] = False

    def get_status(self) -> dict:
        """Get current status for UI."""
        # Return cached status - don't call indexer.get_stats() which rescans
        return {
            **self.status,
            'queue_size': len(self._queue),
        }
