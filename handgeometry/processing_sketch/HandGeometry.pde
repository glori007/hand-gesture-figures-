import oscP5.*;
import netP5.*;

OscP5 osc;

// Aligned 1-11 with Wekinator Output Indices
final int G_NONE          = 1;  // Wekinator Class 1
final int G_FIST          = 2;  // Wekinator Class 2
final int G_INDEX_ONLY    = 3;  // Wekinator Class 3
final int G_ROCK_SIGN     = 4;  // Wekinator Class 4
final int G_LOVE_SIGN     = 5;  // Wekinator Class 5
final int G_PALM_SWIPE    = 6;  // Wekinator Class 6
final int G_SPAWN_SPHERE  = 7;  // Wekinator Class 7
final int G_SPAWN_CUBE    = 8;  // Wekinator Class 8
final int G_SPAWN_PYRAMID = 9;  // Wekinator Class 9
final int G_SPAWN_TORUS   = 10; // Wekinator Class 10
final int G_ZOOM_MODE     = 11; // Wekinator Class 11

final int SHAPE_SPHERE   = 0;
final int SHAPE_CUBE     = 1;
final int SHAPE_PYRAMID  = 2;
final int SHAPE_TORUS    = 3;

GeoShape currentShape = null;
float rotSpeedX = 0, rotSpeedY = 0;
boolean frozen = false;
float prevHandSize = -1;

boolean colorMode  = false;
float   colorPhase = 0;

boolean erasing     = false;
float   eraseAmount = 0;
String  warningMsg     = "";
float   warningAlpha   = 0;

int lastRawGesture = 1; 
int gestureStartTime = 0;
int confirmedActiveGesture = 1; 

// DEBOUNCE SMOOTHING COUNTERS (Prevents lag while filtering transition spikes)
int indexGestureScore = 0;
int zoomGestureScore = 0;
final int HOLD_DURATION_THRESHOLD = 500; // Reset to a snappy 500ms for fast gesture response

void setup() {
  size(1280, 720, P3D);
  smooth(8);
  frameRate(60);
  colorMode(HSB, 360, 100, 100, 100);
  osc = new OscP5(this, 12000);
  println("[System Matrix] Operational. Smooth Filter Active on Port 12000.");
}

void draw() {
  background(230, 15, 8);
  drawBackground();

  if (erasing) {
    eraseAmount += 0.04;
    if (eraseAmount >= 1.0) {
      currentShape = null;
      erasing = false; eraseAmount = 0;
      frozen = false; colorMode = false; colorPhase = 0;
      rotSpeedX = 0; rotSpeedY = 0; 
      confirmedActiveGesture = 1;
    }
  }

  if (currentShape != null && !frozen && !erasing) {
    currentShape.rotX += rotSpeedX;
    currentShape.rotY += rotSpeedY;
    rotSpeedX *= 0.94; rotSpeedY *= 0.94; // Smooth rotational friction
  }

  if (colorMode && currentShape != null) {
    colorPhase = (colorPhase + 1.2) % 360;
  }

  if (currentShape != null) {
    currentShape.draw(colorMode, colorPhase, erasing ? eraseAmount : 0);
  }

  if (currentShape == null && !erasing) {
    drawEmptyHint();
  }

  if (warningAlpha > 0) {
    warningAlpha -= 1.5;
    drawWarning();
  }

  drawHUD();
}

void drawBackground() {
  pushStyle(); stroke(220, 10, 18, 25); strokeWeight(0.5);
  for (int x = 0; x < width; x += 60)  line(x, 0, x, height);
  for (int y = 0; y < height; y += 60) line(0, y, width, y);
  popStyle();
}

void drawEmptyHint() {
  pushStyle(); colorMode(RGB); fill(255, 255, 255, 35); noStroke(); textAlign(CENTER, CENTER); textSize(15);
  text("hold a geometric formation for 0.5s to compile shape", width/2, height/2); popStyle();
}

void drawWarning() {
  pushStyle(); colorMode(RGB);
  fill(220, 80, 60, warningAlpha * 0.85); noStroke();
  rect(width/2 - 170, height - 90, 340, 44, 22); fill(255, 255, 255, warningAlpha);
  textAlign(CENTER, CENTER); textSize(14); text(warningMsg, width/2, height - 68); popStyle();
}

void drawHUD() {
  pushStyle(); colorMode(RGB); fill(200, 200, 200, 100); noStroke();
  textSize(13); textAlign(LEFT, TOP);
  text("VECTOR CONTROL MATRIX", 20, 20);
  if (currentShape != null) {
    text("Mesh Asset: " + currentShape.typeName(), 20, 40);
    text("Chroma Cycling: " + (colorMode ? "ACTIVE" : "disabled"), 20, 56);
    text("Rotational Lock: " + (frozen   ? "LOCKED" : "free"), 20, 72);
    text("Current Scale: " + nf(currentShape.scale, 1, 2) + "x", 20, 88);
    if(confirmedActiveGesture == G_ZOOM_MODE) {
      fill(40, 150, 220); text("<- PROXIMITY ZOOM ENGAGED ->", 20, 110);
    }
  } else {
    text("Canvas State: Idle", 20, 40);
  }
  popStyle();
}

void oscEvent(OscMessage msg) {
  String addr = msg.addrPattern();

  // 1. Gesture Event Processing
  if (addr.equals("/gesture/event") || addr.equals("/wek/outputs")) {
    int gestureVal = msg.checkTypetag("f") ? int(msg.get(0).floatValue()) : msg.get(0).intValue();
    handleGestureTimeGating(gestureVal);
    
    // Leaky Bucket Smooth Filter Updates
    if (gestureVal == G_INDEX_ONLY) indexGestureScore = min(indexGestureScore + 2, 10);
    else                             indexGestureScore = max(indexGestureScore - 1, 0);
    
    if (gestureVal == G_ZOOM_MODE)   zoomGestureScore = min(zoomGestureScore + 2, 10);
    else                             zoomGestureScore = max(zoomGestureScore - 1, 0);
    return;
  }

  // 2. Real-time Rotation Stream
  if (addr.equals("/shape/rotate")) {
    // Requires confirmed gesture AND score clearance. Tolerates short multi-frame drops for maximum smoothness!
    if (confirmedActiveGesture == G_INDEX_ONLY && indexGestureScore > 3 && currentShape != null && !frozen && !erasing) {
      rotSpeedX = msg.get(1).floatValue() * 4.0;
      rotSpeedY = msg.get(0).floatValue() * 4.0;
    }
    return;
  }

  // 3. Real-time Zoom Stream
  if (addr.equals("/shape/zoom")) {
    float handSize = msg.get(0).floatValue();
    if (handSize < 0) {
      prevHandSize = -1;
      return;
    }
    
    // Requires confirmed gesture AND score clearance. Completely lag-free!
    if (confirmedActiveGesture == G_ZOOM_MODE && zoomGestureScore > 3 && currentShape != null && !erasing) {
      if (prevHandSize > 0) {
        float delta = (handSize - prevHandSize) * 4.5;
        currentShape.scale = constrain(currentShape.scale + delta, 0.3, 3.5);
      }
      prevHandSize = handSize;
    } else {
      prevHandSize = -1;
    }
    return;
  }
}

void handleGestureTimeGating(int g) {
  if (g == lastRawGesture) {
    if (millis() - gestureStartTime >= HOLD_DURATION_THRESHOLD) {
      if (g != confirmedActiveGesture) {
        confirmedActiveGesture = g;
        executeConfirmedGesture(confirmedActiveGesture);
      }
    }
  } else {
    lastRawGesture = g;
    gestureStartTime = millis();
  }
}

void executeConfirmedGesture(int g) {
  boolean isSpawn = (g == G_SPAWN_SPHERE || g == G_SPAWN_CUBE || g == G_SPAWN_PYRAMID || g == G_SPAWN_TORUS);
  if (isSpawn) {
    if (currentShape != null) { triggerWarning("canvas occupied — sweep to erase"); return; }
    if (erasing) return;
    switch (g) {
      case G_SPAWN_SPHERE:   spawnShape(SHAPE_SPHERE);   break;
      case G_SPAWN_CUBE:     spawnShape(SHAPE_CUBE);     break;
      case G_SPAWN_PYRAMID:  spawnShape(SHAPE_PYRAMID);  break;
      case G_SPAWN_TORUS:    spawnShape(SHAPE_TORUS);    break;
    }
    return;
  }

  if (currentShape == null || erasing) return;
  switch (g) {
    case G_FIST:        frozen = true; rotSpeedX = 0; rotSpeedY = 0; break;
    case G_INDEX_ONLY:  frozen = false; break;
    case G_ROCK_SIGN:   colorMode = true; break;
    case G_LOVE_SIGN: colorMode = false; colorPhase = 0; break;
    case G_PALM_SWIPE:  erasing = true; eraseAmount = 0; break;
    case G_ZOOM_MODE:   frozen = true; rotSpeedX = 0; rotSpeedY = 0; break;
  }
}

void spawnShape(int type) {
  currentShape = new GeoShape(type);
  frozen = false; colorMode = false; colorPhase = 0; rotSpeedX = 0; rotSpeedY = 0;
}

void triggerWarning(String msg) { warningMsg = msg; warningAlpha = 255; }

void keyPressed() {
  if (key == '1') executeConfirmedGesture(G_FIST);
  else if (key == '2') executeConfirmedGesture(G_INDEX_ONLY);
  else if (key == '3') executeConfirmedGesture(G_ROCK_SIGN);
  else if (key == '4') executeConfirmedGesture(G_LOVE_SIGN);
  else if (key == '5') executeConfirmedGesture(G_PALM_SWIPE);
  else if (key == '6') executeConfirmedGesture(G_SPAWN_SPHERE);
  else if (key == '7') executeConfirmedGesture(G_SPAWN_CUBE);
  else if (key == '8') executeConfirmedGesture(G_SPAWN_PYRAMID);
  else if (key == '9') executeConfirmedGesture(G_SPAWN_TORUS);
  else if (key == '0') executeConfirmedGesture(G_ZOOM_MODE);
}

// ── GeoShape ENGINE ─────────────────────────────────────────────────────────
class GeoShape {
  int type;
  float rotX = 0, rotY = 0, scale = 1.0, spawnAnim = 0, baseHue;
  GeoShape(int type) { this.type = type; this.baseHue = random(360); }
  String typeName() {
    if(type==SHAPE_SPHERE) return "SPHERE"; if(type==SHAPE_CUBE) return "CUBE";
    if(type==SHAPE_PYRAMID) return "PYRAMID"; return "TORUS";
  }
  void draw(boolean colorOn, float cPhase, float eraseAmt) {
    if (spawnAnim < 1.0) spawnAnim = min(spawnAnim + 0.035, 1.0);
    float ease = (float)(Math.pow(2, -10*spawnAnim) * Math.sin((spawnAnim*10 - 0.75) * (TWO_PI / 3.0)) + 1);
    pushMatrix(); translate(width/2, height/2, 0); rotateX(rotX); rotateY(rotY);
    if (eraseAmt > 0) { translate(eraseAmt * 600, 0, 0); scale((1.0 - eraseAmt) * scale * ease);
    } else { scale(scale * ease); }
    float h = colorOn ? (baseHue + cPhase) % 360 : 200; float s = colorOn ? 85 : 18; float b = colorOn ? 95 : 85;
    pushMatrix(); fill(h, s, b, 88); stroke(h, s * 0.4, 100, 65); strokeWeight(1.2); drawGeometry(); popMatrix();
    popMatrix();
  }
  void drawGeometry() {
    float sz = 100;
    if (type == SHAPE_SPHERE) { sphereDetail(32); sphere(sz); }
    else if (type == SHAPE_CUBE) { drawMeshCube(sz * 0.9); }
    else if (type == SHAPE_PYRAMID) { drawMeshPyramid(sz); }
    else if (type == SHAPE_TORUS) { drawTorus(sz * 0.9, sz * 0.35); }
  }
  void drawMeshCube(float s) {
    int div = 12; float h = s;
    int[][] faces = {{0,1,0},{0,-1,0},{-1,0,0},{1,0,0},{0,0,1},{0,0,-1}};
    for (int f = 0; f < 6; f++) { int nx = faces[f][0], ny = faces[f][1], nz = faces[f][2];
      for (int i = 0; i < div; i++) { beginShape(QUAD_STRIP);
        for (int j = 0; j <= div; j++) { float u0 = map(i, 0, div, -h, h), u1 = map(i+1, 0, div, -h, h), v = map(j, 0, div, -h, h);
          for (float u : new float[]{u0, u1}) { if (nx != 0) vertex(nx*h, v, u); else if (ny != 0) vertex(u, ny*h, v); else vertex(u, v, nz*h); }
        } endShape();
      } 
    }
  }
  void drawMeshPyramid(float s) {
    int div = 12; float h2 = s * 1.6, b2 = s * 1.1; float[][] corners = {{-b2,b2,b2},{b2,b2,b2},{b2,b2,-b2},{-b2,b2,-b2}};
    for (int f = 0; f < 4; f++) { float[] c0 = corners[f], c1 = corners[(f+1) % 4];
      for (int i = 0; i < div; i++) { float t0 = (float)i/div, t1 = (float)(i+1)/div; beginShape(QUAD_STRIP);
        for (int j = 0; j <= div; j++) { float u = (float)j/div;
          for (float t : new float[]{t0, t1}) { vertex(lerp(lerp(c0[0], c1[0], u), 0, t), lerp(lerp(c0[1], c1[1], u), -h2, t), lerp(lerp(c0[2], c1[2], u), 0, t)); }
        } endShape();
      } 
    }
    for (int i = 0; i < div; i++) { float u0 = map(i, 0, div, -b2, b2), u1 = map(i+1, 0, div, -b2, b2);
      beginShape(QUAD_STRIP); for (int j = 0; j <= div; j++) { float v = map(j, 0, div, -b2, b2); vertex(u0, b2, v); vertex(u1, b2, v); } endShape();
    }
  }
  void drawTorus(float R, float r) {
    int seg = 36, tube = 18;
    for (int i = 0; i < seg; i++) { float a0 = TWO_PI * i / seg, a1 = TWO_PI * (i+1) / seg; beginShape(QUAD_STRIP);
      for (int j = 0; j <= tube; j++) { float b = TWO_PI * j / tube;
        for (float a : new float[]{a0, a1}) { vertex((R + r*cos(b))*cos(a), (R + r*cos(b))*sin(a), r*sin(b)); }
      } endShape(); 
    }
  }
}
