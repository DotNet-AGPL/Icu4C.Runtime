#!/usr/bin/env node
// Convert a Markdown article into WeChat-compatible HTML (all CSS inlined).
//
// Usage:
//   node convert.js <input.md> <output.html> [--keep-title]
//
// WeChat's editor strips <style> tags and class names, so `juice` inlines the theme
// CSS onto every element. The first level-1 heading ("# Title") is treated as the
// article title (printed to stdout) and removed from the body, because the title is
// entered in a separate field in the WeChat editor. Pass --keep-title to keep it.

import fs from 'node:fs';
import { marked } from 'marked';
import juice from 'juice';

const args = process.argv.slice(2);
const keepTitle = args.includes('--keep-title');
const files = args.filter((a) => !a.startsWith('--'));

if (files.length < 2) {
  console.error('usage: node convert.js <input.md> <output.html> [--keep-title]');
  process.exit(1);
}
const [inFile, outFile] = files;

let md = fs.readFileSync(inFile, 'utf8');

// Extract the leading "# Title" as the article title.
let title = '';
const titleMatch = md.match(/^\s*#\s+(.+?)\s*\r?\n/);
if (titleMatch && md.indexOf(titleMatch[0]) <= 2) {
  title = titleMatch[1].trim();
  if (!keepTitle) {
    md = md.slice(titleMatch[0].length);
  }
}

const body = marked.parse(md, { gfm: true, breaks: false });

const wrapped = `<div class="wx-article">\n${body}\n</div>\n`;

const css = fs.readFileSync(new URL('./wechat-theme.css', import.meta.url), 'utf8');

const inlined = juice(wrapped, {
  extraCss: css,
  removeStyleTags: true,
  preserveMediaQueries: false,
  applyStyleTags: false,
});

const html =
  `<!doctype html>\n<html lang="zh-CN">\n<head>\n<meta charset="utf-8">\n` +
  `<title>${title || 'article'}</title>\n</head>\n<body>\n${inlined}\n</body>\n</html>\n`;

fs.writeFileSync(outFile, html, 'utf8');

if (title) {
  console.log(`title : ${title}`);
}
console.log(`output: ${outFile}`);
