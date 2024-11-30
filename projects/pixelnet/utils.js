// let header = `#ifdef GL_ES
// precision lowp float;
// #endif`;
// let vs = `// VERTEX SHADER
// ${header}
// attribute vec3 aPosition;
// // Always include this to get the position of the pixel and map the shader correctly onto the shape
// void main() {
//   // Copy the position data into a vec4, adding 1.0 as the w parameter
//   vec4 positionVec4 = vec4(aPosition, 1.0);
//   // Scale to make the output fit the canvas
//   positionVec4.xy = positionVec4.xy * 2.0 - 1.0;
//   // Send the vertex information on to the fragment shader
//   gl_Position = positionVec4;
// }
// `;

function minit() {
  return (Math.random() * 2 - 1) * 1.5;
}

function binit() {
  return Math.random();
}

function mat4init() {
  return `mat4(${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()},${minit()})`;
}

function vec4init() {
  return `vec4(${binit()},${binit()},${binit()},${binit()})`;
}

function netinit() {
  return `Net(${mat4init()}, ${mat4init()}, ${mat4init()}, ${mat4init()}, ${mat4init()}, ${vec4init()}, ${vec4init()},  ${vec4init()}, ${vec4init()})`;
}
