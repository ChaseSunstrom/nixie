import { createRoot } from "react-dom/client";
import { StoreProvider } from "./lib/store";
import { App } from "./App";
import "./tokens/base.css";

createRoot(document.getElementById("root")!).render(
  <StoreProvider>
    <App />
  </StoreProvider>,
);
