import type {
  AuthProvider,
  DataProvider,
  AccessControlProvider,
} from "@refinedev/core";
import { authProvider } from "./authProvider";
import { dataProvider } from "./dataProvider";
import { meRequest, AdminApiError } from "./client";
import { saveIdentity, clearIdentity } from "./session";

export const refineAuth: AuthProvider = {
  login: async (params) => {
    await authProvider.login(params);
    return { success: true };
  },
  logout: async () => {
    await authProvider.logout();
    return { success: true };
  },
  check: async () => {
    try {
      await authProvider.checkAuth();
      return { authenticated: true };
    } catch (error) {
      return { authenticated: false, error: error as Error };
    }
  },
  onError: async (error) => ({
    logout: error instanceof AdminApiError && error.status === 401,
    error,
  }),
  getIdentity: async () => {
    try {
      const identity = await meRequest();
      saveIdentity(identity);
      return identity;
    } catch (error) {
      if (error instanceof AdminApiError && error.status === 401) {
        clearIdentity();
        return null;
      }
      throw error;
    }
  },
  getPermissions: () => authProvider.getPermissions(),
};
export const refineAccess: AccessControlProvider = {
  can: async ({ resource, action }) => ({
    can: await authProvider.canAccess({
      resource: resource ?? "",
        action,
    }),
  }),
};
export const refineData: DataProvider = {
  getApiUrl: () => "/api/admin",
  getList: async ({ resource, pagination, sorters, filters, meta }) => {
    const filter: Record<string, unknown> = { ...(meta?.filters ?? {}) };
    for (const item of filters ?? []) {
      if (!("field" in item) || item.operator !== "eq")
        throw new Error("不支持的筛选条件");
      filter[item.field] = item.value;
    }
    const result = await dataProvider.getList(resource, {
      pagination: {
        page: pagination?.currentPage ?? 1,
        perPage: pagination?.pageSize ?? 20,
      },
      sort: sorters?.[0]
        ? { field: sorters[0].field, order: sorters[0].order.toUpperCase() }
        : undefined,
      filter,
      signal: meta?.signal ?? meta?.queryContext?.signal,
    });
    return result as any;
  },
  getOne: async ({ resource, id }) =>
    dataProvider.getOne(resource, { id }) as any,
  create: async ({ resource, variables }) =>
    dataProvider.create(resource, {
      data: variables as Record<string, any>,
    }) as any,
  update: async ({ resource, id, variables, meta }) =>
    dataProvider.update(resource, {
      id,
      data: variables as Record<string, any>,
      previousData: meta?.previousData,
    }) as any,
  deleteOne: async ({ resource, id, meta }) =>
    dataProvider.delete(resource, {
      id,
      previousData: meta?.previousData,
    }) as any,
  updateMany: async ({ resource, ids, variables }) => {
    await dataProvider.updateMany(resource, {
      ids,
      data: variables as Record<string, any>,
    });
    return { data: ids.map((id) => ({ id })) } as any;
  },
  custom: async ({ meta, payload }) => {
    if (typeof meta?.action !== "string") throw new Error("管理操作缺少名称");
    return {
      data: await dataProvider.execute(
        meta.action,
        payload as Record<string, unknown>,
        meta.signal,
      ),
    } as any;
  },
};
