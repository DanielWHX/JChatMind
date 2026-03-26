
# AI Agent System – JChatMind

JChatMind is an intelligent AI Agent system built on top of the Spring AI framework, designed to support autonomous decision-making, tool invocation, and knowledge retrieval.

The system implements a Think-Execute loop, enabling it to understand complex tasks, plan execution steps, invoke external tools, and retrieve relevant information from a knowledge base using RAG (Retrieval-Augmented Generation) to complete multi-step workflows.

Unlike traditional chatbots, JChatMind is a true Agent system: it can plan, invoke tools, retrieve knowledge, and stream execution progress to the frontend in real time.。

### Demo

![image](https://file1.kamacoder.com/i/web/2026-01-09_16-30-36.jpg)

![image](https://file1.kamacoder.com/i/web/2026-01-09_16-31-19.jpg)

![image](https://file1.kamacoder.com/i/web/2026-01-09_16-31-49.jpg)

![image](https://file1.kamacoder.com/i/web/2026-01-09_16-32-08.jpg)



### Key Feature

Key Features
1. Agent Loop (Think–Execute with State Management)
Supports multi-step reasoning and execution
Maintains explicit states: THINKING, EXECUTING, DONE, ERROR
Includes step limits and error handling to prevent infinite loops

2. Tool Invocation Framework
Tools are registered and managed in a unified framework
Supports fixed and optional tools
Allows adding new tools without modifying core logic
Tool outputs are fed back into the conversation context

3. RAG Pipeline (PostgreSQL + pgvector)
Markdown parsing and chunking
Embedding generation and storage
Vector similarity search using pgvector
Indexed with ivfflat for scalability

4. Multi-Model Support
Unified ChatClient interface
Supports switching between different LLM providers
Uses a registry pattern for model management

6. SSE-based Streaming
Streams execution status to frontend in real time
Lightweight implementation for one-way communication


