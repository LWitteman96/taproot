// delete-account — irreversible, in-app account deletion.
//
// WHY THIS EXISTS: App Store Review Guideline 5.1.1(v) requires that an app
// offering account creation also offers in-app account deletion, and
// deactivation does not count. It is the single most common cause of a first
// review rejection, which is why it is written now rather than at submission.
//
// WHY IT IS SERVER-SIDE: deleting a row in auth.users needs the service role
// key, which cannot ship in the app, and RLS gives no path to auth.users at
// all. Everything the user owns in public.* hangs off auth.users via ON DELETE
// CASCADE, so the auth deletion is the whole deletion.
//
// ORDER OF OPERATIONS — this is the part worth keeping intact:
//
//   1. Resolve the caller from their JWT. NEVER from the request body. A user
//      id in a body is an id the caller chose; a user id from a verified JWT is
//      the caller. This function deletes accounts, so that distinction is the
//      entire security model.
//   2. Revoke the third-party grant (Apple), best-effort. Failure here is
//      logged and ignored: a stale grant is a nuisance, a blocked deletion is a
//      review rejection.
//   3. Purge storage objects, best-effort but BEFORE the auth delete.
//   4. Delete the auth user, which cascades every public.* row.
//
// Purge-then-delete rather than delete-then-purge, because the failure modes
// are not symmetric. If a purge fails, the user is still signed in and can
// retry. If the auth delete succeeds first and the purge then fails, the files
// are orphaned forever with nobody left who can retry.

import { createClient } from 'npm:@supabase/supabase-js@2';

import { corsHeaders, jsonResponse } from '../_shared/cors.ts';

Deno.serve(async (request: Request): Promise<Response> => {
  // Every path out of here returns a Response with CORS headers on it. An
  // exception escaping into Deno.serve produces a bare 500 the browser then
  // reports as a CORS failure, which is the least debuggable way for the one
  // screen the App Store checks to break.
  try {
    return await deleteAccount(request);
  } catch (error) {
    console.error('delete-account: unhandled', error);
    return jsonResponse({ error: 'Account deletion failed' }, 500);
  }
});

async function deleteAccount(request: Request): Promise<Response> {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (request.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  const authorization = request.headers.get('Authorization');
  if (!authorization?.startsWith('Bearer ')) {
    return jsonResponse({ error: 'Missing bearer token' }, 401);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    console.error('delete-account: service role environment is not configured');
    return jsonResponse({ error: 'Server misconfigured' }, 500);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // ── 1. The caller, from their JWT ─────────────────────────────────────────
  // A transient failure reaching the auth server throws rather than returning
  // an error, and it is not the caller's session that is at fault, so the two
  // cases get different answers: 401 for a token that was rejected, 503 for a
  // token that could not be checked.
  const jwt = authorization.slice('Bearer '.length);
  let userId: string;
  try {
    const { data: caller, error: callerError } = await admin.auth.getUser(jwt);
    if (callerError || !caller?.user) {
      return jsonResponse({ error: 'Invalid session' }, 401);
    }
    userId = caller.user.id;
  } catch (error) {
    console.error('delete-account: could not verify the session', error);
    return jsonResponse({ error: 'Could not verify the session' }, 503);
  }

  // ── 2. Third-party grant, best-effort ─────────────────────────────────────
  // Best-effort is a promise this try/catch has to keep: a stale grant is a
  // nuisance, a blocked deletion is a review rejection. The revoke below does
  // nothing yet, but it is a network call the moment it is implemented.
  try {
    await revokeAppleGrant(userId);
  } catch (error) {
    console.error('delete-account: Apple revoke failed, continuing', error);
  }

  // ── 3. Storage purge ──────────────────────────────────────────────────────
  // Taproot has no buckets: plant art ships in the app bundle, and storage is
  // switched off in config.toml. The step keeps its slot here rather than being
  // deleted, because the moment a bucket exists it belongs in exactly this
  // position — after the grant revoke, before the auth delete.
  //
  //   const { data: objects } = await admin.storage.from('<bucket>')
  //     .list(userId, { limit: 1000 });
  //   if (objects?.length) {
  //     await admin.storage.from('<bucket>')
  //       .remove(objects.map((object) => `${userId}/${object.name}`));
  //   }

  // ── 4. The auth user, which cascades everything else ──────────────────────
  const { error: deleteError } = await admin.auth.admin.deleteUser(userId);
  if (deleteError) {
    console.error('delete-account: auth delete failed', deleteError.message);
    return jsonResponse({ error: 'Account deletion failed' }, 500);
  }

  console.info(`delete-account: deleted ${userId}`);
  return jsonResponse({ success: true }, 200);
}

/// Revokes the Sign in with Apple grant, best-effort.
///
/// Apple's /auth/revoke needs three things: the client id, a client secret
/// signed with the .p8 key, and a token Apple issued for *this* user. Taproot
/// stores none of them yet — Apple sign-in is disabled in config.toml and
/// nothing captures the refresh token at sign-in — so this returns early and
/// says so in the log rather than pretending to have revoked anything.
///
/// Capturing that token is the auth branch's job. When it lands, this becomes a
/// POST to https://appleid.apple.com/auth/revoke with
/// {client_id, client_secret, token, token_type_hint}. It stays best-effort:
/// nothing it can do may block step 4.
async function revokeAppleGrant(userId: string): Promise<void> {
  const clientId = Deno.env.get('SUPABASE_AUTH_EXTERNAL_APPLE_CLIENT_ID');
  const clientSecret = Deno.env.get('SUPABASE_AUTH_EXTERNAL_APPLE_SECRET');
  if (!clientId || !clientSecret) {
    console.info(
      `delete-account: no Apple credentials configured, skipping revoke for ${userId}`,
    );
    return;
  }

  console.warn(
    `delete-account: Apple credentials are configured but no Apple token is ` +
      `stored for ${userId}; the grant was not revoked`,
  );
  return await Promise.resolve();
}
