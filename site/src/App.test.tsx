import { cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import App from "./App";

beforeEach(() => {
  window.history.replaceState({}, "", "/");
  Object.defineProperty(window, "matchMedia", {
    configurable: true,
    value: vi.fn().mockImplementation((query: string) => ({
      matches: false,
      media: query,
      onchange: null,
      addEventListener: vi.fn(),
      removeEventListener: vi.fn(),
      addListener: vi.fn(),
      removeListener: vi.fn(),
      dispatchEvent: vi.fn()
    }))
  });
  Object.defineProperty(window, "scrollTo", { configurable: true, value: vi.fn() });
  Object.defineProperty(Element.prototype, "scrollIntoView", { configurable: true, value: vi.fn() });
  Object.defineProperty(globalThis, "IntersectionObserver", {
    configurable: true,
    value: class IntersectionObserverMock {
      readonly root = null;
      readonly rootMargin = "0px";
      readonly thresholds = [0];
      disconnect = vi.fn();
      observe = vi.fn();
      takeRecords = vi.fn(() => []);
      unobserve = vi.fn();
    }
  });
});

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
});

describe("public site shell", () => {
  it("marks the active route and restores focus after client navigation", async () => {
    render(<App />);

    const primaryNavigation = screen.getByRole("navigation", { name: "主导航" });
    const supportLink = within(primaryNavigation).getByRole("link", { name: "支持" });
    fireEvent.click(supportLink);

    await waitFor(() => expect(document.title).toBe("MyLeafy 技术支持"));
    expect(document.documentElement).toHaveAttribute("lang", "zh-CN");
    expect(within(primaryNavigation).getByRole("link", { name: "支持" })).toHaveAttribute("aria-current", "page");
    expect(screen.getByRole("heading", { level: 1 })).toHaveFocus();
  });

  it("closes the mobile navigation with Escape and restores button focus", async () => {
    render(<App />);
    const menuButton = screen.getByRole("button", { name: "打开导航菜单" });

    fireEvent.click(menuButton);
    expect(screen.getByRole("navigation", { name: "移动端导航" })).toBeInTheDocument();
    fireEvent.keyDown(document, { key: "Escape" });

    await waitFor(() => expect(screen.queryByRole("navigation", { name: "移动端导航" })).not.toBeInTheDocument());
    expect(menuButton).toHaveFocus();
  });
});

describe("share link states", () => {
  it("does not offer a copy action for an invalid timetable invite", () => {
    window.history.replaceState({}, "", "/share/timetable/ABCDE2");
    render(<App />);

    expect(screen.getByRole("alert")).toHaveTextContent("链接无效");
    expect(screen.queryByRole("button", { name: "复制邀请码" })).not.toBeInTheDocument();
  });

  it("reports clipboard success and failure without a false success state", async () => {
    const writeText = vi.fn().mockResolvedValueOnce(undefined).mockRejectedValueOnce(new Error("denied"));
    Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText } });
    window.history.replaceState({}, "", "/share/timetable/ABCDEFGHJKL2");
    render(<App />);

    fireEvent.click(screen.getByRole("button", { name: "复制邀请码" }));
    await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("邀请码已复制"));

    fireEvent.click(screen.getByRole("button", { name: "已复制" }));
    await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("无法访问剪贴板"));
  });

  it("does not route an invalid community post back to the homepage as if it were valid", () => {
    window.history.replaceState({}, "", "/share/community/post/not-a-uuid");
    render(<App />);

    expect(screen.getByRole("alert")).toHaveTextContent("无法通过此链接打开帖子");
    expect(screen.queryByRole("link", { name: "打开 MyLeafy" })).not.toBeInTheDocument();
  });
});
