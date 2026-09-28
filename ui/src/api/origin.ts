// Development keeps the restored local API; production uses the HTTPS site origin.
export const API_ORIGIN = (import.meta.env.VITE_API_ORIGIN ?? (import.meta.env.DEV ? "http://localhost:8080" : "")).replace(/\/$/, "");
