package com.kama.jchatmind.demo;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.kama.jchatmind.agent.JChatMind;
import com.kama.jchatmind.agent.JChatMindFactory;
import com.kama.jchatmind.agent.tools.KnowledgeTools;
import com.kama.jchatmind.model.dto.ChatMessageDTO;
import com.kama.jchatmind.model.request.CreateChatMessageRequest;
import com.kama.jchatmind.model.response.CreateChatSessionResponse;
import com.kama.jchatmind.model.response.GetChatMessagesResponse;
import com.kama.jchatmind.model.vo.ChatMessageVO;
import com.kama.jchatmind.service.ChatMessageFacadeService;
import com.kama.jchatmind.service.ChatSessionFacadeService;
import com.kama.jchatmind.service.RagService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Set;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;

import static org.assertj.core.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

/** Public guest HTTP contract; all model execution is replaced with an inert runtime. */
class GuestDemoHttpTest {
    private static final String ADMIN = "admin-test-secret-longer-than-thirty-two-characters";
    private final ObjectMapper json = new ObjectMapper();
    private ChatSessionFacadeService sessions;
    private ChatMessageFacadeService messages;
    private JChatMindFactory factory;
    private JChatMind runtime;
    private GuestDemoService demo;
    private MockMvc http;

    @BeforeEach
    void setup() {
        sessions = mock(ChatSessionFacadeService.class);
        messages = mock(ChatMessageFacadeService.class);
        factory = mock(JChatMindFactory.class);
        runtime = mock(JChatMind.class);
        AtomicInteger ids = new AtomicInteger();
        when(sessions.createChatSession(any())).thenAnswer(invocation -> CreateChatSessionResponse.builder()
                .chatSessionId("private-db-session-" + ids.incrementAndGet()).build());
        when(messages.getChatMessagesBySessionId(anyString())).thenAnswer(invocation ->
                GetChatMessagesResponse.builder().chatMessages(new ChatMessageVO[]{
                        ChatMessageVO.builder().id("message-1").role(ChatMessageDTO.RoleType.ASSISTANT)
                                .content("Visible answer for " + invocation.getArgument(0)).build(),
                        ChatMessageVO.builder().id("system-1").role(ChatMessageDTO.RoleType.SYSTEM)
                                .content("PRIVATE SYSTEM PROMPT").build(),
                        ChatMessageVO.builder().id("tool-1").role(ChatMessageDTO.RoleType.TOOL)
                                .content("PRIVATE RAW TOOL RESULT").build()
                }).build());
        when(factory.createGuest(anyString(), anyString(), anyString(), any())).thenReturn(runtime);
        DemoSettings settings = new DemoSettings(ADMIN, "signing-test-secret-different-and-longer-than-thirty-two", "orbit-agent", "orbit-kb");
        demo = new GuestDemoService(settings, sessions, messages, factory);
        http = MockMvcBuilders.standaloneSetup(new GuestDemoController(demo), new AdminProbe())
                .addFilters(new CloudApiAccessFilter(settings)).build();
    }

    @AfterEach
    void close() { demo.close(); }

    private String create() throws Exception {
        String response = http.perform(post("/api/demo/sessions"))
                .andExpect(status().isOk()).andExpect(jsonPath("maxTurns").value(8))
                .andReturn().getResponse().getContentAsString();
        assertThat(response).doesNotContain("private-db-session", "orbit-agent", "orbit-kb");
        return json.readTree(response).get("sessionToken").asText();
    }

    private JsonNode view(String token) throws Exception {
        return json.readTree(http.perform(get("/api/demo/session").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
    }

    private void awaitIdle(String token) throws Exception {
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(3);
        while (view(token).get("status").asText().equals("running") && System.nanoTime() < deadline) Thread.sleep(5);
        assertThat(view(token).get("status").asText()).isEqualTo("idle");
    }

    @Test
    void isolatesVisitorsAndOmitsPrivateMessages() throws Exception {
        String first = create();
        String second = create();
        assertThat(first).isNotEqualTo(second);
        assertThat(view(first).toString()).contains("private-db-session-1").doesNotContain("private-db-session-2", "PRIVATE");
        assertThat(view(second).toString()).contains("private-db-session-2").doesNotContain("private-db-session-1", "PRIVATE");
        http.perform(get("/api/demo/session")).andExpect(status().isUnauthorized());
        http.perform(get("/api/demo/session").header("Authorization", "Bearer " + first.substring(0, 5) + "tampered"))
                .andExpect(status().isUnauthorized());
        http.perform(get("/api/demo/session").header("Authorization", "Bearer private-db-session-1"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void runsTheFixedAgentWithServerAssignedUserIdentity() throws Exception {
        String token = create();
        http.perform(post("/api/demo/messages").header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"message\":\"What is Team pricing?\"}"))
                .andExpect(status().isAccepted()).andExpect(jsonPath("status").value("running"));
        awaitIdle(token);
        ArgumentCaptor<CreateChatMessageRequest> captured = ArgumentCaptor.forClass(CreateChatMessageRequest.class);
        verify(messages).agentCreateChatMessage(captured.capture());
        assertThat(captured.getValue().getRole()).isEqualTo(ChatMessageDTO.RoleType.USER);
        assertThat(captured.getValue().getAgentId()).isEqualTo("orbit-agent");
        assertThat(captured.getValue().getSessionId()).isEqualTo("private-db-session-1");
        verify(factory).createGuest(eq("orbit-agent"), eq("private-db-session-1"), eq("orbit-kb"), any());
        assertThat(view(token).get("remainingTurns").asInt()).isEqualTo(7);
    }

    @Test
    void exposesOnlyPairedGuestEvidence() throws Exception {
        String token = create();
        when(messages.getChatMessagesBySessionId(anyString())).thenReturn(GetChatMessagesResponse.builder()
                .chatMessages(new ChatMessageVO[]{
                    ChatMessageVO.builder().id("call").role(ChatMessageDTO.RoleType.ASSISTANT)
                        .metadata(ChatMessageDTO.MetaData.builder().toolCalls(java.util.List.of(
                            new org.springframework.ai.chat.messages.AssistantMessage.ToolCall("search-1", "function", "KnowledgeTool", "PRIVATE ARGUMENTS"))).build()).build(),
                    ChatMessageVO.builder().id("evidence").role(ChatMessageDTO.RoleType.TOOL)
                        .metadata(ChatMessageDTO.MetaData.builder().toolResponse(
                            new org.springframework.ai.chat.messages.ToolResponseMessage.ToolResponse("search-1", "KnowledgeTool", "Team costs USD 18 per user.")).build()).build(),
                    ChatMessageVO.builder().id("unpaired").role(ChatMessageDTO.RoleType.TOOL)
                        .metadata(ChatMessageDTO.MetaData.builder().toolResponse(
                            new org.springframework.ai.chat.messages.ToolResponseMessage.ToolResponse("other", "KnowledgeTool", "PRIVATE RESULT")).build()).build()
                }).build());
        String result = view(token).toString();
        assertThat(result).contains("Team costs USD 18 per user.", "tool").doesNotContain("PRIVATE", "search-1");
    }

    @Test
    void enforcesLengthAndTurnLimits() throws Exception {
        String token = create();
        http.perform(post("/api/demo/messages").header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(java.util.Map.of("message", "x".repeat(1501)))))
                .andExpect(status().isBadRequest());
        verifyNoInteractions(factory);
        for (int i = 0; i < 8; i++) {
            http.perform(post("/api/demo/messages").header("Authorization", "Bearer " + token)
                            .contentType(MediaType.APPLICATION_JSON).content("{\"message\":\"Pricing?\"}"))
                    .andExpect(status().isAccepted());
            awaitIdle(token);
        }
        http.perform(post("/api/demo/messages").header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"message\":\"One more?\"}"))
                .andExpect(status().isTooManyRequests());
        verify(runtime, times(8)).run();
    }

    @Test
    void rejectsParallelTurnsAndLimitsOverallConcurrency() throws Exception {
        CountDownLatch hold = new CountDownLatch(1);
        doAnswer(invocation -> { hold.await(5, TimeUnit.SECONDS); return null; }).when(runtime).run();
        String first = create(); String second = create(); String third = create();
        try {
            http.perform(post("/api/demo/messages").header("Authorization", "Bearer " + first)
                            .contentType(MediaType.APPLICATION_JSON).content("{\"message\":\"Pricing?\"}"))
                    .andExpect(status().isAccepted());
            http.perform(post("/api/demo/messages").header("Authorization", "Bearer " + first)
                            .contentType(MediaType.APPLICATION_JSON).content("{\"message\":\"Again?\"}"))
                    .andExpect(status().isConflict());
            http.perform(post("/api/demo/messages").header("Authorization", "Bearer " + second)
                            .contentType(MediaType.APPLICATION_JSON).content("{\"message\":\"Pricing?\"}"))
                    .andExpect(status().isAccepted());
            http.perform(post("/api/demo/messages").header("Authorization", "Bearer " + third)
                            .contentType(MediaType.APPLICATION_JSON).content("{\"message\":\"Pricing?\"}"))
                    .andExpect(status().isTooManyRequests());
        } finally { hold.countDown(); }
    }

    @Test
    void protectsAllOriginalAdminAndSseEndpoints() throws Exception {
        for (String path : List.of("/api/agents", "/api/chat-sessions", "/api/knowledge-bases", "/sse/connect/example")) {
            http.perform(get(path)).andExpect(status().isUnauthorized());
            http.perform(get(path).header("Authorization", "Bearer " + create())).andExpect(status().isUnauthorized());
        }
        http.perform(get("/api/agents").header("X-JChatMind-Admin", ADMIN)).andExpect(status().isOk());
        http.perform(get("/api/agents").header("X-JChatMind-Admin", "wrong")).andExpect(status().isUnauthorized());
    }

    @Test
    void returnsSafeFailureAndDisallowsBrokenConversationReuse() throws Exception {
        doThrow(new RuntimeException("SECRET PROVIDER TOKEN and SQL trace")).when(runtime).run();
        String token = create();
        http.perform(post("/api/demo/messages").header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"message\":\"Pricing?\"}"))
                .andExpect(status().isAccepted());
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(3);
        while (view(token).get("status").asText().equals("running") && System.nanoTime() < deadline) Thread.sleep(5);
        assertThat(view(token).get("status").asText()).isEqualTo("failed");
        assertThat(view(token).get("error").asText()).contains("could not complete").doesNotContain("SECRET", "SQL");
    }

    @Test
    void knowledgeToolCannotRetrieveUnconfiguredKnowledge() {
        RagService rag = mock(RagService.class);
        when(rag.similaritySearch("orbit-kb", "pricing")).thenReturn(List.of("Team is $18"));
        KnowledgeTools scoped = new KnowledgeTools(rag).scopedTo(Set.of("orbit-kb"));
        assertThat(scoped.knowledgeQuery("other-private-kb", "pricing")).contains("not available");
        verifyNoInteractions(rag);
        assertThat(scoped.knowledgeQuery("orbit-kb", "pricing")).isEqualTo("Team is $18");
        verify(rag).similaritySearch("orbit-kb", "pricing");
    }

    @RestController
    static class AdminProbe {
        @GetMapping("/api/agents") public String agents() { return "admin"; }
    }
}
