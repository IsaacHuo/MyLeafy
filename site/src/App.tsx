import { lazy, Suspense } from "react";
import { BrowserRouter } from "react-router-dom";
import { PublicSite } from "./public/PublicSite";

const AdminConsole = lazy(() => import("./admin/AdminConsole"));

export default function App() {
  const staging=window.location.hostname.endsWith('.pages.dev')||window.location.hostname.includes('staging');
  const banner=staging?<div role="status" style={{padding:'8px 16px',background:'#fff3cd',color:'#513c06',textAlign:'center'}}>MyLeafy 预览环境 · 发布前请核对后端环境</div>:null;
  // React-admin owns its router and remains outside the public shell.
  if (/^\/admin(?:\/|$)/.test(window.location.pathname)) {
    return <>{banner}<Suspense fallback={<main className="grid min-h-[100dvh] place-items-center bg-paper p-6 text-text">Loading admin...</main>}><AdminConsole /></Suspense></>;
  }
  return <>{banner}<BrowserRouter><PublicSite /></BrowserRouter></>;
}

