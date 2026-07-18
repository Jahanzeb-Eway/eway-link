import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { withSupabase } from 'jsr:@supabase/server@^1';
import { createClient } from 'npm:@supabase/supabase-js@2';

type ServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
  token_uri?: string;
};

type PushOutboxRow = {
  id: number;
  recipient_id: string;
  event_type: string;
  title: string;
  body: string;
  data: Record<string, unknown> | null;
  status: string;
  attempt_count: number;
};

type PushDevice = {
  id: string;
  token: string;
  platform: string;
};

type WebhookPayload = {
  record?: Record<string, unknown>;
  outbox_id?: number | string;
  id?: number | string;
};

const jsonHeaders = {
  'Content-Type': 'application/json',
};

function jsonResponse(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  });
}

function getSupabaseSecretKey(): string {
  const secretKeysJson = Deno.env.get('SUPABASE_SECRET_KEYS');
  if (secretKeysJson) {
    const keys = JSON.parse(secretKeysJson) as Record<string, string>;
    const key = keys.default ?? Object.values(keys)[0];
    if (key) return key;
  }

  const legacyKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (legacyKey) return legacyKey;
  throw new Error('Supabase server secret is unavailable.');
}

function getFirebaseServiceAccount(): ServiceAccount {
  const raw = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
  if (!raw) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT is not configured.');
  }

  const account = JSON.parse(raw) as ServiceAccount;
  if (!account.project_id || !account.client_email || !account.private_key) {
    throw new Error('FIREBASE_SERVICE_ACCOUNT is incomplete.');
  }
  return account;
}

function bytesToBase64Url(bytes: Uint8Array): string {
  let binary = '';
  const chunkSize = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    const chunk = bytes.subarray(offset, offset + chunkSize);
    binary += String.fromCharCode(...chunk);
  }
  return btoa(binary)
    .replaceAll('+', '-')
    .replaceAll('/', '_')
    .replace(/=+$/g, '');
}

function textToBase64Url(value: string): string {
  return bytesToBase64Url(new TextEncoder().encode(value));
}

function pemToBytes(pem: string): Uint8Array {
  const normalized = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replaceAll(/\s/g, '');
  const binary = atob(normalized);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

async function createGoogleAccessToken(
  account: ServiceAccount,
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = textToBase64Url(
    JSON.stringify({ alg: 'RS256', typ: 'JWT' }),
  );
  const claims = textToBase64Url(
    JSON.stringify({
      iss: account.client_email,
      sub: account.client_email,
      aud: account.token_uri ?? 'https://oauth2.googleapis.com/token',
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      iat: now,
      exp: now + 3600,
    }),
  );
  const unsignedToken = `${header}.${claims}`;

  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    pemToBytes(account.private_key),
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(unsignedToken),
  );
  const assertion = `${unsignedToken}.${bytesToBase64Url(
    new Uint8Array(signature),
  )}`;

  const tokenResponse = await fetch(
    account.token_uri ?? 'https://oauth2.googleapis.com/token',
    {
      method: 'POST',
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion,
      }),
    },
  );

  const tokenBody = await tokenResponse.json() as Record<string, unknown>;
  const accessToken = tokenBody.access_token?.toString();
  if (!tokenResponse.ok || !accessToken) {
    throw new Error(
      `Google authentication failed (${tokenResponse.status}): ${JSON.stringify(tokenBody)}`,
    );
  }
  return accessToken;
}

function stringifyData(
  data: Record<string, unknown> | null,
  row: PushOutboxRow,
): Record<string, string> {
  const result: Record<string, string> = {
    event_type: row.event_type,
    title: row.title,
    body: row.body,
  };

  for (const [key, value] of Object.entries(data ?? {})) {
    if (value !== null && value !== undefined) {
      result[key] = typeof value === 'string' ? value : JSON.stringify(value);
    }
  }
  return result;
}

function isInvalidDeviceResponse(
  status: number,
  responseBody: Record<string, unknown>,
): boolean {
  if (status === 404) return true;
  const error = responseBody.error;
  if (!error || typeof error !== 'object') return false;
  const typedError = error as Record<string, unknown>;
  if (typedError.status === 'NOT_FOUND') return true;

  const details = typedError.details;
  if (!Array.isArray(details)) return false;
  return details.some((detail) => {
    if (!detail || typeof detail !== 'object') return false;
    const errorCode = (detail as Record<string, unknown>).errorCode;
    return errorCode === 'UNREGISTERED' || errorCode === 'INVALID_ARGUMENT';
  });
}

export default {
  fetch: withSupabase({ auth: ['secret'] }, async (request: Request) => {
    if (request.method !== 'POST') {
      return jsonResponse({ error: 'POST is required.' }, 405);
    }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  if (!supabaseUrl) {
    return jsonResponse({ error: 'SUPABASE_URL is unavailable.' }, 500);
  }

  const admin = createClient(supabaseUrl, getSupabaseSecretKey(), {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  let outboxId: string | undefined;
  try {
    const payload = await request.json() as WebhookPayload;
    const rawId = payload.record?.id ?? payload.outbox_id ?? payload.id;
    outboxId = rawId?.toString();
    if (!outboxId) {
      return jsonResponse({ error: 'The push outbox ID is required.' }, 400);
    }

    const { data: existing, error: readError } = await admin
      .from('push_outbox')
      .select(
        'id, recipient_id, event_type, title, body, data, status, attempt_count',
      )
      .eq('id', outboxId)
      .single();
    if (readError) throw readError;

    const current = existing as PushOutboxRow;
    if (current.status === 'sent' || current.status === 'skipped') {
      return jsonResponse({
        ok: true,
        status: current.status,
        outbox_id: current.id,
      });
    }

    const { data: claimed, error: claimError } = await admin
      .from('push_outbox')
      .update({
        status: 'processing',
        attempt_count: current.attempt_count + 1,
        processing_started_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
        last_error: null,
      })
      .eq('id', outboxId)
      .in('status', ['pending', 'failed'])
      .select(
        'id, recipient_id, event_type, title, body, data, status, attempt_count',
      )
      .maybeSingle();
    if (claimError) throw claimError;
    if (!claimed) {
      return jsonResponse({
        ok: true,
        status: 'already_processing',
        outbox_id: outboxId,
      }, 202);
    }

    const row = claimed as PushOutboxRow;
    const { data: deviceRows, error: deviceError } = await admin
      .from('push_device_tokens')
      .select('id, token, platform')
      .eq('user_id', row.recipient_id)
      .eq('app_id', 'com.eway.ewaylink')
      .eq('is_active', true);
    if (deviceError) throw deviceError;

    const devices = (deviceRows ?? []) as PushDevice[];
    if (devices.length === 0) {
      await admin
        .from('push_outbox')
        .update({
          status: 'skipped',
          delivered_device_count: 0,
          last_error: 'Recipient has no active registered device.',
          updated_at: new Date().toISOString(),
        })
        .eq('id', row.id);
      return jsonResponse({
        ok: true,
        status: 'skipped',
        outbox_id: row.id,
      });
    }

    const serviceAccount = getFirebaseServiceAccount();
    const accessToken = await createGoogleAccessToken(serviceAccount);
    const endpoint =
      `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;
    const data = stringifyData(row.data, row);
    let deliveredCount = 0;
    let invalidDeviceCount = 0;
    const errors: string[] = [];

    for (const device of devices) {
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token: device.token,
            notification: {
              title: row.title,
              body: row.body,
            },
            data,
            android: {
              priority: 'HIGH',
              notification: {
                channel_id: 'eway_push_notifications',
                sound: 'default',
              },
            },
            apns: {
              payload: {
                aps: {
                  sound: 'default',
                  'content-available': 1,
                },
              },
            },
          },
        }),
      });
      const responseBody = await response.json() as Record<string, unknown>;

      if (response.ok) {
        deliveredCount += 1;
        continue;
      }

      if (isInvalidDeviceResponse(response.status, responseBody)) {
        invalidDeviceCount += 1;
        await admin
          .from('push_device_tokens')
          .update({
            is_active: false,
            updated_at: new Date().toISOString(),
          })
          .eq('id', device.id);
      } else {
        errors.push(
          `FCM ${response.status} for ${device.platform}: ${JSON.stringify(responseBody)}`,
        );
      }
    }

    if (deliveredCount > 0) {
      await admin
        .from('push_outbox')
        .update({
          status: 'sent',
          delivered_device_count: deliveredCount,
          last_error: errors.length > 0 ? errors.join('\n').slice(0, 4000) : null,
          sent_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        })
        .eq('id', row.id);
      return jsonResponse({
        ok: true,
        status: 'sent',
        outbox_id: row.id,
        delivered_devices: deliveredCount,
        invalid_devices: invalidDeviceCount,
      });
    }

    if (errors.length === 0 && invalidDeviceCount === devices.length) {
      await admin
        .from('push_outbox')
        .update({
          status: 'skipped',
          delivered_device_count: 0,
          last_error: 'All registered device tokens were invalid.',
          updated_at: new Date().toISOString(),
        })
        .eq('id', row.id);
      return jsonResponse({
        ok: true,
        status: 'skipped',
        outbox_id: row.id,
        invalid_devices: invalidDeviceCount,
      });
    }

    throw new Error(errors.join('\n') || 'FCM did not deliver the notification.');
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (outboxId) {
      await admin
        .from('push_outbox')
        .update({
          status: 'failed',
          last_error: message.slice(0, 4000),
          updated_at: new Date().toISOString(),
        })
        .eq('id', outboxId);
    }
    return jsonResponse({
      ok: false,
      outbox_id: outboxId ?? null,
      error: message,
    }, 500);
  }
  }),
};
