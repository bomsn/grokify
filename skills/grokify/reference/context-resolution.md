# Context resolution

What goes into `<reference_material>`, where it comes from, and what
never goes in.

## Skills

A skill reference is either plugin-qualified (`content-writing:blog-writing`)
or bare (`blog-writing`). Resolve it by searching, in order, and stopping
at the first `SKILL.md` found:

1. `./.claude/skills/<name>/SKILL.md`
2. `./.claude/plugins/*/skills/<name>/SKILL.md`
3. `$HOME/.claude/skills/<name>/SKILL.md`
4. `$HOME/.claude/skills/*/<name>/SKILL.md`
5. `$HOME/.claude/plugins/**/<plugin>/skills/<name>/SKILL.md`
6. `$HOME/.claude/plugins/**/skills/<name>/SKILL.md`

When a plugin is named, prefer a path containing that plugin's directory
before falling back to a bare name match.

A portable search:

```bash
find "$HOME/.claude" ./.claude -type f -name SKILL.md -path "*<name>*" 2>/dev/null
```

On Windows, `$HOME/.claude` is `%USERPROFILE%\.claude`.

### What to include from a skill

Include `SKILL.md` in full. Then follow the links it declares: most skills
keep their substance in `reference/*.md` and treat `SKILL.md` as a router.
A skill included without its reference files contributes a table of
contents and no craft.

Skills chain. When a brand skill says it is incomplete without a parent
skill, resolve and include the parent too. The parent carries the craft;
the child carries the brand rules that override it. Include the parent
first and the child second, so the override reads last.

### Skills that come along automatically

Any skill that governed the original draft belongs in the payload whether
or not the user names it in a flag. If the draft was written under a blog
skill, Grok is rewriting a blog post against that skill's rules, and it
needs them. The user typing `--skill` is a way to add more, not the only
way to include any.

Skills that shaped nothing in the draft stay out. A screenshot skill has
no bearing on a rewrite.

## Files and folders

`--context <path>` takes either.

**A file** is included in full when it is text: `.md`, `.mdx`, `.txt`,
`.html`, `.json`, `.yaml`, `.csv`, source files, and anything else that
reads as text. Binary files are skipped and named in the skipped list.

**A folder** is walked to a depth of three. Include text files under
64 KB each, in path order, until the reference budget is reached. List
every file that was skipped or truncated, in the response footer, not in
the payload. Silent truncation is the failure mode that makes a rewrite
wrong in a way nobody catches.

`.gitignore` is respected. `node_modules`, `vendor`, `.git`, `dist`,
`build`, and lock files are always skipped.

## Samples of the author's own writing

The single highest-value source in the payload, ahead of every style rule
and every skill. A style guide describes a voice; a paragraph the author
actually wrote demonstrates it, and the model matches what it can see.

Look for them in this order and include one or two, tagged
`type="author-sample"`:

- Past pieces the same author or publication produced, in the repo or
  passed through `--context`
- Earlier messages in this conversation that the user wrote themselves,
  when the rewrite is a message or a reply
- Published work at a URL the user names

Two short samples beat one long one, and they should differ from each
other. A single reused exemplar makes every rewrite converge on its
phrasing, which is its own kind of tell.

Do not manufacture a sample. Text written by an AI, including anything
from this conversation that this model produced, is not an author sample.
Including one teaches the rewrite to reproduce the voice it exists to
remove.

## The optional project style file

If any of these exist, include the first one found as a
`type="style-guide"` source:

- `./.grokify.md`
- `./GROKIFY.md`
- `./.claude/grokify.md`

It holds whatever a project wants applied to every rewrite: house voice,
banned words, product term spellings, a CTA, a signature block. There is
no schema and no default. When no such file exists, nothing is assumed
and nothing is invented.

## The mode catalogue is not reference material

`reference/modes.md` never goes into a payload. The `Register:` line takes
the one contract that applies, copied in as text. Shipping the whole file
sends thirteen registers the piece is not being written in, and every one
of them is an instruction competing with the one that is. It also costs
several kilobytes on a command line that has a hard ceiling.

The same holds for any skill: what goes in is the part that governed the
draft, not the whole catalogue it came from.

## Never included

Exclude these even when they sit inside a folder passed to `--context`,
and name what was excluded so the omission is visible:

- `.env`, `.env.*`, and any file matching `*secret*`, `*credential*`,
  `*token*`, `*password*`
- Private keys, certificates, `.pem`, `.key`, `.p12`, `id_rsa`
- Files containing what reads as an API key, access token, or connection
  string, wherever they live
- Customer or employee personal data: contact lists, exports, invoices,
  medical or financial records
- Anything the user has said in the conversation not to send

A rewrite is worth nothing if the price is a credential in a third
party's logs.

## Budget

Aim for a total payload under roughly 40,000 characters, and treat
120,000 as the hard ceiling. The draft, `<original_request>`, and the rule blocks are never trimmed.
Trim reference material in this order:

1. Reference files of skills that only shaped part of the draft
2. Sections of a skill's reference files that govern research or
   publishing rather than writing
3. `--context` files, longest first, keeping their first and last
   sections
4. Additional skills beyond the two most relevant

Author samples are trimmed last, after everything above. They earn their
tokens.

Report what was trimmed in the footer.
