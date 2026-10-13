import {
  createContext,
  useContext,
  useEffect,
  useState,
  type ReactNode,
} from "react";
import {
  QueryClient,
  useQuery,
  QueryClientProvider,
} from "@tanstack/react-query";
import { toast, Toaster } from "sonner";
import { authProvider } from "./authProvider";
import { meRequest, type AdminIdentityResponse, AdminApiError } from "./client";
import {
  readCampusScope,
  saveCampusScope,
  clearIdentity,
  saveIdentity,
} from "./session";
import { dataProvider } from "./dataProvider";
const Context = createContext<{
  identity: AdminIdentityResponse | null;
  loading: boolean;
  error: unknown;
  campus: string;
  setCampus: (value: string) => void;
  login: (username: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
  can: (resource: string, action?: string) => boolean;
}>({
  identity: null,
  loading: true,
  error: null,
  campus: "all",
  setCampus: () => {},
  login: async () => {},
  logout: async () => {},
  can: () => false,
});
export const queryClient = new QueryClient({
  defaultOptions: {
    queries: { retry: false, refetchOnWindowFocus: false, staleTime: 15000 },
  },
});
export function AdminProviders({ children }: { children: ReactNode }) {
  return (
    <QueryClientProvider client={queryClient}>
      <Session>
        {children}
        <Toaster richColors position="bottom-right" />
      </Session>
    </QueryClientProvider>
  );
}
function Session({ children }: { children: ReactNode }) {
  const [identity, setIdentity] = useState<AdminIdentityResponse | null>(null),
    [loading, setLoading] = useState(true),
    [error, setError] = useState<unknown>(null),
    [campus, setScope] = useState(
      () =>
        new URLSearchParams(window.location.search).get("campus") ??
        readCampusScope(),
    );
  useEffect(() => {
    let active = true;
    meRequest()
      .then((value) => {
        if (active) {
          saveIdentity(value);
          setIdentity(value);
        }
      })
      .catch((err) => {
        if (active && (!(err instanceof AdminApiError) || err.status !== 401))
          setError(err);
      })
      .finally(() => active && setLoading(false));
    return () => {
      active = false;
    };
  }, []);
  useEffect(() => {
    const expire = () => {
      clearIdentity();
      setIdentity(null);
      queryClient.clear();
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
  }, []);
  const setCampus = (value: string) => {
    saveCampusScope(value);
    setScope(value);
    void queryClient.cancelQueries({ queryKey: ["admin"] });
  };
  return (
    <Context.Provider
      value={{
        identity,
        loading,
        error,
        campus,
        setCampus,
        login: async (username, password) => {
          await authProvider.login({ username, password });
          const value = await meRequest();
          saveIdentity(value);
          setIdentity(value);
          setError(null);
        },
        logout: async () => {
          await authProvider.logout();
          setIdentity(null);
          queryClient.clear();
        },
        can: (resource, action = "list") =>
          identity?.permissions.some(
            (p) =>
              p.resource === resource &&
              (p.actions.includes(action) || p.actions.includes("*")),
          ) ?? false,
      }}
    >
      {children}
    </Context.Provider>
  );
}
export const useAdmin = () => useContext(Context);
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
