# Modes

A mode supplies the `Register:` line in `<style_contract>`. Copy the
contract text verbatim into the payload. A free-form instruction from the
user is layered on top and wins wherever the two disagree.

## auto (default)

Read the draft and pick the mode it is already trying to be: a post with
headings and a hook is `blog`, a message that opens with a greeting is
`email` or `client`, a page of setup steps is `docs`, a two-paragraph
answer is `plain`. Name the chosen mode in the footer so the user can
override it.

When the draft matches no mode cleanly, use `plain`.

## plain

Contract: say the same thing the way you would say it to a colleague who
asked. Keep every fact. Cut the framing, the throat-clearing, and the
summary at the end. Length lands wherever the content lands, usually
shorter than the draft.

For: chat replies, explanations, answers to a direct question, anything
that got a TED talk when it needed a sentence.

## blog

Contract: write it as a post for a publication that expects the reader to
already be interested. Open on the specific thing the post is about, not
on context the reader supplied by clicking. Keep the heading structure
unless it is hiding a better one. Every section earns its place with
something concrete: a number, an example, a decision and its reason.
Close on the last real point.

For: articles, guides, newsletters, launch posts, teardowns.

## email

Contract: write it as an email one working professional sends another.
Subject line if the draft has one. A first sentence that says why the
email exists. The ask in its own sentence, unhedged. Sign-off matching
the relationship. Nothing that would read as filler if the recipient
skimmed it on a phone.

For: outreach, follow-ups, internal mail, updates.

## client

Contract: write it as a message to a paying client. Direct about status,
including bad status. Take responsibility in plain words where
responsibility belongs, without over-apologizing or hedging. Give the
concrete next step and a date. Assume the client is smart, busy, and
uninterested in process detail unless it changes what they get.

For: project updates, delay notices, scope conversations, replies to
complaints, handovers.

## chat

Contract: write it as a message in Slack, Teams, WhatsApp, or a comment
thread. One point per message. No headings. No greeting unless the draft
has one. Short enough to read without scrolling.

For: standup notes, quick replies, PR comments, DMs.

## docs

Contract: write it as product documentation. Second person, present
tense, imperative for steps. One idea per paragraph. Preconditions before
actions, actions before results. Keep code, paths, and UI labels exactly
as written. Say what happens when a step fails.

For: setup guides, how-tos, knowledge base articles, API docs, help
center pages.

## technical

Contract: write it for an engineer who will act on it. Lead with the
finding or the change. Keep file paths, symbols, versions, and error
strings intact and inline. Give the reasoning once, in the place where it
changes a decision. Skip the narrative arc.

For: bug reports, RFCs, pull request descriptions, commit messages,
architecture notes, incident write-ups, code review comments.

## social

Contract: write it for the feed the draft belongs to. First line carries
the whole post if nobody reads the second. No hashtag clusters unless the
draft has them. No engagement bait, no "thoughts?", no numbered listicle
unless the content is genuinely a list. Sound like a person posting, not
a brand scheduling.

For: X, LinkedIn, Reddit, Bluesky, Mastodon, Discord announcements.

## exec

Contract: write it for someone with thirty seconds and budget authority.
Outcome, impact, ask - in that order, in three to six sentences. No code,
no implementation detail, no process. Numbers where numbers exist. If a
decision is needed, the last sentence is the decision.

For: status summaries, board notes, escalations, stakeholder updates.

## marketing

Contract: write it as copy that has to earn the next click. Concrete
benefit before feature. One idea per block. Specific proof instead of
adjectives: a number, a named customer, a before and after. Keep the
call to action and its link exactly as the draft has it.

For: landing pages, ads, product pages, email campaigns, one-pagers.

## academic

Contract: write it for a reader who will check the citations. Formal
register without ornament. Claims carry their evidence in the same
sentence or the one after. Preserve every citation, figure reference, and
hedge exactly. Passive voice is acceptable where the convention of the
field expects it.

For: papers, abstracts, grant text, literature reviews, reports for
regulated readers.

## tighten

Contract: keep the draft's voice and structure. Remove what does not
carry information: restated points, throat-clearing openers, closing
summaries, adverbs doing no work, sentences that exist to introduce the
next sentence. Change nothing else. Target roughly two thirds of the
original length unless `--length` says otherwise.

For: a draft that is right but long.

## translate

Contract: write the piece in the language named by `--lang`, as a native
writer of that language would write it for this audience - not as a
translation of the English sentence order. Keep proper nouns, product
names, code, and URLs unchanged. Match the formality register the target
language expects for this channel.

For: localizing a finished piece.

## Adding a mode

A mode is a contract paragraph, nothing more. Write it as observable
instructions - what to lead with, what to keep, what to cut, how long -
never as a list of adjectives. "Professional and engaging" tells a model
nothing; "the ask in its own sentence, unhedged" tells it what to write.
