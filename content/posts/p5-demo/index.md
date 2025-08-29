+++
title = 'Geometric Random Graphs: Visualizing Network Connectivity with P5.js'
date = 2025-03-15
draft = true
summary = "Explore how geometric embedding affects network structure through interactive visualizations, demonstrating local vs global connectivity patterns in 2D space."
+++


{{< box warning >}} Warning: All sketches in this page are running on your machine. May the gods of computing bestow their blessing upon you. {{< /box >}}

## Geometric graphs

When working with networks it is common to assume that edge properties and node properties are somewhat independent. Nodes often contain information about the entity they represent and edges describe the relationships between those entities. However in `practice` it is often the case that nodes may be embedded in some space of interested. Let us consider the case where nodes represent cities and edges are the roads between them. It is intuitive to assume that each node (i.e. city) is associated [^prova] with some coordinates. Given the coordinates of a node it is natural to assume that each link (i.e. road) has a certain length that might not be explicitly listed among the properties of those edges.

{{< sidenote "this sidenote" >}} This is a sidenote content block, shown on the right on wide screens and toggled inline on mobile when the label is tapped.  {{< /sidenote >}}

These extra pieces of information are introduced by the space in which the nodes are embedded thanks to some **distance metric** (e.g. Euclidean distance) defined on it.
When this extra information is available we can employ it to enrich the mechanism that shape our networks. For example, we can make the rule that nodes are only able to make connections within a certain "range" defined by that distance like in the sketch below.

{{< sidenote "left sidenote" "left" >}} This is a sidenote content block positioned on the left side.  {{< /sidenote >}}


{{< p5 src="geometricgraph" height=400 width=400 title="Geometric Graph" >}}

### Image sidenote example

Use the `sideimg` shortcode to show an image as a sidenote on wide screens and inline on mobile. You can specify the position as the third parameter:

{{< sideimg "architecture" "/neural.webp" "right" >}}

Here's an example with left positioning:

{{< sideimg "left example" "/nnet.png" "left" >}}

## Other Section

This embedding into a 2D space can open up many new possibilities. As we have seen before the generation of random networks can now rely on the new concept of "distance".
It is now possible to define a **local** connectivity (i.e. connecting preferentially to nodes at a short distance) vs **global** (i.e. connecting equally to nodes at every distance).  {{< sidenote "this other sidenote" >}} This is a other sidenote content block, shown on the right on wide screens and toggled inline on mobile when the label is tapped.  {{< /sidenote >}} This approach[^other] is called [Geometric Random Graph](https://en.wikipedia.org/wiki/Random_geometric_graph). In this type of network the connectivity is controlled by a radius parameter, such that each node wires with all the nodes within that radius. Below you can see how the number of links and connected components vary as the radius parameter changes. The network starts off with no edges but as the connection radius increase the number of connected components quickly converges to a single giant component. We are employing a hard threshold (i.e. connections are made with every node within the range, and no nodes outside the range) for simplicity for now but other alternatives exist, where connections are made probabilistically and closer nodes have higher probabilities (i.e. Gaussian probability decay as distance increases), which we are going to use later on.

{{< box info >}} Incididunt labore eiusmod culpa eu nostrud tempor laborum consequat eiusmod excepteur.  {{< /box >}}


{{< box tip >}} Incididunt labore eiusmod culpa eu nostrud tempor laborum consequat eiusmod excepteur.  {{< /box >}}

[^prova]: This is a friggin test
[^other]: https://en.wikipedia.org/wiki/Random_geometric_graph