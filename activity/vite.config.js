import { defineConfig, loadEnv } from "vite";

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  const apiTarget = env.VITE_ACTIVITY_API_TARGET || "http://127.0.0.1:8787";
  return {
    base: "/",
    build: {
      outDir: "../dist",
      emptyOutDir: true,
    },
    server: {
      allowedHosts: [".trycloudflare.com"],
      proxy: {
        "/api": {
          target: apiTarget,
          changeOrigin: true,
          ws: true,
          rewrite: (path) => path.replace(/^\/api/, ""),
        },
      },
    },
  };
});
