import 'jsr:@supabase/functions-js/edge-runtime.d.ts';
import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function response(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

function serviceKey(): string {
  const raw = Deno.env.get('SUPABASE_SECRET_KEYS');
  if (raw) {
    const keys = JSON.parse(raw) as Record<string, string>;
    const key = keys.default ?? Object.values(keys)[0];
    if (key) return key;
  }
  const legacy = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (legacy) return legacy;
  throw new Error('Supabase server secret is unavailable.');
}

function cleanUsername(value: unknown): string {
  return String(value ?? '').trim().toLowerCase();
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (request.method !== 'POST') {
    return response({ message: 'Method not allowed.' }, 405);
  }

  try {
    const authorization = request.headers.get('Authorization') ?? '';
    const token = authorization.replace(/^Bearer\s+/i, '').trim();
    if (!token) return response({ message: 'Authentication is required.' }, 401);

    const admin = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      serviceKey(),
      { auth: { persistSession: false, autoRefreshToken: false } },
    );
    const { data: userData, error: userError } = await admin.auth.getUser(token);
    if (userError || !userData.user) {
      return response({ message: 'Your session is no longer valid.' }, 401);
    }

    const { data: caller } = await admin
      .from('profiles')
      .select('role, is_active')
      .eq('id', userData.user.id)
      .maybeSingle();
    if (caller?.role !== 'owner' || caller?.is_active !== true) {
      return response({ message: 'Only an active Owner can manage employees.' }, 403);
    }

    const body = await request.json() as Record<string, unknown>;
    const action = String(body.action ?? '');

    if (action === 'create') {
      const fullName = String(body.full_name ?? '').trim();
      const username = cleanUsername(body.username);
      const role = String(body.role ?? 'employee');
      const password = String(body.password ?? '');

      if (fullName.length < 2 || fullName.length > 100) {
        return response({ message: 'Enter the employee full name.' }, 400);
      }
      if (!/^[a-z0-9._-]{3,32}$/.test(username)) {
        return response({ message: 'Username must be 3–32 lowercase letters, numbers, dots, dashes or underscores.' }, 400);
      }
      if (!['coordinator', 'employee'].includes(role)) {
        return response({ message: 'Select a valid employee role.' }, 400);
      }
      if (password.length < 8) {
        return response({ message: 'Temporary password must contain at least 8 characters.' }, 400);
      }

      const { data: existing } = await admin
        .from('profiles')
        .select('id')
        .ilike('username', username)
        .maybeSingle();
      if (existing) return response({ message: 'This username is already in use.' }, 409);

      const internalEmail = `${username}@auth.eway.com.pk`;
      const { data: created, error: createError } = await admin.auth.admin.createUser({
        email: internalEmail,
        password,
        email_confirm: true,
        user_metadata: { full_name: fullName, username },
      });
      if (createError || !created.user) {
        return response({ message: createError?.message ?? 'Employee account could not be created.' }, 400);
      }

      const { error: profileError } = await admin.from('profiles').upsert({
        id: created.user.id,
        full_name: fullName,
        username,
        role,
        is_active: true,
        updated_at: new Date().toISOString(),
      });
      if (profileError) {
        await admin.auth.admin.deleteUser(created.user.id);
        return response({ message: profileError.message }, 400);
      }
      return response({ success: true, employee_id: created.user.id }, 201);
    }

    const employeeId = String(body.employee_id ?? '');
    if (!employeeId || employeeId === userData.user.id) {
      return response({ message: 'Select another employee account.' }, 400);
    }

    if (action === 'set_active') {
      const isActive = body.is_active === true;
      const { error: authUpdateError } = await admin.auth.admin.updateUserById(
        employeeId,
        { ban_duration: isActive ? 'none' : '876000h' },
      );
      if (authUpdateError) {
        return response({ message: authUpdateError.message }, 400);
      }
      const { error } = await admin
        .from('profiles')
        .update({ is_active: isActive, updated_at: new Date().toISOString() })
        .eq('id', employeeId)
        .neq('role', 'owner');
      if (error) return response({ message: error.message }, 400);
      return response({ success: true });
    }

    if (action === 'reset_password') {
      const password = String(body.password ?? '');
      if (password.length < 8) {
        return response({ message: 'New password must contain at least 8 characters.' }, 400);
      }
      const { error } = await admin.auth.admin.updateUserById(employeeId, { password });
      if (error) return response({ message: error.message }, 400);
      return response({ success: true });
    }

    return response({ message: 'Unsupported employee action.' }, 400);
  } catch (error) {
    return response({ message: error instanceof Error ? error.message : 'Unexpected server error.' }, 500);
  }
});
