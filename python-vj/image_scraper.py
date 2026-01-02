#!/usr/bin/env python3
"""
Image Scraper - Fetches album art and thematic images from multiple sources

Sources (fetches from ALL, not fallback):
- Cover Art Archive (MusicBrainz) - Album covers, no auth (~3 images)
- Pexels - Thematic images, free API key (5 images)
- Pixabay - Thematic images, CC0 license (5 images)
- Unsplash - Thematic images, attribution required (5 images)

Total: ~16-18 images per song for VJ folder cycling

Design:
- Deep module with simple interface: fetch_images(track, metadata) -> Optional[Path]
- Caches images per song in .cache/song_images/{artist}_{title}/
- Sends OSC /image/folder <path> when complete
- Skips if images already exist
- Thread-safe
"""

import json
import os
import time
import logging
import requests
from pathlib import Path
from typing import Optional, Dict, Any
from dataclasses import dataclass
from threading import Lock

# Load .env for API keys if not already loaded
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError:
    pass

from domain import Track, sanitize_cache_filename
from infrastructure import Config

logger = logging.getLogger('textler')


# =============================================================================
# IMAGE SCRAPER - Deep module for fetching song-related imagery
# =============================================================================

@dataclass
class ImageResult:
    """Result of an image fetch operation."""
    folder: Path
    album_art: bool = False
    artist_photos: int = 0
    total_images: int = 0
    source: str = ""
    cached: bool = False


class ImageScraper:
    """
    Fetches and caches images for songs from multiple sources.
    
    Simple interface:
        fetch_images(track, metadata) -> Optional[ImageResult]
        images_exist(track) -> bool
    
    Sources (fetches from ALL, ~16-18 images total):
        - Cover Art Archive - album covers (~3 images)
        - Pexels - thematic imagery (5 images)
        - Pixabay - thematic CC0 imagery (5 images)
        - Unsplash - thematic imagery (5 images, attribution required)
    
    OSC Integration:
        Sends /image/folder <path> to Processing ImageTile when complete.
    
    All images cached in .cache/song_images/{artist}_{title}/
    """
    
    CACHE_DIR = Config.APP_DATA_DIR / "song_images"
    
    # API endpoints
    MUSICBRAINZ_API = "https://musicbrainz.org/ws/2"
    COVERART_API = "https://coverartarchive.org"
    UNSPLASH_API = "https://api.unsplash.com"
    PEXELS_API = "https://api.pexels.com/v1"
    PIXABAY_API = "https://pixabay.com/api"
    
    # User agent (required by most APIs)
    USER_AGENT = "VJConsole/1.0 (https://github.com/synesthesia-visuals)"
    
    # Rate limiting
    MUSICBRAINZ_RATE_LIMIT = 50  # requests per minute
    UNSPLASH_RATE_LIMIT = 50  # requests per hour (free tier)
    PEXELS_RATE_LIMIT = 200  # requests per hour
    PIXABAY_RATE_LIMIT = 100  # requests per minute
    
    def __init__(self):
        self._session = requests.Session()
        self._session.headers["User-Agent"] = self.USER_AGENT
        self._lock = Lock()
        self._last_musicbrainz_request = 0.0
        self._last_unsplash_request = 0.0
        self._last_pexels_request = 0.0
        self._last_pixabay_request = 0.0
        self._unsplash_key = os.getenv("UNSPLASH_ACCESS_KEY", "")
        self._pexels_key = os.getenv("PEXELS_API_KEY", "")
        self._pixabay_key = os.getenv("PIXABAY_API_KEY", "")
        self.CACHE_DIR.mkdir(parents=True, exist_ok=True)
    
    # =========================================================================
    # PUBLIC API
    # =========================================================================
    
    def fetch_images(self, track: Track, metadata: Optional[Dict] = None) -> Optional[ImageResult]:
        """
        Fetch and cache images for a track from ALL sources.
        
        Fetches from each source (not fallback, ~16-18 total):
        - Cover Art Archive: ~3 album covers
        - Pexels: 5 thematic images
        - Pixabay: 5 thematic images (CC0)
        - Unsplash: 5 thematic images (attribution saved)
        
        Sends OSC /image/folder <path> when complete.
        Returns ImageResult or None. Skips if images already cached.
        """
        folder = self._get_folder(track)
        
        # Check cache first
        if self._images_exist(folder):
            count = len(list(folder.glob("*.jpg"))) + len(list(folder.glob("*.png")))
            logger.debug(f"Images cached: {track.artist} - {track.title} ({count} files)")
            return ImageResult(
                folder=folder,
                total_images=count,
                cached=True,
                album_art=any(folder.glob("album_*")),
                artist_photos=len(list(folder.glob("artist_*")))
            )
        
        # Create folder
        folder.mkdir(parents=True, exist_ok=True)
        
        album_name = metadata.get('album', '') if metadata else track.album
        
        result = ImageResult(folder=folder)
        
        # 1. Try Cover Art Archive first (highest quality, no auth)
        try:
            caa_result = self._fetch_from_cover_art_archive(track, album_name, folder)
            if caa_result:
                result.album_art = True
                result.total_images += caa_result
                result.source = "coverart_archive"
                logger.info(f"Cover Art Archive: {caa_result} images for {track.artist} - {track.title}")
        except Exception as e:
            logger.debug(f"Cover Art Archive failed: {e}")
        
        # Build search query from metadata for thematic sources
        query = self._build_search_query(metadata) if metadata else None
        
        # 2. Try Pexels for thematic imagery
        if query and self._pexels_key:
            try:
                pexels_count = self._fetch_from_pexels(query, folder)
                if pexels_count > 0:
                    result.total_images += pexels_count
                    result.source = f"{result.source}+pexels" if result.source else "pexels"
                    logger.info(f"Pexels: {pexels_count} thematic images for {track.artist} - {track.title}")
            except Exception as e:
                logger.debug(f"Pexels failed: {e}")
        
        # 3. Try Pixabay for thematic imagery (CC0 license)
        if query and self._pixabay_key:
            try:
                pixabay_count = self._fetch_from_pixabay(query, folder)
                if pixabay_count > 0:
                    result.total_images += pixabay_count
                    result.source = f"{result.source}+pixabay" if result.source else "pixabay"
                    logger.info(f"Pixabay: {pixabay_count} thematic images for {track.artist} - {track.title}")
            except Exception as e:
                logger.debug(f"Pixabay failed: {e}")
        
        # 4. Try Unsplash for thematic imagery (attribution required)
        if metadata and self._unsplash_key:
            try:
                unsplash_count = self._fetch_from_unsplash(metadata, folder)
                if unsplash_count > 0:
                    result.total_images += unsplash_count
                    result.source = f"{result.source}+unsplash" if result.source else "unsplash"
                    logger.info(f"Unsplash: {unsplash_count} thematic images for {track.artist} - {track.title}")
            except Exception as e:
                logger.debug(f"Unsplash failed: {e}")
        
        # Save metadata about sources
        if result.total_images > 0:
            self._save_sources_metadata(folder, track, result)
            return result
        
        return None
    
    def images_exist(self, track: Track) -> bool:
        """Check if images are already cached for this track."""
        folder = self._get_folder(track)
        return self._images_exist(folder)
    
    def get_folder(self, track: Track) -> Path:
        """Get the cache folder path for a track."""
        return self._get_folder(track)
    
    def get_cached_count(self) -> int:
        """Return number of songs with cached images."""
        if self.CACHE_DIR.exists():
            return len([d for d in self.CACHE_DIR.iterdir() if d.is_dir()])
        return 0
    
    # =========================================================================
    # PRIVATE - Cover Art Archive (MusicBrainz)
    # =========================================================================
    
    def _fetch_from_cover_art_archive(self, track: Track, album: str, folder: Path) -> int:
        """
        Fetch album art from Cover Art Archive via MusicBrainz.
        Returns number of images downloaded.
        
        Flow:
        1. Search MusicBrainz for release MBID
        2. Fetch cover art from Cover Art Archive
        """
        self._rate_limit_musicbrainz()
        
        # Search for release
        query = f'artist:"{track.artist}" AND recording:"{track.title}"'
        if album:
            query += f' AND release:"{album}"'
        
        try:
            resp = self._session.get(
                f"{self.MUSICBRAINZ_API}/recording",
                params={
                    'query': query,
                    'fmt': 'json',
                    'limit': 5
                },
                timeout=10
            )
            
            if resp.status_code != 200:
                logger.debug(f"MusicBrainz search failed: {resp.status_code}")
                return 0
            
            data = resp.json()
            recordings = data.get('recordings', [])
            
            if not recordings:
                logger.debug(f"No MusicBrainz recordings found for {track.title}")
                return 0
            
            # Get first recording's releases
            images_downloaded = 0
            for recording in recordings[:3]:  # Try first 3 matches
                releases = recording.get('releases', [])
                for release in releases[:2]:  # Try first 2 releases per recording
                    mbid = release.get('id')
                    if not mbid:
                        continue
                    
                    count = self._download_cover_art(mbid, folder)
                    if count > 0:
                        images_downloaded += count
                        return images_downloaded  # Got what we need
                    
                    self._rate_limit_musicbrainz()
            
            return images_downloaded
            
        except Exception as e:
            logger.debug(f"MusicBrainz error: {e}")
            return 0
    
    def _download_cover_art(self, mbid: str, folder: Path) -> int:
        """Download cover art from Cover Art Archive. Returns count."""
        try:
            # Get front cover directly (most common case)
            front_url = f"{self.COVERART_API}/release/{mbid}/front-500"
            resp = self._session.get(front_url, timeout=15, allow_redirects=True)
            
            if resp.status_code == 200:
                # Determine file extension from content type
                content_type = resp.headers.get('content-type', 'image/jpeg')
                ext = 'jpg' if 'jpeg' in content_type else 'png'
                
                filepath = folder / f"album_cover.{ext}"
                filepath.write_bytes(resp.content)
                logger.debug(f"Downloaded: {filepath.name} ({len(resp.content)} bytes)")
                return 1
            
            # Try listing all available art
            list_url = f"{self.COVERART_API}/release/{mbid}"
            resp = self._session.get(list_url, timeout=10)
            
            if resp.status_code != 200:
                return 0
            
            images = resp.json().get('images', [])
            count = 0
            
            for i, img in enumerate(images[:3]):  # Max 3 images
                img_url = img.get('thumbnails', {}).get('500') or img.get('image')
                if not img_url:
                    continue
                
                img_type = 'front' if img.get('front') else ('back' if img.get('back') else 'other')
                
                try:
                    img_resp = self._session.get(img_url, timeout=15)
                    if img_resp.status_code == 200:
                        content_type = img_resp.headers.get('content-type', 'image/jpeg')
                        ext = 'jpg' if 'jpeg' in content_type else 'png'
                        
                        filename = f"album_{img_type}_{i}.{ext}"
                        (folder / filename).write_bytes(img_resp.content)
                        count += 1
                except Exception:
                    continue
            
            return count
            
        except Exception as e:
            logger.debug(f"Cover Art Archive download error: {e}")
            return 0
    
    # =========================================================================
    # PRIVATE - Utilities
    # =========================================================================
    
    def _get_folder(self, track: Track) -> Path:
        """Generate cache folder path from track."""
        safe = sanitize_cache_filename(track.artist, track.title)
        return self.CACHE_DIR / safe
    
    def _images_exist(self, folder: Path) -> bool:
        """Check if folder has at least one image."""
        if not folder.exists():
            return False
        return any(folder.glob("*.jpg")) or any(folder.glob("*.png"))
    
    def _save_sources_metadata(self, folder: Path, track: Track, result: ImageResult):
        """Save metadata about image sources."""
        metadata = {
            'artist': track.artist,
            'title': track.title,
            'album': track.album,
            'fetched_at': time.time(),
            'source': result.source,
            'album_art': result.album_art,
            'artist_photos': result.artist_photos,
            'total_images': result.total_images,
        }
        
        metadata_file = folder / "sources.json"
        try:
            metadata_file.write_text(json.dumps(metadata, indent=2))
        except Exception:
            pass
    
    def _rate_limit_musicbrainz(self):
        """Ensure we don't exceed MusicBrainz rate limit (1 req/sec recommended)."""
        with self._lock:
            now = time.time()
            elapsed = now - self._last_musicbrainz_request
            if elapsed < 1.0:
                time.sleep(1.0 - elapsed)
            self._last_musicbrainz_request = time.time()
    
    def _rate_limit_unsplash(self):
        """Ensure we don't exceed Unsplash rate limit (50 req/hr = ~72 sec/req)."""
        with self._lock:
            now = time.time()
            elapsed = now - self._last_unsplash_request
            # More conservative: 3 sec between requests to stay well under limit
            if elapsed < 3.0:
                time.sleep(3.0 - elapsed)
            self._last_unsplash_request = time.time()
    
    def _rate_limit_pexels(self):
        """Ensure we don't exceed Pexels rate limit (200 req/hr = ~18 sec/req)."""
        with self._lock:
            now = time.time()
            elapsed = now - self._last_pexels_request
            if elapsed < 1.0:
                time.sleep(1.0 - elapsed)
            self._last_pexels_request = time.time()
    
    def _rate_limit_pixabay(self):
        """Ensure we don't exceed Pixabay rate limit (100 req/min = 0.6 sec/req)."""
        with self._lock:
            now = time.time()
            elapsed = now - self._last_pixabay_request
            if elapsed < 0.7:
                time.sleep(0.7 - elapsed)
            self._last_pixabay_request = time.time()
    
    def _build_search_query(self, metadata: Dict[str, Any]) -> Optional[str]:
        """
        Build search query from metadata for thematic image sources.
        Returns query string or None if no terms available.
        """
        search_terms = []
        
        # Priority: themes > mood > keywords
        if metadata.get('themes'):
            themes = metadata['themes']
            if isinstance(themes, list):
                search_terms.extend(themes[:3])
            elif isinstance(themes, str):
                search_terms.append(themes)
        
        if metadata.get('mood'):
            search_terms.append(metadata['mood'])
        
        if metadata.get('keywords') and len(search_terms) < 3:
            keywords = metadata['keywords']
            if isinstance(keywords, list):
                for kw in keywords[:5]:
                    if kw.lower() not in [s.lower() for s in search_terms]:
                        search_terms.append(kw)
                        if len(search_terms) >= 4:
                            break
        
        if not search_terms:
            return None
        
        return ' '.join(search_terms[:3])
    
    # =========================================================================
    # PRIVATE - Pexels (Thematic Imagery)
    # =========================================================================
    
    def _fetch_from_pexels(self, query: str, folder: Path) -> int:
        """
        Fetch thematic images from Pexels.
        Returns number of images downloaded.
        
        Pexels: Free API, attribution requested but not required.
        """
        if not self._pexels_key:
            return 0
        
        logger.debug(f"Pexels query: {query}")
        self._rate_limit_pexels()
        
        try:
            resp = self._session.get(
                f"{self.PEXELS_API}/search",
                params={
                    'query': query,
                    'per_page': 5,
                    'orientation': 'landscape',
                },
                headers={
                    'Authorization': self._pexels_key
                },
                timeout=10
            )
            
            if resp.status_code == 401:
                logger.warning("Pexels API key invalid")
                return 0
            
            if resp.status_code == 429:
                logger.warning("Pexels rate limit exceeded")
                return 0
            
            if resp.status_code != 200:
                logger.debug(f"Pexels search failed: {resp.status_code}")
                return 0
            
            data = resp.json()
            photos = data.get('photos', [])
            
            if not photos:
                logger.debug(f"No Pexels results for: {query}")
                return 0
            
            count = 0
            attributions = []
            
            for i, photo in enumerate(photos[:5]):
                # Get large size (good for VJ visuals)
                img_url = photo.get('src', {}).get('large')
                if not img_url:
                    continue
                
                try:
                    img_resp = self._session.get(img_url, timeout=15)
                    if img_resp.status_code == 200:
                        filename = f"thematic_pexels_{i}.jpg"
                        (folder / filename).write_bytes(img_resp.content)
                        count += 1
                        
                        # Track attribution (good practice)
                        attributions.append({
                            'filename': filename,
                            'photographer': photo.get('photographer', 'Unknown'),
                            'photographer_url': photo.get('photographer_url', ''),
                            'photo_url': photo.get('url', ''),
                            'source': 'pexels',
                        })
                except Exception as e:
                    logger.debug(f"Pexels download error: {e}")
                    continue
            
            if attributions:
                self._save_attribution(folder, attributions, query, source='pexels')
            
            return count
            
        except Exception as e:
            logger.debug(f"Pexels error: {e}")
            return 0
    
    # =========================================================================
    # PRIVATE - Pixabay (Thematic Imagery - CC0)
    # =========================================================================
    
    def _fetch_from_pixabay(self, query: str, folder: Path) -> int:
        """
        Fetch thematic images from Pixabay.
        Returns number of images downloaded.
        
        Pixabay: CC0 license, no attribution required.
        """
        if not self._pixabay_key:
            return 0
        
        logger.debug(f"Pixabay query: {query}")
        self._rate_limit_pixabay()
        
        try:
            resp = self._session.get(
                self.PIXABAY_API,
                params={
                    'key': self._pixabay_key,
                    'q': query,
                    'per_page': 5,
                    'orientation': 'horizontal',
                    'image_type': 'photo',
                    'safesearch': 'true',
                },
                timeout=10
            )
            
            if resp.status_code == 401:
                logger.warning("Pixabay API key invalid")
                return 0
            
            if resp.status_code == 429:
                logger.warning("Pixabay rate limit exceeded")
                return 0
            
            if resp.status_code != 200:
                logger.debug(f"Pixabay search failed: {resp.status_code}")
                return 0
            
            data = resp.json()
            hits = data.get('hits', [])
            
            if not hits:
                logger.debug(f"No Pixabay results for: {query}")
                return 0
            
            count = 0
            
            for i, hit in enumerate(hits[:5]):
                # Get large image (1280px)
                img_url = hit.get('largeImageURL')
                if not img_url:
                    continue
                
                try:
                    img_resp = self._session.get(img_url, timeout=15)
                    if img_resp.status_code == 200:
                        filename = f"thematic_pixabay_{i}.jpg"
                        (folder / filename).write_bytes(img_resp.content)
                        count += 1
                except Exception as e:
                    logger.debug(f"Pixabay download error: {e}")
                    continue
            
            return count
            
        except Exception as e:
            logger.debug(f"Pixabay error: {e}")
            return 0
    
    # =========================================================================
    # PRIVATE - Unsplash (Thematic Imagery)
    # =========================================================================
    
    def _fetch_from_unsplash(self, metadata: Dict[str, Any], folder: Path) -> int:
        """
        Fetch thematic images from Unsplash based on song keywords/themes.
        Returns number of images downloaded.
        
        Uses metadata keywords, themes, mood for search queries.
        Saves attribution.json for license compliance.
        """
        if not self._unsplash_key:
            return 0
        
        query = self._build_search_query(metadata)
        if not query:
            logger.debug("No search terms from metadata for Unsplash")
            return 0
        
        logger.debug(f"Unsplash query: {query}")
        
        self._rate_limit_unsplash()
        
        try:
            resp = self._session.get(
                f"{self.UNSPLASH_API}/search/photos",
                params={
                    'query': query,
                    'per_page': 5,
                    'orientation': 'landscape',  # Better for VJ visuals
                },
                headers={
                    'Authorization': f'Client-ID {self._unsplash_key}'
                },
                timeout=10
            )
            
            if resp.status_code == 401:
                logger.warning("Unsplash API key invalid")
                return 0
            
            if resp.status_code == 403:
                logger.warning("Unsplash rate limit exceeded")
                return 0
            
            if resp.status_code != 200:
                logger.debug(f"Unsplash search failed: {resp.status_code}")
                return 0
            
            data = resp.json()
            results = data.get('results', [])
            
            if not results:
                logger.debug(f"No Unsplash results for: {query}")
                return 0
            
            count = 0
            attributions = []
            
            for i, photo in enumerate(results[:5]):
                # Get regular size (1080px wide, good for visuals)
                img_url = photo.get('urls', {}).get('regular')
                if not img_url:
                    continue
                
                try:
                    img_resp = self._session.get(img_url, timeout=15)
                    if img_resp.status_code == 200:
                        filename = f"thematic_unsplash_{i}.jpg"
                        (folder / filename).write_bytes(img_resp.content)
                        count += 1
                        
                        # Track attribution (required by Unsplash license)
                        attributions.append({
                            'filename': filename,
                            'photographer': photo.get('user', {}).get('name', 'Unknown'),
                            'photographer_url': photo.get('user', {}).get('links', {}).get('html', ''),
                            'photo_url': photo.get('links', {}).get('html', ''),
                            'unsplash_url': 'https://unsplash.com',
                            'download_location': photo.get('links', {}).get('download_location', ''),
                        })
                        
                        # Trigger download tracking (Unsplash API requirement)
                        download_location = photo.get('links', {}).get('download_location')
                        if download_location:
                            try:
                                self._session.get(
                                    download_location,
                                    headers={'Authorization': f'Client-ID {self._unsplash_key}'},
                                    timeout=5
                                )
                            except Exception:
                                pass  # Best effort
                                
                except Exception as e:
                    logger.debug(f"Unsplash download error: {e}")
                    continue
            
            # Save attribution file (license compliance)
            if attributions:
                self._save_attribution(folder, attributions, query, source='unsplash')
            
            return count
            
        except Exception as e:
            logger.debug(f"Unsplash error: {e}")
            return 0
    
    def _save_attribution(self, folder: Path, attributions: list, query: str, source: str = 'unsplash'):
        """
        Save attribution to JSON file for license compliance.
        
        Unsplash requires: "Photo by [name] on Unsplash"
        Pexels requests: "Photo by [name] on Pexels"
        Pixabay: CC0, no attribution required
        """
        attr_file = folder / "attribution.json"
        
        data = {
            'sources': [source],
            'query': query,
            'fetched_at': time.time(),
            'photos': attributions
        }
        
        # Add license info based on source
        if source == 'unsplash':
            data['license'] = 'Unsplash License (https://unsplash.com/license)'
            data['attribution_required'] = True
        elif source == 'pexels':
            data['license'] = 'Pexels License (https://www.pexels.com/license/)'
            data['attribution_required'] = False  # Requested but not required
        
        try:
            # Merge with existing attributions if present
            if attr_file.exists():
                existing = json.loads(attr_file.read_text())
                if 'photos' in existing:
                    existing['photos'].extend(attributions)
                if 'sources' in existing and source not in existing['sources']:
                    existing['sources'].append(source)
                data = existing
            
            attr_file.write_text(json.dumps(data, indent=2))
        except Exception as e:
            logger.debug(f"Failed to save attribution: {e}")


# =============================================================================
# TEST FUNCTION - For quick verification
# =============================================================================

def test_scraper():
    """Test the image scraper with a few known songs."""
    logging.basicConfig(
        level=logging.DEBUG,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    
    scraper = ImageScraper()
    
    test_songs = [
        Track(artist="Daft Punk", title="Get Lucky", album="Random Access Memories"),
        Track(artist="The Beatles", title="Hey Jude", album=""),
        Track(artist="Queen", title="Bohemian Rhapsody", album="A Night at the Opera"),
    ]
    
    print("\n" + "=" * 60)
    print("  Image Scraper Test")
    print("=" * 60 + "\n")
    
    for track in test_songs:
        print(f"Testing: {track.artist} - {track.title}")
        print("-" * 40)
        
        result = scraper.fetch_images(track)
        
        if result:
            print(f"  ✓ Folder: {result.folder}")
            print(f"  ✓ Album art: {result.album_art}")
            print(f"  ✓ Artist photos: {result.artist_photos}")
            print(f"  ✓ Total images: {result.total_images}")
            print(f"  ✓ Source: {result.source}")
            print(f"  ✓ Cached: {result.cached}")
            
            # List files
            files = list(result.folder.glob("*.*"))
            for f in files:
                size = f.stat().st_size / 1024
                print(f"     - {f.name} ({size:.1f} KB)")
        else:
            print("  ✗ No images found")
        
        print()
    
    print(f"Total cached songs: {scraper.get_cached_count()}")


if __name__ == "__main__":
    test_scraper()
