import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { createClient } from "@supabase/supabase-js";

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
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
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

async function requestBody(req: Request): Promise<Record<string, unknown>> {
  try {
    return await req.json() as Record<string, unknown>;
  } catch (_) {
    throw new HttpError(400, "invalid_json", "요청 형식을 확인해주세요.");
  }
}

async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function clientIp(req: Request): string {
  return req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    req.headers.get("cf-connecting-ip")?.trim() ||
    req.headers.get("x-real-ip")?.trim() ||
    `unknown:${crypto.randomUUID()}`;
}

function validate(body: Record<string, unknown>) {
  const email = typeof body.email === "string"
    ? body.email.trim().toLowerCase()
    : "";
  const password = typeof body.password === "string" ? body.password : "";
  const nickname = typeof body.nickname === "string" ? body.nickname.trim() : "";

  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || email.length > 254) {
    throw new HttpError(400, "invalid_email", "올바른 이메일 주소를 입력해주세요.");
  }
  if (password.length < 8 || password.length > 72) {
    throw new HttpError(400, "invalid_password", "비밀번호는 8~72자로 입력해주세요.");
  }
  if (nickname.length < 2 || nickname.length > 30) {
    throw new HttpError(400, "invalid_nickname", "닉네임은 2~30자로 입력해주세요.");
  }

  return { email, password, nickname };
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (origin && !allowedOrigins().has(origin)) {
    return json(
      { code: "origin_not_allowed", message: "허용되지 않은 요청이에요." },
      403,
      origin,
    );
  }
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }

  try {
    if (req.method !== "POST") {
      throw new HttpError(405, "method_not_allowed", "지원하지 않는 요청이에요.");
    }

    const { email, password, nickname } = validate(await requestBody(req));
    const db = database();
    const [emailHash, ipHash] = await Promise.all([
      sha256(email),
      sha256(clientIp(req)),
    ]);
    const { data: reservation, error: reservationError } = await db.rpc(
      "reserve_email_signup_attempt",
      { p_ip_hash: ipHash, p_email_hash: emailHash },
    );
    if (reservationError) throw reservationError;
    if (reservation !== "allowed") {
      throw new HttpError(
        429,
        "signup_rate_limit",
        "가입 요청이 많아요. 1시간 뒤 다시 시도해주세요.",
      );
    }

    const { error } = await db.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { nickname },
    });
    if (error) {
      const duplicate = error.code === "email_exists" ||
        error.message.toLowerCase().includes("already");
      if (duplicate) {
        throw new HttpError(
          409,
          "email_exists",
          "이미 가입된 이메일이에요. 로그인해주세요.",
        );
      }
      if (error.code === "weak_password") {
        throw new HttpError(400, "weak_password", "더 안전한 비밀번호를 입력해주세요.");
      }
      throw error;
    }

    return json({ created: true }, 201, origin);
  } catch (error) {
    if (error instanceof HttpError) {
      return json({ code: error.code, message: error.message }, error.status, origin);
    }
    console.error(
      "email-signup error",
      error instanceof Error ? error.message : "unknown error",
    );
    return json(
      { code: "internal_error", message: "가입을 처리하지 못했어요. 잠시 후 다시 시도해주세요." },
      500,
      origin,
    );
  }
});
