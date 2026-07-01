import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        primary: {
          DEFAULT: "#4F8F67",
          strong: "#2F6B45",
          ink: "#24543A",
          wash: "#EEF7F1",
          soft: "#F6FBF7"
        },
        secondary: {
          DEFAULT: "#F5F5F3",
          ink: "#6B6B63",
          wash: "#F7F7F5",
          soft: "#FBFBFA"
        },
        neutral: {
          50: "#F9FAFB",
          100: "#F3F4F6",
          200: "#E5E7EB",
          300: "#D1D5DB",
          500: "#6B7280",
          600: "#4B5563",
          700: "#374151",
          800: "#1F2937",
          900: "#111827"
        },
        success: "#2F8F55",
        warning: "#B7791F",
        danger: "#B42318",
        info: "#4F8F67",
        surface: "#FFFFFF",
        "surface-high": "#F7F7F5",
        "surface-low": "#E8E8E3",
        text: "#171717",
        paper: {
          DEFAULT: "#FAFAF8",
          muted: "#F1F1ED"
        }
      },
      boxShadow: {
        soft: "0 10px 30px rgba(23, 23, 23, 0.08)",
        lift: "0 24px 70px rgba(23, 23, 23, 0.08)",
        primary: "0 18px 46px rgba(79, 143, 103, 0.22)",
        line: "inset 0 0 0 1px rgba(23, 23, 23, 0.08)"
      },
      fontFamily: {
        sans: ["Inter", "ui-sans-serif", "system-ui", "-apple-system", "BlinkMacSystemFont", "\"Segoe UI\"", "sans-serif"],
        display: ["Inter", "ui-sans-serif", "system-ui", "-apple-system", "BlinkMacSystemFont", "\"Segoe UI\"", "sans-serif"],
        mono: ["SFMono-Regular", "Consolas", "\"Liberation Mono\"", "monospace"]
      }
    }
  },
  plugins: []
};

export default config;
