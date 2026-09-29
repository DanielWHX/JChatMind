package com.kama.jchatmind.agent;

import com.kama.jchatmind.converter.ChatMessageConverter;
import com.kama.jchatmind.model.dto.ChatMessageDTO;
import com.kama.jchatmind.model.response.CreateChatMessageResponse;
import com.kama.jchatmind.service.ChatMessageFacadeService;
import com.kama.jchatmind.service.SseService;
import java.util.*;
import org.junit.jupiter.api.Test;
import org.springframework.ai.chat.client.ChatClient;
import org.springframework.ai.chat.messages.*;
import org.springframework.ai.chat.model.*;
import org.springframework.ai.chat.prompt.Prompt;
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;

class ToolHistoryRegressionTest {
    private AssistantMessage call(String... ids) {
        return AssistantMessage.builder().content("").toolCalls(Arrays.stream(ids)
                .map(id -> new AssistantMessage.ToolCall(id, "function", "KnowledgeTool", "{}"))
                .toList()).build();
    }
    private ToolResponseMessage result(String id) {
        return ToolResponseMessage.builder().responses(List.of(
                new ToolResponseMessage.ToolResponse(id, "KnowledgeTool", "handbook evidence"))).build();
    }
    private List<Message> run(List<Message> history, int window) {
        List<Message> received = new ArrayList<>();
        ChatModel model = mock(ChatModel.class);
        when(model.call(any(Prompt.class))).thenAnswer(invocation -> {
            Prompt prompt = invocation.getArgument(0);
            received.addAll(prompt.getInstructions());
            Set<String> pending = new HashSet<>();
            for (Message message : prompt.getInstructions()) {
                if (message instanceof ToolResponseMessage tool) {
                    for (var response : tool.getResponses()) {
                        assertThat(pending.remove(response.id())).as("orphan tool response: %s", response.id()).isTrue();
                    }
                } else {
                    assertThat(pending).as("missing responses before next message").isEmpty();
                    if (message instanceof AssistantMessage assistant) {
                        assistant.getToolCalls().forEach(c -> pending.add(c.id()));
                    }
                }
            }
            assertThat(pending).isEmpty();
            return new ChatResponse(List.of(new Generation(new AssistantMessage("Answer"))));
        });
        ChatMessageFacadeService messages = mock(ChatMessageFacadeService.class);
        when(messages.createChatMessage(any(ChatMessageDTO.class))).thenReturn(
                CreateChatMessageResponse.builder().chatMessageId("answer").build());
        new JChatMind("agent", "test", "", "Be concise", ChatClient.builder(model).build(), window,
                history, List.of(), List.of(), "session", mock(SseService.class), messages,
                mock(ChatMessageConverter.class)).run();
        verify(model).call(any(Prompt.class));
        return received;
    }
    @Test void databaseTailMayBeginWithAnOrphanToolResult() {
        List<Message> received = run(List.of(result("old"), new UserMessage("Current question")), 20);
        assertThat(received).noneMatch(m -> m instanceof ToolResponseMessage);
        assertThat(received).anyMatch(m -> "Current question".equals(m.getText()));
    }
    @Test void addingSystemPromptMustNotLeaveAnOrphanAtTheWindowBoundary() {
        List<Message> history = new ArrayList<>(List.of(call("old"), result("old")));
        for (int i = 0; i < 18; i++) history.add(new UserMessage("question " + i));
        run(history, 20);
    }
    @Test void completeParallelToolExchangeKeepsBothResults() {
        List<Message> received = run(List.of(call("a", "b"), result("a"), result("b"), new UserMessage("Next")), 20);
        assertThat(received.stream().filter(m -> m instanceof ToolResponseMessage).count()).isEqualTo(2);
    }
    @Test void incompleteParallelExchangeIsNotSentToTheModel() {
        List<Message> received = run(List.of(call("a", "b"), result("a"), new UserMessage("Retry")), 20);
        assertThat(received).noneMatch(m -> m instanceof ToolResponseMessage);
    }
}
