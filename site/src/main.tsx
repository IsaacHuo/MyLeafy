import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import "./styles.css";

const preloadRetryKey = "leafy-vite-preload-retry-at";

window.addEventListener("vite:preloadError", (event) => {
  event.preventDefault();
  const lastRetryAt = Number(sessionStorage.getItem(preloadRetryKey) ?? 0);
  if (Date.now() - lastRetryAt < 60_000) {
    console.error("A site update could not finish loading after retry.");
    return;
  }
  sessionStorage.setItem(preloadRetryKey, String(Date.now()));
  window.location.reload();
});

ReactDOM.createRoot(document.getElementById("root") as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
