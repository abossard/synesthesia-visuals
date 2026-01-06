var t=0;

function update(dt) {
  t+=speed*.02*(dt*60.0);
  setUniform("advance", t);
}