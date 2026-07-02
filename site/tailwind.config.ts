import type { Config } from "tailwindcss";

const config: Config = {
  content: ["./index.html", "./src/**/*.{ts,tsx}"],
  theme: {
    extend: {
      colors: {
        primary: {
          DEFAULT: "#4E8261",
          strong: "#315F45",
          ink: "#244B37",
          wash: "#EAF3EC",
          soft: "#F6FAF6"
        },
        secondary: {
          DEFAULT: "#D8CC8F",
          ink: "#6D6234",
          wash: "#F4EFCF",
          soft: "#FBF7E5"
        },
        leaf: {
          deep: "#1E4F3E",
          mid: "#4E8261",
          light: "#8DAA6E",
          paper: "#D8CC8F"
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
        "surface-high": "#F8F5EA",
        "surface-low": "#ECE5CC",
        text: "#18201A",
        paper: {
          DEFAULT: "#FCFAF1",
          muted: "#F4EFD9"
        }
      },
      boxShadow: {
        soft: "0 10px 30px rgba(24, 32, 26, 0.08)",
        lift: "0 24px 70px rgba(24, 32, 26, 0.10)",
        primary: "0 18px 46px rgba(78, 130, 97, 0.22)",
        line: "inset 0 0 0 1px rgba(23, 23, 23, 0.08)"
      },
      fontFamily: {
        sans: ["Lora", "Georgia", "\"Times New Roman\"", "serif"],
        display: ["Lora", "Georgia", "\"Times New Roman\"", "serif"],
        mono: ["SFMono-Regular", "Consolas", "\"Liberation Mono\"", "monospace"]
      }
    }
  },
  plugins: []
};

export default config;
