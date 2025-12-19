class CellularAutomataLevel extends Level {
  int cols = 140;
  int rows = 80;
  boolean[][] grid;
  boolean[][] next;
  
  public void reset() {
    grid = new boolean[cols][rows];
    next = new boolean[cols][rows];
    for (int x = 0; x < cols; x++) {
      for (int y = 0; y < rows; y++) {
        grid[x][y] = random(1) > 0.8f;
      }
    }
  }
  
  public void update(float dt, float t, AudioEnvelope audio) {
    for (int x = 1; x < cols-1; x++) {
      for (int y = 1; y < rows-1; y++) {
        int n = neighbors(x,y);
        if (grid[x][y]) {
          next[x][y] = (n == 2 || n == 3);
        } else {
          next[x][y] = (n == 3);
        }
      }
    }
    boolean[][] tmp = grid; grid = next; next = tmp;
  }
  
  public int neighbors(int x, int y) {
    int c = 0;
    for (int dx=-1; dx<=1; dx++) {
      for (int dy=-1; dy<=1; dy++) {
        if (dx==0 && dy==0) continue;
        if (grid[x+dx][y+dy]) c++;
      }
    }
    return c;
  }
  
  public void render(PGraphics pg) {
    pg.pushStyle();
    float cellW = (float)pg.width / cols;
    float cellH = (float)pg.height / rows;
    pg.noStroke();
    pg.fill(10, 10, 18);
    pg.rect(0,0,pg.width,pg.height);
    pg.fill(180, 240, 255);
    for (int x=0; x<cols; x++) {
      for (int y=0; y<rows; y++) {
        if (grid[x][y]) {
          pg.rect(x*cellW, y*cellH, cellW+1, cellH+1);
        }
      }
    }
    pg.popStyle();
  }
  
  public String getName() { return "Cellular Automata"; }
}
