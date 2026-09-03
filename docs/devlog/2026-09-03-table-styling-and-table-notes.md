# Style markdown tables and render in-table footnotes as table notes

*2026-09-03 · tags: hugo, css, tables, footnotes*

## The problem

The tensor cores post needed a throughput table, and the site had never
styled one. Goldmark's bare `<table>` came out left-aligned in the default
browser look, and a footnote reference placed in a header cell
(`Sparse[^sparse]`) did not work: the reference is meant to become a
Tufte-style margin sidenote, and inside a table it rendered as a broken
inline blob instead.

Two smaller items rode along in the same session. The browser tab showed
`while(True): <post title>` on every page; it now shows only the page title
(the home page keeps the site name). And the image shortcode lost the border
and shadow around images, an edit made by hand while the table work was going
on.

## Styling the table

Hugo has had table render hooks since 0.134.0, and CI pins 0.148.2, so
`layouts/_default/_markup/render-table.html` is Hugo's default table template
with one wrapper `<div class="post-table">` around it. The wrapper is what
makes centring and overflow possible: it is `width: fit-content; margin: auto`
with `overflow-x: auto`, so a narrow table sits centred and a wide one scrolls
inside its own box instead of widening the page. `assets/css/table.css`
holds the rest: a thin rounded border on the wrapper, an uppercase muted
header row, hairline row dividers, a hover highlight, `tabular-nums`, and a
bold first column. Rounded corners with an outer border need
`border-collapse: separate; border-spacing: 0` on the table, otherwise the
collapsed borders poke through the radius.

## Why a footnote in a cell cannot be a sidenote

`layouts/partials/fn-transform.html` rewrites each Goldmark footnote
reference into a span holding a hidden checkbox, a `[n]` label, and the note
body. On screens 1600px and wider the body is a `float: right` with a
negative right margin that pushes it into the page margin; on narrower
screens the checkbox toggles it open as an inline inset. Neither works inside
a table cell. A cell is a block formatting context, so it contains its own
floats: the body floats to the right edge of the cell, not the page. And once
the table sits in a wrapper with `overflow-x: auto`, anything pushed outside
the box is clipped.

## Three attempts

The first attempt kept the sidenote behaviour and worked around the cell. A
second partial ran after `fn-transform.html`, found each sidenote inside a
`.post-table` block with a regex, and moved the checkbox and the note body out
of the table into a trailing `.post-table-notes` div, leaving only the label
in the cell. The label still toggled the checkbox through its `for`
attribute, and checkbox and body remained siblings so the narrow-screen
`:checked ~` selector kept working. On wide screens the notes container was
`position: absolute` at `top: 0` in the right margin, with the notes stacked
in normal flow so several could not overlap. This rendered correctly at both
widths. It was removed anyway, because supporting one rare case cost a
nested scroll wrapper, an absolute-positioning block under a media query, a
regex pass over the HTML, and the loss of the hover highlight that links a
label to its note (they were no longer in the same element).

The second attempt avoided code entirely by moving the reference out of the
cell into a caption paragraph under the table. Hugo's block attributes
(`markup.goldmark.parser.attribute.block = true`) let a paragraph carry a
class from a trailing `{.table-caption}` line, and a paragraph is exactly what
the sidenote machinery expects, so the note floated into the margin with no
new templates. This was the wrong reading of the request: the marker was
supposed to stay in the cell, with the explanation under the table, as table
notes are usually typeset.

The third attempt was hand-written markup: `Sparse<sup>1</sup>` in the cell
and `<sup>1</sup> text` in the caption. Zero code, but it threw away the
footnote syntax, numbered markers by hand, and duplicated the note text. It
was replaced the same day.

## The solution

`layouts/partials/table-notes.html` runs on the output of
`fn-transform.html`. For each `<div class="post-table">…</div>` block,
optionally followed by a `<p class="table-caption">`, it matches every
sidenote span inside the table, extracts the number and body, replaces the
span in the cell with `<sup>n</sup>`, and appends `<br><sup>n</sup> body`
to the caption paragraph, creating one when the table has no caption. Table
and caption are then wrapped in `<figure class="post-table-figure">`. The
author writes ordinary footnote syntax; numbering follows Hugo's global
footnote order.

Making the caption exactly as wide as the table without measuring anything
uses one CSS trick. The figure is `width: fit-content`, which would normally
grow to fit the caption text. Giving the caption `width: 0; min-width: 100%`
removes it from the figure's intrinsic width calculation while still
stretching it to the figure's final width, so the figure sizes to the table
and the caption follows. Playwright measured figure, table and caption at
376px each on desktop and 374px on a 390px viewport.

## What to know next time

The notes partial depends on the exact markup `fn-transform.html` emits: the
class names, the `[n]` label text, and the single space before the
`footnote-content` span. Changing any of it makes the regex stop matching
silently. Hugo builds, and tables with footnotes revert to showing raw
sidenote markup in cells. Both partials carry a comment saying so. Folding
the table logic into `fn-transform.html` would remove the coupling, but that
partial does global find-and-replace over the page with no notion of where a
reference sits, so it would be a rewrite rather than an addition.

Enabling block attributes changes how a line starting with `{` directly after
a paragraph, table, list or heading is parsed. All existing content was
grepped for such lines before turning it on; the only hits were inside a
plain-text attachment that markdown never renders.

Note bodies must stay inline content, the same constraint the sidenote
transform already imposes. A nested `<span>` inside a body would confuse the
lazy `.*?</span></span>` match.

The site's screenshot script in `scripts/` only knows three viewports, none
of which reaches the 1600px sidenote breakpoint. Checking margin notes means
a small Playwright script with a 1900px viewport, and `boundingBox()` values
are viewport-relative, so a clip for `fullPage: true` needs `window.scrollY`
added.
