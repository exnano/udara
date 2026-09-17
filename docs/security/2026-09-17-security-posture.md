# Udara security posture evaluation

Date: 2026-09-17. Scope: current working-tree macOS app (unreleased 1.5.0), Hono Worker, local release tooling, and low-volume production probes at `https://udara.exnano.io`. Deployed Worker version: `f395a8d5-7fce-4fa3-acb8-38511879e029`. Installed artifact inspected separately: 1.4.0. This is a focused source/configuration review and smoke evaluation, not a penetration-test certification or load test.

## Verdict

Good baseline for sandboxing, credential separation, TLS and input validation. **Address quota-abuse protection before broad public distribution.** No critical vulnerability was identified within the reviewed scope. One high, two medium and two low findings remain open. No runtime controls or production configuration were changed by this evaluation.

## Findings

### SEC-01 — High: public API can exhaust shared provider quota

Evidence: `hono/src/index.ts:21` accepts anonymous requests; line 84 invokes AQICN for any valid non-MY country or DOE fallback. `hono/wrangler.jsonc` has no rate-limit binding and enables both custom-domain and workers.dev access. Every AQICN request is uncached. A caller controls country and coordinates and need not use the Mac app. There is no server-side provider circuit breaker; providers reduce upstream 429/5xx to `unavailable`, and the API's 300-second retry hint is voluntary for callers.

Impact: a script can consume the shared WAQI quota, increase Worker usage and deny data to legitimate users. The DOE cache does not mitigate this path. No traffic flood was attempted. Cloudflare zone rules could offer mitigation, but reading rulesets returned 403, so their presence/effectiveness is unverified.

Recommended fix: add Worker-level per-client throttling (using Cloudflare-provided client IP, with NAT-aware limits), plus an aggregate provider budget/cooldown and safe 429/Retry-After responses. Honor upstream Retry-After without retry storms. Apply controls to both hostnames, or disable workers.dev once the custom domain is the only supported route. A static token embedded in the public app is not an effective access boundary. Cloudflare's per-location rate limiter alone is not a strict global quota; use coordinated state if a strict provider budget is required.

Acceptance: tests prove blocked calls make zero upstream requests; controlled probes verify 429 and recovery on both hostnames without stressing the provider.

### SEC-02 — Medium: macOS location permission disclosure names the old recipient

Evidence: both app build configurations in `Udara.xcodeproj/project.pbxproj:33` and line 34 still say coordinates are sent to Open-Meteo for forecasts in `NSLocationUsageDescription`. The current code sends approximate GPS coordinates to Apple reverse geocoding, then the Udara backend; AQICN also receives coordinates on its lookup path. The About page in `Sources/UdaraApp/CitySearchView.swift:88` is more current, but does not repair the system permission string. The alternate When-In-Use string is generic, so which string macOS displays matters.

Impact: users may grant permission based on an inaccurate data-flow description.

Recommended fix: update both location usage descriptions consistently for Apple, Udara/Cloudflare and the applicable provider. Explain approximate-coordinate retention and upstream disclosure in privacy documentation. Verify the generated Release Info.plist and a fresh permission prompt. Keep disclosure clear that city search still uses Open-Meteo.

### SEC-03 — Medium: no upper bound on remote response bodies

Evidence: `hono/src/providers/doe.ts` and `aqicn.ts` call `response.json()` without byte/record limits. `Sources/UdaraCore/OpenMeteoProvider.swift:35` buffers the full response with `URLSession.data(for:)`, including responses used by BackendProvider. Timeouts exist but do not bound how many bytes arrive during that time.

Impact: a compromised or malfunctioning trusted upstream could exhaust Worker or app memory. This is conditional upstream-origin risk, not a demonstrated anonymous arbitrary-body injection or SSRF exploit.

Recommended fix: enforce streamed byte limits before decoding, cap station/attribution counts and string sizes, and handle oversized responses as sanitized provider failures. Checking Content-Length alone is insufficient. Add oversized/chunked-payload tests; preserve usable cache on failure.

### SEC-04 — Low: monitoring gap for quota and availability incidents

Evidence: `hono/wrangler.jsonc` disables observability and the Worker exposes only per-response timing/cache diagnostics. No project-level aggregate error, quota-exhaustion or circuit-breaker alerts are configured. Cloudflare account-level monitoring was not verified.

Impact: abuse, upstream outage or repeated fallback may be noticed only through user reports.

Recommended fix: add privacy-preserving metrics for status, provider, latency bucket, cache state and rate-limit outcomes. Do not log raw URLs, coordinates, tokens, upstream payloads or stable device identifiers. Configure failure/quota alerts without enabling indiscriminate request logging.

### SEC-05 — Low: new backend deployment is not tied to committed source

Evidence: the backend directory remains untracked and the broader working tree contains unreleased changes. Cloudflare has a deployment version, but no committed backend revision is available to reproduce it from the repository.

Impact: recovery, review and supply-chain traceability depend on this local workstation.

Recommended fix: commit the reviewed backend and lockfile after remediation, record source revision with deployment version, and add a local deploy preflight for checks/tests and clean source. This can remain fully local; GitHub Actions is not necessary.

## Verified controls

- Coordinates are numeric, finite and bounded; metric is allowlisted. Live invalid latitude/NaN/metric requests returned sanitized HTTP 400. Country accepts any two letters; it is a routing hint, not an authorization claim.
- Upstream hosts are fixed; request input does not supply an arbitrary target URL. No direct user-controlled SSRF path found. There is no SQL, shell execution, HTML rendering or account session in the Worker.
- API responses use no-store; DOE uses one fixed dataset cache key per hostname, with five-minute envelope expiry and observation freshness validation. Coordinates are not cache keys. The internal cache path is not a public dataset endpoint (live 404).
- Live `/.env` returned 404; unsupported POST returned 404. No credential or stack trace appeared in tested errors. No permissive CORS middleware is configured; CORS is not an abuse defense against native clients.
- `.env` and `hono/.dev.vars` are ignored, not tracked, and have mode 0600. Exact known WAQI token values were not found in the 56 enumerated tracked/bundle file paths scanned. This is not a complete historical or pattern-based secret scan.
- App configuration generation copies URL settings only. Dotenv is parsed literally rather than sourced as shell; Release URL validation requires HTTPS and rejects credentials/query/fragment and xcconfig injection characters.
- App transport uses an ephemeral URLSession with timeouts; normal platform TLS trust is retained. Production backend requests successfully passed via the actual Swift provider in deployment smoke testing. HTTP health redirects to HTTPS (301).
- GPS requires OS permission, uses one-shot location acquisition and rounds coordinates to 0.01 degrees before external requests. Saved approximate current location is persisted locally; station readings are stripped before persistence. Revocation handling clears current location through repository state updates.
- App Sandbox, outbound networking and location are the declared entitlements; hardened runtime is configured. Installed 1.4.0 has those entitlements, no get-task-allow, a valid strict code signature and Gatekeeper acceptance as Notarized Developer ID. This does not certify the unreleased 1.5.0 artifact.
- Local release tooling requires clean/tagged source, tests, Developer ID identity, hardened runtime, sandbox/no debug entitlement, both architectures, accepted app/DMG notarization, stapling, Gatekeeper checks and a post-stapling checksum.

## Validation and limits

- Backend TypeScript check and 29 tests passed.
- 42 Swift core tests and 26 Python release-tooling tests passed.
- `bun audit --json` in `hono/` returned `{}` with exit 0 (no reported advisories). SwiftPM has no third-party package dependencies. Dependency audit results are time-specific and not proof of absence of unknown vulnerabilities.
- Zone rulesets, minimum TLS version and HTTPS configuration API reads returned 403 with current OAuth permissions. Actual HTTPS and HTTP redirect behavior were verified, but WAF/rate-limit policy, account MFA, token scope, billing limits and edge log retention were not audited.
- No traffic flooding, malformed large bodies, secret rotation, production changes, app publishing or Git operations were performed. No fresh notarized 1.5.0 artifact or clean-Mac runtime assessment was produced.
- Cloudflare error 1010 for Python urllib was previously observed while curl and the real Swift client worked. That client-signature filter is not evidence of a sufficient quota-abuse control.

## Remediation order

1. Add and test quota controls/cooldown across all public routes.
2. Correct permission disclosures and document location handling before releasing 1.5.0.
3. Bound upstream/app response sizes and add privacy-safe operational metrics.
4. Commit reviewed source and redeploy from a traceable revision, then rerun production smoke checks.

## References

- [Cloudflare Worker rate limiting](https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/): enforcement is local to a Cloudflare location and is not a strict global accounting system.
- [Cloudflare Workers best practices](https://developers.cloudflare.com/workers/best-practices/workers-best-practices/): bounded/streamed processing and operational controls informed this review.

## Release review — 17 September 2026

Reviewed again for the 1.5.0 publication request. SEC-01 through SEC-04 remain open; SEC-05 is only partially addressed by committing the backend with the release (the deployed revision and clean-source deployment preflight still need reconciliation). This report remains active and must not be archived as completed. Publishing a build does not close these findings.

## DOE/Open-Meteo correction — 1.5.1

AQICN integration and shared-token usage are removed. SEC-01's specific WAQI quota exposure no longer applies; generic public endpoint/provider quota abuse remains open because no Worker rate limiter is configured. SEC-02 permission strings now name Apple, Udara, DOE and Open-Meteo; fresh real permission-dialog acceptance is still pending. SEC-03/04 and deployment preflight follow-ups remain open. Do not archive this report as fully remediated.
