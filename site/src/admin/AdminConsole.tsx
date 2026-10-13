import { useEffect } from "react";
import { BrowserRouter, Routes, Route, Navigate } from "react-router-dom";
import { AdminProviders, useAdmin } from "./providers/context";
import { purgeLegacyAdminSession } from "./providers/session";
import { AdminLogin } from "./components/AdminLogin";
import { AdminLayout } from "./components/AdminLayout";
import { Loading, ErrorState } from "./components/ui";
import { AdminDashboard } from "./dashboard/Dashboard";
import { ResourceList } from "./resources/ResourcePages";
import { resourceConfigs } from "./resources/config";
import { ManualPage } from "./resources/CompositePages";
import { AndroidReleasesPage } from "./resources/AndroidReleasesPage";
import {
  WorkQueuePage,
  OperationsPage,
  QualityPage,
} from "./resources/InsightsPages";
import "./admin.css";
export default function AdminConsole() {
  useEffect(() => {
    purgeLegacyAdminSession();
    document.body.classList.add("leafy-admin-active");
    return () => {
      document.body.classList.remove("leafy-admin-active");
      delete document.body.dataset.adminTheme;
    };
  }, []);
  return (
    <BrowserRouter basename="/admin">
      <AdminProviders>
        <ConsoleRoutes />
      </AdminProviders>
    </BrowserRouter>
  );
}
function ConsoleRoutes() {
  const { loading, identity, error, can } = useAdmin();
  if (loading) return <Loading />;
  if (!identity)
    return error ? (
      <ErrorState error={error} retry={() => window.location.reload()} />
    ) : (
      <AdminLogin />
    );
  return (
    <AdminLayout>
      <Routes>
        <Route index element={<AdminDashboard />} />
        <Route path="manual" element={<ManualPage />} />
        <Route
          path="android-releases/*"
          element={
            can("android-releases") ? <AndroidReleasesPage /> : <Denied />
          }
        />
        <Route
          path="work-queue"
          element={can("work-queue") ? <WorkQueuePage /> : <Denied />}
        />
        <Route
          path="operations"
          element={can("operations") ? <OperationsPage /> : <Denied />}
        />
        <Route
          path="data-quality"
          element={can("data-quality") ? <QualityPage /> : <Denied />}
        />
        {Object.entries(resourceConfigs).map(([resource, config]) => (
          <Route
            key={resource}
            path={`${resource}/*`}
            element={
              can(resource) ? (
                <ResourceList
                  key={resource}
                  resource={resource}
                  config={config}
                />
              ) : (
                <Denied />
              )
            }
          />
        ))}
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </AdminLayout>
  );
}
function Denied() {
  return <ErrorState error="当前账号无权访问此页面。" />;
}
