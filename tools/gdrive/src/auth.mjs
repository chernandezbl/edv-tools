import { google } from "googleapis";
import { readFileSync, writeFileSync, existsSync, mkdirSync } from "node:fs";
import { join } from "node:path";
import { createServer } from "node:http";
import { homedir } from "node:os";
import { URL } from "node:url";

const CONFIG_DIR = join(homedir(), ".edv-tools");
const CREDENTIALS_PATH = join(CONFIG_DIR, "credentials.json");
const TOKEN_PATH = join(CONFIG_DIR, "gdrive-token.json");

const SCOPES = [
  "https://www.googleapis.com/auth/spreadsheets",
  "https://www.googleapis.com/auth/drive.file",
  "https://www.googleapis.com/auth/presentations",
  "https://www.googleapis.com/auth/documents",
];

function loadCredentials() {
  if (!existsSync(CREDENTIALS_PATH)) {
    console.error(`Missing credentials file: ${CREDENTIALS_PATH}`);
    console.error("");
    console.error("Setup:");
    console.error("  1. Go to https://console.cloud.google.com/");
    console.error("  2. Create a project and enable Sheets, Slides, Docs, and Drive APIs");
    console.error("  3. Create an OAuth 2.0 Client ID (Desktop app)");
    console.error(`  4. Download the JSON and save it as ${CREDENTIALS_PATH}`);
    process.exit(1);
  }

  const creds = JSON.parse(readFileSync(CREDENTIALS_PATH, "utf-8"));
  const { client_id, client_secret } = creds.installed || creds.web || {};
  if (!client_id || !client_secret) {
    console.error("Invalid credentials.json — expected 'installed' or 'web' client config");
    process.exit(1);
  }
  return { client_id, client_secret };
}

function waitForAuthCode(authUrl) {
  return new Promise((resolve, reject) => {
    const server = createServer((req, res) => {
      const url = new URL(req.url, "http://localhost");
      const code = url.searchParams.get("code");
      if (code) {
        res.writeHead(200, { "Content-Type": "text/html" });
        res.end("<h2>Authenticated! You can close this tab.</h2>");
        server.close();
        resolve(code);
      } else {
        res.writeHead(400);
        res.end("Missing code parameter");
      }
    });

    server.listen(3000, () => {
      console.log(`\nOpen this URL in your browser to authorize:\n\n  ${authUrl}\n`);
      console.log("Waiting for authorization...");
    });

    server.on("error", reject);
  });
}

export async function authorize() {
  const { client_id, client_secret } = loadCredentials();

  const oauth2Client = new google.auth.OAuth2(
    client_id,
    client_secret,
    "http://localhost:3000"
  );

  // Try cached token
  if (existsSync(TOKEN_PATH)) {
    const token = JSON.parse(readFileSync(TOKEN_PATH, "utf-8"));
    oauth2Client.setCredentials(token);

    // Refresh if expired
    if (token.expiry_date && Date.now() >= token.expiry_date) {
      const { credentials } = await oauth2Client.refreshAccessToken();
      oauth2Client.setCredentials(credentials);
      writeFileSync(TOKEN_PATH, JSON.stringify(credentials, null, 2));
    }

    return oauth2Client;
  }

  // First-time auth: browser flow
  const authUrl = oauth2Client.generateAuthUrl({
    access_type: "offline",
    scope: SCOPES,
    prompt: "consent",
  });

  const code = await waitForAuthCode(authUrl);
  const { tokens } = await oauth2Client.getToken(code);
  oauth2Client.setCredentials(tokens);

  mkdirSync(CONFIG_DIR, { recursive: true });
  writeFileSync(TOKEN_PATH, JSON.stringify(tokens, null, 2));
  console.log(`Token saved to ${TOKEN_PATH}`);

  return oauth2Client;
}
