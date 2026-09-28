-- Local bootstrap reconstructed from the existing MyBatis mapper contracts.
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS agent (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text,
  description text,
  system_prompt text,
  model text,
  allowed_tools jsonb,
  allowed_kbs jsonb,
  chat_options jsonb,
  created_at timestamp,
  updated_at timestamp
);

CREATE TABLE IF NOT EXISTS chat_session (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_id uuid REFERENCES agent(id) ON DELETE CASCADE,
  title text,
  metadata jsonb,
  created_at timestamp,
  updated_at timestamp
);

CREATE TABLE IF NOT EXISTS chat_message (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid REFERENCES chat_session(id) ON DELETE CASCADE,
  role text,
  content text,
  metadata jsonb,
  created_at timestamp,
  updated_at timestamp
);

CREATE TABLE IF NOT EXISTS knowledge_base (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text,
  description text,
  metadata jsonb,
  created_at timestamp,
  updated_at timestamp
);

CREATE TABLE IF NOT EXISTS document (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kb_id uuid REFERENCES knowledge_base(id) ON DELETE CASCADE,
  filename text,
  filetype text,
  size bigint,
  metadata jsonb,
  created_at timestamp,
  updated_at timestamp
);

CREATE TABLE IF NOT EXISTS chunk_bge_m3 (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kb_id uuid REFERENCES knowledge_base(id) ON DELETE CASCADE,
  doc_id uuid REFERENCES document(id) ON DELETE CASCADE,
  content text,
  metadata text,
  embedding vector,
  created_at timestamp,
  updated_at timestamp
);

CREATE INDEX IF NOT EXISTS chat_session_agent_idx ON chat_session(agent_id);
CREATE INDEX IF NOT EXISTS chat_message_session_created_idx ON chat_message(session_id, created_at);
CREATE INDEX IF NOT EXISTS document_kb_idx ON document(kb_id);
CREATE INDEX IF NOT EXISTS chunk_bge_m3_kb_idx ON chunk_bge_m3(kb_id);
CREATE INDEX IF NOT EXISTS chunk_bge_m3_doc_idx ON chunk_bge_m3(doc_id);
