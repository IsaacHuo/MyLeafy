import type { AuthProvider } from "react-admin";
import { AdminApiError, loginRequest, logoutRequest, meRequest } from "./client";
import { clearIdentity, readIdentity, saveIdentity } from "./session";

export const authProvider: AuthProvider = {
  login: async ({ username, password }) => {
    const identity = await loginRequest(String(username ?? ""), String(password ?? ""));
    saveIdentity(identity);
  },
  logout: async () => {
    try {
      await logoutRequest();
      clearIdentity();
    } catch (error) {
      if (error instanceof AdminApiError && error.status === 401) {
        clearIdentity();
        return;
      }
      throw error;
    }
  },
  checkAuth: async () => {
    const identity = await meRequest();
    saveIdentity(identity);
  },
  checkError: async (error) => {
    if (error instanceof AdminApiError && error.status === 401) {
      clearIdentity();
      throw error;
    }
  },
  getIdentity: async () => {
    const snapshot = readIdentity() ?? await meRequest();
    saveIdentity(snapshot);
    return {
      ...snapshot.admin,
      id: snapshot.admin.id,
      fullName: snapshot.admin.display_name,
      avatar: undefined,
    };
  },
  getPermissions: async () => {
    const snapshot = readIdentity() ?? await meRequest();
    saveIdentity(snapshot);
    return snapshot.permissions;
  },
  canAccess: async ({ resource, action }) => {
    const snapshot = readIdentity() ?? await meRequest();
    saveIdentity(snapshot);
    return snapshot.permissions.some((permission) =>
      permission.resource === resource
      && (permission.actions.includes(action) || permission.actions.includes("*"))
    );
  },
};
