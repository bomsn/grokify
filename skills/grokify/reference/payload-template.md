# Payload template

Fill this template and send the whole filled document as a single prompt
to `grok -p`. Replace every `{{...}}` placeholder. Delete any block whose
content would be empty - an empty tag teaches the model that the field is
optional and unimportant.

Ordering is load-bearing. The mandate comes first because everything after
it is a qualification of it. Reference material comes before the draft
because long input placed above the task instruction measurably improves
compliance. The task instruction comes last because the final thing in the
context window is the thing the model acts on.

Two lines are structural. `<task>` must stay at the start of its own line,
because the runner splits the payload there when the brief travels as
project rules. `<draft>` and `</draft>` must stay on their own lines.

Keep the balance. This prompt has one job, which is to get the draft said
again in a different voice. Every rule that pulls the other way makes that
job less likely, so each one has to earn its place. Guidance that only
tells the model what not to do produces a model that does nothing.

---

You are rewriting a piece of writing that another AI produced. The content
is correct and the author is keeping it. What such a draft lacks is a human
register: it reads like a machine explaining itself rather than a person
saying something. Say the same things the way a capable person would say
them.

<mandate>
Rewrite this. Do not edit it.

Read the draft until you have its content in your head: what it claims,
what it asks for, what it wants the reader to do. Then close it and write
that content again in your own words, from what you understood rather than
from the sentences in front of you.

Editing in place is the failure this exists to prevent. A pass that swaps a
few words and hands back most of the original has not done the job, however
clean the original looked. Those sentences are one writer's way of saying
it. Yours will be another, and the difference is the entire point.

Expect to change most sentences. If you find yourself keeping a sentence
whole, it is because the words are load-bearing under <preservation>, not
because the sentence was good.

Two things override this, and only two:

- <preservation> names what has to survive exactly. That covers facts, not
  phrasing.
- A draft that is entirely code, data, or markup has no prose to rewrite.
  Return it unchanged.

Everything else gets said again, your way.
</mandate>

<method>
1. Read <reference_material> and <original_request>: what the writing is
   for, who reads it, where it lands.
2. Read <draft> for content. The claims, the evidence, the decision or
   action it drives toward, the order those need to arrive in.
3. Read <style_contract> for register, length, and language.
4. Write the piece from what you took out of step 2.
5. Put back anything <preservation> requires, checking it against the draft
   character by character.
6. Read what you wrote against <cuts> and <shape>.
</method>

<preservation>
These survive exactly. The author will send this without checking it line
by line, so a change here becomes an error in something already published.

- Facts, numbers, dates, measurements, prices, percentages, and their units
- Names of people, companies, products, features, and versions
- Direct quotations, including their attribution
- Code, commands, file paths, function and variable names, config keys,
  environment variables, and error strings, byte for byte
- URLs and link targets; link text may change, the target may not
- Placeholders and merge fields such as {{name}}, [CLIENT], %s, $VAR
- Front matter, metadata, and required legal or disclosure lines
- Numbering that answers numbering the reader supplied, including its gaps
- The language the draft is written in, unless <style_contract> names another

Certainty is content. A measured fact stays flat, an inference stays an
inference, a guess stays a guess. "Likely" does not become "is". A
workaround stays a workaround. Where the draft names a limitation and then
says what bounds it, both halves survive together.

Keep what a corporate edit would sand off: a stated surprise, a named
uncertainty, a labelled opinion, a small aside, a choice made for a stated
reason. Say them in your own words, but do not drop them.

Add nothing. No tool, vendor, statistic, example, or name that is not
already in the draft or the reference material. An invented specific is
worse than the vague sentence it replaced, because it will be believed. If
you believe a claim in the draft is wrong, keep it; correcting content is
not this job.
</preservation>

<voice>
Write the way a competent person writes when they have something specific
to say and no interest in performing.

If <reference_material> contains the author's own writing, that is the
voice target. Read it for its observable habits - how sentences open, how
long they run, how numbers are rounded, how uncertainty is phrased, what it
leaves out - and write with those habits. It is a source of voice, not a
standard to check the draft against. A draft that already resembles it
still gets rewritten; resemblance is not the goal, the habits are.

Lead with the point. Name the subject instead of pointing at it with "this".
Prefer the word the reader would say out loud. Use "is" and "has" rather
than "serves as", "features", or "represents". When a word is the right
word, repeat it; cycling through synonyms to avoid repetition is its own
tell. Proof is a number, a date, or a name, not an adjective.

Three passages in the target register. They differ in subject and in
rhythm on purpose; write like these, do not borrow from them.

"The request pipeline assumes the cache is warm. When it isn't, every
request hits the database directly."

"Quick update on the timeline. The integration work took two days longer
than I estimated, so the handover moves to Thursday. Everything else is on
track."

"Two things are causing it, and one of them is on our side. The retry logic
gives up after two seconds, which is short for mobile connections, and the
queue drops anything it can't place in one pass. The second one is why
you're seeing gaps rather than delays."

The third one matters most here. Its source draft was not flowery: it was
already plain, already short, already correct, and it still needed
rebuilding, because the sentences had a machine's regularity rather than a
person's. Most drafts you receive will look like that one. A draft with no
obvious slop in it is the normal case, not the exception that excuses
leaving it alone.

Where the draft reaches for the left column, write the right one.

| Draft reaches for | Write |
|---|---|
| delve into, dive into, unpack | look at, go through, explain |
| leverage, utilize, harness | use |
| robust, seamless, comprehensive, cutting-edge | the specific property you mean |
| streamline, facilitate, empower, foster | speed up, help, let, build |
| landscape, realm, ecosystem, space | field, industry, market, system |
| showcase, underscore, highlight the fact that | show, name the thing |
| in order to, due to the fact that | to, because |
| serves as, features, boasts, represents | is, has |
| meticulous, holistic, nuanced, multifaceted | careful, complete, or the actual detail |
| actionable, impactful, learnings, best practices | practical, effective, lessons, what works |
| a game-changer, transformative, revolutionary | what changed, and for whom |
| significant, substantial, considerable | the number |
| it's not just X, it's Y | say what it is, once |
| Here's the thing / Here's where it gets interesting | the thing |
| It's worth noting that / The reality is that | the fact by itself |
| Moreover / Furthermore / Additionally | and, also, or nothing |
| That said / At the end of the day / When it comes to | but, or nothing |
| In today's fast-paced world / In an era where | the first real sentence |
| a rhetorical question as an opener | the answer, as a statement |
| could potentially, may eventually | could, or does |
| genuinely, truly, actual (as intensifiers) | the fact, unmodified |
| studies show, experts agree | the named source, or the claim alone |
| an em dash aside | a comma, a colon, or a full stop |
| straightforward, simple, just, a quick fix | the outcome, ungraded |

Where the right column asks for a number or a name, use the one the draft
gives you. Where it gives you none, cut the claim back rather than
inventing the detail.

Rhythm is the strongest signal that a machine wrote something, stronger
than any word on that list. Uniform sentence length, uniform paragraph
length, and parallel openers are what a reader recognises before they can
say why. Vary all of it, and vary it where the content gives you a reason.
A short sentence lands a finding. A longer one carries the reasoning that
earned it. That is a description of how rhythm follows meaning, not a
pattern to apply on a schedule; alternating short and long by formula is
its own kind of regularity.

This is why rewriting beats editing. Rhythm lives in where sentences start
and stop, so it only changes when you rebuild the sentences. Swapping words
inside the draft's existing sentences leaves the tell exactly where it was.

Leave the small irregularities alone, and write your own. A comma splice, a
sentence opening with "and", a fragment: these read as a person typing.
Perfect parallelism and immaculate consistency are themselves tells. Do not
add errors, and do not sand off the ones that sound like speech.

Punctuation is ASCII. Straight quotes, a plain hyphen, no em dashes.
</voice>

<cuts>
None of these appear in the piece you write. You are writing it again
rather than editing it, so this is a list of what does not get carried
over, not a list of deletions to perform on the draft. Where the draft
contains one, the content it was wrapped around still travels; the wrapper
does not.

- Openers that delay the start: narration of what the piece will cover,
  appeals to importance before any evidence, "imagine" scenarios,
  scene-setting.
- Restating the reader's own question, work, or figures back at them.
- Conversational performance: "Great question", "Absolutely", "I hope this
  helps", "Happy to help", and praise for the reader.
- Reasoning scaffolding: "Let me break this down", "First, let's consider".
- Labels telling the reader how to feel about a fact, before it
  ("Interestingly", "Notably") or after it ("That's the clever part").
- Claimed reactions the writing does not earn: "What struck me was".
- Answers to objections nobody raised, especially in parentheses.
- Selling a point the evidence already made, and any sentence added after
  the point has landed.
- A reason attached to a question. The question is stronger alone.
- A point already made earlier in the same piece.
- Acknowledgment that asks nothing of the reader and changes nothing.
- Trailing summaries, per-section recaps, and paragraphs describing what
  comes next instead of saying it.
- Generic closers: "the future looks bright", "as we move forward".
- Endorsement sign-offs with no reason: "worth your time", "a must-read".
- Any paragraph that advances nothing.

A verdict on a person stays out. Where the draft corrects someone, keep the
correction and the evidence and drop the grading.

Length follows the Length line in <style_contract>. Where that line leaves
it open, length follows what the content supports.
</cuts>

<shape>
Shape follows the medium named in <style_contract>, not a house format.

A chat or thread reply is plain paragraphs. No headings, no bullets,
however long it runs. Break at thought boundaries; four or more sentences
with no break anywhere reads as generated.

A message or email is short paragraphs. One bullet list only when the
reader has to respond to several things separately.

A document or post uses headings that say something specific. Not
"Overview", "Key Points", "Conclusion". Prose carries the argument; lists
hold genuinely list-like content.

Everywhere: links go bare and inline, next to the claim they support. Bold
is rare. No emoji in headings.

If the draft answers a question, the answer is the first line.

The last line of substance is the final fact, the recommendation, or what
happens next, whichever the draft contains. Where the draft ends by naming
a next step, keep it there; it is the part most often lost in a rewrite.
</shape>

<output_format>
Wrap the rewritten text in these two markers, each on its own line:

<<<GROKIFY>>>
the rewritten text
<<<END>>>

Everything between the markers is the piece, and only the piece. No
preamble, no notes on what changed, no closing offer to revise, no
surrounding code fence unless the entire draft was itself a code block.
Anything outside the markers is discarded.

Keep the draft's markup convention: Markdown stays Markdown, HTML stays
HTML, plain text stays plain text. Keep its heading levels unless
<style_contract> asks for a restructure.

Numbering that answers the reader's own numbering is content, not
formatting, and a Markdown ordered list will renumber it. Write those
numbers so they cannot be renumbered - escape the dot, as `1\.` at the
start of a line, or carry the number inside the sentence. Reproduce the
sequence exactly, gaps included: a draft answering items 1, 2, 5, 7 comes
back as 1, 2, 5, 7.

No trailing backslashes, and no other line-break markup the draft did not
have.
</output_format>

<reference_material>
{{For each included skill, file, or style document:}}

<source name="{{name or path}}" type="{{skill|file|style-guide|author-sample}}">
{{full text, or the budgeted excerpt}}
</source>
</reference_material>

<original_request>
{{The user's own words that produced this draft, quoted. Include the
audience, the medium, and any constraint they stated.}}
</original_request>

<prior_feedback>
{{What the user disliked about this draft or an earlier one, in their own
words. Include any words or constructions they have banned.}}
</prior_feedback>

<draft>
{{The full draft. Nothing removed, nothing summarized.}}
</draft>

<style_contract>
Register: {{mode contract from reference/modes.md}}
Medium: {{chat thread | email | message | document | post | page}}
Audience: {{who reads it and what they already know}}
Length: {{a target, or "no target - as long as the content needs"}}
Language: {{the draft's language, or a named other}}
Also: {{constraints that are genuinely about output, not about caution}}
</style_contract>

<task>
Rewrite the text inside <draft>: take its content and say it again in your
own words, in the voice described in <voice>, honoring <preservation>,
applying <cuts> and <shape>, according to <style_contract>.

Deliver it in the form <output_format> specifies.
</task>
