// Records the home page typing animation to a tape of millisecond delays.
//
// The animation used to carry this model in the page and re-derive its timings
// on every load. It never needed to: the generator is seeded, so it produces
// one fixed sequence. This script runs it once, offline, and writes that
// sequence into layouts/index.html, leaving the page with a short player.
//
// Nothing here is measured against a clock. These are the delays the animation
// asks for, not delays observed in a browser, which would bake one machine's
// scheduler jitter into the site.
//
//   node scripts/record-typing.js            re-record and patch the layout
//   node scripts/record-typing.js --dry-run  print the tape, touch nothing
//
// Re-run it after editing the tagline in content/_index.md, or after changing
// WPM below. The player refuses to animate if the tape and the text disagree,
// so a stale tape shows up as no animation rather than as wrong timings.

import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const LAYOUT = join(ROOT, 'layouts', 'index.html');
const SOURCE = join(ROOT, 'content', '_index.md');

const WPM = 280;  // how fast the whole line reads out
const LEAD = 140; // dead air before the first key, outside the WPM budget
const SEED = 6;   // which take to record

/* ------------------------------------------------------------------------
   A keyboard. What reads as human is not randomness but which fingers are
   involved: Gentner measured skilled typists at ~114ms between keystrokes when
   the hands alternate and ~131ms (up to 215ms) when one hand types both,
   because alternating hands let the next finger start moving before the
   current key has even landed.
------------------------------------------------------------------------ */
const ROWS = ['`1234567890-=', 'qwertyuiop[]\\', "asdfghjkl;'", 'zxcvbnm,./'];
const OFFSET = [0, 0.5, 0.75, 1.25];  // the stagger between rows
const FINGERS = {                     // standard touch-typing assignment
  L4: '`1qaz', L3: '2wsx', L2: '3edc', L1: '45rtfgvb',
  R1: '67yuhjnm', R2: '8ik,', R3: '9ol.', R4: "0-=p[]\;'/",
};
const SHIFTED = '~!@#$%^&*()_+{}|:"<>?';
const BASE    = "`1234567890-=[]\;',./";

const KEYS = {};                      // char -> {r, x, hand, finger}
ROWS.forEach((row, r) => {
  for (let c = 0; c < row.length; c++) KEYS[row[c]] = { r, x: c + OFFSET[r] };
});
for (const [finger, chars] of Object.entries(FINGERS)) {
  for (const ch of chars) if (KEYS[ch]) { KEYS[ch].hand = finger[0]; KEYS[ch].finger = finger; }
}

// Which physical key a character is, and whether shift is held for it.
function key(ch) {
  if (!ch) return null;
  if (ch >= 'A' && ch <= 'Z') return { k: ch.toLowerCase(), shift: true };
  const s = SHIFTED.indexOf(ch);
  if (s >= 0) return { k: BASE[s], shift: true };
  return { k: ch, shift: false };
}

// Median gap between two characters, from the fingers they ask for.
function gap(prev, ch) {
  const a = key(ch), b = key(prev);
  if (!a) return 120;
  const ka = KEYS[a.k], kb = b && KEYS[b.k];
  let ms;
  if (!ka || !kb) ms = 104;                              // space (thumb), off-map
  else if (a.k === b.k) ms = 88;                         // "ll", "ss": a double tap
  else if (ka.hand !== kb.hand) ms = 108;                // hands alternate: fastest
  else if (ka.finger !== kb.finger)                      // same hand, other finger
    ms = 136 + 15 * Math.abs(ka.r - kb.r);
  else ms = 188 + 22 * Math.abs(ka.r - kb.r);            // same finger again: worst
  if (a.shift && !(b && b.shift)) ms += 72;              // pinky has to find shift
  return ms;
}

function mulberry32(a) {
  return function () {
    a |= 0; a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/* Gaps between keystrokes are positively skewed with a heavy right tail.
   Fitting fourteen distributions to free-text keystroke data, the log-logistic
   wins outright, so sample its inverse CDF instead of reaching for a uniform:
   alpha is the median, beta the tightness. */
function record(text) {
  const rand = mulberry32(SEED);
  const loglogistic = (alpha, beta) => {
    const u = rand();
    return alpha * Math.min(Math.max(Math.pow(u / (1 - u), 1 / beta), 0.5), 2.9);
  };

  // One entry per character: `k` is the time the fingers need to reach the key,
  // `q` the pause owed once it has landed. They do not scale together, so they
  // are kept apart until the tempo is known.
  const seq = [];
  let rate = 1, K = 0, Q = 0;
  for (let n = 0; n < text.length; n++) {
    const k = loglogistic(gap(text[n - 1], text[n]), 5.5) / rate;
    // Speed drifts as a mean-reverting walk rather than fresh noise per key,
    // which is what makes a stretch feel fluent or laboured.
    rate += (1 - rate) * 0.16 + (rand() - 0.5) * 0.19;
    rate = Math.min(Math.max(rate, 0.7), 1.55);

    // The hand rests longest at the end of a sentence, a little at a comma, and
    // now and then stalls at a word break the way a person reaching for the
    // next word does.
    const ch = text[n];
    let q = 0;
    if (ch === '.' || ch === '!' || ch === '?') q = 165 + rand() * 195;
    else if (ch === ',' || ch === ';' || ch === ':') q = 85 + rand() * 105;
    else if (ch === ' ' && rand() < 0.05) q = 105 + rand() * 180;

    seq.push({ k, q });
    K += k; Q += q;
  }
  // The pause owed by the last character is never served: nothing follows it.
  Q -= seq[seq.length - 1].q;

  /* Solve for the tempo that lands the line on WPM. Keystrokes divide by the
     tempo but pauses only by its square root: a quick typist moves their
     fingers much faster than a slow one but does not think proportionally
     faster, and flattening the pauses along with the keys turns the whole thing
     back into a machine reeling off characters. Substituting u = 1/sqrt(T)
     makes this a quadratic, so it solves exactly rather than by search. */
  const want = (text.length / 5) / WPM * 60000;
  const u = (-Q + Math.sqrt(Q * Q + 4 * K * want)) / (2 * K);
  const T = 1 / (u * u), S = Math.sqrt(T);

  // A pause counts as thinking, and gets a blinking cursor, once it is several
  // times longer than this typist's ordinary gap between keys.
  const think = Math.round(4 * (K / seq.length) / T);

  // setTimeout takes an IDL long, so a browser discards the fraction anyway.
  // Truncating here records what is actually scheduled, not what was computed.
  const tape = seq.map((s, i) => Math.trunc(s.k / T + (i ? seq[i - 1].q / S : LEAD)));
  return { tape, think, T, want };
}

function tagline() {
  const raw = readFileSync(SOURCE, 'utf8');
  const body = raw.split(/^\+\+\+$/m).slice(2).join('+++').trim();
  if (!body) throw new Error('no tagline body found in ' + SOURCE);
  return body;
}

const text = tagline();
const { tape, think, want } = record(text);
const total = tape.reduce((a, b) => a + b, 0);

const block = [
  '        /* tape:start  ' + tape.length + ' keystrokes, ' + WPM + 'wpm, ' +
    (total / 1000).toFixed(2) + 's. Regenerate with scripts/record-typing.js */',
  '        var THINK = ' + think + ';',
  '        var TAPE = [',
];
let line = '         ';
tape.forEach((d, i) => {
  const piece = ' ' + d + (i === tape.length - 1 ? '' : ',');
  if ((line + piece).length > 78) { block.push(line); line = '         '; }
  line += piece;
});
block.push(line, '        ];', '        /* tape:end */');
const rendered = block.join('\n');

console.log(text.length + ' chars, ' + tape.length + ' keystrokes');
console.log('lead-in ' + tape[0] + 'ms, total ' + (total / 1000).toFixed(2) + 's');
console.log('typing rate ' + ((text.length / 5) / ((total - LEAD) / 60000)).toFixed(1) + ' wpm' +
            '  (target ' + WPM + ', budget ' + (want / 1000).toFixed(2) + 's)');
console.log('blinking cursor on ' + tape.filter((d) => d > think).length +
            ' pauses over ' + think + 'ms');

if (process.argv.includes('--dry-run')) {
  console.log('\n' + rendered);
} else {
  const layout = readFileSync(LAYOUT, 'utf8');
  const start = layout.indexOf('        /* tape:start');
  const end = layout.indexOf('/* tape:end */');
  if (start < 0 || end < 0) throw new Error('tape markers not found in ' + LAYOUT);
  const patched = layout.slice(0, start) + rendered +
                  layout.slice(end + '/* tape:end */'.length);
  writeFileSync(LAYOUT, patched);
  console.log('\nwrote tape into layouts/index.html');
}
