# Data Flow — contractkit

> **Purpose:** Visual maps of how data flows through the gem, from API
> request to typed model object. Mermaid diagrams render on GitHub and
> in most markdown viewers.
>
> **Audience:** AI agents, first-time contributors, anyone who wants to
> understand the gem's internal flow without reading source.

Related: [[architecture-overview]], [[data-models]], [[../domain/sam-gov]], [[../domain/usaspending]]

---

## Full request flow

```mermaid
sequenceDiagram
    participant App as Your Ruby App
    participant Config as Configuration
    participant Resource as Resource Module
    participant Paginator as Lazy Paginator
    participant Client as API Client
    participant MW as Middleware Stack
    participant API as SAM.gov / USASpending.gov
    participant Parser as Response Parser
    participant Model as Typed Model

    App->>Config: Contractkit.configure { ... }
    Note over Config: sam_api_key, timeout, retries, cache, logger

    App->>Resource: Opportunity.search(ncode: "541512")
    Resource->>Paginator: new(client, params)
    Paginator->>Client: raw_search(params, page 1)
    Client->>MW: Faraday request
    MW->>MW: cache check (GETs only)
    MW->>MW: rate limiter (token bucket)
    MW->>MW: retry middleware (5xx only)
    MW->>MW: instrumentation hooks
    MW->>API: HTTP request
    API-->>MW: JSON response
    MW-->>Client: parsed JSON
    Client->>Parser: parse(opportunitiesData)
    Parser->>Parser: normalize fields
    Parser->>Parser: agency normalization
    Parser->>Parser: set-aside normalization
    Parser->>Parser: date parsing
    Parser->>Model: Opportunity.new(...)
    Model-->>Paginator: Array<Opportunity>
    Paginator->>Paginator: page += 1 (if more)
    Paginator-->>App: lazy Enumerator
    App->>Paginator: .first(10) or .each
```

## Resource query flow

```mermaid
flowchart TD
    A[App calls Resource.search] --> B{Resource type}
    B -->|SAM| C[OpportunitySearch.new]
    B -->|USASpending| D[AwardSearch.new]
    C --> E[Sam::Client#raw_search]
    D --> F[Usaspending::Client#raw_search]
    E --> G[GET /opportunities/v2/search]
    F --> H[POST /search/spending_by_award/]
    G --> I[ResponseParser.parse SAM]
    H --> J[ResponseParser.parse USASpending]
    I --> K[Array of Opportunity]
    J --> L[Array of Award]
    K --> M[LazySearchHandle]
    L --> M
    M --> N{Iteration mode}
    N -->|each| O[Yield one record at a time]
    N -->|each_batch| P[Yield one page at a time]
    N -->|first/limit| Q[Collect N records, auto-paginate]
```

## Cross-reference flow

```mermaid
sequenceDiagram
    participant App as Your App
    participant Opp as Opportunity
    participant XR as CrossReference
    participant Award as Award.search
    participant USAS as USASpending API

    App->>Opp: opp.related_awards(lookback: 3)
    Opp->>XR: awards_for(opportunity:, lookback: 3)
    XR->>XR: build_filters(agency + NAICS + lookback)
    XR->>Award: search(filters: built, limit: 50)
    Award->>USAS: POST spending_by_award
    USAS-->>Award: matching awards
    Award-->>XR: Array<Award>
    XR-->>Opp: Array<Award>

    App->>Opp: opp.likely_incumbent
    Opp->>XR: likely_incumbent(related_awards)
    XR->>XR: group by recipient UEI
    XR->>XR: sum obligations per recipient
    XR->>XR: dominant > 50%?
    XR-->>Opp: Recipient or nil
```

## Recompete flow (time-forward)

```mermaid
sequenceDiagram
    participant App as Your App
    participant RC as Recompete
    participant Idv as Idv.search
    participant Opp as Opportunity.search
    participant USAS as USASpending
    participant SAM as SAM.gov

    App->>RC: expiring(within: 12, naics: "541512")
    RC->>RC: compute date window [today, today+12mo]

    RC->>Idv: search(filters: date_range + naics)
    Idv->>USAS: POST spending_by_award (IDV codes)
    USAS-->>Idv: IDV results
    Idv-->>RC: each IDV

    RC->>RC: filter by last_date_to_order within window?
    RC->>Opp: search(ncode: naics, postedFrom: today-180d)
    Opp->>SAM: GET opportunities/v2/search
    SAM-->>Opp: opportunities
    RC->>RC: match by agency + NAICS
    RC-->>App: yield Match(award, matching_opportunities)

    RC->>Award: search(filters: date_range + naics)
    Note over RC,Award: contracts after IDVs
    Award->>USAS: POST spending_by_award
    USAS-->>Award: contract results
    RC->>RC: filter by period.end_date within window?
    RC->>Opp: search(ncode: naics, postedFrom: today-180d)
    RC-->>App: yield Match(award, matching_opportunities)
```

## Entity enrichment flow

```mermaid
sequenceDiagram
    participant App as Your App
    participant Recipient as Recipient
    participant Entities as Sam::Entities
    participant SAM_E as SAM Entity Management API

    Note over Recipient: Un-enriched recipient<br/>(from Award.search)
    Recipient->>Recipient: name, uei, duns populated<br/>everything else is nil

    App->>Recipient: find_entity(uei)
    Recipient->>Entities: search(uEI: uei)
    Entities->>SAM_E: GET /entity-information/v3/entities
    SAM_E-->>Entities: SAM registration record
    Entities->>Entities: parse registration_status
    Entities->>Entities: parse business_types (CodedValue[])
    Entities->>Entities: parse sba_business_types
    Entities->>Entities: parse exclusionStatusFlag
    Entities->>Entities: parse owner references
    Entities-->>Recipient: enriched Recipient
    Recipient-->>App: full Recipient with cage_code,<br/>registration, exclusions, ownership
```

## Lazy model traversal (N+1 aware)

```mermaid
flowchart TD
    A[Award object] --> B{award.transactions}
    B --> C[Transaction.for_award(award_id)]
    C --> D[POST /api/v2/transactions/]
    D --> E[Array of Transaction]

    A --> F{award.subawards}
    F --> G[Subaward.for_award(award_id)]
    G --> H[POST /api/v2/subawards/]
    H --> I[Array of Subaward]

    A --> J{award.parent_idv}
    J --> K{parent_piid present?}
    K -->|yes| L[Idv.find_by_piid(piid)]
    L --> M[POST spending_by_award]
    M --> N[Idv object]
    K -->|no| O[nil]

    N --> P{idv.child_awards}
    P --> Q[Award.search with parent_piid filter]
    Q --> R[Array of Award]

    N --> S{idv.transactions}
    S --> T[Same as award.transactions]
```

## Middleware execution order

```mermaid
flowchart LR
    A[Faraday Request] --> B[Cache Middleware]
    B -->|GET, cached| Z[Return cached]
    B -->|miss or POST| C[Rate Limiter]
    C -->|bucket has tokens| D[Retry Middleware]
    C -->|bucket empty| C2[Sleep until token]
    C2 --> C
    D --> E{Response status}
    E -->|5xx or network error| D2[Backoff + jitter]
    D2 --> D
    E -->|4xx| F[Instrumentation Middleware]
    E -->|success| F
    F --> G[Logger Middleware]
    G --> H[Faraday Adapter]
    H --> I[External API]
    I --> H
    H --> G
    G --> F
    F -->|emit events| F2[on_event block<br/>+ AS::Notifications]
    F --> J[Return Response]
```

## Configuration flow

```mermaid
flowchart TD
    A[Contractkit.configure] --> B[Configuration singleton]
    B --> C{Access pattern}
    C -->|Global| D[Contractkit.configuration]
    C -->|Per-tenant| E[Client.new sam_api_key: ...]
    D --> F[Sam::Client.new<br/>uses global config]
    E --> G[Sam::Client.new<br/>uses instance config]
    F --> H[Faraday connection<br/>with global middleware]
    G --> I[Faraday connection<br/>with instance middleware]
    H --> J[API calls]
    I --> J
    Note over F,G: Fully isolated — mutating one<br/>doesn't affect the other
```
