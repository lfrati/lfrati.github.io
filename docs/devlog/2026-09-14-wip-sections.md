# Mark unfinished sections as WIP and refuse to publish a post that has any

*2026-09-14 · tags: hugo, css, drafts, toc*

## The problem

A long post is written out of order. Some sections are done, some are a
paragraph and a note to self, and nothing in the source or the preview tells
them apart. The tensor cores draft had `<-TODO: what's register pressure?->`
sitting in the middle of a section: not an HTML comment, so it would have
rendered as visible text the day the post went live. The `<!-- -->` comments
used elsewhere in the same file have the opposite failing: invisible, so they
never nag.

The collatz paper solves this with a fenced div, `::: wip … ::: endwip`,
which renders the enclosed blocks in red with a rule down the left. The blog
needed the same two things: a mark that is loud in the preview, and a
guarantee that a post carrying one cannot be published.

## The shortcode pair, and why it was dropped

Hugo has no fenced-div syntax, so the first idea was a pair of shortcodes,
`{{< wip >}}` emitting `<div class="wip">` and `{{< endwip >}}` emitting
`</div>`. Hugo swaps `{{< >}}` shortcodes for placeholder tokens before
Goldmark runs and substitutes their HTML back afterwards, so the markdown
between the two tags is parsed as ordinary page content: headings, tables
and footnotes inside the region all went through their normal pipeline, and
a footnote kept the page's global numbering and became a sidenote. Hugo
also strips the `<p>` that Goldmark would otherwise wrap around a
placeholder standing on its own line, so the output was clean.

A paired `{{% wip %}} … {{% /wip %}}` with `.Inner` was tried first and
rejected: the `<div>` the shortcode emits opens a CommonMark HTML block that
swallows everything up to the next blank line as literal HTML, so
`**bold**` and `[^n]` came out raw. Blank lines around the tags in the
template fix that, but the open/close pair avoids the question entirely.

What killed the pair was the TOC. `render-heading.html` wraps every H1
section of a post in `<div class="toc-section">`, closing the previous one
when the next H1 arrives. A wip region that contained an H1 had its
`</div>` stolen by that wrapper: the divs crossed, and everything after the
region stayed red. Coordinating the two through `Scratch` does not work,
because shortcodes are not executed in document order relative to render
hooks; a probe showed the section flag already set when a shortcode placed
above the first H1 ran. A guard was built instead: a shortcode knows its
own `.Position` and can `os.ReadFile` the page source, so `wip` scanned
forward to its `endwip` and raised `errorf` on a spanning H1, a missing
closer, or a second opener, and `endwip` scanned backward for its opener.
It worked, seven cases verified, but it was twenty lines of template
defending a rule ("do not span an H1") that only exists because the region
fights the section wrapper.

## The solution

Mark the section, not the paragraphs. `# Title {.wip}` uses the Goldmark
heading attribute syntax the site already relies on for `{.table-caption}`.
The heading hook reads `.Attributes.class`, adds `wip` to the section
wrapper it was going to emit anyway, and records the anchor with
`.Page.Scratch.SetInMap "tocwrap_wip"`. There is nothing to close and
nothing to mis-nest: the region is the wrapper, and the wrapper ends where
the next H1 begins.

The publish gate is one `errorf` in the same branch, raised when the page is
not a draft. CI runs `hugo` without `--buildDrafts`, so a draft never ships
regardless; the gate closes the remaining hole, which is flipping
`draft = false` with a section still marked. The build then dies locally
and in CI with the section title and file in the message. Verified: a
draft with a wip section builds and is skipped under CI flags; the same
page with `draft = false` exits 1; with the mark removed it builds.

The TOC costs two lines. `toc-h1-extract.html` runs after `.Content` has
been rendered, so it reads the `tocwrap_wip` map and adds a `wip` boolean
per heading, and `single.html` puts the class on the line in the button and
the entry in the pane. `wip.css` colors the section red with a left rule, a
small WIP badge after the H1, and the matching TOC line and entry, using a
new `--wip-color` in the root palette.

## What to know next time

Only H1 sections can be marked. H2s are not wrapped by the hook, so
`## sub {.wip}` would color the heading and nothing else. If a paragraph-
level mark is ever needed, the shortcode pair from above can be added
*inside* a section without conflict, since the crossing only happens across
an H1 boundary.

The wrapper must stay a plain block: no `overflow: hidden` on
`.toc-section.wip`, or it becomes a formatting context and traps the margin
sidenotes inside it, the same failure the table-notes work ran into with
cells. A wide-screen check confirmed the sidenote in the marked section
still floats out to the right margin.

`toc-h1-extract.html` depends on `.Content` having been rendered before it
is called, which `single.html` guarantees by rendering the content first.
Calling it earlier would find an empty map and silently show no WIP entries.
