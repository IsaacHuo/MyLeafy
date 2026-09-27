import { lazy, Suspense } from "react";
import { BrowserRouter } from "react-router-dom";
import { PublicSite } from "./public/PublicSite";

const AdminConsole = lazy(() => import("./admin/AdminConsole"));

export default function App() {
  // React-admin owns its router and remains outside the public shell.
  if (/^\/admin(?:\/|$)/.test(window.location.pathname)) {
    return <Suspense fallback={<main className="grid min-h-[100dvh] place-items-center bg-paper p-6 text-text">Loading admin...</main>}><AdminConsole /></Suspense>;
  }
  return <BrowserRouter><PublicSite /></BrowserRouter>;
}

