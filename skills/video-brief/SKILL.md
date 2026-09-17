---
name: video-brief
description: Turn a talk, webinar, panel, podcast, or call recording into notes someone can act on — transcribe it locally (works with no subtitles, any language), then write a brief that separates what was said from what was being sold. Use when handed a YouTube/Vimeo/tldv/conference link or a local recording and asked what's in it, for the takeaways, or for what's relevant to us.
---

# video-brief

Someone pointed you at 90 minutes of video. The deliverable is **a brief that replaces watching it** — not a transcript, and not a chronological recap, which is only the transcript again with words missing.

The transcript is an intermediate artifact. The work is in sections 3–6.

## 1. Decide what the brief is *for* — before you fetch anything

Three shapes, and they select different material out of the same hour:

- **Intel** — a competitor, a market, a vendor. Positions, claims, numbers, pricing, who they're selling to.
- **Craft** — practices worth stealing. The concrete *how*, not the thesis; a talk's thesis is usually its weakest part.
- **Record** — a call or meeting. Decisions, owners, deadlines, and what people actually disagreed about.

Infer it from how the video arrived and say which you picked in one line. If the request is bare ("summarize this"), read the first few minutes of the transcript before choosing — a title lies about a talk more often than its opening does.

## 2. Get the text

```bash
scripts/transcribe.sh [--lang pl] <url-or-file>
```

Writes `transcript.txt` — timestamped paragraphs, the thing to read — plus `meta.json` and the raw SRT/VTT, into a stable directory. Re-running the same input is free; nothing re-downloads.

What it does, and the choices worth knowing:

- **Human-written subtitles win** when the platform has them. Otherwise it transcribes locally with Whisper. On Apple Silicon that runs an order of magnitude faster than realtime — a 98-minute webinar took under 4 minutes on a cold machine here, about 1 minute warm, in both cases less than downloading it. On anything else it falls back to CPU at roughly *realtime* — check `uname -m` before starting a two-hour video, and tell the user it'll take two hours.
- **Machine captions are not the default**, and this is deliberate. YouTube's auto-captions are markedly worse than Whisper, most visibly outside English, and you cannot tell from reading them — the text is fluent and wrong. Pass `--auto-subs` when you only need to know roughly what a three-hour stream covered.
- `--lang pl` (or whatever it is) helps Whisper on a code-switching speaker; without it, language is detected from the first 30 seconds, which is exactly where the host is saying "hello, welcome".
- **The first Whisper run is the slow one** — a Python venv plus a ~1.6 GB model, cached under `~/.cache/fsh-video-brief` and `~/.cache/huggingface` for every run after. The script warns before it starts; don't mistake the model download for a hung transcription.
- Accepts a local media file, or a `.srt`/`.vtt` you already have — a tldv or Meet export goes straight in.
- Audio never leaves the machine. That matters when the recording is a client call; say so if anyone asks whether this is safe to run.

Also open `meta.json`: if the uploader wrote **chapter markers**, they're the author's own outline of the argument, and better than any you'd infer.

## 3. Read the whole transcript

Not the first third, not every fifth paragraph. 90 minutes is ~13k words — one read. The paragraph that pays for the exercise is never signposted, and in a panel it is usually in the Q&A, after the prepared material runs out.

**Cite timestamps.** Every non-obvious claim gets a `(41:20)`. This is the one thing that makes a brief checkable instead of merely confident — the reader can jump to the moment and hear it. Paragraphs in `transcript.txt` are already prefixed with theirs.

## 4. Separate the substance from the pitch

Most public talks are the top of a funnel. Find the ask — a product, a course, a discount, a deadline, a "book a call" — and give it **its own short section**, out of the substance.

Both halves need this. The substance has to stand on its own merits rather than on the speaker's authority, and the ask is often the only *time-sensitive* thing in the video (a discount that expires tomorrow is useless in a brief read next week). Don't sneer at it, don't bury it.

## 5. Distrust every proper noun

Whisper and auto-captions mangle exactly what gets quoted onward: product names, people's names, acronyms, company names — worst across a language boundary, where an English product name lands inside another language's phonetics.

- Mark anything you didn't verify: `"Cezar" (heard, unverified)`.
- Verify the ones the brief leans on — a web search, or the video's description in `meta.json`.
- Numbers mangle too, and silently. A spoken figure that carries an argument is worth re-reading in context before you repeat it.
- Name the engine at the bottom of the brief, so a later reader knows which claims to re-check.

## 6. Write it

- **Header** — title, who, where, when, runtime.
- **Speakers** — names and affiliations. The affiliation is frequently what makes a claim worth anything; "an architect at a big-four consultancy said X" and "someone on a webinar said X" are different facts.
- **The substance**, organized by the *argument* — thesis, diagnosis, the thing they propose, the objections — not by the clock. Give the strongest version of each point, including ones you disagree with.
- **The ask** (section 4), with its deadline if it has one.
- **What it means for us** — only when the brief is intel, and only if you actually have something. One or two lines. Don't manufacture relevance; an honest "nothing new for us here" is a useful result and saves the next person the same 90 minutes.
- **Provenance** — engine used, and the proper-noun caveat.

Quote sparingly and verbatim; paraphrase everything else. A brief that is 40% block quotes is a transcript wearing a hat.

Match the language of the source unless asked otherwise — a Polish webinar summarized into English loses the phrasings that make quoting it worthwhile.

## Limits

- **No speaker diarization.** Whisper emits text, not who said it. Attribute only where the transcript names someone or a handoff is unambiguous ("Tomek, do ciebie"); otherwise write "one of the panelists". A confidently wrong attribution is the worst error this skill can make — it puts words in a named person's mouth.
- **Audio only.** Slides, charts, and screen-shares are invisible. If an argument rests on a chart, you have only what was said aloud about it — say so rather than reconstructing.
- **Live streams** carry pre-roll silence, dead air, and crosstalk that transcribes as nonsense. Skip it; don't try to interpret it.
- Don't file the brief into a repo, a doc, or a channel unless asked. Most briefs are worth reading once, and a skill that auto-files becomes a junk drawer within a month.
