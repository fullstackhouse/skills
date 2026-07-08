#!/usr/bin/env node --experimental-strip-types
/**
 * Standalone CLI for the FSH branded document renderer.
 * Bundled with the `generate-doc` skill — self-contained, no monorepo needed.
 *
 *   node --experimental-strip-types cli.ts --input <file.md> [flags]
 *
 * Flags: --output <file>  --template contract|spec  --format pdf|docx
 *        --title  --subtitle  --client  --date  --no-confidential
 */
import { minimist } from "zx";
import { runRenderDoc } from "./render-doc.ts";

const args = minimist(process.argv.slice(2), {
  string: ["input", "output", "template", "format", "title", "subtitle", "client", "date"],
  boolean: ["confidential"],
  default: { confidential: true },
});

if (!args.input) {
  console.error(
    "Usage: render-doc --input <file.md> [--output <file>] [--template contract|spec]\n" +
      "                  [--format pdf|docx] [--title ..] [--subtitle ..] [--client ..]\n" +
      "                  [--date ..] [--no-confidential]",
  );
  process.exit(1);
}

await runRenderDoc({
  input: args.input,
  output: args.output,
  template: args.template,
  format: args.format,
  title: args.title,
  subtitle: args.subtitle,
  client: args.client,
  date: args.date,
  confidential: args.confidential,
});
