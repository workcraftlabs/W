# Optional ChatGPT matching: researched, not implemented

OpenAI documents Sign in with ChatGPT plan usage for open-source, locally hosted apps. Eligible users can authorize model requests against their ChatGPT plan; this does not expose their ChatGPT conversation history or connected Notion credentials.

Primary sources checked October 18, 2026:
- https://developers.openai.com/siwc/token-sharing-open-source
- https://developers.openai.com/siwc/token-sharing-open-source/preview-limitations

Keep the baseline local matcher and direct Notion client independent. A future optional provider should accept the transcript and candidate records, return a validated ranking or task proposal, and never perform unconfirmed writes. Implement browser authorization with PKCE/state/nonce, a stable per-install host ID, validated tokens/scopes, Keychain storage and renewal, and visible account/usage controls. Follow current registration documentation before implementation; commercial/remote hosting has separate availability constraints.

The preview requires streaming Responses requests with `store: false`. Audio transcription and hosted MCP/connectors are unsupported on this route, so retain local dictation and W's own Notion connection. No credentials are copied from another installed app. This feature is not present in the developer preview.
