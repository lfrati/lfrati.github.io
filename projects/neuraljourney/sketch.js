let theShader;
let fs;
let n1, n2;
let t = 0;

//function preload() {
//    song = loadSound("interstellar.mp3");
//}

function setup() {
    pixelDensity(2);
    // shaders require WEBGL mode to work!
    cnv = createCanvas(700, 700, WEBGL);
    paused = createGraphics(width, height);
    paused.background("black");
    paused.fill("white");
    paused.noStroke();
    paused.triangle(
        width / 2 - 30,
        height / 2 - 30,
        width / 2 + 30,
        height / 2,
        width / 2 - 30,
        height / 2 + 30
    );

    // Move the canvas so it’s inside our <div id="sketch-holder">.
    cnv.parent("sketch-holder");

    frameRate(30);
    noCursor();
    started = false;
    seed = 3;
    console.log(seed);
    randomSeed(seed);
    cnv.mouseClicked(() => {
        if (started) {
            seed += 1;
            console.log(seed);
            randomSeed(seed);
            t = 0;
            theShader = conf2shader(conf);
            shader(theShader);
        } else {
            started = true;
        }
    });

    conf = [
        { type: "fc", width: 2, f: "softmax" },
        { type: "fc", width: 1, f: "cos" },
    ];

    noStroke();

    theShader = conf2shader(conf);
    shader(theShader);
}

function draw() {
    // background("red");
    image(paused, -width / 2, -height / 2);
    if (started) {
        theShader.setUniform("u_resolution", [width, height]);
        theShader.setUniform("u_time", t);
        shader(theShader);
        rect(0, 0, width, height);
        t += 0.02;
    }
}

function conf2shader(conf) {
    code = parse(conf);
    console.log(code)

    fs = `// FRAGMENT SHADER
${header}

uniform vec2 u_resolution;
uniform float u_time;

#define PI 3.1415926538
#define HALF_PI 1.57079632679

#define N 3 // number of recursive applications
#define s 3. // controls steepness of fast-sigmoid
#define range 5. // xy-coords range

#define MAXSTEPS 150
#define MINDIST 0.001
#define RAD 0.4

${functions}

${code}

float SphereSDF(vec3 pos){
return length(pos) - RAD;
}

vec3 warp(vec3 p, float size){
float halfsize = size/2.;
p -= halfsize;
p = mod(p,size) - halfsize;
return p;
}

float map( vec3 p ){
vec4 inp = vec4(p,1.);
vec4 oup = forward(inp, net);
for(int i=0; i < N;i++){
oup = forward(inp + oup, net);
}
return  abs(2. - oup.x + oup.y + oup.z)/200.;
// p = warp(p, 2.);
// return SphereSDF(p);
}

vec3 getNormal(vec3 p) {
vec2 e = vec2(.01, 0.);
vec3 n = map(p) - vec3(
map(p-e.xyy),
map(p-e.yxy),
map(p-e.yyx));
return normalize(n);
}

vec3 march(vec3 from, vec3 direction) {
float totalDistance = 0.0;
int steps = 0;
float dist;
vec3 p = from;
for (int i = 0; i < MAXSTEPS; i++) {
p = from + totalDistance * direction;
dist = map(p);
totalDistance += dist;
steps += 1;
if (abs(dist) < MINDIST) break;
}

if(steps == MAXSTEPS) return vec3(0.);
float d = 1. - float(steps)/float(MAXSTEPS);
return forward(vec4(p,1.),net).rgb * d;
}

void main() {

vec2 st = (gl_FragCoord.xy - u_resolution.xy) / u_resolution.y;
st /= ${pixelDensity()}.;
st *= range;

//   float radius = distance(st,vec2(0.));

float slow = 8.;
vec3 camPos = vec3(0, 0, -2);
vec3 camViewDir = normalize(vec3(st.xy, 1.0));
camPos.x = .7;
camPos.z += u_time/slow;
vec3 col = march(camPos, camViewDir);
gl_FragColor = vec4(col,1.); // R,G,B,A
}`;

    return createShader(vs, fs);
    //return createShader(vs, trippy);
}
