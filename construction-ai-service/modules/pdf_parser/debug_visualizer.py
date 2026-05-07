import os
import logging
import svgwrite

logger = logging.getLogger(__name__)

class DebugVisualizer:
    """
    Phase 0: Incremental Debug Visualization
    Exports SVG overlays at the end of pipeline phases to visualize 
    geometry state (e.g., centerlines, semantic walls, rejected lines).
    """
    
    def __init__(self, output_dir: str = "debug_output"):
        self.output_dir = output_dir
        if not os.path.exists(self.output_dir):
            os.makedirs(self.output_dir)
            
    def _get_filepath(self, phase_name: str, document_id: str) -> str:
        safe_doc_id = "".join(c for c in document_id if c.isalnum() or c in ('-', '_'))
        return os.path.join(self.output_dir, f"{safe_doc_id}_{phase_name}.svg")
        
    def export_geometry(self, phase_name: str, document_id: str, 
                        lines: list, rects: list = None, polygons: list = None, 
                        width: int = 1000, height: int = 1000):
        """
        Draws raw vector geometry to an SVG file.
        lines format: [((x1,y1), (x2,y2)), ...]
        """
        filepath = self._get_filepath(phase_name, document_id)
        dwg = svgwrite.Drawing(filepath, size=(f"{width}px", f"{height}px"), profile='tiny')
        
        # Draw background
        dwg.add(dwg.rect(insert=(0, 0), size=('100%', '100%'), fill='white'))
        
        # Draw lines (Default: black, stroke-width: 1)
        for line in lines:
            try:
                p1, p2 = line
                dwg.add(dwg.line(start=p1, end=p2, stroke='black', stroke_width=1))
            except Exception as e:
                logger.debug(f"Visualizer skipped invalid line: {line}")
                
        # Draw polygons (Default: blue outline, transparent fill)
        if polygons:
            for poly in polygons:
                try:
                    dwg.add(dwg.polygon(points=poly, fill='none', stroke='blue', stroke_width=2))
                except Exception:
                    pass

        try:
            dwg.save()
            logger.info(f"Exported debug visualization: {filepath}")
        except Exception as e:
            logger.error(f"Failed to save SVG visualization: {str(e)}")
