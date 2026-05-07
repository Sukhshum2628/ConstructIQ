import os
import json
import logging

logger = logging.getLogger(__name__)

class PhaseCacheManager:
    """
    Manages state persistence for the PDF Parser pipeline.
    Saves and loads the JSON output of every phase to allow
    incremental development, fast debugging, and failure recovery.
    """
    
    def __init__(self, cache_dir: str = "cache"):
        self.cache_dir = cache_dir
        if not os.path.exists(self.cache_dir):
            os.makedirs(self.cache_dir)
            
    def _get_filepath(self, phase_name: str, document_id: str) -> str:
        """Constructs a safe filename for the phase cache."""
        safe_doc_id = "".join(c for c in document_id if c.isalnum() or c in ('-', '_'))
        return os.path.join(self.cache_dir, f"{safe_doc_id}_{phase_name}.json")
        
    def save_phase_state(self, phase_name: str, document_id: str, data: dict):
        """Serializes the phase output to disk."""
        filepath = self._get_filepath(phase_name, document_id)
        try:
            with open(filepath, 'w', encoding='utf-8') as f:
                json.dump(data, f, indent=2)
            logger.debug(f"Saved phase cache: {filepath}")
        except Exception as e:
            logger.warning(f"Failed to cache phase {phase_name} for {document_id}: {str(e)}")
            
    def load_phase_state(self, phase_name: str, document_id: str) -> dict:
        """Loads a previously serialized phase output. Returns None if missing."""
        filepath = self._get_filepath(phase_name, document_id)
        if os.path.exists(filepath):
            try:
                with open(filepath, 'r', encoding='utf-8') as f:
                    logger.info(f"Loaded phase cache: {filepath}")
                    return json.load(f)
            except Exception as e:
                logger.error(f"Corrupted cache file {filepath}: {str(e)}")
                return None
        return None

    def invalidate_cache(self, document_id: str):
        """Removes all cached phases for a specific document."""
        prefix = "".join(c for c in document_id if c.isalnum() or c in ('-', '_'))
        for filename in os.listdir(self.cache_dir):
            if filename.startswith(prefix) and filename.endswith('.json'):
                try:
                    os.remove(os.path.join(self.cache_dir, filename))
                except Exception as e:
                    logger.warning(f"Could not delete cache file {filename}: {str(e)}")
