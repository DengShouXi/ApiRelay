# App Store Connect metadata — English (T063)

Paste into ASC localization **English (U.S.)**.  
Scope: custody / assignment / entitlements only (SC-010).  
**Do not** mention relay, usage dashboards, or key health probes.

| Field | Limit | Draft |
|-------|-------|-------|
| Name | 30 | ApiRelay |
| Subtitle | 30 | Secure API key vault |
| Promotional Text | 170 | Keep API keys in iCloud Keychain, assign them to tools, and copy when you need them—with optional Face ID before reveal. |
| Keywords | 100 | API,key,vault,Keychain,OpenAI,Claude,Gemini,developer,secure,clipboard |
| What's New | — | First App Store release: store and sync API keys, assign to tools, free tier and one-time unlock. |

## Description

```text
ApiRelay is a private vault for the API keys you use with AI platforms and developer tools.

STORE KEYS SAFELY
Keep key secrets in the system Keychain. Metadata syncs with iCloud; key secrets sync through iCloud Keychain with end-to-end encryption between your own Apple devices—not uploaded to an ApiRelay server.

ORGANIZE & ASSIGN
Group by platform or by the tools you use. Assign keys to consumers so you always know which key belongs where.

COPY WHEN YOU NEED IT
Reveal or copy a secret after optional identity confirmation (Face ID, Touch ID, device passcode, or master password—you choose). Copied secrets can auto-clear from the clipboard after a timeout you set.

FREE & ONE-TIME UNLOCK
Store a limited number of keys for free. Unlock unlimited keys with a one-time In-App Purchase. Restore Purchases is always available in Settings.

PRIVACY-FIRST
No ApiRelay account. No analytics SDK. The app helps you keep and hand out keys; it does not send your API calls through our servers.

Requires iCloud Keychain on each device that should share the same key secrets.
```

## ASC notes (for you)

- Category suggestion: Developer Tools / Productivity  
- Age rating: no unrestricted web, no UGC; answer questionnaire honestly  
- Support URL / Privacy Policy URL: use your published T059b URLs when ready  
- IAP display name (ASC): Unlimited Keys — product id `com.apirelay.iap.unlimited_keys`

## Forbidden phrases (must stay absent)

- system-enforced / cannot be bypassed  
- undelivered capabilities as selling points  
- “secrets never leave this device” (false: iCloud Keychain sync)
