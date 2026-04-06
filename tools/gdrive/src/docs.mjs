import { google } from "googleapis";

/**
 * Create a Google Doc from a markdown string.
 * Handles: # headings, ## subheadings, | tables |, - bullet lists, **bold**, paragraphs.
 * @param {import("googleapis").Auth.OAuth2Client} auth
 * @param {string} markdown
 * @param {string} title
 * @returns {Promise<string>} URL of the created document
 */
export async function mdToDoc(auth, markdown, title) {
  const docs = google.docs({ version: "v1", auth });

  // Create document
  const doc = await docs.documents.create({
    requestBody: { title },
  });
  const documentId = doc.data.documentId;

  // Parse markdown and build requests
  const requests = buildDocRequests(markdown);

  if (requests.length > 0) {
    await docs.documents.batchUpdate({
      documentId,
      requestBody: { requests },
    });
  }

  return `https://docs.google.com/document/d/${documentId}`;
}

function buildDocRequests(md) {
  const lines = md.split("\n");
  const elements = [];

  // Parse markdown into elements (text, heading, table, bullet)
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];

    if (line.startsWith("# ")) {
      elements.push({ type: "heading1", text: line.slice(2).trim() });
    } else if (line.startsWith("## ")) {
      elements.push({ type: "heading2", text: line.slice(3).trim() });
    } else if (line.startsWith("### ")) {
      elements.push({ type: "heading3", text: line.slice(4).trim() });
    } else if (line.startsWith("|")) {
      // Collect table rows
      const tableLines = [];
      while (i < lines.length && lines[i].startsWith("|")) {
        const row = lines[i].trim();
        // Skip separator rows like |---|---|
        if (!row.match(/^\|[-\s:|]+\|$/)) {
          tableLines.push(row);
        }
        i++;
      }
      if (tableLines.length > 0) {
        elements.push({ type: "table", rows: tableLines });
      }
      continue; // i already advanced
    } else if (line.startsWith("- ")) {
      elements.push({ type: "bullet", text: line.slice(2).trim() });
    } else if (line.trim()) {
      elements.push({ type: "paragraph", text: line.trim() });
    }

    i++;
  }

  // Build Docs API requests — insert text forward, tracking cursor index.
  // Strip ** markers before insertion so index math stays correct.
  const requests = [];
  let index = 1; // cursor position in the document

  for (const el of elements) {
    if (el.type === "table") {
      const tableText = el.rows.join("\n") + "\n\n";
      requests.push({
        insertText: { location: { index }, text: tableText },
      });
      requests.push({
        updateTextStyle: {
          range: { startIndex: index, endIndex: index + tableText.length },
          textStyle: { weightedFontFamily: { fontFamily: "Courier New" }, fontSize: { magnitude: 9, unit: "PT" } },
          fields: "weightedFontFamily,fontSize",
        },
      });
      index += tableText.length;
    } else {
      // Strip bold markers before insertion so lengths are accurate
      const cleanText = el.text.replace(/\*\*/g, "");
      const text = cleanText + "\n";
      requests.push({
        insertText: { location: { index }, text },
      });

      // Apply heading styles
      if (el.type === "heading1" || el.type === "heading2" || el.type === "heading3") {
        const namedStyle =
          el.type === "heading1" ? "HEADING_1" :
            el.type === "heading2" ? "HEADING_2" : "HEADING_3";
        requests.push({
          updateParagraphStyle: {
            range: { startIndex: index, endIndex: index + text.length },
            paragraphStyle: { namedStyleType: namedStyle },
            fields: "namedStyleType",
          },
        });
      }

      // Apply bold formatting for text that had ** markers
      if (el.text.includes("**")) {
        const boldRegex = /\*\*(.+?)\*\*/g;
        let match;
        const boldRanges = [];

        while ((match = boldRegex.exec(el.text)) !== null) {
          const boldText = match[1];
          // Position in clean string = match.index minus (number of ** pairs before this) * 4
          // Easier: count ** stripped so far
          const beforeMatch = el.text.slice(0, match.index).replace(/\*\*/g, "");
          const startInClean = beforeMatch.length;
          const endInClean = startInClean + boldText.length;

          boldRanges.push({
            startIndex: index + startInClean,
            endIndex: index + endInClean,
          });
        }

        for (const range of boldRanges) {
          requests.push({
            updateTextStyle: {
              range: { startIndex: range.startIndex, endIndex: range.endIndex },
              textStyle: { bold: true },
              fields: "bold",
            },
          });
        }
      }

      index += text.length;
    }
  }

  return requests;
}
