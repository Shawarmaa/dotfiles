---
name: summarize
description: Summarize any content (YouTube video, article, whitepaper/PDF, podcast episode, book chapter, course notes, etc.) into a rich Obsidian note with section-by-section breakdowns, wikilinks to all technical concepts and people, and reference notes for every linked term. Use when the user provides a URL, file, or content to summarize and document in the vault. For course notes/lecture PDFs, generates structured cheat sheets, study notes, and full notes with preserved math notation.
user_invocable: true
---

# Summarize

Universal content summarizer. Takes any input — YouTube video, web article, whitepaper/PDF, epub book, podcast, lecture, university course notes — and produces a rich, interlinked Obsidian summary note with reference notes for every concept mentioned. For course notes, generates structured cheat sheets (formulas → core concepts → definitions & theorems), study notes, and full notes with LaTeX math preserved.

## Requirements

**Vault structure** — the skill expects these folders inside your Obsidian vault. Folder names are the defaults; override them in the Configuration block below if your vault uses different names.

| Folder | Purpose |
|---|---|
| `09 Summaries/` | Where summary notes land |
| `06 References/` | Concept / company / product / place notes |
| `03 People/` | Person notes (creators, guests, mentioned people) |
| `01 Daily/YYYY/MM/` | Daily notes, named `DD-MM-YYYY ddd.md` (e.g. `29-03-2026 Sun.md`) |
| `_Templates/` | Note templates — skill installs `new person template.md` here on first run |
| (no central folder) | Obsidian Bases live in their respective content folders (e.g. `posts.base` in `09 Summaries/`, `people.base` in `03 People/`) |

**CLI tools** — install these before first use, or let Step 0 walk you through it:

| Tool | Purpose | Install |
|---|---|---|
| `yt-dlp` | YouTube/podcast download + metadata + subs | `brew install yt-dlp` or `pip install yt-dlp` |
| `defuddle` | Web article extraction | `npm install -g defuddle` |
| `pdftotext` | PDF text extraction (non-math PDFs) | `brew install poppler` |
| `marker` | Math-aware PDF extraction (course notes) | `pip install marker-pdf` |
| `pandoc` | EPUB / DOCX → markdown | `brew install pandoc` |
| `mlx_whisper` (optional) | Local audio transcription fallback | `pip install mlx-whisper` |

Alternative to `mlx_whisper`: set `ELEVENLABS_API_KEY` to use ElevenLabs Scribe for transcription.

## Configuration

The skill reads these variables at runtime. Override any of them via environment variables, or edit the defaults here:

```
VAULT_ROOT     = $VAULT_ROOT        # auto-detected if not set (see Step 0a)
SUMMARIES_DIR  = 09 Summaries
REFERENCES_DIR = 06 References
PEOPLE_DIR     = 03 People
DAILY_DIR      = 01 Daily
TEMPLATES_DIR  = _Templates
COURSES_DIR    = 04 Projects/Uni
# Bases live in their content folders, not a central dir:
#   posts.base    → $SUMMARIES_DIR/posts.base
#   people.base   → $PEOPLE_DIR/people.base
#   meetings.base → 02 Meetings/meetings.base
#   books.base    → 05 Books/books.base
```

All paths below are relative to `$VAULT_ROOT`.

## Trigger

When the user provides content to summarize: a URL (YouTube, article, blog), a PDF/file path, pasted text, or a reference to content already in the vault.

## Inputs

- **Source**: URL, file path, or pasted text
- **Audience** (optional): defaults to "general reader." User may specify (e.g. "high school student", "expert", "5-year-old")
- **Depth** (optional): defaults to "full." User may request "tldr only", "section-by-section", or "deep dive"

## Step 0: Bootstrap check (first run)

Before doing any work, verify the environment is ready. **Skip any check that already passes** — only prompt the user when something is actually missing. Do not re-run Step 0 on subsequent invocations if the initial setup succeeded; you can tell it already ran if `$VAULT_ROOT` resolves and the required folders + tools are present.

### 0a. Resolve the vault root

```bash
vault=""
if [ -n "$VAULT_ROOT" ]; then
  vault="$VAULT_ROOT"
else
  dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -d "$dir/.obsidian" ]; then vault="$dir"; break; fi
    dir="$(dirname "$dir")"
  done
fi
echo "Vault: ${vault:-NOT FOUND}"
```

If no vault is found, ask the user:

> **What's the absolute path to your Obsidian vault?**
> Recommended: use a **new, dedicated Obsidian vault** for this skill — not your existing personal vault. The skill creates and modifies many notes and folders, and a clean vault avoids polluting your existing notes. If you don't have one yet, create an empty folder, open it in Obsidian (File → Open vault as folder), and paste that path here.

After they answer, validate that `<answer>/.obsidian/` exists before using it — if not, warn that the path doesn't look like an Obsidian vault (they may need to open it in Obsidian first) and ask them to confirm or re-enter. Use the validated answer as `$VAULT_ROOT` for the session (and suggest they set it permanently in their shell profile).

### 0b. Check required folders

```bash
for d in "$SUMMARIES_DIR" "$REFERENCES_DIR" "$PEOPLE_DIR" "$DAILY_DIR" "$TEMPLATES_DIR"; do
  [ -d "$VAULT_ROOT/$d" ] || echo "MISSING: $d"
done
```

For each missing folder, ask the user: **"Create `<folder>` in your vault? [y/N]"** — if yes, `mkdir -p "$VAULT_ROOT/<folder>"`.

### 0c. Check required CLI tools

```bash
for tool in yt-dlp defuddle pdftotext marker pandoc; do
  command -v "$tool" >/dev/null 2>&1 || echo "MISSING: $tool"
done
```

For each missing tool, tell the user what's missing and **ask before installing** — installs touch the user's system. Use the install commands from the Requirements table above. If the user declines, note which tools are missing and warn that the corresponding content types (YouTube, web articles, PDFs, EPUBs) will fail until installed.

### 0d. Check person template exists

Verify `$VAULT_ROOT/$TEMPLATES_DIR/new person template.md` exists. If missing, warn the user to create one before proceeding.

Once Step 0 passes, proceed to Step 1 (content type detection). If the content is **not** course notes, Step 1 routes to Step 0.5 → 2 → 3 → 4. If it **is** course notes, Step 1 routes directly to Step C.

## Step 0.5: Determine depth mode

Before extraction, establish which depth the user wants:

1. **Scan the invocation first.** If the user's request already specifies a mode, use it and skip the prompt:
   - Words like `minimal`, `fast`, `quick`, `--minimal`, `-m` → minimal mode
   - Words like `detailed`, `deep`, `full`, `--detailed`, `-d` → detailed mode
2. **Otherwise, prompt.** No default — if unspecified, ask every time:

> **Depth?**
> 1. **Detailed** (best results) — full reference notes for every wikilinked concept, person notes for every mentioned person, parallel highest-available-model subagents per section, base updates
> 2. **Minimal** (fast) — summary note only, wikilinks left dangling, person notes for creators/guests only, Sonnet summary

This keeps interactive runs explicit while letting scheduled tasks / cron / `/loop` pass the mode in the invocation (e.g. `/summarize <url> minimal`) without blocking on input.

The chosen mode determines which steps run:

| Step | Detailed | Minimal |
|---|---|---|
| 1 Extract text | ✓ | ✓ |
| 1b Save transcript | ✓ | ✓ |
| 2 Output structure | ✓ | ✓ |
| 3a Depth from word count | ✓ | ✓ |
| 3b Parallel subagents | ✓ (>3000 words, highest available model) | ✓ (>3000 words, Sonnet) |
| 4 Assemble summary | ✓ | ✓ (skip `## People Mentioned` section) |
| 5 Reference notes (concepts) | ✓ | ✗ — wikilinks left dangling |
| 5 Person notes | ✓ (all mentioned) | ✓ (creators/guests only — those in `people` frontmatter) |
| 5c Dangling-link audit | ✓ | ✗ |
| 6 Bases update | ✓ (if bases exist) | ✗ |
| 7 Daily note | ✓ | ✓ |

For book chapter-by-chapter depth (Step 1 book section), detailed mode gets the full 300-600 words per chapter; minimal mode gets a flatter single summary regardless of chapter count.

## Step 1: Detect content type and extract text

### YouTube video
```bash
# Get metadata
yt-dlp --cookies-from-browser chrome \
  --print "%(id)s|%(title)s|%(duration)s|%(upload_date)s|%(view_count)s|%(channel)s|%(channel_id)s" \
  --no-download "<URL>"

# Try auto-subtitles first (fastest, free)
yt-dlp --cookies-from-browser chrome \
  --write-auto-sub --sub-lang en --sub-format json3 \
  --skip-download -o "/tmp/summarize/%(id)s" "<URL>"
```

If auto-subs exist, extract text from the JSON3 file. If not, or if quality is poor:
- Download audio and transcribe (same as `youtube-transcribe` skill — ask user: local mlx_whisper or ElevenLabs Scribe)

### Web article / blog post
```bash
defuddle parse "<URL>" --md -o /tmp/summarize/article.md
```

If defuddle is not installed: `npm install -g defuddle`

Extract title, author, date, domain from defuddle metadata:
```bash
defuddle parse "<URL>" -p title
defuddle parse "<URL>" -p domain
```

### PDF (non-course)
```bash
pdftotext "<path>" /tmp/summarize/paper.txt
```

If `pdftotext` is not available: `brew install poppler`

### Course notes PDF

**Detection:** A PDF is course notes if any of these are true:
- The PDF filename matches a `notes` field entry in a course note under `$COURSES_DIR/` (e.g. `MATH21120 S1 Notes.pdf` matches `[[MATH21120 S1 Notes.pdf]]` in `MATH21120 Groups and Geometry.md`)
- The user explicitly says it's course notes
- The PDF is in `_Attachments/` and its filename contains a course code pattern (e.g. `MATH21120`, `COMP26120`)

**Extraction:** Use `marker` (not `pdftotext`) to preserve LaTeX math notation:
```bash
marker_single "<path>" --output_dir /tmp/summarize/course/
```

This outputs markdown with `$...$` and `$$...$$` math blocks preserved. If `marker` is not installed: `pip install marker-pdf`.

**Resolve the course note:** Search `$COURSES_DIR/` for a `.md` file whose `notes` frontmatter contains a wikilink to this PDF:
```bash
grep -rl "$(basename '<path>')" "$VAULT_ROOT/$COURSES_DIR/" --include="*.md" | head -1
```

Extract from the course note: `course_code` (from filename, e.g. `MATH21120`), `course_name` (e.g. `Groups and Geometry`), `tags` (e.g. `year2`), existing `summary` links.

**When course notes are detected, skip Steps 0.5, 2, 3, 4 and follow the Course Notes Flow (Step C) instead.**

### EPUB (books)
```bash
# Extract full text as markdown (preserves chapter structure)
pandoc "<path>" -t markdown --wrap=none -o /tmp/summarize/book.md

# If you need chapter boundaries, extract the TOC:
pandoc "<path>" -t json | python3 -c "
import json, sys
doc = json.load(sys.stdin)
for block in doc['blocks']:
    if block['t'] == 'Header':
        level = block['c'][0]
        text = ''.join(
            item['c'] if item['t'] == 'Str' else ' ' if item['t'] == 'Space' else ''
            for item in block['c'][2]
        )
        print(f'L{level}: {text}')
"
```

**Chapter splitting strategy for books:**
1. Extract full text with `pandoc` → markdown
2. Identify chapter boundaries from headers (epubs have built-in TOC structure that pandoc preserves as `#`/`##` headers)
3. Split into one chunk per chapter
4. Dispatch parallel Opus subagents — **one per chapter** — same as any other long content
5. A typical book (60-100k words, 15-30 chapters) produces chapters of ~3-5k words each — well within subagent context limits

**For very long books (>30 chapters):** batch chapters into groups of ~5 per subagent to keep the number of parallel agents manageable. Each subagent summarizes its batch and returns section summaries.

**CRITICAL — Book summary depth requirement:**
- Each chapter MUST get its own dedicated `## Chapter N: Title` section with a **substantial** summary (300-600 words per chapter depending on chapter length)
- Do NOT batch multiple chapters into a single brief paragraph — every chapter gets its own detailed treatment
- Include key arguments, data points, examples, and quotes from each chapter
- A 10-chapter book should produce ~3000-6000 words of summary content (excluding frontmatter/tldr)
- A 30-chapter book should produce ~5000-10000 words
- Think of each chapter summary as a standalone mini-essay that captures the chapter's core contribution
- The goal is that someone reading the summary should understand what each chapter argues, not just what the book is "about" at a high level

**Output structure for books:**
- Location: `09 Summaries/<Book Title>.md` (or `09 Summaries/<Author>/<Book Title>.md` if summarizing multiple books by one author)
- Frontmatter tag: `book`
- Extra fields: `creator` (author wikilink), `published` (year), `isbn` (if known), `source` (wikilink to the epub file if it's in the vault, e.g. `"[[Book Title.epub]]"`)
- Each chapter gets its own `## Chapter N: Title` section in the summary
- Add a `## Chapter Navigation` callout at the top if the book has many chapters

### Other files (txt, docx, etc.)

For `.docx`: `pandoc "<path>" -t markdown --wrap=none -o /tmp/summarize/doc.md`

For plain text: read directly.

### Pasted text / vault note
Read directly from user message or vault path.

## Step 1b: Save transcript (audio/video content only)

For any content that has audio — YouTube videos, podcast episodes, lectures/talks with recordings — save the extracted transcript as a permanent vault note.

**When to create a transcript note:**
- YouTube videos (from auto-subs or whisper transcription)
- Podcast episodes (from transcription)
- Lectures/talks with audio/video recordings
- Any content where the source is spoken word

**Do NOT create transcript notes for:** articles, blog posts, PDFs, books, pasted text — these are already text.

**Location:** Same folder as the summary note, with ` Transcript` appended to the filename.

**Format:**
```markdown
---
date: YYYY-MM-DD
duration: <seconds>
recording: "<source URL>"
meeting: "[[<Summary Note Title>]]"
unread: true
---

[Full timestamped transcript text, one line per segment]
```

**Link from summary:** Add `transcript: "[[<Title> Transcript]]"` to the summary note's frontmatter.

This step happens immediately after text extraction (Step 1) and before output structure planning (Step 2). The transcript is the raw source material — always preserve it.

## Step 2: Determine output structure

Based on content type, choose the appropriate format:

| Content type | Location | Frontmatter tags | Extra fields |
|---|---|---|---|
| YouTube video | `09 Summaries/<Channel>/Summaries/<Title>.md` | `youtube` | `recording`, `views`, `creator`, `people`, `guest`, `hosts`, `guests`, `duration`, `uploaded`, `transcript` |
| Article / blog | `09 Summaries/<Title>.md` | `article` | `creator`, `people`, `source` (URL), `published` |
| Whitepaper / PDF | `09 Summaries/<Title>.md` | `paper` | `authors`, `people`, `affiliations`, `source` (wikilink to PDF if in vault, or URL), `published` |
| EPUB / book | `09 Summaries/<Title>.md` | `book` | `creator` (author wikilink), `people`, `published` (year), `isbn`, `source` (wikilink to epub if in vault) |
| Podcast episode | `09 Summaries/<Show>/Summaries/<Title>.md` | `podcast` | `recording`, `people`, `guest`, `hosts`, `guests`, `duration`, `transcript` |
| Lecture / talk | `09 Summaries/<Title>.md` | `lecture` | `creator`, `recording` (if URL), `transcript` |
| Course notes | `09 Summaries/<Code> <Name>/<Code> Cheat Sheet.md` | `course-notes` | `course_code`, `source` (wikilink to PDF), `course` (wikilink to course note) |
| Course notes | `09 Summaries/<Code> <Name>/<Code> <Src> Study Notes.md` | `course-notes` | (same as above) |
| Course notes | `09 Summaries/<Code> <Name>/<Code> <Src> Full.md` | `course-notes` | (same as above) |

**All non-course notes** get: `date`, `categories: ["[[posts.base]]"]`, `unread: true`. No `summary` field — the `> [!tldr]` callout in the body serves this purpose. The `date` field is the **original content's publication date** (not the date it was summarized) — extract it from the article metadata, video upload date, PDF publication date, etc. The `people` field must always include every person who created or appeared in the content (including the creator) — this is what `posts.base` person views filter on.

**Course notes** get: `date`, `tags: [course-notes]`, `course_code`, `source`, `course`, `unread: true` — no `posts.base` category.

If a channel/show folder is needed, check if it already exists before creating.

## Step 3: Analyze structure, determine depth, and plan sections

Read the full extracted text. Identify the natural sections/chapters/topics.

### 3a. Determine summary depth from source length

Summary length must be **proportional** to the source material. A 10-minute video and a 3-hour documentary should not produce the same size summary. Use the source word count to determine the target summary word count:

| Source word count | Source examples | Target summary words | Sections | TLDR |
|---|---|---|---|---|
| <1,500 | 5-min video, short article | 200–400 | 1–2 | 2 sentences |
| 1,500–5,000 | 10–20 min video, blog post, short paper | 500–1,200 | 3–5 | 3 sentences |
| 5,000–15,000 | 30–60 min video, long article, whitepaper | 1,500–3,000 | 5–8 | 3–4 sentences |
| 15,000–40,000 | 1–3 hr video/podcast, long paper | 3,000–6,000 | 8–15 | 4–5 sentences |
| 40,000–80,000 | Short book, multi-hour series | 5,000–10,000 | 15–25 | 5 sentences |
| 80,000+ | Full book (200+ pages) | 8,000–15,000 | 20–40 | 5 sentences |

**The ratio is roughly 1:5 to 1:10** — a 10,000-word source should produce ~1,500–2,500 words of summary. Denser/more technical content skews toward the higher end; conversational/repetitive content skews lower.

**For videos/podcasts**, estimate source words from duration: ~150 words/minute for conversational, ~120 words/minute for interviews with pauses, ~170 words/minute for scripted/narrated content. Or just use the actual transcript word count.

**Per-section depth**: each section's word budget should be proportional to its share of the source material. A section covering 20% of the transcript gets ~20% of the summary word budget. Adjust up for particularly dense/important sections, down for filler/repetitive ones.

### 3b. Plan sections and dispatch

**For long content (>3000 source words):** dispatch parallel subagents (see Model usage table for which model) — one per section — to summarize simultaneously. Each subagent gets:
- The section text
- The audience level
- A **specific word count target** (calculated from 3a above)
- Instructions to use `[[wikilinks]]` for every technical concept, person, place, company, and notable noun

**For short content (<3000 source words):** summarize directly without subagents.

**Model choice**: detailed mode uses the highest available model (Opus if the user has access, else Sonnet); minimal mode always uses Sonnet. Never Haiku.

## Step 4: Assemble the summary note

### Structure

```markdown
---
[frontmatter per Step 2]
---

[embed if applicable: ![[file.pdf]], ```vid URL```, etc.]

> [!tldr]
> [Overview — sentence count per Step 3a depth table. What is it about, who made it, what are the key takeaways?]

## [Section 1 Title]

[Summary paragraphs with [[wikilinks]] to all concepts, people, places, companies, products]

## [Section 2 Title]

[...]

## People Mentioned
- [[Person Name]] — brief context of who they are and their role in this content
```

### Formatting rules

1. **No `# Title` heading** — filename is the title
2. **Never repeat frontmatter in the body** — if it's in metadata, don't write it again
3. **`> [!tldr]`** for the overview, not `## Summary`
4. **`> [!quote]`** callouts for notable quotes (with speaker wikilink and source location if available)
5. **Wikilink EVERYTHING** — people, places, companies, concepts, technical terms, **book/film/show titles**, even if no note exists yet
6. **Use actual Japanese/Chinese characters** for non-English words, not romanization
7. **Timestamps** on topic headings and quotes when available (YouTube, podcasts)
8. **`people` field**: only people who created/appeared in the content. Mentioned people go in `## People Mentioned`

### Audience adaptation

- **High school / college student**: plain language, analogies, explain jargon inline before first wikilink use
- **General reader**: balanced — explain key terms but don't over-simplify
- **Expert**: technical language fine, focus on novel contributions and critiques

## Step C: Course Notes Flow

**This step replaces Steps 0.5, 2, 3, 4 when course notes are detected.** After extraction (Step 1), the flow is:

### C1. Check existing summaries and prompt

Immediately after extraction, check what already exists in `09 Summaries/<Code> <Name>/`:

```bash
course_dir="$VAULT_ROOT/$SUMMARIES_DIR/<Code> <Name>"
cheat="$course_dir/<Code> Cheat Sheet.md"
study="$course_dir/<Code> <Src> Study Notes.md"
full="$course_dir/<Code> <Src> Full.md"
[ -f "$cheat" ] && echo "CHEAT: exists" || echo "CHEAT: new"
[ -f "$study" ] && echo "STUDY: exists" || echo "STUDY: new"
[ -f "$full" ] && echo "FULL: exists" || echo "FULL: new"
```

**Cheat sheet always runs** — it gets created or updated. Then prompt based on what exists:

- If no study notes or full exist: "Cheat Sheet will be created/updated. Also generate Study Notes or Full Notes?"
  - Options: **Cheat Sheet only** / **+ Study Notes** / **+ Full Notes**
- If study notes exist but no full: "Cheat Sheet and Study Notes will be updated. Also generate Full Notes?"
  - Options: **Update existing only** / **+ Full Notes**
- If all exist: no prompt — all three get updated silently

**Start extraction in parallel with the prompt** so there's no wasted time. The user's answer determines what gets written, not what gets extracted.

Scan the invocation first — if the user said `study`, `full`, `cheat`, or `--study`, `--full` etc., skip the prompt and use that mode.

### C1b. Load existing context

Before generating anything, gather all existing material for this course as context:

1. **Read the course note** — understand the full course structure, what PDFs exist (`notes` field), what's already been summarized (`summary` field)
2. **Read all existing summaries** — if a cheat sheet, study notes, or full notes already exist for other semesters/PDFs, read them. This ensures:
   - The cheat sheet merges coherently (no duplicated concepts, consistent notation)
   - Study/full notes can cross-reference earlier material ("as defined in S1...")
   - Numbering and terminology stay consistent across semesters
3. **Use existing summaries as context for other semesters** — if the course has S1 and S2 PDFs and you're processing S2, read the existing S1 summaries (cheat sheet, study/full notes) as background context. Do NOT re-extract unprocessed PDFs through `marker` just for context — that's too slow. If S1 hasn't been summarized yet, note this and suggest the user process it first, but proceed without it.

This accumulated context feeds into every generation step — the cheat sheet knows what's already covered, study notes can reference prior definitions, and the completeness check can flag if S2 assumes something from S1 that wasn't captured.

### C2. Extract and catalog all content

From the `marker` output, systematically catalog every element in the source PDF:

1. **Extract TOC** — from headers in the markdown output
2. **Scan the full text** for every numbered element:
   - Definitions (e.g. `Definition 1.3`, `Definition 3.6 Kolmogorov Axioms`)
   - Theorems (e.g. `Theorem 6.16 The Law of Large Numbers`)
   - Lemmas (e.g. `Lemma 3.7`, `Lemma 4.11 Bayes' Rule`)
   - Corollaries, Propositions, Remarks
   - Examples (e.g. `Example 1.1.2`)
   - Proofs
3. **Build a master manifest** — a list of every section, definition, theorem, lemma, example, and proof in the source. This is the ground truth for the completeness check.
4. **Flag non-examinable content** — scan the extracted text for markers like "non-examinable", "not examinable", "not examined", "beyond the scope", "for interest only", "optional", "will not be assessed". Tag these sections/items in the manifest as `non-examinable`. If a whole section is marked, all items within it inherit the flag.

### Non-examinable content handling

| Output | Treatment |
|---|---|
| **Cheat Sheet** | Exclude entirely — don't waste space on non-exam material |
| **Study Notes** | One-line mention only: "Section X.Y covers Z (non-examinable)" — so you know it exists but don't study it |
| **Full Notes** | Include in full but prefix with `> [!info] Non-examinable` callout before the section |
| **Completeness check** | Non-examinable items are tracked separately — they must appear in full notes but are not required in cheat sheet or study notes |

**Detection is best-effort** — the skill can only catch what's explicitly written in the PDF. If content is marked non-examinable only verbally in lectures or on Canvas, the skill won't know. When in doubt, include it.

### C3. Generate the Cheat Sheet

**One per course** — filename: `<Code> Cheat Sheet.md`. If it already exists, update it with new material from this PDF (merge, don't overwrite sections from other semesters).

**Location:** `09 Summaries/<Code> <Name>/<Code> Cheat Sheet.md`

**Structure — always in this order:**

```markdown
---
date: YYYY-MM-DD
tags:
  - course-notes
course_code: "<Code>"
source:
  - "[[<PDF filename>]]"
course: "[[<Course Note Name>]]"
unread: true
---

## Formulas

[All key formulas from the course as LaTeX math blocks.
Group by topic. Just the math — minimal prose.
Use $$...$$ for display math, $...$ for inline.]

## Core Concepts

[Key ideas, intuitions, and important results that aren't pure formulas.
Mention core proofs and their key ideas here.
Each concept gets a brief explanation of WHY it matters.]

## Definitions & Theorems

[Every definition and theorem statement verbatim from the source,
numbered as in the original (e.g. Definition 1.3, Theorem 6.16).
Use callouts:]

> [!definition] Definition 1.3 — Probability Space
> A probability space, $(\Omega, \mathcal{F}, \mathbb{P})$, consists of three things:
> 1. a set $\Omega$, called the sample space,
> 2. a set $\mathcal{F}$ of subsets of $\Omega$, called the event space,
> 3. a function $\mathbb{P}: \mathcal{F} \to [0,1]$, called the probability measure.

> [!theorem] Theorem 6.16 — Law of Large Numbers (LLN)
> Let $(X_i)_{i=1}^{\infty}$ be a sequence of i.i.d. random variables with finite expectations. Then
> $$\lim_{n\to\infty} \frac{\sum_{i=1}^n X_i}{n} = \mathbb{E}[X_1]$$

> [!lemma] Lemma 4.11 — Bayes' Rule
> If $\mathbb{P}(A), \mathbb{P}(B) > 0$, then
> $$\mathbb{P}(A \mid B) = \mathbb{P}(B \mid A) \times \frac{\mathbb{P}(A)}{\mathbb{P}(B)}$$
```

**When updating:** If the cheat sheet already exists (e.g. S1 was already processed, now processing S2), read the existing file and merge:
- Add new formulas under `## Formulas` (don't duplicate existing ones)
- Add new concepts under `## Core Concepts`
- Add new definitions/theorems under `## Definitions & Theorems` in numerical order
- Update the `source` frontmatter list to include the new PDF
- Update `updated` timestamp

### C4. Generate Study Notes (if requested)

**One per source PDF** — filename: `<Code> <Src> Study Notes.md` (e.g. `MATH21120 S1 Study Notes.md`)

**Location:** `09 Summaries/<Code> <Name>/`

**Writing style — CRITICAL:** Study notes must be written like you're explaining to a smart classmate, not extracting from a textbook. The goal is notes you can actually *learn from*, not a dry reference. Follow these principles:

1. **Lead with intuition, then formalize** — explain what a concept means in plain language *before* the formal definition callout. "A group is basically a set with an operation that behaves nicely — it's associative, has an identity, and everything has an inverse. Here's the formal version:"
2. **Add "why it matters" after every definition/theorem** — not just "this is important" but *how it connects* to what came before and what comes after. "This matters because it lets us classify all groups of prime order — they're all cyclic."
3. **Include practical tips** — shortcuts, common mistakes, which method to use when. "Only use the pivot to change rows below it so you don't undo the hard work !!!"
4. **Worked examples should show reasoning**, not just the answer — "We choose column 2 because it has the most zeros, which simplifies the expansion"
5. **Cross-reference between sections** — "This is the same as the kernel from Section 2.4 but now applied to group homomorphisms"
6. **Summary lists at the end of dense sections** — tie everything together with key takeaways, equivalence lists, or decision trees for when to use which technique
7. **Warnings and common pitfalls** — "Matrix multiplication is NOT commutative — don't assume AB = BA"
8. **Use conversational asides** where they aid understanding — "Think of eigenvectors as vectors that only get stretched/compressed but not rotated"

**Structure:**

```markdown
---
date: YYYY-MM-DD
tags:
  - course-notes
course_code: "<Code>"
source: "[[<PDF filename>]]"
course: "[[<Course Note Name>]]"
unread: true
---

![[<PDF filename>]]

> [!tldr]
> [Overview of what this set of notes covers, key topics, prerequisites]

## Section 1: <Title>

[Plain-language introduction to the section — what are we trying to do here
and why? Set the stage before diving into formalism.]

### <Subsection>

[Intuitive explanation first — what does this concept mean in simple terms?
What problem does it solve? How does it relate to what we already know?]

> [!definition] Definition X.Y — <Name>
> [Verbatim definition with LaTeX]

[Unpack the definition — what does each part mean? What are the edge cases?
What's an example that satisfies it and one that doesn't?]

> [!theorem] Theorem X.Y — <Name>
> [Verbatim theorem statement with LaTeX]

[Why is this true intuitively? What would go wrong if it weren't?]

> [!proof] Proof sketch
> [Key idea of the proof — not the full proof, but enough to reconstruct it.
> Mention the technique used (contradiction, induction, construction, etc.)
> and explain WHY that technique works here.]

> [!example] Example X.Y.Z
> [Key example with full reasoning — not just the setup and result, but
> explain each step: "We choose this approach because...", "Notice that..."]

[Connections to other concepts, practical tips, common mistakes to avoid.
"A helpful way to remember this is..." or "This is analogous to X from
Section Y but now we're working in a different context."]
```

**Dispatch:** For long PDFs (>20 pages), use parallel subagents (highest available model) — one per major section. Each subagent gets:
- The section text from `marker` output
- The writing style principles listed above (include them verbatim in the subagent prompt)
- Instructions to preserve all definitions/theorems verbatim in callouts
- Instructions to write proof sketches with reasoning (key idea + technique + why it works)
- Instructions to include key examples with full step-by-step reasoning
- Instructions to cross-reference other sections where relevant

### C5. Generate Full Notes (if requested)

Same as Study Notes (including all writing style principles) but with **complete proofs** and **all examples** (not just key ones). Filename: `<Code> <Src> Full.md`.

The only differences from Study Notes:
- `> [!proof]` callouts contain the **complete proof** with commentary explaining *why* each step works, not just a sketch
- **Every** example in the source is included with full reasoning, not just selected key ones
- Remarks and additional commentary from the lecturer are preserved
- More detailed cross-references and "big picture" commentary connecting sections

### C6. Completeness check

**Run this after every course notes generation.** Use Sonnet subagent for speed.

1. **Compare against the master manifest** (from Step C2):
   - For Cheat Sheet: every definition and theorem number must appear
   - For Study Notes: every section, definition, theorem, lemma, and key example must appear
   - For Full Notes: everything in the manifest must appear — definitions, theorems, lemmas, corollaries, examples, proofs, remarks

2. **Cross-reference TOC against generated sections:**
   ```bash
   # Extract all section headers from the source
   grep -E '^#{1,3} ' /tmp/summarize/course/output.md | head -50
   # Compare against generated note sections
   grep -E '^#{1,3} ' "<generated_note_path>" | head -50
   ```

3. **Scan for missed numbered elements:**
   ```bash
   # Extract all Definition/Theorem/Lemma numbers from source
   grep -oE '(Definition|Theorem|Lemma|Corollary|Proposition|Example|Remark) [0-9]+\.[0-9]+' /tmp/summarize/course/output.md | sort -u
   # Check which ones appear in the generated note
   for item in <each extracted item>; do
     grep -q "$item" "<generated_note_path>" || echo "MISSING: $item"
   done
   ```

4. **Report:** If anything is missing, list it explicitly and fix it before marking the note as done. The summary is not complete until the completeness check passes with zero missing items.

### C7. Update course note

After all notes are generated, update the course note's `summary` frontmatter field:

```yaml
summary:
  - "[[<Code> Cheat Sheet]]"
  - "[[<Code> S1 Study Notes]]"
  - "[[<Code> S1 Full]]"
```

Only add entries for notes that were actually created. Don't remove existing entries — if S1 was processed before and S2 is being processed now, the summary list should contain both.

### Course notes model usage

| Task | Model |
|------|-------|
| Text extraction | `marker` (CLI) |
| Section summarization | Highest available (always — no Sonnet shortcut for course content) |
| Cheat sheet generation | Highest available |
| Completeness check | **Sonnet** (speed) |

**Never use Haiku for course notes.**

## Step 5: Create reference notes (one layer deep)

**Skip this step for course notes** — course notes use inline `> [!definition]` callouts instead of separate reference notes. Creating a reference note for every math concept (group, homomorphism, kernel, etc.) would be redundant since the definitions are already in the cheat sheet and study/full notes.

**This is the most important step for non-course content. Every wikilink MUST resolve to a note. No dangling links.**

### 5a. Extract and audit all wikilinks

After the summary note is fully assembled, extract every unique wikilink programmatically:

The regex excludes `|` (alias), `#` (heading ref), and `^` (block ref) so `[[Target|Alias]]`, `[[Page#Heading]]`, and `[[Page^block]]` all resolve to the canonical note name (`Target` / `Page`):
```bash
grep -oE '\[\[[^]|#^]+' "<summary_note_path>" | sed 's/\[\[//' | sort -u
```

Then check which ones are missing:

```bash
for term in <each extracted term>; do
  found=$(find "$VAULT_ROOT" -name "$term.md" \
    -not -path "*/.Trash/*" -not -path "*/Clippings/*" 2>/dev/null | head -1)
  if [ -z "$found" ]; then echo "MISSING: $term"; fi
done
```

**Do NOT skip this step. Do NOT estimate from memory which notes exist.** Always run the audit.

### 5b. Create missing notes

#### Technical concepts, companies, products, places
Create in `06 References/<Term>.md`:

```markdown
---
date: YYYY-MM-DD
type: reference
unread: true
---

[2-4 sentence plain-language explanation. Use [[wikilinks]] to cross-reference related concepts.]
```

#### People
Create in `$PEOPLE_DIR/<Full Name>.md` using the person template at `$VAULT_ROOT/$TEMPLATES_DIR/new person template.md` (installed by Step 0d). Conventions:

- **Public figures**: research and write a rich bio (birthday, career, links, key facts). The `> [!info]` callout should be a substantive snapshot — life story, mission, current focus — not a stub.
- **Private individuals**: minimal note with only what's known from the content. The note will grow naturally over time.
- **`> [!note] current age` callout** (from template): keep it if `birthday` is known or can be estimated. If estimated, append `(estimated)` to the callout text — but `birthday` in frontmatter must stay a pure YAML date (e.g. `2001-01-01`), never text.
- **`> [!abstract] total hours talked` callout** (from template): ONLY keep this if the person has had real 1-on-1 calls/meetings with the vault owner (i.e. they appear in meeting notes). Delete the callout for people discovered through summarizing videos, articles, books, or podcasts — those people will never have meeting entries, so the callout would always show 0h.
- **No `# Title` heading** — Obsidian shows the filename as the title.
- **`unread: true`** in frontmatter on every new or modified note.

#### Dispatch in parallel
For large numbers of missing notes (>10), use parallel subagents (highest available model) in batches of ~20-25 notes each. Each subagent creates the notes and returns confirmation.

### 5c. Verify — no dangling links

After all notes are created, re-run the audit from 5a to confirm zero missing notes. If any remain (e.g. a subagent failed or skipped one), create them manually. **The summary is not done until this verification passes.**

## Step 6: Update bases (optional — skip for course notes and if not using Obsidian Bases)

**Skip this step for course notes** — they don't belong in posts.base.

This step only applies if `$VAULT_ROOT/$SUMMARIES_DIR/posts.base` exists. If it doesn't, skip Step 6 entirely.

```bash
[ -f "$VAULT_ROOT/$SUMMARIES_DIR/posts.base" ] || echo "No posts.base — skipping Step 6"
```

If it does exist:
- **`posts.base`**: if new people appeared as creators/guests, add named views for them using the YAML block below, then embed them in their person notes (in a `## episodes` or `## videos` section) via `![[posts.base#Person Name]]`.
- If a new channel/show folder was created, add a channel-specific view to `posts.base` the same way.

Named view YAML block to append under the `views:` list:
```yaml
  - type: table
    name: "Person Name"
    filters:
      and:
        - people.contains(link("Person Name"))
    order:
      - date
      - file.name
    sort:
      - property: date
        direction: DESC
```

## Step 7: Update daily note

Update `$VAULT_ROOT/$DAILY_DIR/YYYY/MM/DD-MM-YYYY ddd.md` (e.g. `01 Daily/2026/04/11-04-2026 Sat.md`). Create the `YYYY/MM/` subdirectories if they don't exist. No `# Title` heading — the filename is the title. Set `unread: true` in frontmatter.

```markdown
## content summary
- summarized [[Note Title]] — [1-line description of what it is]
- created person notes: [[Person 1]], [[Person 2]], ...
```

## Model usage

| Task | Detailed | Minimal |
|------|----------|---------|
| Content extraction | Scripts (defuddle, pdftotext, marker, yt-dlp) | Scripts |
| Section summarization | Highest available (Opus if accessible, else Sonnet) | **Sonnet** |
| Reference note creation | Highest available | (skipped) |
| Person note creation | Highest available | **Sonnet** (creators/guests only) |
| **NEVER** | **Haiku** | **Haiku** |

## Key rules

1. **Wikilink everything** — every concept, person, company, place, and **book/film/show title** gets a `[[wikilink]]`
2. **One layer deep** — create reference/person notes for EVERY wikilinked term that doesn't already have a note
3. **No `# Title` headings** — Obsidian shows filename as title
4. **Never repeat frontmatter in body** — frontmatter is metadata, body is content
5. **Set `unread: true`** on every note created or modified
6. **Parallel Opus subagents** for long content — one per section for summaries, batches of ~20 for reference notes
7. **Audience-appropriate language** — match the user's requested level
8. **Always embed/link the source** — PDF embed, vid embed, or source URL in frontmatter
9. **`> [!tldr]`** is mandatory — every summary starts with a concise overview callout
10. **Person note `## updates` links to the content note, NEVER the daily note**
11. **Course notes always use max detail** — highest available model for all generation steps, Sonnet only for completeness checks
12. **Course notes completeness is mandatory** — verify against both TOC and content body. Every definition, theorem, lemma, and example must be accounted for
13. **Cheat sheet order: Formulas → Core Concepts → Definitions & Theorems** — never deviate from this structure
14. **One cheat sheet per course, updated incrementally** — don't overwrite material from other semesters when adding new content
