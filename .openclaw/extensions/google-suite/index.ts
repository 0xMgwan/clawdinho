import fs from "node:fs";
import path from "node:path";
import { Type } from "@sinclair/typebox";
import { google } from "googleapis";

// Hard-wired per user request
const GOOGLE_PROFILE_ID = "google:davidmachuche@gmail.com";

type AuthProfilesFile = {
  version?: number;
  profiles?: Record<
    string,
    {
      type?: string;
      provider?: string;
      access?: string;
      refresh?: string;
      expires?: number;
      scopes?: string[];
    }
  >;
};

function base64UrlEncode(input: Buffer | string) {
  const b = Buffer.isBuffer(input) ? input : Buffer.from(input, "utf8");
  return b
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/g, "");
}

function buildRawEmail(params: {
  to: string;
  subject: string;
  bodyText: string;
  cc?: string;
  bcc?: string;
  replyTo?: string;
}) {
  // Keep it simple: RFC 2822-ish plain text
  const lines: string[] = [];
  lines.push(`To: ${params.to}`);
  if (params.cc) lines.push(`Cc: ${params.cc}`);
  if (params.bcc) lines.push(`Bcc: ${params.bcc}`);
  if (params.replyTo) lines.push(`Reply-To: ${params.replyTo}`);
  lines.push(`Subject: ${params.subject}`);
  lines.push("MIME-Version: 1.0");
  lines.push('Content-Type: text/plain; charset="UTF-8"');
  lines.push("Content-Transfer-Encoding: 7bit");
  lines.push("");
  lines.push(params.bodyText);
  lines.push("");
  return lines.join("\r\n");
}

function resolveAuthProfilesPath(api: any) {
  // Prefer OpenClaw's resolved stateDir (respects OPENCLAW_STATE_DIR)
  const stateDir = api?.runtime?.state?.resolveStateDir
    ? api.runtime.state.resolveStateDir(api.config)
    : process.env.OPENCLAW_STATE_DIR || "/data/openclaw";

  // Default agent id is usually "main"; allow override for advanced setups.
  const agentId = process.env.OPENCLAW_AGENT_ID || "main";

  return path.join(stateDir, "agents", agentId, "agent", "auth-profiles.json");
}

function loadGoogleRefreshToken(api: any) {
  const authPath = resolveAuthProfilesPath(api);
  if (!fs.existsSync(authPath)) {
    throw new Error(
      `auth-profiles.json not found at ${authPath}. Ensure your Railway volume/stateDir includes this file.`,
    );
  }
  const parsed = JSON.parse(
    fs.readFileSync(authPath, "utf8"),
  ) as AuthProfilesFile;

  const profile = parsed?.profiles?.[GOOGLE_PROFILE_ID];
  const refresh = profile?.refresh;

  if (!refresh) {
    throw new Error(
      `Missing refresh token for profile ${GOOGLE_PROFILE_ID} in ${authPath}.`,
    );
  }
  return refresh;
}

function requireEnv(name: string) {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required env var: ${name}`);
  return v;
}

function getOAuthClient(api: any) {
  const clientId = requireEnv("GOOGLE_CLIENT_ID");
  const clientSecret = requireEnv("GOOGLE_CLIENT_SECRET");
  const refreshToken = loadGoogleRefreshToken(api);

  const oauth2Client = new google.auth.OAuth2(clientId, clientSecret);
  oauth2Client.setCredentials({ refresh_token: refreshToken });
  return oauth2Client;
}

function jsonText(obj: any) {
  return JSON.stringify(obj, null, 2);
}

export default function (api: any) {
  const logger = api?.logger;

  // ----- Gmail: list -----

  api.registerTool({
    name: "gmail_list",
    description:
      "List Gmail message ids for the configured account (supports q, labelIds, pagination).",
    parameters: Type.Object({
      q: Type.Optional(
        Type.String({ description: "Gmail search query (same as in Gmail UI)." }),
      ),
      labelIds: Type.Optional(
        Type.Array(Type.String(), { description: "Label IDs to filter by." }),
      ),
      maxResults: Type.Optional(
        Type.Integer({
          description: "Max results (1-500).",
          minimum: 1,
          maximum: 500,
        }),
      ),
      pageToken: Type.Optional(Type.String({ description: "Pagination token." })),
      includeSpamTrash: Type.Optional(
        Type.Boolean({ description: "Whether to include spam/trash." }),
      ),
    }),
    async execute(_id: string, params: any) {
      const auth = getOAuthClient(api);
      const gmail = google.gmail({ version: "v1", auth });

      const res = await gmail.users.messages.list({
        userId: "me",
        q: params.q,
        labelIds: params.labelIds,
        maxResults: params.maxResults,
        pageToken: params.pageToken,
        includeSpamTrash: params.includeSpamTrash,
      });

      return {
        content: [
          {
            type: "text",
            text: jsonText({
              resultSizeEstimate: res.data.resultSizeEstimate,
              nextPageToken: res.data.nextPageToken,
              messages: res.data.messages || [],
            }),
          },
        ],
      };
    },
  });

  // ----- Gmail: get -----
  api.registerTool({
    name: "gmail_get",
    description: "Get a Gmail message by id.",
    parameters: Type.Object({
      id: Type.String({ description: "Message id from gmail_list." }),
      format: Type.Optional(
        Type.Union(
          [
            Type.Literal("full"),
            Type.Literal("metadata"),
            Type.Literal("minimal"),
            Type.Literal("raw"),
          ],
          { description: "Gmail API message format." },
        ),
      ),
      metadataHeaders: Type.Optional(
        Type.Array(Type.String(), {
          description:
            "If format=metadata, which headers to include (e.g. From, To, Subject, Date).",
        }),
      ),
    }),
    async execute(_id: string, params: any) {
      const auth = getOAuthClient(api);
      const gmail = google.gmail({ version: "v1", auth });

      const res = await gmail.users.messages.get({
        userId: "me",
        id: params.id,
        format: params.format || "full",
        metadataHeaders: params.metadataHeaders,
      });

      return { content: [{ type: "text", text: jsonText(res.data) }] };
    },
  });

  // ----- Gmail: send (optional) -----
  api.registerTool(
    {
      name: "gmail_send",
      description: "Send an email via Gmail API (plain text).",
      parameters: Type.Object({
        to: Type.String({ description: "Recipient email address." }),
        subject: Type.String({ description: "Email subject." }),
        bodyText: Type.String({ description: "Plain-text body." }),
        cc: Type.Optional(
          Type.String({ description: "CC recipients (comma-separated)." }),
        ),
        bcc: Type.Optional(
          Type.String({ description: "BCC recipients (comma-separated)." }),
        ),
        replyTo: Type.Optional(Type.String({ description: "Reply-To address." })),
      }),
      async execute(_id: string, params: any) {
        const auth = getOAuthClient(api);
        const gmail = google.gmail({ version: "v1", auth });

        const raw = buildRawEmail(params);
        const encoded = base64UrlEncode(raw);

        const res = await gmail.users.messages.send({
          userId: "me",
          requestBody: { raw: encoded },
        });

        return { content: [{ type: "text", text: jsonText(res.data) }] };
      },
    },
    { optional: true },
  );

  // ----- Calendar: list events -----

  api.registerTool({
    name: "calendar_list_events",
    description:
      "List Google Calendar events (defaults to primary calendar) within a time window.",
    parameters: Type.Object({
      calendarId: Type.Optional(
        Type.String({ description: 'Calendar id (default: "primary").' }),
      ),
      timeMin: Type.Optional(
        Type.String({
          description:
            "RFC3339 timestamp lower bound (e.g. 2026-03-03T00:00:00+03:00).",
        }),
      ),
      timeMax: Type.Optional(
        Type.String({
          description:
            "RFC3339 timestamp upper bound (e.g. 2026-03-04T00:00:00+03:00).",
        }),
      ),
      q: Type.Optional(Type.String({ description: "Free text search." })),
      maxResults: Type.Optional(
        Type.Integer({
          description: "Max results (1-2500).",
          minimum: 1,
          maximum: 2500,
        }),
      ),
      pageToken: Type.Optional(Type.String({ description: "Pagination token." })),
      singleEvents: Type.Optional(
        Type.Boolean({ description: "Expand recurring events into instances." }),
      ),
      orderBy: Type.Optional(
        Type.Union([Type.Literal("startTime"), Type.Literal("updated")]),
      ),
    }),
    async execute(_id: string, params: any) {
      const auth = getOAuthClient(api);
      const calendar = google.calendar({ version: "v3", auth });

      const res = await calendar.events.list({
        calendarId: params.calendarId || "primary",
        timeMin: params.timeMin,
        timeMax: params.timeMax,
        q: params.q,
        maxResults: params.maxResults,
        pageToken: params.pageToken,
        singleEvents: params.singleEvents ?? true,
        orderBy: params.orderBy || "startTime",
      });

      return {
        content: [
          {
            type: "text",
            text: jsonText({
              nextPageToken: res.data.nextPageToken,
              nextSyncToken: res.data.nextSyncToken,
              items: res.data.items || [],
            }),
          },
        ],
      };
    },
  });

  // ----- Calendar: create event (optional) -----
  api.registerTool(
    {
      name: "calendar_create_event",
      description: "Create a Google Calendar event (defaults to primary calendar).",
      parameters: Type.Object({
        calendarId: Type.Optional(
          Type.String({ description: 'Calendar id (default: "primary").' }),
        ),
        summary: Type.String({ description: "Event title/summary." }),
        description: Type.Optional(Type.String({ description: "Event description." })),
        location: Type.Optional(Type.String({ description: "Event location." })),
        start: Type.String({ description: "Event start (RFC3339)." }),
        end: Type.String({ description: "Event end (RFC3339)." }),
        attendees: Type.Optional(
          Type.Array(
            Type.Object({
              email: Type.String(),
            }),
            { description: "Attendees (email addresses)." },
          ),
        ),
      }),
      async execute(_id: string, params: any) {
        const auth = getOAuthClient(api);
        const calendar = google.calendar({ version: "v3", auth });

        const res = await calendar.events.insert({
          calendarId: params.calendarId || "primary",
          requestBody: {
            summary: params.summary,
            description: params.description,
            location: params.location,
            start: { dateTime: params.start },
            end: { dateTime: params.end },
            attendees: params.attendees,
          },
        });

        return { content: [{ type: "text", text: jsonText(res.data) }] };
      },
    },
    { optional: true },
  );

  // ----- Calendar: update event (optional) -----

  api.registerTool(
    {
      name: "calendar_update_event",
      description:
        "Update (patch) a Google Calendar event by id (defaults to primary calendar).",
      parameters: Type.Object({
        calendarId: Type.Optional(
          Type.String({ description: 'Calendar id (default: "primary").' }),
        ),
        eventId: Type.String({ description: "Event id." }),
        summary: Type.Optional(Type.String({ description: "Event title/summary." })),
        description: Type.Optional(Type.String({ description: "Event description." })),
        location: Type.Optional(Type.String({ description: "Event location." })),
        start: Type.Optional(Type.String({ description: "Event start (RFC3339)." })),
        end: Type.Optional(Type.String({ description: "Event end (RFC3339)." })),
      }),
      async execute(_id: string, params: any) {
        const auth = getOAuthClient(api);
        const calendar = google.calendar({ version: "v3", auth });

        const requestBody: any = {};
        if (params.summary !== undefined) requestBody.summary = params.summary;
        if (params.description !== undefined) requestBody.description = params.description;
        if (params.location !== undefined) requestBody.location = params.location;
        if (params.start !== undefined) requestBody.start = { dateTime: params.start };
        if (params.end !== undefined) requestBody.end = { dateTime: params.end };

        const res = await calendar.events.patch({
          calendarId: params.calendarId || "primary",
          eventId: params.eventId,
          requestBody,
        });

        return { content: [{ type: "text", text: jsonText(res.data) }] };
      },
    },
    { optional: true },
  );

  logger?.info?.(
    { plugin: api.id, profile: GOOGLE_PROFILE_ID },
    "google-suite tools registered",
  );
}
