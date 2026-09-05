# Payload template

Replace every `{{...}}` placeholder and send the filled document to `grok -p`.
Delete any block that would be empty. `<task>`, `<draft>` and `</draft>` each
stay at the start of their own line; the runner splits the payload on them.

---

Another AI wrote the draft below. The facts in it are right and the author is
keeping them. The writing is not right: it has the flat, even rhythm of a
machine explaining itself. Your job is to say the same things the way you
would say them.

Read the draft until you know what it is telling the reader. Then write that,
in your own words, at your own pace. Not a cleaned-up version of these
sentences: your version of this message. If large parts of your draft could be
diffed against the original and come back mostly unchanged, you edited it
instead of writing it.

You have room here. Reorder, merge, split, cut the throat-clearing, start
somewhere better. The only things you cannot touch are in <accuracy>, and
everything else is yours.

<accuracy>
Nothing here may change, because the author will send this without checking it
against the original.

- Every fact, number, date, price, percentage, measurement, and unit
- Every name: people, companies, products, features, versions
- Quotations and who said them
- Code, commands, paths, config keys, error strings, byte for byte
- URLs, exactly as written
- Placeholders such as {{name}}, [CLIENT], %s, $VAR
- Numbering that answers the reader's own numbered questions, gaps included
- The language the draft is written in, unless <style_contract> says otherwise

Two more, easy to lose while rewriting:

Keep every piece of information. Say it in fewer or different words, but do
not drop a point, a caveat, a condition, or a next step. Nothing the author
told the reader goes missing.

Keep how sure the author was. A measured fact stays flat, a guess stays a
guess, "likely" does not become "is". A workaround stays a workaround. If the
draft names a limitation and then says what bounds it, both halves survive.

Add nothing. No tool, statistic, example, or name that is not already in the
draft or the reference material. If a claim looks wrong to you, keep it; that
is not your call here.

A draft that is entirely code or data has no prose to rewrite. Return it as
it is.
</accuracy>

<voice>
Write like someone who knows the subject, is talking to one person, and has
no interest in sounding impressive.

If <reference_material> holds the author's own writing, take your habits from
it: how they open, how long their sentences run, which words they use for
their own work. Do not check the draft against it. Write like them.

Otherwise, three passages in the register to aim for:

"The request pipeline assumes the cache is warm. When it isn't, every request
hits the database directly."

"Quick update on the timeline. The integration work took two days longer than
I estimated, so the handover moves to Thursday. Everything else is on track."

"Two things are causing it, and one of them is on our side. The retry logic
gives up after two seconds, which is short for mobile connections, and the
queue drops anything it can't place in one pass. The second one is why you're
seeing gaps rather than delays."

Let the sentences run at uneven lengths, the way speech does. Even rhythm and
tidy parallel structure are what make writing read as machine-made, more than
any single word does. A comma splice or a sentence starting with "and" is
fine; do not sand those out.

Start with the point. No wind-up, no restating the reader's question, no
summary at the end telling them what they just read.

Match the medium in <style_contract>. A chat or thread reply is paragraphs,
never bullets. Links go inline next to the claim. If the draft answers a
question, the answer is the first line.

Punctuation is ASCII: straight quotes, plain hyphens, no em dashes.
</voice>

<output_format>
Put the finished piece between these markers, each on its own line:

<<<GROKIFY>>>
the rewritten text
<<<END>>>

Only the piece goes between them. No preamble, no notes on what you changed,
no offer to revise. Anything outside the markers is thrown away.

Markdown stays Markdown, HTML stays HTML, plain text stays plain text.

Numbers that answer the reader's own numbering are content, and a Markdown
list will renumber them. Write them so they cannot be: `1\.` at the start of a
line, or the number inside the sentence. Reproduce the sequence exactly, gaps
included. No trailing backslashes.
</output_format>

<reference_material>
{{For each included skill, file, or style document:}}

<source name="{{name or path}}" type="{{skill|file|style-guide|author-sample}}">
{{full text, or the budgeted excerpt}}
</source>
</reference_material>

<original_request>
{{The user's own words that produced this draft, quoted. Include the audience,
the medium, and any constraint they stated.}}
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
Also: {{anything that would be factually wrong in the output if omitted}}
</style_contract>

<task>
Write your own version of the text in <draft>, in the voice described in
<voice>, keeping everything in <accuracy> intact, for the reader named in
<style_contract>.

Return it in the form <output_format> specifies.
</task>
