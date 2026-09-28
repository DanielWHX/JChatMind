import { BrowserRouter } from "react-router-dom";
import JChatMindLayout from "./components/JChatMindLayout.tsx";
import { ChatSessionsProvider } from "./contexts/ChatSessionsContext.tsx";
import GuestDemo from "./components/GuestDemo";

function App() {
  if (window.location.pathname.replace(/\/$/, "") === "/demo") return <GuestDemo />;
  return (
    <BrowserRouter>
      <ChatSessionsProvider>
        <JChatMindLayout />
      </ChatSessionsProvider>
    </BrowserRouter>
  );
}

export default App;
