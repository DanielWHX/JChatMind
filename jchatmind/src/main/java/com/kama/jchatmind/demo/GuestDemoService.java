package com.kama.jchatmind.demo;

import com.kama.jchatmind.agent.JChatMindFactory;
import com.kama.jchatmind.message.SseMessage;
import com.kama.jchatmind.model.dto.ChatMessageDTO;
import com.kama.jchatmind.model.request.CreateChatMessageRequest;
import com.kama.jchatmind.model.request.CreateChatSessionRequest;
import com.kama.jchatmind.model.vo.ChatMessageVO;
import com.kama.jchatmind.service.ChatMessageFacadeService;
import com.kama.jchatmind.service.ChatSessionFacadeService;
import com.kama.jchatmind.service.SseService;
import jakarta.annotation.PreDestroy;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Service;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.time.Instant;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.*;
import java.util.concurrent.*;

@Service
@Profile("cloud")
public class GuestDemoService {
    private static final Logger log = LoggerFactory.getLogger(GuestDemoService.class);
    public static final int MAX_TURNS = 8;
    public static final int MAX_MESSAGE_LENGTH = 1500;
    private static final int DAILY_TURN_LIMIT = 100;
    private static final int DAILY_SESSION_LIMIT = 100;
    private static final long SESSION_SECONDS = 3600;
    private final DemoSettings settings;
    private final ChatSessionFacadeService sessions;
    private final ChatMessageFacadeService messages;
    private final JChatMindFactory factory;
    private final Map<String, GuestSession> guests = new HashMap<>();
    private final Semaphore capacity = new Semaphore(2);
    private final ExecutorService executor = Executors.newFixedThreadPool(2, runnable -> {
        Thread thread = new Thread(runnable, "orbitdesk-guest");
        thread.setDaemon(true);
        return thread;
    });
    private LocalDate budgetDate = LocalDate.now(ZoneOffset.UTC);
    private int dailyTurns;
    private int dailySessions;

    private static final SseService NO_BROWSER_STREAM = new SseService() {
        public SseEmitter connect(String id) { throw new UnsupportedOperationException(); }
        // The original runtime persists every message; guests retrieve them via authenticated polling.
        public void send(String id, SseMessage message) { }
    };

    public GuestDemoService(DemoSettings settings, ChatSessionFacadeService sessions,
                            ChatMessageFacadeService messages, JChatMindFactory factory) {
        this.settings = settings;
        this.sessions = sessions;
        this.messages = messages;
        this.factory = factory;
    }

    public record SessionCreated(String sessionToken, Instant expiresAt, int maxTurns) { }
    public record DemoMessage(String id, String role, String content, List<String> tools) { }
    public record SessionView(String status, List<DemoMessage> messages, int remainingTurns, String error) { }

    public static class DemoException extends RuntimeException {
        public final int status;
        public DemoException(int status, String message) { super(message); this.status = status; }
    }

    private static class GuestSession {
        final String id;
        final Instant expiresAt = Instant.now().plusSeconds(SESSION_SECONDS);
        int turns;
        String status = "idle";
        String error;
        GuestSession(String id) { this.id = id; }
    }

    public synchronized SessionCreated createSession() {
        if (settings.agentId().isBlank() || settings.kbId().isBlank()) {
            throw new DemoException(503, "The live demo is being prepared. Please try again later.");
        }
        resetBudget();
        guests.entrySet().removeIf(entry -> entry.getValue().expiresAt.isBefore(Instant.now())
                && !entry.getValue().status.equals("running"));
        if (dailySessions >= DAILY_SESSION_LIMIT || guests.size() >= 100) {
            throw new DemoException(429, "The demo has reached its session limit. Please try again later.");
        }
        CreateChatSessionRequest request = new CreateChatSessionRequest();
        request.setAgentId(settings.agentId());
        request.setTitle("OrbitDesk portfolio guest");
        String id = sessions.createChatSession(request).getChatSessionId();
        byte[] nonce = new byte[32];
        new SecureRandom().nextBytes(nonce);
        String body = Base64.getUrlEncoder().withoutPadding().encodeToString(nonce);
        String token = body + "." + Base64.getUrlEncoder().withoutPadding().encodeToString(sign(body));
        GuestSession guest = new GuestSession(id);
        guests.put(body, guest);
        dailySessions++;
        return new SessionCreated(token, guest.expiresAt, MAX_TURNS);
    }

    public synchronized SessionView view(String bearer) {
        GuestSession guest = authenticate(bearer);
        List<DemoMessage> visible = new ArrayList<>();
        Map<String, String> evidenceCalls = new HashMap<>();
        for (ChatMessageVO message : messages.getChatMessagesBySessionId(guest.id).getChatMessages()) {
            if (message.getRole() == ChatMessageDTO.RoleType.USER
                    || message.getRole() == ChatMessageDTO.RoleType.ASSISTANT) {
                visible.add(visibleMessage(message));
                if (message.getRole() == ChatMessageDTO.RoleType.ASSISTANT && message.getMetadata() != null
                        && message.getMetadata().getToolCalls() != null) {
                    message.getMetadata().getToolCalls().stream()
                            .filter(call -> Set.of("KnowledgeTool", "getDate", "calculateMonthlyCost").contains(call.name()))
                            .forEach(call -> evidenceCalls.put(call.id(), call.name()));
                }
            } else if (message.getRole() == ChatMessageDTO.RoleType.TOOL && message.getMetadata() != null) {
                var result = message.getMetadata().getToolResponse();
                // Only expose a result paired with a permitted call in this visitor's own runtime.
                if (result != null && result.name().equals(evidenceCalls.remove(result.id()))) {
                    visible.add(new DemoMessage(message.getId(), "tool", result.responseData(), List.of(result.name())));
                }
            }
        }
        return new SessionView(guest.status, visible, MAX_TURNS - guest.turns, guest.error);
    }

    private DemoMessage visibleMessage(ChatMessageVO message) {
        List<String> tools = message.getMetadata() == null || message.getMetadata().getToolCalls() == null
                ? List.of() : message.getMetadata().getToolCalls().stream()
                .map(call -> call.name())
                .filter(name -> Set.of("KnowledgeTool", "getDate", "calculateMonthlyCost", "terminate").contains(name))
                .distinct().toList();
        return new DemoMessage(message.getId(), message.getRole().getRole(),
                message.getContent() == null ? "" : message.getContent(), tools);
    }

    public synchronized void send(String bearer, String content) {
        GuestSession guest = authenticate(bearer);
        if (content == null || content.isBlank() || content.length() > MAX_MESSAGE_LENGTH) {
            throw new DemoException(400, "Enter a message between 1 and 1,500 characters.");
        }
        if (guest.status.equals("running")) throw new DemoException(409, "Please wait for the current reply.");
        if (guest.status.equals("failed")) throw new DemoException(409, "Start a new chat to retry the demo.");
        if (guest.turns >= MAX_TURNS) throw new DemoException(429, "This demo chat has reached its eight-message limit.");
        resetBudget();
        if (dailyTurns >= DAILY_TURN_LIMIT) throw new DemoException(429, "Today's demo limit has been reached. Please try again tomorrow.");
        if (!capacity.tryAcquire()) throw new DemoException(429, "The demo is busy. Please try again shortly.");
        guest.status = "running";
        guest.error = null;
        guest.turns++;
        dailyTurns++;
        try {
            executor.execute(() -> run(guest, content.strip()));
        } catch (RejectedExecutionException error) {
            capacity.release();
            guest.status = "failed";
            guest.error = "The demo is unavailable. Please start a new chat later.";
            throw new DemoException(503, guest.error);
        }
    }

    private void run(GuestSession guest, String content) {
        try {
            messages.agentCreateChatMessage(CreateChatMessageRequest.builder()
                    .agentId(settings.agentId()).sessionId(guest.id)
                    .role(ChatMessageDTO.RoleType.USER).content(content).build());
            factory.createGuest(settings.agentId(), guest.id, settings.kbId(), NO_BROWSER_STREAM).run();
            synchronized (this) { guest.status = "idle"; }
        } catch (Exception error) {
            log.warn("Guest demo request failed ({})", error.getClass().getSimpleName());
            synchronized (this) {
                guest.status = "failed";
                guest.error = "The assistant could not complete this reply. Please start a new chat to retry.";
            }
        } finally {
            capacity.release();
        }
    }

    private GuestSession authenticate(String bearer) {
        if (bearer == null || !bearer.startsWith("Bearer ") || bearer.length() > 200) {
            throw new DemoException(401, "Start a demo chat first.");
        }
        String[] parts = bearer.substring(7).split("\\.", -1);
        if (parts.length != 2) throw new DemoException(401, "Invalid demo session.");
        try {
            if (!MessageDigest.isEqual(sign(parts[0]), Base64.getUrlDecoder().decode(parts[1]))) {
                throw new DemoException(401, "Invalid demo session.");
            }
        } catch (IllegalArgumentException error) {
            throw new DemoException(401, "Invalid demo session.");
        }
        GuestSession guest = guests.get(parts[0]);
        if (guest == null || guest.expiresAt.isBefore(Instant.now())) {
            throw new DemoException(410, "This demo session expired. Please start a new chat.");
        }
        return guest;
    }

    private byte[] sign(String content) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(settings.signingSecret().getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            return mac.doFinal(content.getBytes(StandardCharsets.UTF_8));
        } catch (Exception error) {
            throw new IllegalStateException("Demo signing unavailable");
        }
    }

    private void resetBudget() {
        LocalDate today = LocalDate.now(ZoneOffset.UTC);
        if (!budgetDate.equals(today)) { budgetDate = today; dailyTurns = 0; dailySessions = 0; }
    }

    @PreDestroy
    public void close() { executor.shutdownNow(); }
}
