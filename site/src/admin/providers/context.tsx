import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import { QueryClient, useQuery } from "@tanstack/react-query";
import {
  Refine,
  useGetIdentity,
  useLogin,
  useLogout,
  useInvalidateAuthStore,
} from "@refinedev/core";
import routerProvider from "@refinedev/react-router";
import { App as AntApp, ConfigProvider, theme } from "antd";
import zhCN from "antd/es/locale/zh_CN";
import { toast, Toaster } from "sonner";
import { type AdminIdentityResponse } from "./client";
import { readCampusScope, saveCampusScope, clearIdentity } from "./session";
import { dataProvider } from "./dataProvider";
import { refineAuth, refineData, refineAccess } from "./refine";
import { resourceConfigs } from "../resources/config";

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: { retry: false, refetchOnWindowFocus: false, staleTime: 15000 },
  },
});
const Context = createContext<{
  campus: string;
  setCampus: (value: string) => void;
  themeMode: string;
  dark: boolean;
  setThemeMode: (value: string) => void;
}>({
  campus: "all",
  setCampus: () => {},
  themeMode: "system",
  dark: false,
  setThemeMode: () => {},
});
export function AdminProviders({ children }: { children: ReactNode }) {
  const [campus, setScope] = useState(
    () =>
      new URLSearchParams(window.location.search).get("campus") ??
      readCampusScope(),
  );
  const [themeMode, setMode] = useState(
    () => localStorage.getItem("leafy-admin-theme") ?? "system",
  );
  const [systemDark, setSystemDark] = useState(
    () => window.matchMedia("(prefers-color-scheme: dark)").matches,
  );
  const dark = themeMode === "dark" || (themeMode === "system" && systemDark);
  useEffect(() => {
    const media = window.matchMedia("(prefers-color-scheme: dark)");
    const change = () => setSystemDark(media.matches);
    media.addEventListener("change", change);
    return () => media.removeEventListener("change", change);
  }, []);
  useEffect(() => {
    document.body.dataset.adminTheme = dark ? "dark" : "light";
    localStorage.setItem("leafy-admin-theme", themeMode);
  }, [dark, themeMode]);
  return (
    <ConfigProvider
      locale={zhCN}
      button={{ autoInsertSpace: false }}
      theme={{
        algorithm: dark ? theme.darkAlgorithm : theme.defaultAlgorithm,
        token: {
          motion: false,
          colorPrimary: "#16835b",
          borderRadius: 8,
          fontFamily:
            'Inter, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
        },
        components: { Table: { cellPaddingBlock: 12 } },
      }}
    >
      <AntApp>
        <Refine
          authProvider={refineAuth}
          dataProvider={refineData}
          accessControlProvider={refineAccess}
          routerProvider={routerProvider}
          resources={Object.entries(resourceConfigs).map(([name, config]) => ({
            name,
            list: `/${name}`,
            show: `/${name}/:id`,
            meta: { label: config.label },
          }))}
          options={{
            disableTelemetry: true,
            reactQuery: { clientConfig: queryClient },
            syncWithLocation: false,
            mutationMode: "pessimistic",
          }}
        >
          <Context.Provider
            value={{
              campus,
              setCampus: (value) => {
                saveCampusScope(value);
                setScope(value);
                void queryClient.cancelQueries();
              },
              themeMode,
              dark,
              setThemeMode: setMode,
            }}
          >
            <SessionEvents />
            {children}
            <Toaster richColors position="bottom-right" />
          </Context.Provider>
        </Refine>
      </AntApp>
    </ConfigProvider>
  );
}
function SessionEvents() {
  const invalidate = useInvalidateAuthStore();
  useEffect(() => {
    const expire = () => {
      clearIdentity();
      queryClient.removeQueries({
        predicate: (q) => q.queryKey[0] === "admin",
      });
      void invalidate();
    };
    const warning = (e: Event) =>
      toast.warning(
        `操作已完成，审计未写入，请保留请求 ID：${(e as CustomEvent).detail?.requestID ?? "未提供"}`,
      );
    window.addEventListener("leafy-admin-session-expired", expire);
    window.addEventListener("leafy-admin-audit-warning", warning);
    return () => {
      window.removeEventListener("leafy-admin-session-expired", expire);
      window.removeEventListener("leafy-admin-audit-warning", warning);
    };
  }, [invalidate]);
  return null;
}
export function useAdmin() {
  const context = useContext(Context),
    identity = useGetIdentity<AdminIdentityResponse | null>(),
    login = useLogin<{ username: string; password: string }>(),
    logout = useLogout(),
    invalidate = useInvalidateAuthStore();
  return {
    ...context,
    identity: identity.data ?? null,
    loading: identity.isLoading,
    error: identity.error,
    login: async (username: string, password: string) => {
      const result = await login.mutateAsync({ username, password });
      if (!result.success) throw result.error ?? new Error("登录失败");
      await invalidate();
    },
    logout: async () => {
      const result = await logout.mutateAsync({});
      if (!result.success) throw result.error ?? new Error("退出失败");
      queryClient.removeQueries({
        predicate: (q) => q.queryKey[0] === "admin",
      });
      await invalidate();
    },
    can: (resource: string, action = "list") =>
      identity.data?.permissions.some(
        (p) =>
          p.resource === resource &&
          (p.actions.includes(action) || p.actions.includes("*")),
      ) ?? false,
  };
}
export function useAction<T = Record<string, any>>(
  action: string,
  params: Record<string, unknown> = {},
  enabled = true,
) {
  const { campus, identity } = useAdmin();
  return useQuery({
    queryKey: ["admin", identity?.admin.id, campus, action, params],
    queryFn: ({ signal }) =>
      dataProvider.execute<T>(
        action,
        { ...params, ...(campus !== "all" ? { campusID: campus } : {}) },
        signal,
      ),
    enabled: enabled && !!identity,
  });
}
export function reportError(error: unknown) {
  toast.error(error instanceof Error ? error.message : String(error));
}
