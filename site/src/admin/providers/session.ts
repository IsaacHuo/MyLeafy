import type { AdminIdentityResponse } from "./client";

const snapshotKey = "leafy-admin-identity";
const campusKey = "leafy-admin-campus-scope";
const legacyTokenKey = "leafy-admin-session";

export function readIdentity(): AdminIdentityResponse | null {
  purgeLegacyAdminSession();
  try {
    const value = sessionStorage.getItem(snapshotKey);
    return value ? JSON.parse(value) as AdminIdentityResponse : null;
  } catch {
    return null;
  }
}

export function saveIdentity(identity: AdminIdentityResponse) {
  purgeLegacyAdminSession();
  sessionStorage.setItem(snapshotKey, JSON.stringify({
    admin: identity.admin,
    permissions: identity.permissions,
    session: { expires_at: identity.session.expires_at },
  }));
}

export function clearIdentity() {
  sessionStorage.removeItem(snapshotKey);
  purgeLegacyAdminSession();
}

export function purgeLegacyAdminSession() {
  localStorage.removeItem(legacyTokenKey);
}

export function readCampusScope() {
  return localStorage.getItem(campusKey) || "all";
}

export function saveCampusScope(campusID: string) {
  localStorage.setItem(campusKey, campusID || "all");
  window.dispatchEvent(new CustomEvent("leafy-admin-campus-change", { detail: campusID || "all" }));
}
