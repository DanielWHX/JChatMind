# JChatMind demo verification code
This is synthetic local demo data, not production information.
The JChatMind demo verification code is BLUE-ORCHID-482.

# JChatMind technical stack
JChatMind uses Java, Spring Boot, Spring AI, MyBatis, React, TypeScript, PostgreSQL and pgvector. Markdown files are split into sections and embedded locally with Ollama bge-m3.

# JChatMind agent workflow
A user chooses an Agent and starts a conversation. The Agent reasons, calls configured tools when needed, stores messages in PostgreSQL, and sends completed messages to the interface over SSE. The date tool reads the local date. City and weather tools are hard-coded examples.
