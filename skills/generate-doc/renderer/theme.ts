/**
 * FSH document branding — design tokens, logo, and CSS for branded PDFs.
 *
 * Tokens mirror marketing/app/globals.css (the canonical brand source):
 *   Cherry #9E1B32 (accent) · Ink #111110 · Cream #F7F4F0.
 * Fonts come from Google Fonts (same families next/font uses on the site);
 * they load at render time with system fallbacks if offline.
 */

export type DocTemplate = "contract" | "spec";

export const BRAND = {
  cherry: "#9E1B32",
  ink: "#111110",
  inkMuted: "#5A5750",
  inkFaint: "#9B9690",
  cream: "#F7F4F0",
  tint: "#F6E7EA",
  border: "#E0DBD5",
  card: "#FDFCFA",
} as const;

/** fullstack.house lockup (from marketing/public/fsh-lockup-light.svg). */
export const FSH_LOCKUP_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 900 180" role="img" aria-label="fullstack.house" shape-rendering="geometricPrecision">
  <g id="icon" transform="translate(20,18) scale(0.75)">
    <polygon points="128.0,24.0 208.0,62.0 128.0,100.0 48.0,62.0" fill="#9E1B32"/>
    <polygon points="48.0,78.0 120.0,110.4 120.0,132.4 48.0,100.0" fill="#111110"/>
    <polygon points="48.0,114.0 120.0,146.4 120.0,168.4 48.0,136.0" fill="#111110"/>
    <polygon points="48.0,150.0 72.0,160.8 72.0,182.8 48.0,172.0" fill="#111110"/>
    <polygon points="184.0,88.8 208.0,78.0 208.0,136.0 184.0,146.8" fill="#111110"/>
    <polygon points="136.0,158.0 160.0,147.2 160.0,193.2 136.0,204.0" fill="#111110"/>
    <polygon points="136.0,110.4 208.0,78.0 208.0,100.0 136.0,132.4" fill="#111110"/>
    <polygon points="136.0,146.4 208.0,114.0 208.0,136.0 136.0,168.4" fill="#111110"/>
    <polygon points="136.0,182.4 208.0,150.0 208.0,172.0 136.0,204.4" fill="#111110"/>
  </g>
  <text x="228" y="118" font-family="'IBM Plex Mono','SFMono-Regular','Menlo','Consolas',monospace" font-size="54" font-weight="700" letter-spacing="0.5" fill="#111110">fullstack<tspan fill="#9E1B32">.house</tspan></text>
</svg>`;

/** Bare mark (no wordmark) — used small in the running header. */
export const FSH_MARK_SVG = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 220 210" role="img" aria-label="FSH">
  <polygon points="128,24 208,62 128,100 48,62" fill="#9E1B32"/>
  <polygon points="48,78 120,110.4 120,132.4 48,100" fill="#111110"/>
  <polygon points="48,114 120,146.4 120,168.4 48,136" fill="#111110"/>
  <polygon points="48,150 72,160.8 72,182.8 48,172" fill="#111110"/>
  <polygon points="184,88.8 208,78 208,136 184,146.8" fill="#111110"/>
  <polygon points="136,158 160,147.2 160,193.2 136,204" fill="#111110"/>
  <polygon points="136,110.4 208,78 208,100 136,132.4" fill="#111110"/>
  <polygon points="136,146.4 208,114 208,136 136,168.4" fill="#111110"/>
  <polygon points="136,182.4 208,150 208,172 136,204.4" fill="#111110"/>
</svg>`;

export function svgDataUri(svg: string): string {
  return `data:image/svg+xml;base64,${Buffer.from(svg).toString("base64")}`;
}

const FONT_IMPORT = `@import url('https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;600&family=Inter:wght@400;500;600;700&family=Instrument+Serif:ital@0;1&family=Space+Grotesk:wght@500;600;700&display=swap');`;

/**
 * Full-document stylesheet for a given template.
 *
 * `spec` leans into the brand (cherry accents, serif display type, cover page).
 * `contract` is deliberately sober — a legal document, not a marketing piece:
 * neutral sans headings, no per-heading cherry, muted rules. Cherry survives
 * only on links, so the doc still reads as FSH without looking "designed".
 */
export function buildCss(template: DocTemplate): string {
  const isSpec = template === "spec";

  // decorative accents — cherry for spec, muted neutrals for the sober contract
  const marker = isSpec ? BRAND.cherry : BRAND.inkFaint;
  const hrColor = isSpec ? BRAND.tint : BRAND.border;
  const quoteBorder = isSpec ? BRAND.cherry : BRAND.border;
  const quoteBg = isSpec ? BRAND.cream : "transparent";
  const doctypeColor = isSpec ? BRAND.cherry : BRAND.inkMuted;

  // title block type — serif display for spec, restrained sans for contract
  const titleFont = isSpec ? "'Instrument Serif', Georgia, serif" : "'Space Grotesk', 'Inter', sans-serif";
  const titleWeight = isSpec ? "400" : "700";
  const titleSize = isSpec ? "30pt" : "21pt";

  const accentBar = isSpec
    ? `h2::before { content: ""; display: block; width: 32px; height: 3px; background: ${BRAND.cherry}; margin-bottom: 8px; border-radius: 2px; }`
    : "";

  return `${FONT_IMPORT}
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; }
  body {
    font-family: 'Inter', -apple-system, 'Segoe UI', Roboto, Arial, sans-serif;
    font-size: 10.5pt;
    line-height: 1.62;
    color: ${BRAND.ink};
    -webkit-print-color-adjust: exact;
    print-color-adjust: exact;
  }

  /* Sections flow naturally across pages; we only prevent BAD breaks
     (orphaned headings via break-after, split list items) — not whole
     sections, which leaves half-empty pages. */
  .section + .section { margin-top: 4px; }

  /* headings */
  h1, h2, h3, h4 { font-family: 'Space Grotesk', 'Inter', sans-serif; color: ${BRAND.ink}; line-height: 1.25; font-weight: 600; break-after: avoid; }
  h1 { font-size: 22pt; font-weight: 700; margin: 0 0 4px; letter-spacing: -0.01em; }
  h2 { font-size: 14pt; margin: 30px 0 12px; padding-bottom: 6px; border-bottom: 1px solid ${BRAND.border}; }
  h3 { font-size: 11.5pt; margin: 22px 0 8px; color: ${BRAND.inkMuted}; }
  h4 { font-size: 10.5pt; margin: 16px 0 6px; text-transform: uppercase; letter-spacing: 0.06em; color: ${BRAND.inkFaint}; font-family: 'IBM Plex Mono', monospace; font-weight: 600; }
  ${accentBar}

  p { margin: 0 0 11px; orphans: 2; widows: 2; }
  a { color: ${BRAND.cherry}; text-decoration: none; }
  strong { font-weight: 600; }
  em { font-style: italic; }

  ul, ol { margin: 0 0 13px; padding-left: 22px; }
  li { margin: 0 0 6px; padding-left: 3px; orphans: 2; widows: 2; break-inside: avoid; }
  li::marker { color: ${marker}; }
  /* legal numbering: 1. → a. → i. down the nesting levels */
  ol { list-style-type: decimal; }
  ol ol { list-style-type: lower-alpha; }
  ol ol ol { list-style-type: lower-roman; }
  ol ol, ul ul { margin: 6px 0 8px; }

  hr { border: none; border-top: ${isSpec ? "2px" : "1px"} solid ${hrColor}; margin: 20px 0; }

  blockquote {
    margin: 12px 0; padding: 8px 14px;
    border-left: 3px solid ${quoteBorder};
    background: ${quoteBg};
    color: ${BRAND.inkMuted};
  }

  code { font-family: 'IBM Plex Mono', monospace; font-size: 9pt; background: ${BRAND.cream}; padding: 1px 4px; border-radius: 3px; }
  pre { background: ${BRAND.cream}; border: 1px solid ${BRAND.border}; border-radius: 6px; padding: 12px; overflow-x: auto; }
  pre code { background: none; padding: 0; }

  /* tables */
  table { width: 100%; border-collapse: collapse; margin: 12px 0; font-size: 9.5pt; }
  th, td { padding: 7px 10px; text-align: left; border-bottom: 1px solid ${BRAND.border}; vertical-align: top; }
  thead th { background: ${BRAND.cream}; font-family: 'Space Grotesk', sans-serif; font-weight: 600; border-bottom: 1.5px solid ${BRAND.ink}; }
  tbody tr:last-child td { border-bottom: 1px solid ${BRAND.ink}; }

  /* keep table rows and list items from splitting across pages */
  tr { break-inside: avoid; }
  /* content images (mockups/screenshots) — framed, never split across pages */
  img { max-width: 100%; height: auto; display: block; margin: 10px 0 16px; border: 1px solid ${BRAND.border}; border-radius: 5px; break-inside: avoid; }

  /* ── document title block (contract) = page-1 letterhead ── */
  .doc-titleblock { margin: 0 0 26px; padding: 0 0 18px; border-bottom: ${isSpec ? "2px" : "1px"} solid ${isSpec ? BRAND.ink : BRAND.border}; }
  .doc-titleblock .logo { width: ${isSpec ? "190px" : "150px"}; margin-bottom: 20px; }
  .doc-titleblock .doctype { font-family: 'IBM Plex Mono', monospace; font-size: 8.5pt; letter-spacing: 0.16em; text-transform: uppercase; color: ${doctypeColor}; margin-bottom: 6px; }
  .doc-titleblock h1 { font-family: ${titleFont}; font-weight: ${titleWeight}; font-size: ${titleSize}; letter-spacing: ${isSpec ? "0" : "-0.01em"}; }
  .doc-titleblock .subtitle { color: ${BRAND.inkMuted}; font-size: 12pt; margin-top: 2px; }
  .doc-titleblock .meta { margin-top: 14px; font-family: 'IBM Plex Mono', monospace; font-size: 8.5pt; color: ${BRAND.inkMuted}; }
  .doc-titleblock .meta span { margin-right: 18px; }

  /* ── cover page (spec) ── (page 1 = letterhead, no running header) */
  .cover { height: 253mm; display: flex; flex-direction: column; page-break-after: always; }
  .cover .top { flex: 0 0 auto; }
  .cover .logo { width: 230px; }
  .cover .mid { flex: 1 1 auto; display: flex; flex-direction: column; justify-content: center; }
  .cover .doctype { font-family: 'IBM Plex Mono', monospace; font-size: 10pt; letter-spacing: 0.18em; text-transform: uppercase; color: ${BRAND.cherry}; margin-bottom: 14px; }
  .cover h1 { font-family: 'Instrument Serif', Georgia, serif; font-weight: 400; font-size: 46pt; line-height: 1.05; max-width: 15em; }
  .cover .subtitle { font-size: 15pt; color: ${BRAND.inkMuted}; margin-top: 14px; max-width: 30em; }
  .cover .rule { width: 60px; height: 4px; background: ${BRAND.cherry}; margin: 24px 0; border-radius: 2px; }
  .cover .bottom { flex: 0 0 auto; font-family: 'IBM Plex Mono', monospace; font-size: 9pt; color: ${BRAND.inkMuted}; border-top: 1px solid ${BRAND.border}; padding-top: 12px; }
  .cover .bottom span { margin-right: 22px; }
  `;
}

/**
 * Running-footer: confidentiality note + page numbers. Uses a web-safe font
 * (Arial) because the footer sandbox falls back to serif for absent web fonts.
 */
export function footerTemplate(confidential: boolean): string {
  const left = confidential ? "Poufne — dokument przygotowany przez Full Stack House" : "Full Stack House";
  return `<div style="width:100%; box-sizing:border-box; font-family:Arial,Helvetica,sans-serif; font-size:7pt; color:#9B9690; padding:0 18mm; display:flex; align-items:center; justify-content:space-between;">
    <span>${left}</span>
    <span>Strona <span class="pageNumber"></span> / <span class="totalPages"></span></span>
  </div>`;
}
