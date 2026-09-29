import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    // host: true escucha en todas las interfaces. Sin esto Vite solo atiende a
    // la propia maquina, y desde tu navegador verias un timeout.
    host: true,
    port: 3000,
    // strictPort: si el 3000 esta ocupado, falla en vez de moverse al 3001 en
    // silencio. Un puerto que cambia solo rompe CORS mas tarde, y para
    // entonces el sintoma ya no se parece a la causa.
    strictPort: true,
  },
});
