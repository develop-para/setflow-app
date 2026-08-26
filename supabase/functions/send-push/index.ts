import "jsr:@supabase/functions-js/edge-runtime.d.ts";

import { createClient } from "@supabase/supabase-js";

// push_outbox를 비우고 FCM으로 보낸다.
//
// 엣지 펑션인 이유는 하나다: FCM이 외부 API고, Postgres 안에서는 OAuth2 토큰을
// 서명해 부를 방법이 없다. AGENTS.md 2절이 허용하는 바로 그 경우이며, 사용자
// 핵심 동작(댓글 쓰기·상담 답변)의 경로에는 놓지 않았다 — 트리거는 발신함에
// 줄만 넣고 곧바로 끝난다.
//
// 필요한 시크릿은 FCM_SERVICE_ACCOUNT 하나다(Firebase 콘솔 > 프로젝트 설정 >
// 서비스 계정 > 새 비공개 키 생성으로 받는 JSON 전체를 한 줄로).
// 없으면 이 함수는 아무것도 보내지 않고 503으로 그 사실을 말한다.

const BATCH = 100;
const MAX_ATTEMPTS = 5;

class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string,
    message: string,
  ) {
    super(message);
  }
}

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

interface OutboxRow {
  id: number;
  user_id: string;
  kind: string;
  title: string;
  body: string;
  data: Record<string, unknown>;
  attempts: number;
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

function serviceAccount(): ServiceAccount {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) {
    throw new HttpError(
      503,
      "fcm_not_configured",
      "FCM_SERVICE_ACCOUNT 시크릿이 없습니다.",
    );
  }
  const parsed = JSON.parse(raw) as ServiceAccount;
  if (!parsed.project_id || !parsed.client_email || !parsed.private_key) {
    throw new HttpError(
      503,
      "fcm_not_configured",
      "FCM_SERVICE_ACCOUNT가 서비스 계정 JSON이 아닙니다.",
    );
  }
  return parsed;
}

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function pemToPkcs8(pem: string): Uint8Array {
  // 시크릿에 한 줄로 넣으면 줄바꿈이 \n 문자열로 들어온다.
  const normalized = pem.replace(/\\n/g, "\n");
  const body = normalized
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(body);
  return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

/// 서비스 계정으로 서명한 JWT를 구글 토큰 엔드포인트에서 액세스 토큰으로 바꾼다.
async function accessToken(account: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claim = {
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const encoder = new TextEncoder();
  const unsigned = `${
    base64url(encoder.encode(JSON.stringify(header)))
  }.${base64url(encoder.encode(JSON.stringify(claim)))}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign(
      "RSASSA-PKCS1-v1_5",
      key,
      encoder.encode(unsigned),
    ),
  );
  const assertion = `${unsigned}.${base64url(signature)}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!response.ok) {
    throw new HttpError(
      502,
      "fcm_auth_failed",
      `구글 토큰 발급 실패 (${response.status})`,
    );
  }
  const payload = await response.json() as { access_token?: string };
  if (!payload.access_token) {
    throw new HttpError(502, "fcm_auth_failed", "액세스 토큰이 비어 있습니다.");
  }
  return payload.access_token;
}

/// FCM은 토큰 하나씩 받는다. 한 사용자의 기기가 여러 대면 각각 보낸다.
/// 404/403은 죽은 토큰이라는 뜻이라 지운다 — 안 지우면 영원히 재시도한다.
async function sendToToken(
  projectId: string,
  token: string,
  row: OutboxRow,
  bearer: string,
): Promise<{ ok: boolean; stale: boolean; error?: string }> {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        authorization: `Bearer ${bearer}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: row.title, body: row.body },
          data: Object.fromEntries(
            Object.entries({ kind: row.kind, ...row.data }).map((
              [key, value],
            ) => [key, String(value)]),
          ),
          android: { priority: "HIGH" },
          apns: {
            headers: { "apns-priority": "10" },
            payload: { aps: { sound: "default" } },
          },
        },
      }),
    },
  );
  if (response.ok) return { ok: true, stale: false };
  const text = await response.text();
  return {
    ok: false,
    stale: response.status === 404 || response.status === 403,
    error: `${response.status} ${text.slice(0, 200)}`,
  };
}

Deno.serve(async () => {
  try {
    const db = database();
    const account = serviceAccount();

    const { data: rows, error } = await db
      .from("push_outbox")
      .select("id, user_id, kind, title, body, data, attempts")
      .is("sent_at", null)
      .lt("attempts", MAX_ATTEMPTS)
      .order("created_at", { ascending: true })
      .limit(BATCH);
    if (error) throw new HttpError(500, "outbox_read_failed", error.message);
    if (!rows || rows.length === 0) {
      return Response.json({ drained: 0, sent: 0 });
    }

    const bearer = await accessToken(account);
    let sent = 0;

    for (const row of rows as OutboxRow[]) {
      const { data: tokens } = await db
        .from("device_tokens")
        .select("token")
        .eq("user_id", row.user_id);

      if (!tokens || tokens.length === 0) {
        // 받을 기기가 사라졌다. 재시도해도 달라지지 않으므로 닫는다.
        await db
          .from("push_outbox")
          .update({ sent_at: new Date().toISOString(), last_error: "no_device" })
          .eq("id", row.id);
        continue;
      }

      const failures: string[] = [];
      let delivered = false;
      for (const { token } of tokens as { token: string }[]) {
        const result = await sendToToken(
          account.project_id,
          token,
          row,
          bearer,
        );
        if (result.ok) {
          delivered = true;
        } else {
          if (result.stale) {
            await db.from("device_tokens").delete().eq("token", token);
          }
          if (result.error) failures.push(result.error);
        }
      }

      if (delivered) {
        // 기기 하나라도 받았으면 보낸 것이다. 나머지는 그 기기의 사정이다.
        await db
          .from("push_outbox")
          .update({ sent_at: new Date().toISOString() })
          .eq("id", row.id);
        sent++;
      } else {
        await db
          .from("push_outbox")
          .update({
            attempts: row.attempts + 1,
            last_error: failures.join(" | ").slice(0, 500),
          })
          .eq("id", row.id);
      }
    }

    return Response.json({ drained: rows.length, sent });
  } catch (error) {
    if (error instanceof HttpError) {
      return Response.json(
        { code: error.code, message: error.message },
        { status: error.status },
      );
    }
    return Response.json(
      { code: "unexpected", message: String(error) },
      { status: 500 },
    );
  }
});
