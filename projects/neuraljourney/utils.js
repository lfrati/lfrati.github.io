let header = `#ifdef GL_ES
precision lowp float;
#endif`;
let vs = `// VERTEX SHADER
${header}
attribute vec3 aPosition;
// Always include this to get the position of the pixel and map the shader correctly onto the shape
void main() {
  // Copy the position data into a vec4, adding 1.0 as the w parameter
  vec4 positionVec4 = vec4(aPosition, 1.0);
  // Scale to make the output fit the canvas
  positionVec4.xy = positionVec4.xy * 2.0 - 1.0; 
  // Send the vertex information on to the fragment shader
  gl_Position = positionVec4;
}
`;

let functions = `
vec4 relu_norm(vec4 xs){return (max(xs,0.)-0.4)/0.58;}
vec4 relu(vec4 xs){return max(xs,0.);}
vec4 leaky_relu(vec4 xs){return max(xs,0.1 * xs);}
vec4 sigmoid(vec4 xs){return (1.0/(1.0+exp(-2.0*xs)));}
vec4 fsigmoid(vec4 xs){return ((s * xs)/(s * abs(xs) + 1.)) * 0.5  + 0.5;}
vec4 round (vec4 xs){return floor(xs+0.5);}
mat4 lerp(mat4 w1, mat4 w2, float t){return w1 + (w2 - w1)*t;}
vec4 lerp(vec4 w1, vec4 w2, float t){return w1 + (w2 - w1)*t;}
float max4 (vec4 xs) {
  return max(max(max(xs.x,xs.y),xs.z),xs.w);
}
// https://blog.feedly.com/tricks-of-the-trade-logsumexp/
vec4 softmax(in vec4 xs){float c = max4(xs); return xs - log( dot( exp(xs - c), vec4(1.0))) - c;}
`;

function minit() {
  return (random() * 2 - 1) * 1.5;
}

function binit() {
  return -1;
}

function mat4init() {
  return `mat4(${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()})`;
}

function vec4init() {
  return `vec4(${binit()},${binit()},${binit()},${binit()})`;
}

function reseed() {
  seed = int(`${day()}${hour()}${second()}${millis()}`);
  console.log("seed", seed);
  randomSeed(seed);
}

function make_init(params) {
  init = "const Net net = Net(";
  for (let i in params) {
    p = params[i];
    if (i > 0) {
      init += ", ";
    }
    if (p[0] == "w") init += `${mat4init()}`;
    else init += `${vec4init()}`;
  }
  init += ");\n";
  return init;
}

function make_net(params) {
  net = "struct Net{\n";
  for (let p of params) {
    if (p[0] == "w") net += `  mat4 ${p};\n`;
    else net += `  vec4 ${p};\n`;
  }
  net += "};\n";
  return net;
}

function make_lerp(params) {
  lerp_fun = "Net lerp(in Net n1, in Net n2, in float t){\n  Net n3;\n";
  for (let p of params) {
    lerp_fun += `  n3.${p} = lerp(n1.${p}, n2.${p}, t);\n`;
  }
  lerp_fun += "  return n3;\n}\n";
  return lerp_fun;
}

function parse(conf) {
  forward = "vec4 forward(in vec4 x0_0, in Net net){\n";
  params = [];
  inputs = 1;
  outputs = 1;
  n = conf.length;
  i = 0;

  for (let l in conf) {
    layer = conf[l];
    inputs = outputs;

    if (l == n - 1 && layer.width != 1) {
      console.log(
        `ERROR - Expected last layer to have width 1: Found ${layer.width}.`
      );
      return "";
    }

    if (layer.type == "fc") {
      outputs = layer.width;
      forward += `  // fc : ${inputs} -> ${outputs}\n`;
      for (let out = 0; out < outputs; out++) {
        l = `  vec4 x${i + 1}_${out} = ${layer.f}(`;
        for (let inp = 0; inp < inputs; inp++) {
          w = `w${i}_${inp}_${out}`;
          if (inp > 0) {
            l += " + ";
          }
          l += `x${i}_${inp} * net.${w}`;
          params.push(w);
        }
        b = `b${i}_${out}`;
        forward += `${l} + net.${b});\n`;
        params.push(b);
      }
      forward += `\n`;
      i += 1;
    } else if (layer.type == "par") {
      outputs = inputs;
      forward += `  // par : ${inputs} -> ${
        outputs * parseInt(layer.width)
      } -> ${inputs}\n`;
      for (let inp = 0; inp < inputs; inp++) {
        merge = "";
        for (let wid = 0; wid < layer.width; wid++) {
          w = `w${i}_${inp}_${wid}`;
          params.push(w);
          matmul = `x${i}_${inp} * net.${w}`;
          forward += `  vec4 x${i + 1}_${inp}_${wid} = (${matmul});\n`;
          if (wid > 0) merge += " + ";
          merge += `x${i + 1}_${inp}_${wid}`;
        }
        b = `b${i}_${inp}`;
        params.push(b);
        forward += `  vec4 x${i + 1}_${inp} = ${
          layer.f
        }(${merge} + net.${b});\n`;
      }
      forward += `\n`;
      i += 1;
    } else if (layer.type == "fun") {
      outputs = inputs;
      forward += `  // map ${layer.f} : ${inputs} -> ${outputs}\n`;
      for (let inp = 0; inp < inputs; inp++) {
        forward += `  x${i}_${inp} = ${layer.f}(x${i}_${inp});\n`;
      }
      forward += "\n";
    }
  }

  forward += `  return x${i}_0;\n}\n`;

  net = make_net(params);
  init = make_init(params);
  lerp_fun = make_lerp(params);
  code = [net, init, forward, lerp_fun].join("\n");

  return code;
}