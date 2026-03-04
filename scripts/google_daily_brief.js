#!/usr/bin/env node
/**
 * Direct Gmail + Google Calendar daily brief for Railway.
 * Uses OAuth refresh token + client credentials from env.
 * Required env:
 *  - GOOGLE_CLIENT_ID
 *  - GOOGLE_CLIENT_SECRET
 *  - GOOGLE_REFRESH_TOKEN
 */

const { GOOGLE_CLIENT_ID, GOOGLE_CLIENT_SECRET, GOOGLE_REFRESH_TOKEN } = process.env;

function req(name, val) {
  if (!val) {
    console.log('AUTH_NEEDED');
    process.exit(2);
  }
}

req('GOOGLE_CLIENT_ID', GOOGLE_CLIENT_ID);
req('GOOGLE_CLIENT_SECRET', GOOGLE_CLIENT_SECRET);
req('GOOGLE_REFRESH_TOKEN', GOOGLE_REFRESH_TOKEN);

async function getAccessToken() {
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: GOOGLE_CLIENT_ID,
      client_secret: GOOGLE_CLIENT_SECRET,
      refresh_token: GOOGLE_REFRESH_TOKEN,
      grant_type: 'refresh_token',
    }),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`Token refresh failed: ${res.status}`);
  return json.access_token;
}

async function gmailListUnread(accessToken) {
  const url = new URL('https://gmail.googleapis.com/gmail/v1/users/me/messages');
  url.searchParams.set('maxResults', '10');
  url.searchParams.set('q', 'in:inbox is:unread newer_than:7d');
  const res = await fetch(url, { headers: { authorization: `Bearer ${accessToken}` } });
  const json = await res.json();
  if (!res.ok) throw new Error('Gmail list failed');
  return (json.messages || []).map(m => m.id);
}

async function gmailGetMeta(accessToken, id) {
  const url = `https://gmail.googleapis.com/gmail/v1/users/me/messages/${encodeURIComponent(id)}?format=metadata&metadataHeaders=From&metadataHeaders=Subject`;
  const res = await fetch(url, { headers: { authorization: `Bearer ${accessToken}` } });
  const json = await res.json();
  if (!res.ok) throw new Error('Gmail get failed');
  const headers = json.payload?.headers || [];
  const get = (n) => (headers.find(h => (h.name || '').toLowerCase() === n.toLowerCase())?.value || '');
  return { from: get('From'), subject: get('Subject') };
}

async function calendarNext24h(accessToken) {
  const now = new Date();
  const plus = new Date(now.getTime() + 24*60*60*1000);
  const url = new URL('https://www.googleapis.com/calendar/v3/calendars/primary/events');
  url.searchParams.set('timeMin', now.toISOString());
  url.searchParams.set('timeMax', plus.toISOString());
  url.searchParams.set('singleEvents', 'true');
  url.searchParams.set('orderBy', 'startTime');
  const res = await fetch(url, { headers: { authorization: `Bearer ${accessToken}` } });
  const json = await res.json();
  if (!res.ok) throw new Error('Calendar list failed');
  return (json.items || []).map(ev => ({
    summary: ev.summary || '(no title)',
    start: ev.start?.dateTime || ev.start?.date,
  }));
}

(async () => {
  try {
    const accessToken = await getAccessToken();
    const ids = await gmailListUnread(accessToken);
    const metas = [];
    for (const id of ids.slice(0, 6)) metas.push(await gmailGetMeta(accessToken, id));
    const events = await calendarNext24h(accessToken);

    console.log('DAILY BRIEF — Gmail + Calendar (draft-first)');
    console.log('');
    console.log('INBOX (unread)');
    if (!metas.length) console.log('- No unread messages found.');
    metas.forEach(m => console.log(`- ${m.subject || '(no subject)'} — ${m.from || '(unknown)'}`));
    console.log('');
    console.log('CALENDAR (next 24h)');
    if (!events.length) console.log('- No events in next 24h.');
    events.slice(0, 10).forEach(e => console.log(`- ${e.start} — ${e.summary}`));
    console.log('');
    console.log('DRAFT REPLIES (not sent)');
    console.log('- Tell me which subject to reply to + key points; I’ll draft for approval.');
  } catch (e) {
    console.log('AUTH_NEEDED');
  }
})();
