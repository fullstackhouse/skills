/**
 * Render any Markdown file into a branded FSH PDF (contract- or spec-styled).
 *
 * Pipeline: Markdown → HTML (marked, GFM) → wrap in FSH theme → Chromium page.pdf().
 * A running header/footer (logo + page numbers + confidentiality) repeats on
 * every page; `spec` adds a cover page, `contract` a formal title block.
 *
 * Optional YAML-ish frontmatter at the top of the .md sets defaults:
 *   ---
 *   title: Umowa wdrożeniowa
 *   subtitle: Helmet ERP
 *   client: Helmet Sp. z o.o.
 *   date: 2026-07-08
 *   template: contract        # contract | spec
 *   confidential: true
 *   ---
 * CLI flags override frontmatter.
 */
import { chalk, $ } from "zx";
import { chromium } from "playwright";
import { marked } from "marked";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";
import { pathToFileURL, fileURLToPath } from "node:url";
import { buildCss, footerTemplate, FSH_LOCKUP_SVG, type DocTemplate } from "./theme.ts";

/** Directory of this renderer (bundled assets live alongside it). */
const RENDERER_DIR = path.dirname(fileURLToPath(import.meta.url));

export type DocFormat = "pdf" | "docx";

export interface RenderDocOptions {
  input: string;
  output?: string;
  template?: DocTemplate;
  format?: DocFormat;
  title?: string;
  subtitle?: string;
  client?: string;
  date?: string;
  confidential?: boolean;
}

interface DocMeta {
  title?: string;
  subtitle?: string;
  client?: string;
  date?: string;
  template?: DocTemplate;
  format?: DocFormat;
  confidential?: boolean;
}

/** Minimal frontmatter parser (key: value lines between leading `---` fences). */
function parseFrontmatter(raw: string): { meta: DocMeta; body: string } {
  if (!raw.startsWith("---")) return { meta: {}, body: raw };
  const end = raw.indexOf("\n---", 3);
  if (end === -1) return { meta: {}, body: raw };

  const block = raw.slice(raw.indexOf("\n") + 1, end);
  const body = raw.slice(end + 4).replace(/^\s*\n/, "");
  const meta: DocMeta = {};

  for (const line of block.split("\n")) {
    const m = line.match(/^([A-Za-z_]+):\s*(.*)$/);
    if (!m) continue;
    const key = m[1].toLowerCase();
    let value = m[2].trim().replace(/^["']|["']$/g, "");
    if (key === "title") meta.title = value;
    else if (key === "subtitle") meta.subtitle = value;
    else if (key === "client") meta.client = value;
    else if (key === "date") meta.date = value;
    else if (key === "template" && (value === "contract" || value === "spec")) meta.template = value;
    else if (key === "format" && (value === "pdf" || value === "docx")) meta.format = value;
    else if (key === "confidential") meta.confidential = value === "true" || value === "yes";
  }
  return { meta, body };
}

function escapeHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function metaLine(label: string, value?: string): string {
  return value ? `<span><strong>${escapeHtml(label)}:</strong> ${escapeHtml(value)}</span>` : "";
}

function titleBlock(meta: Required<Pick<DocMeta, "template">> & DocMeta): string {
  if (!meta.title) return "";
  // No doctype kicker: it duplicated the title (e.g. "UMOWA" over "Umowa wdrożeniowa").
  return `<div class="doc-titleblock">
    <div class="logo">${FSH_LOCKUP_SVG}</div>
    <h1>${escapeHtml(meta.title)}</h1>
    ${meta.subtitle ? `<div class="subtitle">${escapeHtml(meta.subtitle)}</div>` : ""}
    <div class="meta">
      ${metaLine("Klient", meta.client)}
      ${metaLine("Data", meta.date)}
    </div>
  </div>`;
}

function coverPage(meta: DocMeta): string {
  const title = meta.title ?? "Specyfikacja techniczna";
  return `<section class="cover">
    <div class="top"><div class="logo">${FSH_LOCKUP_SVG}</div></div>
    <div class="mid">
      <div class="doctype">Specyfikacja techniczna</div>
      <h1>${escapeHtml(title)}</h1>
      ${meta.subtitle ? `<div class="subtitle">${escapeHtml(meta.subtitle)}</div>` : ""}
      <div class="rule"></div>
    </div>
    <div class="bottom">
      ${metaLine("Klient", meta.client)}
      ${metaLine("Data", meta.date)}
      <span>fullstack.house</span>
    </div>
  </section>`;
}

/** Drop a redundant leading `# H1` so it doesn't repeat under our title block. */
function stripLeadingH1(markdown: string): string {
  return markdown.replace(/^\s*#\s+.*(?:\r?\n|$)/, "");
}

const mdToHtml = (md: string): string => marked.parse(md, { async: false, gfm: true, breaks: false }) as string;

/**
 * Ensure a blank line precedes every ATX heading. Source docs sometimes place a
 * `## §` heading directly after a list item with no blank line, which both
 * marked and pandoc then swallow as list continuation (heading renders as literal
 * "## ..." text). Applied to both output paths.
 */
function ensureBlankBeforeHeadings(markdown: string): string {
  const out: string[] = [];
  for (const line of markdown.split("\n")) {
    if (/^#{1,6}\s/.test(line) && out.length > 0 && out[out.length - 1].trim() !== "") {
      out.push("");
    }
    out.push(line);
  }
  return out.join("\n");
}

/**
 * CommonMark (marked) ignores lettered list markers (a. b. c.) that legal docs
 * use for sub-points, rendering them as run-on text. Rewrite them to numeric
 * markers so marked nests them as an <ol>; CSS then styles nested lists a/b/c.
 * (The pandoc/DOCX path parses lettered lists natively, so this is PDF-only.)
 */
function normalizeLetterSublists(markdown: string): string {
  return markdown
    .split("\n")
    .map((line) => {
      const m = line.match(/^(\s{2,})([a-p])([.)])(\s+)(\S.*)$/);
      if (!m) return line;
      const num = m[2].charCodeAt(0) - 96; // a→1, b→2, …
      return `${m[1]}${num}.${m[4]}${m[5]}`;
    })
    .join("\n");
}

/**
 * Render body Markdown, wrapping each top-level `## ` section in a `<section>`
 * so short sections don't split across a page break (see `.section` CSS).
 * Content before the first `## ` (e.g. contract parties) becomes its own block.
 */
function renderSections(markdown: string): string {
  const chunks = markdown.split(/(?=^##\s)/m).filter((c) => c.trim().length > 0);
  if (chunks.length <= 1) return `<section class="section">${mdToHtml(markdown)}</section>`;
  return chunks.map((c) => `<section class="section">${mdToHtml(c)}</section>`).join("\n");
}

export function buildHtml(markdown: string, meta: DocMeta, baseDir?: string): string {
  const template: DocTemplate = meta.template ?? "contract";
  const renderLead = Boolean(meta.title);
  const stripped = renderLead ? stripLeadingH1(markdown) : markdown;
  const contentHtml = renderSections(normalizeLetterSublists(ensureBlankBeforeHeadings(stripped)));

  const lead = !renderLead ? "" : template === "spec" ? coverPage(meta) : titleBlock({ ...meta, template });

  // <base> so relative image paths (mockups) resolve against the source .md's
  // directory even though the HTML is rendered from a temp file.
  const base = baseDir ? `\n  <base href="${pathToFileURL(baseDir).href.replace(/\/?$/, "/")}" />` : "";

  return `<!DOCTYPE html>
<html lang="pl">
<head>
  <meta charset="UTF-8" />${base}
  <style>${buildCss(template)}</style>
</head>
<body>
  ${lead}
  <main>${contentHtml}</main>
</body>
</html>`;
}

/** Branded PDF via Chromium (full visual control: header/footer, cover, CSS). */
async function renderPdf(body: string, meta: DocMeta, outputPath: string, baseDir: string): Promise<void> {
  const html = buildHtml(body, meta, baseDir);

  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "fsh-doc-"));
  const htmlPath = path.join(tempDir, "doc.html");
  fs.writeFileSync(htmlPath, html);

  const browser = await chromium.launch({ headless: true });
  try {
    const page = await browser.newPage();
    await page.goto(`file://${htmlPath}`, { waitUntil: "networkidle" });
    await page.pdf({
      path: outputPath,
      format: "A4",
      printBackground: true,
      displayHeaderFooter: true,
      // No running header — page 1 carries the branded letterhead (title block);
      // the footer (page numbers + confidentiality) repeats on every page.
      headerTemplate: "<div></div>",
      footerTemplate: footerTemplate(meta.confidential ?? true),
      margin: { top: "18mm", bottom: "16mm", left: "18mm", right: "18mm" },
    });
  } finally {
    await browser.close();
  }
}

/**
 * Editable DOCX via pandoc — for documents that get redlined (e.g. contracts).
 * Branding is intentionally light here: a logo + title block prepended as
 * Markdown, styled by an optional `src/doc/reference.docx`. Full-page headers
 * and cover pages are a PDF-only affordance.
 */
async function renderDocx(body: string, meta: DocMeta, outputPath: string, baseDir: string): Promise<void> {
  if (!(await hasPandoc())) {
    throw new Error(
      "DOCX output requires `pandoc` on PATH (https://pandoc.org/installing.html). " +
        "Install it, or render PDF instead (--format pdf).",
    );
  }
  const renderLead = Boolean(meta.title);
  const content = ensureBlankBeforeHeadings(renderLead ? stripLeadingH1(body) : body);

  const parts: string[] = [];
  const logo = path.join(RENDERER_DIR, "assets", "fsh-lockup-light.png");
  if (fs.existsSync(logo)) parts.push(`![](${logo}){width=1.8in}\n`);
  if (meta.title) {
    parts.push(`# ${meta.title}\n`);
    if (meta.subtitle) parts.push(`**${meta.subtitle}**\n`);
    const metaBits = [
      meta.client ? `**Klient:** ${meta.client}` : "",
      meta.date ? `**Data:** ${meta.date}` : "",
    ]
      .filter(Boolean)
      .join(" · ");
    if (metaBits) parts.push(`${metaBits}\n`);
    parts.push("\n---\n");
  }
  parts.push(content);

  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), "fsh-doc-"));
  const mdPath = path.join(tempDir, "doc.md");
  fs.writeFileSync(mdPath, parts.join("\n"));

  // lists_without_preceding_blankline: match CommonMark/marked — let a list
  // interrupt a paragraph (source docs omit the blank line before sub-lists).
  // --resource-path resolves relative image paths against the source .md's dir.
  const pandocArgs = ["-f", "markdown+lists_without_preceding_blankline", "-t", "docx", "-o", outputPath, `--resource-path=${baseDir}`, mdPath];
  const refDoc = path.join(RENDERER_DIR, "reference.docx");
  if (fs.existsSync(refDoc)) pandocArgs.push(`--reference-doc=${refDoc}`);

  await $`pandoc ${pandocArgs}`;
}

/** Is pandoc available on PATH? (DOCX-only dependency.) */
async function hasPandoc(): Promise<boolean> {
  try {
    await $`pandoc --version`.quiet();
    return true;
  } catch {
    return false;
  }
}

export async function renderDoc(opts: RenderDocOptions): Promise<string> {
  const inputPath = path.resolve(opts.input);
  if (!fs.existsSync(inputPath)) {
    throw new Error(`Input file not found: ${inputPath}`);
  }

  const raw = fs.readFileSync(inputPath, "utf8");
  const { meta: fmMeta, body } = parseFrontmatter(raw);

  // CLI flags override frontmatter.
  const format: DocFormat = opts.format ?? fmMeta.format ?? "pdf";
  const meta: DocMeta = {
    title: opts.title ?? fmMeta.title,
    subtitle: opts.subtitle ?? fmMeta.subtitle,
    client: opts.client ?? fmMeta.client,
    date: opts.date ?? fmMeta.date,
    template: opts.template ?? fmMeta.template ?? "contract",
    format,
    confidential: opts.confidential ?? fmMeta.confidential ?? true,
  };

  const ext = format === "docx" ? ".docx" : ".pdf";
  const outputPath = opts.output
    ? path.resolve(opts.output)
    : path.join(path.dirname(inputPath), `${path.basename(inputPath, path.extname(inputPath))}${ext}`);
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });

  const baseDir = path.dirname(inputPath); // relative image paths resolve here
  console.log(chalk.blue(`Rendering ${chalk.bold(meta.template)} → ${chalk.bold(format.toUpperCase())}...`));
  if (format === "docx") {
    await renderDocx(body, meta, outputPath, baseDir);
  } else {
    await renderPdf(body, meta, outputPath, baseDir);
  }

  console.log(chalk.green(`${format.toUpperCase()}: ${outputPath}`));
  return outputPath;
}

export async function runRenderDoc(options: {
  input: string;
  output?: string;
  template?: string;
  format?: string;
  title?: string;
  subtitle?: string;
  client?: string;
  date?: string;
  confidential?: boolean;
}): Promise<void> {
  const template =
    options.template === "spec" || options.template === "contract"
      ? (options.template as DocTemplate)
      : undefined;
  if (options.template && !template) {
    throw new Error(`--template must be "contract" or "spec" (got "${options.template}")`);
  }

  const format =
    options.format === "pdf" || options.format === "docx" ? (options.format as DocFormat) : undefined;
  if (options.format && !format) {
    throw new Error(`--format must be "pdf" or "docx" (got "${options.format}")`);
  }

  await renderDoc({ ...options, template, format });
}
