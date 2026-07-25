import { createClient } from "npm:@supabase/supabase-js@2";
import { jpegDimensions } from "../functions/community-validate-upload/index.ts";

const url = requiredEnvironment("LEAFY_SMOKE_SUPABASE_URL");
const anonKey = requiredEnvironment("LEAFY_SMOKE_ANON_KEY");
const serviceRoleKey = requiredEnvironment("LEAFY_SMOKE_SERVICE_ROLE_KEY");

const admin = createClient(url, serviceRoleKey, { auth: { persistSession: false } });
const userClient = createClient(url, anonKey, { auth: { persistSession: false } });
const runID = crypto.randomUUID();
const email = `leafy-upload-smoke-${runID}@example.com`;
const password = `Leafy-${crypto.randomUUID()}-9!`;
const eduID = `upload-smoke-${runID}`;
const postID = crypto.randomUUID();
const imageID = crypto.randomUUID();

let authUserID: string | null = null;
let profileID: string | null = null;
let fullPath: string | null = null;
let thumbnailPath: string | null = null;

try {
  const { data: createdUser, error: createUserError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  assertNoError(createUserError, "create synthetic auth user");
  authUserID = createdUser.user?.id ?? null;
  assert(authUserID, "synthetic auth user id is missing");

  const { data: signIn, error: signInError } = await userClient.auth.signInWithPassword({ email, password });
  assertNoError(signInError, "sign in synthetic auth user");
  const accessToken = signIn.session?.access_token;
  assert(accessToken, "synthetic access token is missing");

  const { data: claim, error: claimError } = await admin.rpc("edge_claim_community_identity", {
    p_auth_user_id: authUserID,
    p_campus_id: "bjfu",
    p_edu_id: eduID,
    p_display_name: "上传闭环合成测试",
  });
  assertNoError(claimError, "claim synthetic community identity");
  profileID = typeof claim?.profile_id === "string" ? claim.profile_id : null;
  assert(profileID, "synthetic profile id is missing");

  const { error: profileError } = await admin
    .from("profiles")
    .update({
      nickname: "上传闭环合成测试",
      display_name: "上传闭环合成测试",
      is_profile_complete: true,
    })
    .eq("id", profileID);
  assertNoError(profileError, "complete synthetic profile");

  const { error: termsError } = await admin.from("community_terms_acceptances").insert({
    user_id: profileID,
    terms_version: "leafy-community-eula-2026-05-08",
  });
  assertNoError(termsError, "accept community terms");

  const { error: createPostError } = await userClient.rpc("create_community_post_v3", {
    p_id: postID,
    p_title: "上传闭环合成测试",
    p_body: "该记录由生产冒烟脚本创建并立即清理。",
    p_category: "测试",
    p_is_anonymous: false,
    p_image_count: 1,
  });
  assertNoError(createPostError, "create pending synthetic image post");

  const jpeg = decodeBase64(
    "/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////2wBDAf//////////////////////////////////////////////////////////////////////////////////////wAARCAABAAEDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIQAxAAAAF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABBQJ//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAwEBPwF//8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/aAAgBAgEBPwF//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQAGPwJ//8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPyF//9oADAMBAAIAAwAAABD/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAEDAQE/EH//xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oACAECAQE/EH//xAAUEAEAAAAAAAAAAAAAAAAAAAAA/9oACAEBAAE/EH//2Q==",
  );
  assert(jpegDimensions(jpeg), "embedded JPEG fixture is invalid");

  fullPath = `posts/${profileID}/${postID}/full/${imageID}.jpg`;
  thumbnailPath = `posts/${profileID}/${postID}/thumb/${imageID}.jpg`;
  for (const path of [fullPath, thumbnailPath]) {
    const { error: uploadError } = await userClient.storage
      .from("community-images")
      .upload(path, jpeg, { contentType: "image/jpeg", upsert: false });
    assertNoError(uploadError, `upload ${path.includes("/full/") ? "full" : "thumbnail"} image`);
  }

  const validationResponse = await fetch(`${url}/functions/v1/community-validate-upload`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      kind: "post",
      // Swift's default UUID encoding is uppercase while Storage paths are canonical lowercase.
      post_id: postID.toUpperCase(),
      full_path: fullPath,
      thumbnail_path: thumbnailPath,
    }),
  });
  const validationBody = await validationResponse.json().catch(() => ({}));
  console.log(JSON.stringify({
    stage: "validate-upload",
    status: validationResponse.status,
    response: validationBody,
  }));
  assert(validationResponse.ok, `upload validation returned ${validationResponse.status}`);
  const receiptID = typeof validationBody.receipt_id === "string" ? validationBody.receipt_id : null;
  assert(receiptID, "upload validation receipt is missing");

  const { error: attachError } = await userClient.rpc("attach_community_post_image_v1", {
    p_receipt_id: receiptID,
    p_image_id: imageID,
    p_sort_order: 0,
  });
  assertNoError(attachError, "attach validated image");

  const { data: post, error: postError } = await admin
    .from("posts")
    .select("status, expected_image_count, image_upload_completed_at")
    .eq("id", postID)
    .single();
  assertNoError(postError, "read published synthetic post");
  assert(post, "published synthetic post is missing");
  assert(post.status === "published", `expected published post, received ${post.status}`);
  assert(post.expected_image_count === 1, "expected image count was not preserved");
  assert(post.image_upload_completed_at, "image upload completion timestamp is missing");

  console.log(JSON.stringify({ stage: "complete", status: "published" }));
} finally {
  if (fullPath || thumbnailPath) {
    await admin.storage.from("community-images").remove(
      [fullPath, thumbnailPath].filter((path): path is string => Boolean(path)),
    );
  }
  await admin.from("posts").delete().eq("id", postID);
  if (profileID) {
    await admin.from("community_terms_acceptances").delete().eq("user_id", profileID);
    await admin.from("profile_auth_links").delete().eq("profile_id", profileID);
    await admin.from("profiles").delete().eq("id", profileID);
  }
  if (authUserID) {
    await admin.auth.admin.deleteUser(authUserID);
  }
}

function requiredEnvironment(name: string) {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`${name} is required`);
  return value;
}

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function assertNoError(error: { message?: string } | null, stage: string) {
  if (error) throw new Error(`${stage}: ${error.message ?? "unknown error"}`);
}

function decodeBase64(value: string) {
  return Uint8Array.from(atob(value), (character) => character.charCodeAt(0));
}
