/**
 * ScreenLayout — Screen-relative positioning helpers
 *
 * Provides utilities for positioning elements relative to screen dimensions,
 * making visuals resolution-independent and properly centered.
 *
 * Use these helpers instead of hardcoded pixel values to ensure visuals
 * work correctly at any resolution (720p, 1080p, etc.)
 */

class ScreenLayout {

  private PGraphics g;

  ScreenLayout(PGraphics g) {
    this.g = g;
  }

  // ============================================
  // CENTER POINTS
  // ============================================

  /**
   * Get center X coordinate
   */
  float centerX() {
    return g.width * 0.5;
  }

  /**
   * Get center Y coordinate
   */
  float centerY() {
    return g.height * 0.5;
  }

  /**
   * Get center as PVector
   */
  PVector center() {
    return new PVector(centerX(), centerY());
  }

  // ============================================
  // RELATIVE POSITIONING (0.0 - 1.0)
  // ============================================

  /**
   * Convert relative X (0.0-1.0) to absolute pixels
   */
  float relX(float normalizedX) {
    return g.width * normalizedX;
  }

  /**
   * Convert relative Y (0.0-1.0) to absolute pixels
   */
  float relY(float normalizedY) {
    return g.height * normalizedY;
  }

  /**
   * Convert relative position to absolute PVector
   */
  PVector rel(float normalizedX, float normalizedY) {
    return new PVector(relX(normalizedX), relY(normalizedY));
  }

  // ============================================
  // GRID POSITIONING (0-7 for Launchpad)
  // ============================================

  /**
   * Map Launchpad column (0-7) to screen X coordinate
   */
  float gridX(int col) {
    return map(col, 0, 7, g.width * 0.1, g.width * 0.9);
  }

  /**
   * Map Launchpad row (0-7) to screen Y coordinate
   * Note: Row 0 is bottom on Launchpad, top on screen
   */
  float gridY(int row) {
    return map(row, 0, 7, g.height * 0.9, g.height * 0.1);
  }

  /**
   * Map Launchpad cell to screen position
   */
  PVector gridPos(int col, int row) {
    return new PVector(gridX(col), gridY(row));
  }

  // ============================================
  // SAFE MARGINS
  // ============================================

  /**
   * Get left margin (10% of width)
   */
  float marginLeft() {
    return g.width * 0.1;
  }

  /**
   * Get right margin (90% of width)
   */
  float marginRight() {
    return g.width * 0.9;
  }

  /**
   * Get top margin (10% of height)
   */
  float marginTop() {
    return g.height * 0.1;
  }

  /**
   * Get bottom margin (90% of height)
   */
  float marginBottom() {
    return g.height * 0.9;
  }

  /**
   * Get safe content width (80% of screen width)
   */
  float contentWidth() {
    return g.width * 0.8;
  }

  /**
   * Get safe content height (80% of screen height)
   */
  float contentHeight() {
    return g.height * 0.8;
  }

  // ============================================
  // SIZE SCALING
  // ============================================

  /**
   * Scale size relative to screen width
   * Example: scaleW(0.1) = 10% of screen width
   */
  float scaleW(float ratio) {
    return g.width * ratio;
  }

  /**
   * Scale size relative to screen height
   * Example: scaleH(0.1) = 10% of screen height
   */
  float scaleH(float ratio) {
    return g.height * ratio;
  }

  /**
   * Scale size relative to smallest dimension (maintains aspect ratio)
   * Use this for circles/squares that should look consistent
   */
  float scaleMin(float ratio) {
    return min(g.width, g.height) * ratio;
  }

  /**
   * Scale size relative to largest dimension
   */
  float scaleMax(float ratio) {
    return max(g.width, g.height) * ratio;
  }

  // ============================================
  // DIMENSIONS
  // ============================================

  /**
   * Get screen width
   */
  float width() {
    return g.width;
  }

  /**
   * Get screen height
   */
  float height() {
    return g.height;
  }

  /**
   * Get aspect ratio (width/height)
   */
  float aspectRatio() {
    return (float)g.width / g.height;
  }
}
