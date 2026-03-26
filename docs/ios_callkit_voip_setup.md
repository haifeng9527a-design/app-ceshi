# iOS CallKit / VoIP Push Setup

## Supabase Edge Function Secrets

`send_push` now supports direct VoIP APNs delivery for iOS call invitations.

Set these secrets for the `send_push` function runtime:

- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_AUTH_KEY_BASE64`
- `APNS_BUNDLE_ID`
- `APNS_USE_SANDBOX`

Recommended values for current debug-device testing:

- `APNS_BUNDLE_ID=com.example.teacherHub`
- `APNS_USE_SANDBOX=true`

`APNS_AUTH_KEY_BASE64` should be the Base64-encoded contents of the downloaded `.p8` APNs auth key.

Example when using Supabase Edge Functions:

```bash
base64 -i AuthKey_XXXXXXXXXX.p8 | tr -d '\n'
```

Use the output as `APNS_AUTH_KEY_BASE64`, then set:

```bash
supabase secrets set \
  APNS_KEY_ID=YOUR_KEY_ID \
  APNS_TEAM_ID=YOUR_TEAM_ID \
  APNS_AUTH_KEY_BASE64=YOUR_BASE64_P8 \
  APNS_BUNDLE_ID=com.example.teacherHub \
  APNS_USE_SANDBOX=true
```

After updating secrets, redeploy the `send_push` function.

## Device Test Checklist

1. Reinstall the iOS app from Xcode after enabling Push Notifications and Background Modes.
2. Launch the app once and log in, so both `fcm` and `apns_voip` tokens are saved.
3. Verify the target user has fresh `device_tokens` rows for:
   - `platform = fcm`
   - `platform = apns_voip`
4. Send a normal chat message and confirm iOS still receives a regular notification.
5. Send a call invitation while the iPhone app is foregrounded:
   - expected: native CallKit incoming UI appears
   - expected: answering opens the Agora page
6. Send a call invitation while the app is backgrounded:
   - expected: CallKit incoming UI appears on lock screen / system UI
7. Reject from CallKit:
   - expected: `call_invitations.status` becomes `rejected`
8. Answer from CallKit:
   - expected: `call_invitations.status` becomes `accepted`
   - expected: Flutter resumes and opens `AgoraCallPage`
9. Cancel from caller side before answer:
   - expected: active incoming call UI is dismissed and no stale ringing state remains
10. Re-run Android incoming-call regression to ensure `teacherhub.call` channel changes did not break existing behavior.
