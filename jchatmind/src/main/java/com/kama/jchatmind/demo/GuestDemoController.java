package com.kama.jchatmind.demo;

import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@Profile("cloud")
@RequestMapping("/api/demo")
public class GuestDemoController {
    private final GuestDemoService demo;
    public GuestDemoController(GuestDemoService demo) { this.demo = demo; }

    public record SendMessage(String message) { }

    @PostMapping("/sessions")
    public GuestDemoService.SessionCreated create() { return demo.createSession(); }

    @GetMapping("/session")
    public GuestDemoService.SessionView view(@RequestHeader(value = "Authorization", required = false) String token) {
        return demo.view(token);
    }

    @PostMapping("/messages")
    public ResponseEntity<Map<String, String>> send(
            @RequestHeader(value = "Authorization", required = false) String token,
            @RequestBody SendMessage message) {
        demo.send(token, message.message());
        return ResponseEntity.accepted().body(Map.of("status", "running"));
    }

    @ExceptionHandler(GuestDemoService.DemoException.class)
    public ResponseEntity<Map<String, String>> expected(GuestDemoService.DemoException error) {
        return ResponseEntity.status(error.status).body(Map.of("error", error.getMessage()));
    }

    @ExceptionHandler(Exception.class)
    public ResponseEntity<Map<String, String>> unavailable(Exception error) {
        return ResponseEntity.status(503).body(Map.of("error", "The demo is unavailable. Please try again later."));
    }
}
