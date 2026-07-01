const siteOrigin = "https://myleafy.space";
const appIconURL = `${siteOrigin}/app-icon.png`;
const defaultPreview = {
  title: "MyLeafy | 校园课表与校园工具",
  description: "MyLeafy 是校园课表、社区和共享课表工具。",
  imageURL: appIconURL,
};

export async function onRequestGet(context) {
  const requestURL = new URL(context.request.url);
  const communityPostMatch = requestURL.pathname.match(/^\/share\/community\/post\/([0-9a-fA-F-]{36})\/?$/);
  const timetableMatch = requestURL.pathname.match(/^\/share\/timetable\/([A-Za-z2-7-]+)\/?$/);

  if (communityPostMatch) {
    const postID = communityPostMatch[1];
    const preview = await fetchPreview(context, `kind=community-post&id=${encodeURIComponent(postID)}`);
    return htmlResponse(renderSharePage({
      kind: "community-post",
      title: preview.title,
      description: preview.description,
      canonicalURL: `${siteOrigin}/share/community/post/${postID}`,
      imageURL: preview.imageURL,
      appURL: `leafy://community-post?id=${encodeURIComponent(postID)}`,
      eyebrow: "Community post",
      actionTitle: "打开 MyLeafy",
      fallbackTitle: "获取/更新 MyLeafy",
    }));
  }

  if (timetableMatch) {
    const code = normalizeInviteCode(timetableMatch[1]);
    const preview = await fetchPreview(context, `kind=timetable-invite&code=${encodeURIComponent(code)}`);
    return htmlResponse(renderSharePage({
      kind: "timetable-invite",
      title: preview.title,
      description: preview.description,
      canonicalURL: `${siteOrigin}/share/timetable/${code}`,
      imageURL: preview.imageURL,
      appURL: `leafy://timetable-invite?code=${encodeURIComponent(code)}`,
      eyebrow: "Shared timetable",
      actionTitle: "在 App 中接受",
      fallbackTitle: "获取/更新 MyLeafy",
    }));
  }

  return htmlResponse(renderSharePage({
    kind: "unknown",
    title: defaultPreview.title,
    description: defaultPreview.description,
    canonicalURL: `${siteOrigin}/`,
    imageURL: defaultPreview.imageURL,
    appURL: "leafy://timetable",
    eyebrow: "MyLeafy",
    actionTitle: "打开 MyLeafy",
    fallbackTitle: "了解 MyLeafy",
  }), 404);
}

async function fetchPreview(context, query) {
  const supabaseURL = context.env.SUPABASE_URL || context.env.VITE_SUPABASE_URL;
  if (!supabaseURL) {
    return defaultPreview;
  }

  try {
    const endpoint = `${String(supabaseURL).replace(/\/+$/, "")}/functions/v1/share-preview?${query}`;
    const response = await fetch(endpoint, {
      headers: { Accept: "application/json" },
    });

    if (!response.ok) {
      return defaultPreview;
    }

    const preview = await response.json();
    return {
      title: nonEmptyString(preview.title) || defaultPreview.title,
      description: nonEmptyString(preview.description) || defaultPreview.description,
      imageURL: nonEmptyString(preview.imageURL) || defaultPreview.imageURL,
    };
  } catch (error) {
    console.error("share page preview fetch failed", error instanceof Error ? error.message : String(error));
    return defaultPreview;
  }
}

function renderSharePage({
  kind,
  title,
  description,
  canonicalURL,
  imageURL,
  appURL,
  eyebrow,
  actionTitle,
  fallbackTitle,
}) {
  const escapedTitle = escapeHTML(title);
  const escapedDescription = escapeHTML(description);
  const escapedCanonicalURL = escapeHTML(canonicalURL);
  const escapedImageURL = escapeHTML(imageURL);
  const escapedAppURL = escapeHTML(appURL);
  const accentLabel = kind === "timetable-invite" ? "共享课表邀请" : kind === "community-post" ? "社区帖子" : "MyLeafy";

  return `<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="description" content="${escapedDescription}" />
    <meta name="theme-color" content="#eef5ef" />
    <meta property="og:title" content="${escapedTitle}" />
    <meta property="og:description" content="${escapedDescription}" />
    <meta property="og:type" content="website" />
    <meta property="og:url" content="${escapedCanonicalURL}" />
    <meta property="og:image" content="${escapedImageURL}" />
    <meta property="og:image:secure_url" content="${escapedImageURL}" />
    <meta property="og:image:type" content="image/png" />
    <meta property="og:image:width" content="1024" />
    <meta property="og:image:height" content="1024" />
    <meta name="twitter:card" content="summary" />
    <meta name="twitter:title" content="${escapedTitle}" />
    <meta name="twitter:description" content="${escapedDescription}" />
    <meta name="twitter:image" content="${escapedImageURL}" />
    <link rel="canonical" href="${escapedCanonicalURL}" />
    <title>${escapedTitle}</title>
    <style>
      :root {
        color-scheme: light;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
        color: #1d261f;
        background: #eef5ef;
      }
      body {
        margin: 0;
        min-height: 100dvh;
        background: #eef5ef;
      }
      main {
        box-sizing: border-box;
        min-height: 100dvh;
        display: grid;
        place-items: center;
        padding: 32px 18px;
      }
      article {
        width: min(100%, 720px);
        border: 1px solid rgba(20, 40, 25, 0.12);
        border-radius: 8px;
        background: rgba(255, 255, 255, 0.92);
        padding: clamp(24px, 5vw, 44px);
        box-shadow: 0 24px 70px rgba(20, 40, 25, 0.08);
      }
      img {
        width: 56px;
        height: 56px;
        border-radius: 12px;
        border: 1px solid rgba(20, 40, 25, 0.12);
      }
      p {
        color: rgba(29, 38, 31, 0.68);
        font-size: 16px;
        line-height: 1.7;
      }
      .eyebrow {
        margin-top: 22px;
        color: #2d6c43;
        font-size: 13px;
        font-weight: 700;
      }
      h1 {
        margin: 12px 0 0;
        font-size: clamp(34px, 7vw, 58px);
        line-height: 1.05;
        letter-spacing: 0;
      }
      .badge {
        display: inline-flex;
        margin-top: 20px;
        border-radius: 999px;
        background: rgba(54, 118, 74, 0.12);
        color: #245736;
        padding: 7px 12px;
        font-size: 13px;
        font-weight: 700;
      }
      .actions {
        display: flex;
        flex-wrap: wrap;
        gap: 12px;
        margin-top: 28px;
      }
      a {
        min-height: 44px;
        display: inline-flex;
        align-items: center;
        justify-content: center;
        border-radius: 8px;
        padding: 0 18px;
        text-decoration: none;
        font-size: 15px;
        font-weight: 700;
      }
      .primary {
        background: #36764a;
        color: white;
      }
      .secondary {
        border: 1px solid rgba(20, 40, 25, 0.14);
        color: #1d261f;
        background: white;
      }
    </style>
  </head>
  <body>
    <main>
      <article>
        <img src="/app-icon.png" alt="MyLeafy 应用图标" />
        <div class="eyebrow">${escapeHTML(eyebrow)}</div>
        <h1>${escapedTitle}</h1>
        <span class="badge">${escapeHTML(accentLabel)}</span>
        <p>${escapedDescription}</p>
        <div class="actions">
          <a class="primary" href="${escapedAppURL}">${escapeHTML(actionTitle)}</a>
          <a class="secondary" href="https://apps.apple.com/cn/search?term=MyLeafy%20%E5%8C%97%E4%BA%AC%E6%9E%97%E4%B8%9A%E5%A4%A7%E5%AD%A6">${escapeHTML(fallbackTitle)}</a>
        </div>
      </article>
    </main>
  </body>
</html>`;
}

function htmlResponse(body, status = 200) {
  return new Response(body, {
    status,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": status === 200 ? "public, max-age=300" : "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function normalizeInviteCode(value) {
  return String(value || "")
    .toUpperCase()
    .replace(/[^A-Z2-7]/g, "");
}

function nonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0 ? value.trim() : null;
}

function escapeHTML(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}
