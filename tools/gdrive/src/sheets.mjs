import { google } from "googleapis";

/**
 * Create a Google Sheet from a CSV string.
 * @param {import("googleapis").Auth.OAuth2Client} auth
 * @param {string} csv - Raw CSV content
 * @param {string} title - Sheet title
 * @returns {Promise<string>} URL of the created spreadsheet
 */
export async function csvToSheet(auth, csv, title) {
  const sheets = google.sheets({ version: "v4", auth });
  const drive = google.drive({ version: "v3", auth });

  // Parse CSV into rows
  const rows = csv
    .trim()
    .split("\n")
    .map((line) => parseCsvLine(line));

  // Create spreadsheet
  const spreadsheet = await sheets.spreadsheets.create({
    requestBody: {
      properties: { title },
      sheets: [{ properties: { title: "Data" } }],
    },
  });

  const spreadsheetId = spreadsheet.data.spreadsheetId;

  // Write data
  await sheets.spreadsheets.values.update({
    spreadsheetId,
    range: "Data!A1",
    valueInputOption: "RAW",
    requestBody: { values: rows },
  });

  // Format header row bold + auto-resize
  const sheetId = spreadsheet.data.sheets[0].properties.sheetId;
  await sheets.spreadsheets.batchUpdate({
    spreadsheetId,
    requestBody: {
      requests: [
        {
          repeatCell: {
            range: { sheetId, startRowIndex: 0, endRowIndex: 1 },
            cell: {
              userEnteredFormat: { textFormat: { bold: true } },
            },
            fields: "userEnteredFormat.textFormat.bold",
          },
        },
        {
          autoResizeDimensions: {
            dimensions: {
              sheetId,
              dimension: "COLUMNS",
              startIndex: 0,
              endIndex: rows[0]?.length || 1,
            },
          },
        },
      ],
    },
  });

  const url = `https://docs.google.com/spreadsheets/d/${spreadsheetId}`;
  return url;
}

function parseCsvLine(line) {
  const fields = [];
  let current = "";
  let inQuote = false;

  for (let i = 0; i < line.length; i++) {
    const ch = line[i];
    if (ch === '"') {
      inQuote = !inQuote;
    } else if (ch === "," && !inQuote) {
      fields.push(current);
      current = "";
    } else {
      current += ch;
    }
  }
  fields.push(current);
  return fields;
}
