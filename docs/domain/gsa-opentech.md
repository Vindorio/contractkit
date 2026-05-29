# GSA OpenTech

> **Purpose:** What GSA OpenTech is, how it relates to contractkit's
> data sources, and what developers should know about its API ecosystem.
>
> **Audience:** AI agents and new developers who encounter "GSA OpenTech"
> references and need to place it in the data landscape.

Related: [[sam-gov]], [[usaspending]], [[fpds]], [[entities]]

---

## What GSA OpenTech is

GSA OpenTech is GSA's **API gateway program** — a single portal
(`open.gsa.gov`) that documents and provides access keys for multiple
federal APIs, including:

- SAM.gov Opportunities API
- SAM.gov Entity Management API
- SAM.gov Exclusions API

It is NOT a separate data source — it's the **doorway** through which
you request and manage API keys for SAM.gov's various services.

## What it hosts

| API | Key scope | contractkit usage |
|---|---|---|
| SAM Opportunities API | `api.data.gov` key (public or federal tier) | `Opportunity.search`, `.find`, `.modified_since` |
| SAM Entity Management API | Same key, different endpoint | `Recipient.find_entity` (entity registration) |
| SAM Exclusions API | Same key, separate service | Deferred (M4 ships exclusion *status* only, not history) |

All three share the same API key and the same key management dashboard
at `api.data.gov`. GSA OpenTech is the documentation layer.

## Key acquisition

```
Developer → api.data.gov/signup → create account
         → Request SAM.gov API key → public tier (1k/day)
         OR
         → Verify .gov/.mil email → federal tier (10k/day)
```

The key is a long alphanumeric string. For the **Opportunities API**,
it's passed as a query parameter `api_key=<key>`. For the **Entity
Management API**, it's passed as an `x-api-key` header.

## Relevance to contractkit

**The gem does not interact with GSA OpenTech directly.** When the
gem's README says "get a SAM.gov API key at api.data.gov/signup",
that's GSA OpenTech. The key is then set via:

```ruby
Contractkit.configure do |c|
  c.sam_api_key = ENV["SAM_API_KEY"]
end
```

The gem uses this key to authenticate against SAM.gov's APIs (both
Opportunities and Entity Management). The key management — renewal,
tier upgrade, re-attestation — is the consumer's responsibility.

## API key scope and behavior

### Public tier (default)

- ~1,000 requests/day
- Automatic for any email address
- Sufficient for development and low-volume production

### Federal tier

- ~10,000 requests/day
- Requires `.gov` or `.mil` email verification
- Must be re-attested periodically (typically annually)

### Key behavior quirks

- **Inactive keys are reaped** — if you don't use a key for an
  extended period, it may be deactivated
- **No hard 90-day expiry** by default (contrary to some documentation)
- **Key rejection manifests as 404** on the Opportunities endpoint
  (not the documented 403). The gem handles this by raising
  `Contractkit::Sam::AuthenticationError`

The gem's rate limiter defaults to 20 req/min for SAM — conservative
and sustainable for both tiers. Consumers on the federal tier who
need higher throughput can adjust via configuration.

## Postman collection and docs

GSA OpenTech publishes:

- **Interactive API docs** (Swagger/OpenAPI) at
  `https://open.gsa.gov/api/` for each service
- **Postman collection** with pre-configured requests
- **Rate limit documentation** (though actual limits often differ
  from documented — see [[sam-gov]] §"Rate limits — documented vs real")

These are useful for initial exploration, not for production use.
The gem handles pagination, error handling, rate limiting, and
response parsing so you don't need to work with the raw API.

## Future: additional GSA APIs

GSA OpenTech hosts several other APIs that are **out of scope for
contractkit v0.1-v0.2**:

| API | What it does | Why out of scope |
|---|---|---|
| SAM Exclusions API | Full exclusion history (dates, programs) | M4 ships exclusion *status* from entity response; history deferred |
| FPDS ATOM feed | Real-time contract action notifications | FPDS has no REST API; ATOM is a different ingestion model |
| GSA eLibrary | GSA schedule pricing | Consumer concern (different domain) |
| GSA Advantage | Product catalog | Not procurement data |
| Federal Hierarchy | Agency-component-level mapping | Useful as reference data; v0.2 agency normalization may use it |

## Key takeaways for AI agents

1. **GSA OpenTech is the key issuance portal, not a data source.**
   The gem uses the key to talk to SAM.gov APIs; GSA OpenTech is
   where you get that key.

2. **One key, multiple SAM APIs.** The same `SAM_API_KEY` works for
   Opportunities, Entity Management, and (future) Exclusions.

3. **Key behavior is under-documented.** The gem's rate limiter,
   error handling, and 404-on-bad-key detection are based on
   production observation, not official docs.

4. **The gem abstracts key management.** Consumers set
   `c.sam_api_key` once; the gem's middleware handles
   authentication, rate limiting, retry, and key redaction in logs.

## References

- GSA OpenTech portal: https://open.gsa.gov/
- API key signup: https://api.data.gov/signup/
- SAM Opportunities API docs: https://open.gsa.gov/api/sam-opportunities/
- SAM Entity Management API docs: https://open.gsa.gov/api/entity-api/
