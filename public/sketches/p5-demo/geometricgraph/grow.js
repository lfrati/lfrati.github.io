let nodes = [];
let edges = [];
let radius = 50;
let numNodes = 50;

function setup() {
  createCanvas(400, 400);
  background(0);
  
  // Create random nodes
  for (let i = 0; i < numNodes; i++) {
    nodes.push({
      x: random(width),
      y: random(height),
      id: i
    });
  }
  
  // Create edges based on radius
  createEdges();
}

function draw() {
  background(0);
  
  // Draw edges
  stroke(255, 100);
  strokeWeight(1);
  for (let edge of edges) {
    line(edge.from.x, edge.from.y, edge.to.x, edge.to.y);
  }
  
  // Draw nodes
  fill(255);
  noStroke();
  for (let node of nodes) {
    ellipse(node.x, node.y, 6, 6);
  }
  
  // Draw radius circle around mouse
  if (mouseX > 0 && mouseY > 0) {
    stroke(255, 50);
    strokeWeight(1);
    noFill();
    ellipse(mouseX, mouseY, radius * 2, radius * 2);
  }
}

function createEdges() {
  edges = [];
  for (let i = 0; i < nodes.length; i++) {
    for (let j = i + 1; j < nodes.length; j++) {
      let d = dist(nodes[i].x, nodes[i].y, nodes[j].x, nodes[j].y);
      if (d <= radius) {
        edges.push({
          from: nodes[i],
          to: nodes[j]
        });
      }
    }
  }
}

function mousePressed() {
  // Add new node at mouse position
  let newNode = {
    x: mouseX,
    y: mouseY,
    id: nodes.length
  };
  nodes.push(newNode);
  
  // Create new edges
  for (let i = 0; i < nodes.length - 1; i++) {
    let d = dist(newNode.x, newNode.y, nodes[i].x, nodes[i].y);
    if (d <= radius) {
      edges.push({
        from: newNode,
        to: nodes[i]
      });
    }
  }
}

function keyPressed() {
  if (key === 'r' || key === 'R') {
    // Reset
    nodes = [];
    edges = [];
    for (let i = 0; i < numNodes; i++) {
      nodes.push({
        x: random(width),
        y: random(height),
        id: i
      });
    }
    createEdges();
  } else if (key === '+') {
    // Increase radius
    radius += 10;
    createEdges();
  } else if (key === '-') {
    // Decrease radius
    radius = max(10, radius - 10);
    createEdges();
  }
}
