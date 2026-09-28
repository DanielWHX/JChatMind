# Optional cloud providers

The default public OrbitDesk demo uses DeepSeek and its fixed handbook. These options preserve the original application's additional provider settings for the private administrator interface; they do not add guest capabilities.

## GLM

To use the existing `glm-4.6` model option, add `ZHIPUAI_API_KEY` to the private `.local/cloud/secrets.env`. Optional overrides are `ZHIPUAI_BASE_URL` (default `https://open.bigmodel.cn/api/paas`) and `ZHIPUAI_MODEL` (default `glm-4.6`). Keep the model default unless intentionally using a different provider model; changing this setting does not rename the existing UI model label.

Without a real key, GLM is **not usable**. The original Java model bean/UI option still exists; the fallback key only preserves application startup and is not a working credential. Choosing GLM before configuration will fail. No GLM request has been verified by this configuration change.

## SMTP

Set `SMTP_HOST`, `SMTP_PORT`, `SMTP_USERNAME`, and `SMTP_PASSWORD` in the same private file. For port 587, the defaults enable SMTP authentication and require STARTTLS. Providers using implicit TLS on port 465 usually require `SMTP_SSL_ENABLE=true`, `SMTP_STARTTLS_ENABLE=false`, and `SMTP_STARTTLS_REQUIRED=false`; follow the mailbox provider's actual settings. `SMTP_AUTH` is also configurable.

Without these credentials the SMTP service is **not usable**: the default host remains localhost with placeholder credentials. The original optional `emailTool` still appears to administrators, but it is not selected for the public demo and guests cannot invoke it. Enable it for an administrator's Agent only after configuring and testing the mailbox. The existing tool's “queued” response reports asynchronous submission, not confirmed delivery. No email was sent or mailbox authenticated by this change.

After changing private settings, recreate the API so it receives the new environment:

```bash
bash scripts/cloud-compose.sh up -d --wait api web
```

## File tools

`FileSystemTools` remains unregistered, matching the original source (`@Component` is commented out). It is therefore **not currently available** in the cloud tool list. Its dormant implementation uses the process working directory; the image's working directory is `/app`. This change does not enable it, move the working directory, or claim a persistent file workspace exists. Before a future activation, provide a separate persistent directory and verify path/symlink boundaries rather than exposing the application JAR/config directory.
