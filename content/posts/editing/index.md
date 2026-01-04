+++
title = "An elegant editor for a more civilized age"
date = 2025-10-06
draft = false
summary = "The features of an editor that make editing text a pleasure"
+++

# Why (Neo)Vim is popular
tl;dr IMHO it's not about the editor (which is amazing). It's how well it implements some key text-editing ideas.

People love to debate which editor is the best. Why VSCode is so much better than Neovim. Why Neovim is so much better than Vim. [Or why real programmers use butterflies.](https://xkcd.com/378/)

But if I had to argue why I like Neovim, I would say it's not about Neovim.
It's about the fact it very effectively implements a few key concepts that make text editing a pleasure.

# Concept 1: Meta(editing)

An editor sits between your thoughts and the text.
But unfortunately your thoughts don't immediately map to text (yet?).
Sometimes you want to _talk text_ to put down words, sometimes you want to _talk TO the text_ to arrange or reshape those words.

If you use Word to edit code, well first of all how do you stand with such massive cojones, and second, you've probably transcended physical reality so you are not reading this. But let's say for the sake of argument you do indeed use Word.
The communication channel with the text is your keyboard. The communication channel with Word is the mouse. Pretty easy and straightforward.

However reaching for the mouse all the time and clicking through the interface is not pleasant. Maybe you just want to make a word **bold**, and your hands are already on the keyboard so you think why not just use a shortcut, let's say `Cmd+b(old)`. {{<fn>}} While writing this I asked my wife to check that Cmd+b makes text bold in Word. She said "ok, wait I'm starting the application and it takes a while..." foreshadowing #3 {{</fn>}}

After a while you might think, there is also this other thing that I really like to do often, maybe I should make another shortcut...
The problem is that the keyboard is already very busy with the alphabet. So you gotta get creative with Ctrl/Alt \& co. Things quickly get out of control.

But then a thought occurs to you.
What if your editor listened for instructions on what to do with your text, and when you tell it "Listen, I'm about to give you a bunch of text, write it down until I send you another special character" it then, and only then, starts putting your words into the file..
Then talking to the editor would become your... let's say "normal" mode?

Now your life is great, you have the same power of creating text you had before, at the press of a key. And for that tiny overhead you now have access to a whole new mode of interacting with the editor, now you two can speak a common language.


# Concept 2: Multidimensional arrangements

{{< wrap src="images/text.png" caption="" align="left" width="100" >}}

I'm not familiar with the evolution of UX for text editing, but I have a feeling that there is a reason text files are usually shaped like pages. Because that makes sense to anyone that ever held a book (people still read those, right?).
And so when you open several files the "pages" get arranged in a neat list of tabs. The current page is highlighted and the other pages are one click away, to the left/right of it.
{{< img src="images/tabs.png" caption="Tabs? Pages? Chaos?" width="600" >}}

But that analogy is not that great if you think about it. Because what you have on screen is quite different than a book. Maybe a massive scroll would be more accurate? The main issue is that at any time you only see a small portion of the scroll. And to move around you gotta scroll, a lot. But that's not nice.

Luckily you don't have to. Because some editors (*cough* n?vim *cough*) let you have multiple views on different areas of the same long-ass scroll. That's both a blessing and a curse because it trips up people that arrive in vim-land expecting the _pages analogy_.

Instead enlightened editors do it this way:
- Buffers represent files loaded in memory.
- [Windows](https://neovim.io/doc/user/windows.html) (not to be confused with the OS) are viewports into existing buffers. Different windows can show different parts of the same buffer.
- Tabs are collections of windows.

Please refer to the following [explanatory graphics](https://dev.to/iggredible/using-buffers-windows-and-tabs-efficiently-in-vim-56jc) (<small>consult a doctor if headache persists for more than 24h, don't show to kids under the age of 10</small>)
{{< img src="images/vim_tabs.webp" caption="Mind expansion in progress..." width="400" >}}

Isn't it beautiful? It basically gives you [compound eyes](https://en.wikipedia.org/wiki/Compound_eye), each fragment a window (again, not the OS. Pretty much never the OS) into a different part of a document.

# Concept 3: Get out of your way

I've so far talked about ways of interacting with and thinking about text that makes sense to me. The last point I want to mention is more practical.

_It's about getting out of your effin' way._ Become an invisible layer between the screen and your thoughts. And that requires one key ingredient: being responsive and unintrusive.

I've sometime chatted with friends about editing text and one adage I've often heard was some variation of "The editor is not the bottleneck, my thinking takes most of the time anyways." What I personally want is to be in the flow. To look at the screen and see words appear, be it quickly or slowly. I want every twitch of my fingers to be followed by a transformation of the state in front of me.

This can only happen if the system can process keystrokes fast. You might think: "Duh, what kind of potato cannot process keystrokes adequately?". I guess a blazingly fast potato being fried in a ton of crappy code? For example, I've used vim-mode plugins in VSCode. Switching modes was slow enough that sometimes keystrokes would get lost, and I would fail to change mode and it would start interpreting text as commands or vice-versa, not great. Some other editor... let's just say it's still opening.

Responsiveness is only half of the equation. Another key component of flow for me is lack of distractions. If you don't need a button don't press it, right? WRONG. My brain hates visual clutter, the feeling of claustrophobia when usable space is taken away and offered in sacrifice at the altar of GUI, the nagging sensation of having multiple buttons tugging your gaze towards them, flashing even! TUIs have an elegance to them, a calm quiet, a lack of interactivity that becomes strength, not weakness.

This is it. I like an editor that allows me to easily talk to it, that arranges text in flexible and powerful ways, while being responsive and undistracting.
An editor that lets the quantum wave of my thoughts expand and morph freely. Instead of collapsing it into drudgery.

## (Bonus) Lua is a very cool language.
Unlike [vimscript](https://vimdoc.sourceforge.net/htmldoc/usr_41.html), Lua is a small, elegant language that's a pleasure to use. So much so it made me want to write my own [search plugin](https://github.com/lfrati/onesearch.nvim) and [slime-like plugin](https://github.com/lfrati/szent.nvim).
