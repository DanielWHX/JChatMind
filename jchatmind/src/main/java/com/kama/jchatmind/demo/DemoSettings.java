package com.kama.jchatmind.demo;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Profile;
import org.springframework.stereotype.Component;

@Component
@Profile("cloud")
public record DemoSettings(String adminSecret, String signingSecret, String agentId, String kbId) {
    public DemoSettings(
            @Value("${JCHATMIND_ADMIN_SECRET:}") String adminSecret,
            @Value("${JCHATMIND_DEMO_SIGNING_SECRET:}") String signingSecret,
            @Value("${JCHATMIND_DEMO_AGENT_ID:}") String agentId,
            @Value("${JCHATMIND_DEMO_KB_ID:}") String kbId) {
        if (adminSecret.length() < 32 || signingSecret.length() < 32 || adminSecret.equals(signingSecret)) {
            throw new IllegalStateException("Cloud admin and demo signing secrets must be distinct and at least 32 characters");
        }
        this.adminSecret = adminSecret;
        this.signingSecret = signingSecret;
        this.agentId = agentId;
        this.kbId = kbId;
    }
}
