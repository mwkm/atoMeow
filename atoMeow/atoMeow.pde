/*

  atomeow - a sample Processing implementation of my article:
  Blue noise sampling using an N-body simulation-based methos  
  https://www.researchgate.net/publication/316709742_Blue_noise_sampling_using_an_N-body_simulation-based_method

  MIT License
  
  Copyright (c) 2021 Kin-Ming Wong (Mike Wong), @artxiels
  
  Permission is hereby granted, free of charge, to any person obtaining a copy
  of this software and associated documentation files (the "Software"), to deal
  in the Software without restriction, including without limitation the rights
  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
  copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:
  
  The above copyright notice and this permission notice shall be included in all
  copies or substantial portions of the Software.
  
  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
  SOFTWARE.

*/

//  The following global variables control
//  various sim parameters

int   numDots    = 8192;   // # of dots in the sim
float dotCharge  = 0.2;   // Charge per dot, keep (numDots * numDots) lower than say 2000.

//  Simulation controls
//
float blankLevel = 0.95;    // Threshold to repel (0.0 - 1.0, default: 1.0)
float timeStep   = 0.001;  // Sim timestep       (Default: 0.001)
float dMax       = 0.005;   // Max dot displacment    (Default: 0.005)
float sustain    = 0.95;   // Sustained Velocity between steps (Default: 0.95)

//  GLSL Sim buffer dimension
//
static int bufXY    = 256;    // GLSL workbuf dimensions, i.e. numDots MAX. 128^2 = 16384, 64^2 = 4096
static int simXY    = 512;    // Electrostatic field resolution (higher, more expensive)

//  Random seed (random() used in 'initDots' only)
static int rndSeed  = 123;    

//  GPU SIM resources (better keep them unchanged)
PGraphics hidden;
PShader   posShader, velShader, accShader;
PImage[]  accBuf;
PImage    velBuf, posBuf, fieldBuf;
String    accShaderFile = "shaderAcc.glsl";
String    velShaderFile = "shaderVel.glsl";
String    posShaderFile = "shaderPos.glsl";

//  active 'Acc' buffer index
int activeAcc = 0;

//  pre-computed variables
float dt   = timeStep;
float dt_2 = 0.5 * timeStep;
float dtt  = dt * dt;
float vMax = dMax / dt;


//
//  ======= Core Processing code ========
//

void setup() {

  size(800, 800, P2D);
  background(0);
  noStroke();
  randomSeed(rndSeed); 

  //  Load your fav image (square shaped) here :)
  PImage target = loadImage("hoku.png");

  initSIM();
  initDots(numDots);
  updateField(target);  // this function will resize the 'field' to simXY size.

}


void draw() {
  
  background(255);

  // Say we wan to run the sim for 3 steps in each 'draw() frame'  
  if (frameCount < 250) sim(3);
  
  // Ink our dots
  drawDots(numDots, 5.0, color(0, 250));
  
  if (frameCount >250) {
    noLoop();
    save("hokusai_dots.png");
  }
}


//
//  ======= supporting functions =======
//


//  Run the simulation for 'n' steps.
//
void sim(int n) {
  
  for (int i = 0; i < n; i++) {    

    //  Off-screen GPU (PGraphics) sim
    hidden.beginDraw();

    //  Acc update: Computes per-particle acceleration caused
    //  by other particles and the undelying electro-static field
    //
    updateAccShaderUniforms();  
    hidden.filter(accShader);
    accBuf[activeAcc] = hidden.copy();

    //  Vel update: Updates per-particle velocity using a
    //  customized Velocity Verlet algorithm
    updateVelShaderUniforms();  
    hidden.filter(velShader);
    velBuf = hidden.copy();

    //  Pos update: Updates per-particle velocity with
    //  a displacement limit imposed.
    updatePosShaderUniforms();  
    hidden.filter(posShader);
    posBuf = hidden.copy();
    
    hidden.endDraw();
    activeAcc = 1 - activeAcc; // swap active accBuf index
  }
  
}

//  Initialize essential GPU sim resources (RUN ONCE OK)
//
void initSIM() {

  //  SIM shaders
  accShader = loadShader(accShaderFile);
  velShader = loadShader(velShaderFile);
  posShader = loadShader(posShaderFile);

  //  Workhorse offscreen engine for shaders
  hidden  = createGraphics(bufXY, bufXY, P2D);

  //  buffers (Processing Image) for SIM storage
  accBuf    = new PImage[2];
  accBuf[0] = createImage(bufXY, bufXY, ARGB);
  accBuf[1] = createImage(bufXY, bufXY, ARGB);

  velBuf    = createImage(bufXY, bufXY, ARGB);
  posBuf    = createImage(bufXY, bufXY, ARGB);

}



//  Initialize Dots position for Sim
//
void initDots(int np) {
  posBuf.loadPixels();
  for (int i = 0; i < np; i++) {
    float x = random(-1.0, 1.0);
    float y = random(-1.0, 1.0);
    Float2 xy = new Float2(x, y);
    color cxy = encodeF2(xy);
    posBuf.pixels[i] = cxy;    
  }
  posBuf.updatePixels();
}


//  Visualize the Dots using info from 'posBuf'
//
void drawDots(int np, float r, color c) {
  fill(c);
  posBuf.loadPixels();
  for (int i = 0; i < np; i++) {
    color pc = posBuf.pixels[i];    
    Float2 p = decodeF2(pc);
    circle((p.x+1.0)* width/2, (p.y+1)*height/2, r);
  }
  posBuf.updatePixels();
}


//  'fieldBuf' stores the charge (float) info of each pixel of the field
//
void updateField(PImage bmp) {

  PGraphics hBmp = createGraphics(simXY, simXY, P2D);
  fieldBuf = createImage(simXY, simXY, ARGB);
  hBmp.beginDraw();
  hBmp.image(bmp, 0, 0, simXY, simXY);
  fieldBuf = hBmp.copy();
  hBmp.endDraw();

  fieldBuf.loadPixels();
  float bmpChargeTotal = 0.0;
  for (int i = 0; i < simXY*simXY; i++) {
    color pxColor = fieldBuf.pixels[i];
    
    //  We evaluate the brightness here, so you can be creative here.
    float gray = (0.2989 * red(pxColor) + 0.5870 * green(pxColor) + 0.1140 * blue(pxColor)) / 255.0;

    bmpChargeTotal += blankLevel - gray;
    fieldBuf.pixels[i] = encode(gray);
  }
  fieldBuf.updatePixels();

  float dotChargeTotal = float(numDots) * dotCharge;
  float bmpCharge = dotChargeTotal / bmpChargeTotal;

  fieldBuf.loadPixels();
  for (int i = 0; i < simXY*simXY; i++) {
    float gray = decode(fieldBuf.pixels[i]);
    fieldBuf.pixels[i] = encode((blankLevel - gray) * bmpCharge);
  }
  fieldBuf.updatePixels();

}

//  Update 'Acc' shader uniforms
//
void updateAccShaderUniforms() {  
  accShader.set("u_resolution", float(bufXY), float(bufXY));
  accShader.set("u_pos", posBuf);
  accShader.set("u_bmpQ", fieldBuf);
  accShader.set("u_simXY", simXY);
  accShader.set("u_dotCharge", dotCharge);
  accShader.set("u_numDots", numDots);
}

//  Update 'Vel' shader uniforms
//
void updateVelShaderUniforms() {  
  velShader.set("u_resolution", float(bufXY), float(bufXY));
  velShader.set("u_vel", velBuf);
  velShader.set("u_a0", accBuf[1-activeAcc]);  // Last Acc.
  velShader.set("u_a1", accBuf[activeAcc]);    // Latest Acc.
  velShader.set("u_vMax", vMax);
  velShader.set("u_sustain", sustain);    
  velShader.set("u_dt_2", dt_2);
  velShader.set("u_numDots", numDots);
}

//  Update 'Pos' shader uniforms
//
void updatePosShaderUniforms() {  
  posShader.set("u_resolution", float(bufXY), float(bufXY));
  posShader.set("u_pos", posBuf);
  posShader.set("u_vel", velBuf);
  posShader.set("u_acc", accBuf[activeAcc]);
  posShader.set("u_dMax", dMax);
  posShader.set("u_dt", dt);    
  posShader.set("u_dtt", dtt);  
  posShader.set("u_numDots", numDots);
}
