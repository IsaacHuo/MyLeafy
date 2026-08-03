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

    const primaryNavigation = screen.getByRole("navigation", { name: "Primary navigation" });
    const supportLink = within(primaryNavigation).getByRole("link", { name: "Support" });
    fireEvent.click(supportLink);

    await waitFor(() => expect(document.title).toBe("MyLeafy Support"));
    expect(within(primaryNavigation).getByRole("link", { name: "Support" })).toHaveAttribute("aria-current", "page");
    expect(screen.getByRole("heading", { level: 1 })).toHaveFocus();
  });

  it("closes the mobile navigation with Escape and restores button focus", async () => {
    render(<App />);
    const menuButton = screen.getByRole("button", { name: "Open navigation menu" });

    fireEvent.click(menuButton);
    expect(screen.getByRole("navigation", { name: "Mobile navigation" })).toBeInTheDocument();
    fireEvent.keyDown(document, { key: "Escape" });

    await waitFor(() => expect(screen.queryByRole("navigation", { name: "Mobile navigation" })).not.toBeInTheDocument());
    expect(menuButton).toHaveFocus();
  });
});

describe("share link states", () => {
  it("does not offer a copy action for an invalid timetable invite", () => {
    window.history.replaceState({}, "", "/share/timetable/ABCDE2");
    render(<App />);

    expect(screen.getByRole("alert")).toHaveTextContent("Invalid link");
    expect(screen.queryByRole("button", { name: /copy invite code/i })).not.toBeInTheDocument();
  });

  it("reports clipboard success and failure without a false success state", async () => {
    const writeText = vi.fn().mockResolvedValueOnce(undefined).mockRejectedValueOnce(new Error("denied"));
    Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText } });
    window.history.replaceState({}, "", "/share/timetable/ABCDEFGHJKL2");
    render(<App />);

    fireEvent.click(screen.getByRole("button", { name: "Copy invite code" }));
    await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Invite code copied"));

    fireEvent.click(screen.getByRole("button", { name: "Copied" }));
    await waitFor(() => expect(screen.getByRole("status")).toHaveTextContent("Clipboard access is unavailable"));
  });

  it("does not route an invalid community post back to the homepage as if it were valid", () => {
    window.history.replaceState({}, "", "/share/community/post/not-a-uuid");
    render(<App />);

    expect(screen.getByRole("alert")).toHaveTextContent("cannot be opened");
    expect(screen.queryByRole("link", { name: "Open MyLeafy" })).not.toBeInTheDocument();
  });
});
