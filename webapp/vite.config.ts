import { defineConfig } from "vite";

export default defineConfig({
  base: process.env.PAGES_BASE ?? "./",
  build: { target: "es2022" },
});
