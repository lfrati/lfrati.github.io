+++
title = 'New beginnings'
date = 2025-09-06
draft = false
summary = 'For a long time I had a simple Jekyll website but it was time for a refresh and Hugo seems pretty cool...'
math = true
thumbnail = "helloworld.avif"
+++

<script src="leader-line.min.js"></script>
<script>
    let width = 0;
    function getWidth() {
    return Math.max(
      document.body.scrollWidth,
      document.documentElement.scrollWidth,
      document.body.offsetWidth,
      document.documentElement.offsetWidth,
      document.documentElement.clientWidth
    );}
    document.addEventListener('DOMContentLoaded', function() {
        let start = document.getElementById('table-of-contents');
        let end = document.getElementById('tocButton');
        new LeaderLine( start, end, {color: 'grey', size:4, dash: {animation: true}, endPlug: 'hand', endPlugSize:0.8, startSocket : 'left', endSocket: 'top'});
        start = document.getElementById('start');
        end = document.querySelector('[data-footnote-id="fn1"]');
        let style = window.getComputedStyle(end)
        if (style.display != 'none'){
          new LeaderLine( start, end, {color: 'grey', size:4, dash: {animation: true}, endPlug: 'hand', endPlugSize:0.8, startSocket : "right", endSocket: 'bottom', path :'grid'});//, startSocketGravity:600});
        }
        width = getWidth()
        const pageWidthSpan = document.getElementById('pageWidth')
        if (pageWidthSpan) { pageWidthSpan.textContent = width }
        pageWidthSpan.style = 'color:var(--fail-red);background:#202020;padding: 0px 2px'
        if(width >= 1600){pageWidthSpan.style = 'color:var(--success-green);background:#202020;padding: 1px 3px'}
    });
</script>

{{< box warning >}}This blog is best viewed on a screen at least 1600px wide. Your width: <strong><span id="pageWidth"></span></strong>{{< /box >}}

# Table of Contents

Books are cool. Paper has a unique feeling to it but also some pretty strong limitations. For example, getting around in a book isn't always the easiest thing. Luckily for us we can use some CSS and JS to help us with a ToC. I saw one implementation I liked on [Substack](https://substack.com/) and I implemented it.

Getting the sections to highlight nicely has been more of a headache than I thought. For now I got Hugo to wrap sections into `div`s that I can then observe using [Intersection Observers](https://developer.mozilla.org/en-US/docs/Web/API/Intersection_Observer_API) {{<fn>}} I could've observed the headings but then I would've needed to keep track of state because a long section could have no headings in the viewport so... tradeoffs{{</fn>}}. 
I later stumbled upon a [scroll-driven animation](https://kizu.dev/scroll-driven-animations/#table-ofcontents-with-highlighted-current-sections) solution that looks very nice but _oh well_ future work.

Ah, before I forget, if you click on the ToC it shows you more info and lets you navigate to sections, with some highlighting upon landing. And the headings are linkable in case you are into taking quite specific notes.


# Feet, notes and footnotes

Speaking of things that are usually a pain in a book, footnotes. Gosh I hate seeing a little non-clickable [n] and then having to go hunt, first at the bottom of the page, then at the end of the chapter and then begrudgingly at the end of the book for some related info.

Hugo has some nice footnotes that send you to the bottom of the page when clicked and have a nice
"<a class="footnote-backref" role="doc-backlink">↩︎</a>" that lets you go back. Since I hope you are reading this on a _reasonably_ sized screen (a smartphone is not _reasonably_ sized, <small style="color:lightgrey">sorry</small>) I've added a preview in the right column<span id="start">.&nbsp;&nbsp;</span>

If you are a compulsive hoverer like me you've also probably already noticed that if you hover the preview or the footnote number it highlights where it's coming from. You're welcome.

# Images and captions

Images can be placed using `img` shortcode

{{< img src="gaussian_sample.png" caption="Sampled edges and their marginals for a bivariate gaussian distribution." width="400" >}}

If you would like to take a closer look because it's too small feel free to click on it and open it in a new page (I made a hover preview but the JS/CSS weren't worth it).

# Side elements do not overlap

Multiple side images and footnotes are spaced to avoid overlap. 

Here is another image but it's not immediately to the right of the link (unless you have ungodly huge font size, in which case use your imagination).

This sentence references a second note{{< fn >}}Side elements are queued and spaced; they won’t overlap even when close in the flow.{{< /fn >}} and a third note{{< fn >}}Hopefully I'm not overlapping with other elements... right?{{< /fn >}}so you can see that stacking behavior takes care of both images and sidenotes.

Placing things to the right of specific elements is a surprisingly tricky problem but maybe it'll get easier when [anchor positioning](https://kizu.dev/anchor-positioning-experiments/) becomes widely implemented.

# Interactive sketches

A fun blog needs some interactivity and my weapon of choice is [P5.js](https://p5js.org/). I've embedded one simple example below, feel free to click on it and enjoy some interactivity.

{{< p5 src="neuromodularity/threshold" size="auto" title="Geometric Graph" >}}

# Math ❤️ LaTeX

A respectable blog should also support some properly formatted math and Hugo has us covered in this department. It nicely renders both inline math like \(e^{i\pi}+1=0\) and block math with display delimiters:

_e.g._ Fibonacci sequence (recurrence):
\[
F_n = \begin{cases}
0, & n = 0 \\
1, & n = 1 \\
F_{n-1} + F_{n-2}, & n \ge 2
\end{cases}
\]
Closed form (Binet’s formula):
\[
F_n = \frac{\varphi^n - \psi^n}{\sqrt{5}}, \quad \varphi = \frac{1+\sqrt{5}}{2},\; \psi = \frac{1-\sqrt{5}}{2}
\]

# Talk is cheap, show me the code.
Okay, okay, no need to get cranky.
```python
def fibonacci_of(n):
    if n in {0, 1}:  # Base case
        return n
    return fibonacci_of(n - 1) + fibonacci_of(n - 2)  # Recursive case


# >>> [fibonacci_of(n) for n in range(32)]
#     [ 0, 1, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377, 610, 987, 1597, 2584, 4181, 6765, 10946, 17711, 28657, 46368, 75025, 121393, 196418, 317811, 514229, 832040, 1346269]  
```
There you go, nicely syntax-highlighted by Hugo and with the customary <button class="copy-button" type="button" style="opacity:1; position:static;">Copy</button> button.

# Styled external links and internal anchors
You should be careful when you click on stuff online, better to know in advance if it's going to send you somewhere far far away. To help you pack adequately for the journey external links get an icon (e.g. [Hyperlink](https://en.wikipedia.org/wiki/Hyperlink) ) while internal links do not (e.g. [Colored callouts](#colored-callouts))



# Colored callouts

Sometimes you need a bit of extra punch to make sure the user notices something. Getting that extra oomph is pretty easy with Hugo's shortcodes

{{< box important >}}Warning: Sketches run in your browser, so performance varies across devices.{{< /box >}}

# Image gallery example

And when you don't feel like making a shortcode (yet) it's pretty nice to mix some HTML into the markdown, albeit unsafe.

```html
<div style="text-align: center; padding: 10px 0;">
  <img src="/posts/neuromodularity/evolved.png" alt="Evolved topology" style="max-width: 80%; height: auto;" />
  <p style="font-size: 90%; color: #666; margin-top: 8px;">Evolved topology illustration.</p>
</div>
```

<div style="text-align: center; padding: 10px 0;">
  <img src="/posts/neuromodularity/evolved.png" alt="Evolved topology" style="max-width: 80%; height: auto;" />
  <p style="font-size: 90%; color: #666; margin-top: 8px;">Evolved topology illustration.</p>
</div>

To conclude, a special thanks to [LeaderLine](https://anseki.github.io/leader-line/) for helping me point at HTML elements
