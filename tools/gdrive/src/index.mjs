#!/usr/bin/env node
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { authorize } from "./auth.mjs";
import { csvToSheet } from "./sheets.mjs";
import { mdToSlides } from "./slides.mjs";
import { mdToDoc } from "./docs.mjs";

const USAGE = `Usage:
  gdrive sheets <file.csv>  [--title "My Sheet"]    Convert CSV to Google Sheets
  gdrive slides <file.md>   [--title "My Deck"]     Convert Markdown to Google Slides
  gdrive docs   <file.md>   [--title "My Doc"]      Convert Markdown to Google Docs`;

const args = process.argv.slice(2);
const command = args[0];
const filePath = args[1];

if (!command || !filePath || ["--help", "-h"].includes(command)) {
  console.log(USAGE);
  process.exit(command ? 1 : 0);
}

// Parse --title flag
let title = null;
const titleIdx = args.indexOf("--title");
if (titleIdx !== -1 && args[titleIdx + 1]) {
  title = args[titleIdx + 1];
}

const fullPath = resolve(filePath);
let content;
try {
  content = readFileSync(fullPath, "utf-8");
} catch {
  console.error(`Cannot read file: ${fullPath}`);
  process.exit(1);
}

// Default title from filename
if (!title) {
  title = fullPath.split("/").pop().replace(/\.\w+$/, "");
}

const auth = await authorize();

switch (command) {
  case "sheets": {
    const url = await csvToSheet(auth, content, title);
    console.log(`Spreadsheet created: ${url}`);
    break;
  }
  case "slides": {
    const url = await mdToSlides(auth, content, title);
    console.log(`Presentation created: ${url}`);
    break;
  }
  case "docs": {
    const url = await mdToDoc(auth, content, title);
    console.log(`Document created: ${url}`);
    break;
  }
  default:
    console.error(`Unknown command: ${command}`);
    console.log(USAGE);
    process.exit(1);
}
