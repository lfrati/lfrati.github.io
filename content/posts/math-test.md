+++
title = "Testing LaTeX Math Rendering"
date = 2024-01-24T18:09:49-08:00
summary = "Testing LaTeX and Hugo together like best buddies"
draft = true
+++

# Testing LaTeX Math Rendering

This post demonstrates how LaTeX math equations are rendered in your Hugo blog.

## Inline Math

You can include inline equations like this: \(a^*=x-b^*\) within your text.

Here's another inline example: \(E = mc^2\) which is Einstein's famous equation.

## Block Math

For standalone equations, you can use block formatting:

\[
\begin{aligned}
KL(\hat{y} || y) &= \sum_{c=1}^{M}\hat{y}_c \log{\frac{\hat{y}_c}{y_c}} \\
JS(\hat{y} || y) &= \frac{1}{2}(KL(y||\frac{y+\hat{y}}{2}) + KL(\hat{y}||\frac{y+\hat{y}}{2}))
\end{aligned}
\]

## Alternative Block Format

You can also use dollar signs for block equations:

$$
\int_{-\infty}^{\infty} e^{-x^2} dx = \sqrt{\pi}
$$

## More Examples

Here's a simple quadratic equation: \(ax^2 + bx + c = 0\)

And its solution:

\[
x = \frac{-b \pm \sqrt{b^2 - 4ac}}{2a}
\]

## Matrix Example

\[
\begin{bmatrix}
a & b \\
c & d
\end{bmatrix}
\begin{bmatrix}
x \\
y
\end{bmatrix} = 
\begin{bmatrix}
ax + by \\
cx + dy
\end{bmatrix}
\]