import { google } from "googleapis";

/**
 * Create a Google Slides presentation from a markdown string.
 * Handles: # title, ## section headings, | tables |, - bullet lists, **bold**, paragraphs.
 * @param {import("googleapis").Auth.OAuth2Client} auth
 * @param {string} markdown
 * @param {string} title
 * @returns {Promise<string>} URL of the created presentation
 */
export async function mdToSlides(auth, markdown, title) {
  const slides = google.slides({ version: "v1", auth });

  // Create presentation
  const pres = await slides.presentations.create({
    requestBody: { title },
  });
  const presentationId = pres.data.presentationId;

  // Parse markdown into sections
  const sections = parseMarkdown(markdown);

  // Build slide creation requests
  const requests = [];

  // Update the default title slide
  const titleSlide = pres.data.slides[0];
  const titlePlaceholder = titleSlide.pageElements.find(
    (el) => el.shape?.placeholder?.type === "CENTERED_TITLE" || el.shape?.placeholder?.type === "TITLE"
  );
  const subtitlePlaceholder = titleSlide.pageElements.find(
    (el) => el.shape?.placeholder?.type === "SUBTITLE"
  );

  if (titlePlaceholder) {
    requests.push({
      insertText: {
        objectId: titlePlaceholder.objectId,
        text: sections.title || title,
      },
    });
  }
  if (subtitlePlaceholder && sections.subtitle) {
    requests.push({
      insertText: {
        objectId: subtitlePlaceholder.objectId,
        text: sections.subtitle,
      },
    });
  }

  // Create content slides for each section
  for (const section of sections.slides) {
    const slideId = `slide_${Math.random().toString(36).slice(2, 10)}`;
    const bodyId = `body_${Math.random().toString(36).slice(2, 10)}`;
    const titleId = `title_${Math.random().toString(36).slice(2, 10)}`;

    requests.push({
      createSlide: {
        objectId: slideId,
        slideLayoutReference: { predefinedLayout: "TITLE_AND_BODY" },
        placeholderIdMappings: [
          { layoutPlaceholder: { type: "TITLE" }, objectId: titleId },
          { layoutPlaceholder: { type: "BODY" }, objectId: bodyId },
        ],
      },
    });

    requests.push({
      insertText: {
        objectId: titleId,
        text: section.heading,
      },
    });

    // Build body text from section content
    const bodyText = formatSectionContent(section.content);
    if (bodyText) {
      requests.push({
        insertText: {
          objectId: bodyId,
          text: bodyText,
        },
      });

      // Make body text smaller for tables
      if (section.hasTable) {
        requests.push({
          updateTextStyle: {
            objectId: bodyId,
            style: {
              fontFamily: "Courier New",
              fontSize: { magnitude: 9, unit: "PT" },
            },
            fields: "fontFamily,fontSize",
            textRange: { type: "ALL" },
          },
        });
      }
    }
  }

  if (requests.length > 0) {
    await slides.presentations.batchUpdate({
      presentationId,
      requestBody: { requests },
    });
  }

  return `https://docs.google.com/presentation/d/${presentationId}`;
}

function parseMarkdown(md) {
  const lines = md.split("\n");
  const result = { title: "", subtitle: "", slides: [] };
  let currentSection = null;

  for (const line of lines) {
    if (line.startsWith("# ") && !result.title) {
      result.title = line.slice(2).trim();
    } else if (line.startsWith("Report generated:") || line.startsWith("Organization:")) {
      result.subtitle = (result.subtitle ? result.subtitle + "\n" : "") + line.trim();
    } else if (line.startsWith("## ")) {
      if (currentSection) result.slides.push(currentSection);
      currentSection = { heading: line.slice(3).trim(), content: [], hasTable: false };
    } else if (currentSection) {
      if (line.startsWith("|")) currentSection.hasTable = true;
      currentSection.content.push(line);
    }
  }
  if (currentSection) result.slides.push(currentSection);

  return result;
}

function formatSectionContent(lines) {
  const parts = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;

    if (trimmed.startsWith("|")) {
      // Table row — format as aligned text
      if (trimmed.match(/^\|[-\s|]+\|$/)) continue; // skip separator
      const cells = trimmed
        .split("|")
        .filter(Boolean)
        .map((c) => c.trim());
      parts.push(cells.join("  |  "));
    } else {
      // Strip markdown bold markers for plain text
      parts.push(trimmed.replace(/\*\*/g, ""));
    }
  }

  return parts.join("\n");
}
