# Rebuild the tagline typing animation on keystroke timings and ship it as a tape

*2026-09-10 · tags: hugo, javascript, animation, home*

## The problem

The home page tagline types itself out on load, added in `0179fd7`. It did
not look like typing. Every gap came from the same expression regardless of
what was being typed: `15 + r*r*45` inside a word, `25 + r*r*170` at a space,
with a fixed extra pause after `.` and `,` and a 4% chance of a stall
anywhere. Squaring the uniform skews the gaps low, so most are short and a
few are long, which is the right shape in aggregate. The trouble is that the
shape was the only structure present. The delay before a character had no
relationship to that character, so the line came out as noise at a constant
average rate.

## What real typing timings look like

Two facts from the keystroke dynamics literature drove the rewrite.

The first is that the gap between two keys depends mostly on which fingers
they need. Gentner measured experienced typists at a mean of 114ms when the
two keystrokes fall on different hands, range 90 to 157, against 131ms when
one hand types both, range 99 to 215. Alternating hands is faster because the
next finger can start moving while the current key is still travelling. Dvorak
put opposite-hand digraphs about 11.5% above the overall average rate. So the
same-hand and different-hand cases differ by roughly 15%, and the same-finger
case is much worse than either.

The second is the shape of the distribution. A study fitted fourteen
candidate distributions to flight times in free-text keystroke profiles,
including log-normal, gamma, Weibull, Burr and exgaussian. The log-logistic
won outright in both the two- and three-parameter families, taking above 65%
of best-match counts on most datasets against 28% for log-normal. Flight times
are positively skewed with a heavy right tail.

Both are cheap to implement. The keyboard is four row strings plus a
touch-typing finger assignment, which gives each character a hand, a finger
and a row. `gap()` then returns a median: 88ms for the same key twice, 108ms
for alternating hands, 136ms plus a row-distance term for same hand different
finger, 188ms plus a larger row term for the same finger on a different key,
and 72ms on top when shift is needed and was not already held. Sampling is the
log-logistic inverse CDF, `alpha * (u/(1-u))^(1/beta)`, which is one line.

On the current tagline this fires 46 alternating-hand pairs, 38 same-hand
different-finger, 9 same-finger and 43 involving the space bar. That spread is
what stopped it reading as a machine.

A mean-reverting random walk on a rate multiplier sits on top of that, so
fluent and laboured stretches last several characters. Per-key noise
averages out immediately and is not audible; drift is.

## Realism and patience are in direct conflict here

The first working version ran the line at 73 words per minute, which is an
ordinary skilled typing speed, and took 22.4 seconds. The tagline is 136
characters, and at any honest human rate a line that long takes 14 to 20
seconds. The original animation did it in about 5, which works out to 326 wpm
and is precisely why it did not look human.

The fix was to scale keystrokes without scaling the pauses. A quick typist
moves their fingers much faster than a slow one but does not think
proportionally faster, so flattening the sentence-end and comma pauses along
with the keys turns the result back into a machine reeling off characters.
Keystrokes divide by a tempo factor, pauses by its square root.

## Trying to guarantee a speed floor by inflating the mean

The request was for at least 130 wpm, measured over the whole line including
pauses. At that point the animation still sampled fresh on every load, so the
rate was a random variable and 130 had to be a floor rather than an average.

This went badly. Over 200 simulated loads the minimum was 88 wpm against a
median of 110. Tightening the drift's mean reversion from 0.06 to 0.16 and the
log-logistic tail clamp from 3.4 to 2.9 helped the spread. Cutting the typo
rate from 1.8% to 1.1% per letter helped more, since each typo and its
correction cost around a second and the count was Poisson with a mean near
two.
The floor still sat around 120. Reaching a hard 130 meant a tempo that put the
median near 180 wpm and the maximum above 200, which is not plausible typing.

The approach was wrong. Guaranteeing a floor on a random variable by raising
its mean wastes the whole distribution to protect against its own tail. The
answer, which came from the user, was to stop sampling at runtime: record one
take and replay it. A seeded generator, mulberry32 with a fixed seed, makes
the sequence deterministic, and a deterministic line has an exact rate rather
than a distribution with a floor.

## The typo that landed on the first character

While the seed was still a placeholder the animation mistyped the very first
character of the line. That reads as a broken page, not as a person. The
guard added afterwards restricts a slip to the middle of the text, between
25% and 80%, because one in the first word looks like a bug and one in the
last few characters never gets a chance to resolve before the cursor settles.

The guard is still in `record-typing.js` but is currently unreachable: typos
were dropped entirely at the user's request. One fumble per line reads as
charming in principle and as sloppy in practice on a page you see every time
you visit the site.

## An escaping trap, hit three times

The layout was being rewritten through shell heredocs. Inside a JavaScript
string literal `\;` is not an escape sequence, so it evaluates to a bare `;`
and the backslash disappears. Two tables depended on it. The right-pinky
finger group lost the `\` key, leaving that key with no hand or finger, and
`BASE` came out 20 characters against `SHIFTED`'s 21, which silently shifted
every symbol from `|` onwards by one position so `|` resolved to `;` and `:`
to `'`.

None of it was visible, because the tagline contains no backslashes and no
shifted punctuation. It would have surfaced only when the tagline changed.

Fixing it took three attempts, and two of those failed for a separate reason:
the replacement pairs written into the patch script were byte-identical, an
old string and a new string that differed only in an escape the Python parser
had already collapsed. An `assert old != new` catches this immediately and is
worth writing by default. The final version built the backslash with
`chr(92)` to sidestep the question. A check that every printable ASCII
character resolves to a real key, and that `SHIFTED` and `BASE` are the same
length, now runs as part of verification.

## Landing on a speed

The declared rate went 150, then 180, then 280 wpm, iterating against how it
actually looked rather than against the number. Total time on screen fell
from 9.33 to 5.97 seconds. Halving the lead-in from 260ms to 140ms mattered more per
millisecond than the rate did, because dead air before anything happens is the
part that reads as sluggish.

The tempo is solved from the composed take rather than tuned by hand, so the
declared rate is exact. Total time is `K/T + Q/sqrt(T)` where `K` is the
keystroke budget and `Q` the pauses. Substituting `u = 1/sqrt(T)` makes this
`K*u^2 + Q*u - want = 0`, an ordinary quadratic, so it solves in closed form.
This replaced 60 rounds of bisection and agrees with them to 4.4e-16.

One bug here is worth recording. The solver budgeted the pause owed by the
final character, which is never served because nothing follows it. The line
finished early at 185 wpm against a declared 180 until `Q` dropped that term.

## Recording the tape

An audit answered whether the model was worth shipping. It defined 47 keys and
the tagline touches 23. The shifted-symbol table took zero lookups, since
capitals go through a separate branch. The double-tap branch never fired,
because the sentence happens to contain no doubled letter. And the whole thing
existed to compute a constant: 136 numbers, 415 bytes.

Page weight was never the argument. The script was 3.1KB gzipped against a
26KB CSS bundle and 3.5MB of images, on a site that already ships a 100KB
copy of leader-line and per-post sketches of 7 to 14KB. The argument is that a
seeded generator computing a fixed answer on every page load is machinery
pretending to be a decision.

So the model moved to `scripts/record-typing.js` and the page now replays what
it produced. Recording captures the delays the script asks for, run under Node
with a stubbed `document`, `window` and `setTimeout`. It does not measure a
real browser. Observed wall-clock timings would bake one machine's scheduler
jitter, layout cost and frame boundaries into the site and would differ on
every capture. The requested delays are the artifact.

Truncation is what makes the recording exact rather than approximate. The old
code passed fractional milliseconds to `setTimeout`, whose `timeout` argument
is an IDL `long`, so a browser discards the fraction before scheduling
anything. Storing `Math.trunc` of each delay records what was really being
scheduled. The two versions were then diffed by running each under the same
stub and comparing what they scheduled: all 136 delays identical, the cursor
blinking on the same two pauses at indices 0 and 75, the same final text, and
5.901 seconds both.

The page script went from 7506 bytes to 2444, or 3097 to 1144 gzipped, and is
now a 136-number array and a 22-line player.

## What to know next time

`setTimeout` truncates. The `timeout` argument is an IDL `long`, so
`setTimeout(fn, 192.7)` fires at 192ms. Fractional delays computed anywhere in
an animation are already being discarded, which means recording integers loses
nothing.

The generator was kept rather than deleted, because the speed knob is the part
that actually got used and it is worth being able to turn again. Re-run
`node scripts/record-typing.js` after editing the tagline in
`content/_index.md` or changing `WPM`, and it patches the tape back into the
layout between the `tape:start` and `tape:end` markers. `--dry-run` prints
without writing.

A tape only fits the text it was cut from, so the player compares
`TAPE.length` against `text.length` and does nothing when they disagree.
Editing the tagline without re-recording shows the line plainly instead of
typing out something wrong. That failure is loud enough to notice and safe
enough to ship.

Running a page script under Node with a stubbed DOM is a cheap and exact way
to test animation timing. Capturing the `setTimeout` sequence proves
equivalence between two implementations far better than watching them, and it
also verified the reduced-motion path, the stale-tape guard, and the missing
element case without a browser.

Pauses must not scale with tempo the way keystrokes do. This is the one part
of the model that carries the human rhythm at high speed. At 280 wpm the
median gap is 36ms while the longest pause is still 244ms, and that ratio is
what stops it sounding mechanical.
