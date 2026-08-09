import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { createClient } from "@supabase/supabase-js";
import { createRemoteJWKSet, jwtVerify } from "jose";

const googleJwks = createRemoteJWKSet(
  new URL("https://www.googleapis.com/oauth2/v3/certs"),
);
const accessLifetimeMs = 15 * 60 * 1000;
const refreshLifetimeMs = 30 * 24 * 60 * 60 * 1000;

class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

function serviceKey(): string {
  const modernSecrets = Deno.env.get("SUPABASE_SECRET_KEYS");
  if (modernSecrets) {
    const parsed = JSON.parse(modernSecrets) as Record<string, string>;
    if (parsed.default) return parsed.default;
  }
  const legacyKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (legacyKey) return legacyKey;
  throw new HttpError(503, "server_not_configured", "서버 설정을 확인해주세요.");
}

function database() {
  const url = Deno.env.get("SUPABASE_URL");
  if (!url) {
    throw new HttpError(503, "server_not_configured", "서버 설정을 확인해주세요.");
  }
  return createClient(url, serviceKey(), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function allowedOrigins(): Set<string> {
  const configured = Deno.env.get("ALLOWED_ORIGINS") ?? "";
  return new Set([
    "http://localhost:7357",
    "http://127.0.0.1:7357",
    ...configured.split(",").map((item) => item.trim()).filter(Boolean),
  ]);
}

function corsHeaders(origin: string | null): HeadersInit {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, content-type",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Cache-Control": "no-store",
    "Content-Type": "application/json; charset=utf-8",
    "X-Content-Type-Options": "nosniff",
  };
  if (origin && allowedOrigins().has(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
    headers.Vary = "Origin";
  }
  return headers;
}

function json(
  body: Record<string, unknown>,
  status: number,
  origin: string | null,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: corsHeaders(origin),
  });
}

function randomToken(byteLength: number): string {
  const bytes = crypto.getRandomValues(new Uint8Array(byteLength));
  return btoa(String.fromCharCode(...bytes))
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

async function tokenHash(token: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(token),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function bearerToken(req: Request): string {
  const authorization = req.headers.get("Authorization") ?? "";
  const [scheme, token] = authorization.split(" ");
  if (scheme.toLowerCase() !== "bearer" || !token) {
    throw new HttpError(401, "missing_token", "로그인이 필요해요.");
  }
  return token;
}

async function requestBody(req: Request): Promise<Record<string, unknown>> {
  try {
    return await req.json() as Record<string, unknown>;
  } catch (_) {
    throw new HttpError(400, "invalid_json", "요청 형식을 확인해주세요.");
  }
}

async function verifyGoogleToken(idToken: string) {
  const audiences = (Deno.env.get("GOOGLE_CLIENT_IDS") ?? "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  if (audiences.length === 0) {
    throw new HttpError(
      503,
      "google_not_configured",
      "Google 로그인을 설정하고 있어요.",
    );
  }

  try {
    const { payload } = await jwtVerify(idToken, googleJwks, {
      audience: audiences,
      issuer: ["accounts.google.com", "https://accounts.google.com"],
    });
    if (
      !payload.sub ||
      typeof payload.email !== "string" ||
      payload.email_verified !== true
    ) {
      throw new Error("required claims are missing");
    }
    return {
      subject: payload.sub,
      email: payload.email.toLowerCase(),
      name: typeof payload.name === "string" ? payload.name : null,
      picture: typeof payload.picture === "string" ? payload.picture : null,
    };
  } catch (_) {
    throw new HttpError(401, "invalid_google_token", "Google 인증을 다시 진행해주세요.");
  }
}

async function issueSession(
  req: Request,
  user: Record<string, unknown>,
) {
  const accessToken = randomToken(32);
  const refreshToken = randomToken(64);
  const now = Date.now();
  const db = database();
  const { error } = await db.from("user_sessions").insert({
    user_id: user.id,
    access_token_hash: await tokenHash(accessToken),
    refresh_token_hash: await tokenHash(refreshToken),
    access_expires_at: new Date(now + accessLifetimeMs).toISOString(),
    refresh_expires_at: new Date(now + refreshLifetimeMs).toISOString(),
    user_agent: req.headers.get("user-agent"),
    ip: req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? null,
  });
  if (error) throw error;

  return {
    access_token: accessToken,
    refresh_token: refreshToken,
    expires_in: Math.floor(accessLifetimeMs / 1000),
    user,
  };
}

async function googleSignIn(req: Request) {
  const body = await requestBody(req);
  if (typeof body.id_token !== "string" || body.id_token.length < 100) {
    throw new HttpError(400, "missing_google_token", "Google 인증 정보가 필요해요.");
  }
  const identity = await verifyGoogleToken(body.id_token);
  const db = database();
  const selection = "id,email,role,nickname,avatar_url,status,is_first_run";
  const { data: existing, error: lookupError } = await db
    .from("users")
    .select(selection)
    .eq("provider", "google")
    .eq("provider_uid", identity.subject)
    .maybeSingle();
  if (lookupError) throw lookupError;

  let user = existing;
  if (!user) {
    const { data: emailOwner, error: emailError } = await db
      .from("users")
      .select("id,provider")
      .eq("email", identity.email)
      .maybeSingle();
    if (emailError) throw emailError;
    if (emailOwner) {
      throw new HttpError(
        409,
        "account_conflict",
        "같은 이메일로 가입된 계정이 있어요.",
      );
    }

    const { data: created, error: createError } = await db
      .from("users")
      .insert({
        email: identity.email,
        provider: "google",
        provider_uid: identity.subject,
        nickname: identity.name,
        avatar_url: identity.picture,
        role: "general",
        status: "active",
        last_login_at: new Date().toISOString(),
      })
      .select(selection)
      .single();
    if (createError) throw createError;
    user = created;
  } else {
    if (user.status !== "active") {
      throw new HttpError(403, "account_unavailable", "현재 이용할 수 없는 계정이에요.");
    }
    const { error: updateError } = await db
      .from("users")
      .update({
        last_login_at: new Date().toISOString(),
        avatar_url: user.avatar_url ?? identity.picture,
      })
      .eq("id", user.id);
    if (updateError) throw updateError;
  }

  return await issueSession(req, user as Record<string, unknown>);
}

async function refreshSession(req: Request) {
  const body = await requestBody(req);
  if (typeof body.refresh_token !== "string") {
    throw new HttpError(400, "missing_refresh_token", "세션 정보가 필요해요.");
  }
  const refreshHash = await tokenHash(body.refresh_token);
  const db = database();
  const { data: session, error } = await db
    .from("user_sessions")
    .select("id,user_id,refresh_expires_at")
    .eq("refresh_token_hash", refreshHash)
    .is("revoked_at", null)
    .gt("refresh_expires_at", new Date().toISOString())
    .maybeSingle();
  if (error) throw error;
  if (!session) {
    throw new HttpError(401, "invalid_refresh_token", "다시 로그인해주세요.");
  }

  const { data: user, error: userError } = await db
    .from("users")
    .select("status")
    .eq("id", session.user_id)
    .maybeSingle();
  if (userError) throw userError;
  if (!user || user.status !== "active") {
    await db.from("user_sessions").update({
      revoked_at: new Date().toISOString(),
    }).eq("id", session.id);
    throw new HttpError(403, "account_unavailable", "현재 이용할 수 없는 계정이에요.");
  }

  const accessToken = randomToken(32);
  const refreshToken = randomToken(64);
  const now = Date.now();
  const { data: rotated, error: rotateError } = await db
    .from("user_sessions")
    .update({
      access_token_hash: await tokenHash(accessToken),
      refresh_token_hash: await tokenHash(refreshToken),
      access_expires_at: new Date(now + accessLifetimeMs).toISOString(),
      refresh_expires_at: new Date(now + refreshLifetimeMs).toISOString(),
      last_used_at: new Date(now).toISOString(),
    })
    .eq("id", session.id)
    .eq("refresh_token_hash", refreshHash)
    .select("id")
    .maybeSingle();
  if (rotateError) throw rotateError;
  if (!rotated) {
    throw new HttpError(401, "session_already_rotated", "다시 로그인해주세요.");
  }

  return {
    access_token: accessToken,
    refresh_token: refreshToken,
    expires_in: Math.floor(accessLifetimeMs / 1000),
  };
}

async function userForAccessToken(req: Request) {
  const accessHash = await tokenHash(bearerToken(req));
  const db = database();
  const { data: session, error } = await db
    .from("user_sessions")
    .select("id,user_id,access_expires_at")
    .eq("access_token_hash", accessHash)
    .is("revoked_at", null)
    .gt("access_expires_at", new Date().toISOString())
    .maybeSingle();
  if (error) throw error;
  if (!session) {
    throw new HttpError(401, "invalid_access_token", "다시 로그인해주세요.");
  }
  const { data: user, error: userError } = await db
    .from("users")
    .select("id,email,role,nickname,avatar_url,status,is_first_run")
    .eq("id", session.user_id)
    .single();
  if (userError) throw userError;
  if (user.status !== "active") {
    await db.from("user_sessions").update({
      revoked_at: new Date().toISOString(),
    }).eq("id", session.id);
    throw new HttpError(403, "account_unavailable", "현재 이용할 수 없는 계정이에요.");
  }
  await db.from("user_sessions").update({
    last_used_at: new Date().toISOString(),
  }).eq("id", session.id);
  return user;
}

async function logout(req: Request) {
  const accessHash = await tokenHash(bearerToken(req));
  const { error } = await database()
    .from("user_sessions")
    .update({ revoked_at: new Date().toISOString() })
    .eq("access_token_hash", accessHash)
    .is("revoked_at", null);
  if (error) throw error;
  return { signed_out: true };
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (origin && !allowedOrigins().has(origin)) {
    return json({ code: "origin_not_allowed", message: "허용되지 않은 요청이에요." }, 403, origin);
  }
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }

  try {
    const pathname = new URL(req.url).pathname;
    const action = pathname.split("/").filter(Boolean).at(-1) ?? "health";
    if (req.method === "GET" && action === "custom-auth") {
      return json({ status: "ok", auth: "custom" }, 200, origin);
    }
    if (req.method === "POST" && action === "google") {
      return json(await googleSignIn(req), 200, origin);
    }
    if (req.method === "POST" && action === "refresh") {
      return json(await refreshSession(req), 200, origin);
    }
    if (req.method === "GET" && action === "me") {
      return json({ user: await userForAccessToken(req) }, 200, origin);
    }
    if (req.method === "POST" && action === "logout") {
      return json(await logout(req), 200, origin);
    }
    throw new HttpError(404, "not_found", "요청한 기능을 찾을 수 없어요.");
  } catch (error) {
    if (error instanceof HttpError) {
      return json({ code: error.code, message: error.message }, error.status, origin);
    }
    console.error(
      "custom-auth error",
      error instanceof Error ? error.message : "unknown error",
    );
    return json({ code: "internal_error", message: "잠시 후 다시 시도해주세요." }, 500, origin);
  }
});
