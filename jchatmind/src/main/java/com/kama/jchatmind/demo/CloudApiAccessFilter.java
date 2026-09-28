package com.kama.jchatmind.demo;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.context.annotation.Profile;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/** Cloud exposes only the guest contract; the original admin APIs stay private. */
@Component
@Profile("cloud")
@Order(Ordered.HIGHEST_PRECEDENCE)
public class CloudApiAccessFilter extends OncePerRequestFilter {
    private final DemoSettings settings;

    public CloudApiAccessFilter(DemoSettings settings) { this.settings = settings; }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain chain)
            throws ServletException, IOException {
        response.setHeader("Cache-Control", "no-store");
        response.setHeader("X-Content-Type-Options", "nosniff");
        String path = request.getServletPath();
        // MockMvc and a root-context servlet may have an empty servletPath.
        if (path.isEmpty()) path = request.getRequestURI();
        boolean publicRoute = (path.equals("/health") && request.getMethod().equals("GET"))
                || (path.equals("/api/demo/sessions") && request.getMethod().equals("POST"))
                || (path.equals("/api/demo/session") && request.getMethod().equals("GET"))
                || (path.equals("/api/demo/messages") && request.getMethod().equals("POST"));
        if (!publicRoute) {
            String secret = request.getHeader("X-JChatMind-Admin");
            if (secret == null || !MessageDigest.isEqual(secret.getBytes(StandardCharsets.UTF_8),
                    settings.adminSecret().getBytes(StandardCharsets.UTF_8))) {
                response.setStatus(401);
                response.setContentType("application/json");
                response.getWriter().write("{\"error\":\"Authentication required.\"}");
                return;
            }
        }
        chain.doFilter(request, response);
    }
}
