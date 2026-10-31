# PR description format

The house format for PR bodies. Skills that write one point here. A repo's own PR template or documented format wins over it.

Write from general to specific, so a reader can stop after any section with a correct, just less detailed, picture.

A small PR gets one or two short paragraphs and no headings. Larger PRs use the sections below, in this order, with these emoji. Drop any section with nothing real to say.

Headings carry the content. Keep the emoji, and make the words specific to this PR wherever that adds something, so that reading only the headings tells the story:

```markdown
### 🎯 Searching an order number returned every order
### 🔧 Search now matches the whole number
### 🧭 Staff find the right order first time; other searches are unchanged
```

Never `### 🎯 The problem` or `### 🔧 The fix`. Other sections keep a plain label like `### 🔍 Details` only when nothing specific would help.

- **🎯 The problem:** what someone hit and what it cost them, in plain words and without identifiers. If the PR fixes nothing, state the goal instead.
- **🔧 The fix:** the cause in a sentence, then what the PR does about it. Name things by what they do.
- **🧭 The impact:** what merging itself does: it changes what runs or, for a spec, only commits to a plan. Then what will be different, for whom, and what stays the same. When several behaviours change, add a short before/after table of what people see.
- **🧩 How the pieces fit:** when the PR adds a flow or changes how parts work together, even inside one module. Only small internal changes skip it. See below.
- **🔍 Details:** what a reviewer needs, not everything decided: names, the choice behind the approach and anything counter-intuitive.
- **✅ Testing:** what was proven, the real results and what wasn't verified, not a run log of repeat counts and every check.
- **⚠️ Worth knowing:** risks, follow-ups and breaking changes.

## How the pieces fit

Zoom in through these levels, each under a bold label:

- **System:** the people and outside systems around ours, and what passes between them.
- **Modules:** the deployable parts and modules, and who calls or notifies whom.
- **Inside a module:** the main components of the module where most of the change lives.

Show only the levels that changed, for spec PRs too, and skip one that would just repeat the level above, even for a new flow. System appears only when people or outside systems change. A new flow inside one module is usually Inside a module alone.

Each level gets one or two plain sentences and one `flowchart TD` Mermaid diagram of about 12 nodes at most. Use plain labels in double quotes and label each arrow with what passes along it. When an existing flow changes, show "today" and "after" as two subgraphs.

Keep the description accurate when the PR changes.
