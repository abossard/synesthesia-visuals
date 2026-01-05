abstract class Level {
  public abstract void reset();
  public abstract void update(float dt, float t, AudioEnvelope audio);
  public abstract void render(PGraphics pg);
  public abstract String getName();
}
