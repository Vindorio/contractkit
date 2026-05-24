# Tango SDK Data Models: Comprehensive Research Findings

**Research Date:** May 2026  
**Scope:** Tango Python SDK (`tango-python/`) with focus on Pydantic models, schemas, and API client method signatures  
**Purpose:** Inform Vindor's ActiveRecord modeling and scoring pipeline for SAM.gov opportunity evaluation

---

## 1. Model Map: Core Pydantic Models & Field Reference

### Contracts

| Field | Type | Location | Notes |
|-------|------|----------|-------|
| `key` | str | explicit_schemas.py:317 | Unique award identifier (required) |
| `piid` | str | explicit_schemas.py:348 | Procurement Instrument ID |
| `award_date` | date | explicit_schemas.py:240 | Contract award date |
| `obligated` | Decimal | explicit_schemas.py:341 | Currently obligated/funded amount |
| `total_contract_value` | Decimal | explicit_schemas.py:409 | Total estimated value (base + all options) |
| `base_and_exercised_options_value` | Decimal | explicit_schemas.py:244 | Base + exercised options (not all options) |
| `description` | str | explicit_schemas.py:278 | Contract description |
| `recipient` | RecipientProfile | explicit_schemas.py:371 | Vendor/awardee details (expandable) |
| `parent_award` | ParentAward | explicit_schemas.py:342 | Link to parent IDV (for task orders under IDIQ) |
| `solicitation_identifier` | str | explicit_schemas.py:396 | SAM.gov solicitation ID (denormalized) |
| `set_aside` | str | explicit_schemas.py:383 | Set-aside type (e.g., "Small Business") |
| `naics_code` | int | explicit_schemas.py:329 | Primary NAICS classification |
| `psc_code` | str | explicit_schemas.py:362 | Product Service Code |
| `place_of_performance` | PlaceOfPerformance | explicit_schemas.py:352 | Geographic location (expandable) |
| `competition` | Competition | explicit_schemas.py:250 | Competition details (expandable) |
| `transactions` | list[AwardTransaction] | explicit_schemas.py:415 | Modification history (expandable) |
| `subawards_summary` | SubawardsSummary | explicit_schemas.py:399 | Count + total subaward amount |
| `fiscal_year` | int | explicit_schemas.py:298 | Fiscal year of award |

**Discriminators vs IDVs:**
- Contracts are FPDS Type 01 (Fixed Price Delivery Orders, Time & Materials, etc.)
- IDVs are FPDS Type 02 (Indefinite Delivery Indefinite Quantity)
- Tango schema does not expose an explicit discriminator field; type is inferred from endpoint (`/api/contracts/` vs `/api/idvs/`)

**Key Sources:**
- Contract schema: `explicit_schemas.py:239-435`
- Models.py docstring: `models.py:285-299`

---

### IDVs (Indefinite Delivery Vehicles)

| Field | Type | Location | Notes |
|-------|------|----------|-------|
| `uuid` | str | explicit_schemas.py:965 | Internal Tango UUID |
| `key` | str | explicit_schemas.py:966 | Unique award identifier (required) |
| `piid` | str | explicit_schemas.py:967 | Procurement Instrument ID |
| `award_date` | date | explicit_schemas.py:969 | IDV award date |
| `obligated` | Decimal | explicit_schemas.py:980 | Obligated amount (sum of task orders) |
| `total_contract_value` | Decimal | explicit_schemas.py:972 | IDV ceiling value |
| `base_and_exercised_options_value` | Decimal | explicit_schemas.py:976 | Base + exercised options |
| `idv_type` | dict | explicit_schemas.py:981 | IDV category (GWAC, IDIQ, etc.) — {code, description} |
| `multiple_or_single_award_idv` | dict | explicit_schemas.py:982 | Single vs Multi-award flag — {code, description} |
| `type_of_idc` | dict | explicit_schemas.py:985 | Type of Indefinite Contract — {code, description} |
| `period_of_performance` | dict | explicit_schemas.py:1035 | Contains `start_date` and `last_date_to_order` |
| `recipient` | RecipientProfile | explicit_schemas.py:987 | Awardee entity |
| `parent_award` | ParentAward | explicit_schemas.py:1004 | Link to parent IDV (if this IDV is a child) |
| `awarding_office` | AwardOffice | explicit_schemas.py:1011 | Contracting office |
| `funding_office` | AwardOffice | explicit_schemas.py:1018 | Funding office |
| `competition` | Competition | explicit_schemas.py:1056 | Competition details |
| `legislative_mandates` | LegislativeMandates | explicit_schemas.py:1025 | Statutory requirements |
| `transactions` | list[AwardTransaction] | explicit_schemas.py:1042 | Modification history |
| `subawards_summary` | SubawardsSummary | explicit_schemas.py:1049 | Subaward aggregates |
| `awards` / `orders` | list[Contract] | explicit_schemas.py:1063, 1067 | Child task orders under this IDV |

**Key PoP Fields for Recompete:**
- `period_of_performance.start_date`: IDV start (explicit_schemas.py:60)
- `period_of_performance.last_date_to_order`: **Critical expiration date** (explicit_schemas.py:61)

**API Filtering:**
- `last_date_to_order_gte` / `last_date_to_order_lte` available on `list_idvs()`: client.py:798-799

**Key Sources:**
- IDV schema: `explicit_schemas.py:963-1086`
- IDV PoP schema: `explicit_schemas.py:59-64`

---

### Vehicles (Solicitation-Centric Groupings)

| Field | Type | Location | Notes |
|-------|------|----------|-------|
| `uuid` | str | explicit_schemas.py:1090 | Tango internal ID (unique per vehicle) |
| `solicitation_identifier` | str | explicit_schemas.py:1091 | SAM.gov solicitation ID (unique) |
| `agency_id` | str | explicit_schemas.py:1097 | Awarding agency code |
| `organization_id` | str | explicit_schemas.py:1098 | Organization hierarchy ID |
| `is_synthetic_solicitation` | bool | explicit_schemas.py:1094 | Flag: hand-rolled grouping vs auto-generated |
| `program_acronym` | str | explicit_schemas.py:1113 | Vehicle program (OASIS, Alliant, GWAC, etc.) |
| `vehicle_type` | dict | explicit_schemas.py:1112 | Vehicle type — {code, description} |
| `type_of_idc` | dict | explicit_schemas.py:1117 | Indefinite contract type |
| `contract_type` | dict | explicit_schemas.py:1118 | Contract type category |
| `who_can_use` | dict | explicit_schemas.py:1116 | Use restrictions |
| `description` | str | explicit_schemas.py:1123 | Vehicle description |
| `fiscal_year` | int | explicit_schemas.py:1125 | Fiscal year |
| `award_date` | date | explicit_schemas.py:1126 | Earliest award on vehicle |
| `latest_award_date` | date | explicit_schemas.py:1127 | Most recent award |
| `last_date_to_order` | date | explicit_schemas.py:1130 | Latest PoP expiration across IDVs |
| **Rollup fields** | | | |
| `idv_count` | int | explicit_schemas.py:1134 | Number of awardees |
| `awardee_count` | int | explicit_schemas.py:1135 | Distinct vendors |
| `order_count` | int | explicit_schemas.py:1136 | Total task orders issued |
| `total_obligated` | Decimal | explicit_schemas.py:1137 | Sum of obligations |
| `vehicle_obligations` | Decimal | explicit_schemas.py:1140 | Denormalized obligated value |
| `vehicle_contracts_value` | Decimal | explicit_schemas.py:1143 | Sum of contract values |
| **SAM.gov-derived** | | | |
| `solicitation_title` | str | explicit_schemas.py:1147 | Opportunity title |
| `solicitation_description` | str | explicit_schemas.py:1150 | Opportunity description |
| `solicitation_date` | date | explicit_schemas.py:1153 | SAM posting date |
| `opportunity_id` | str | explicit_schemas.py:1156 | SAM opportunity ID |
| `naics_code` | int | explicit_schemas.py:1157 | Primary NAICS |
| `psc_code` | str | explicit_schemas.py:1163 | Primary PSC |
| `set_aside` | str | explicit_schemas.py:1169 | Set-aside type |
| **Expansions** | | | |
| `awardees` | list[IDV] | explicit_schemas.py:1171 | Child IDVs under vehicle |
| `metrics` | VehicleMetrics | explicit_schemas.py:1174 | Computed market metrics (expandable) |

**Vehicle-Level Metrics (from VehicleMetrics expansion):**
- `avg_offers_received` (float): avg competitiveness
- `award_concentration_hhi` (float): market concentration (Herfindahl index)
- `order_concentration_hhi` (float): order distribution concentration
- `competed_rate` (float): % of awards competed
- `using_agency_count` (int): distinct using agencies
- `avg_order_value`, `max_order_value` (float): pricing stats
- `recent_obligations_24mo`, `recent_orders_24mo`: recency metrics
- `days_since_last_order` (int): activity staleness

**Key Sources:**
- Vehicle schema: `explicit_schemas.py:1089-1192`
- Vehicle metrics: `explicit_schemas.py:924-959`

---

### Entities (Vendors / Businesses)

| Field | Type | Location | Notes |
|-------|------|----------|-------|
| `uei` | str | explicit_schemas.py:557 | Unique Entity ID (required, primary key) |
| `legal_business_name` | str | explicit_schemas.py:498 | Official company name |
| `dba_name` | str | explicit_schemas.py:453 | Doing Business As name |
| `cage_code` | str | explicit_schemas.py:442 | CAGE code for DoD contracting |
| `business_types` | dict | explicit_schemas.py:439 | Business classifications |
| `primary_naics` | str | explicit_schemas.py:514 | Primary NAICS code |
| `naics_codes` | dict | explicit_schemas.py:504 | All NAICS codes (expandable) |
| `psc_codes` | dict | explicit_schemas.py:521 | All PSC codes (expandable) |
| `sba_business_types` | dict | explicit_schemas.py:545 | SBA categories (8(a), HUBZone, WOSB, etc.) |
| **SAM.gov Registration** | | | |
| `registration_status` | str | explicit_schemas.py:532 | Active/Inactive/Expired |
| `sam_registration_date` | date | explicit_schemas.py:542 | When SAM registration started |
| `sam_activation_date` | date | explicit_schemas.py:536 | When SAM became active |
| `sam_expiration_date` | date | explicit_schemas.py:539 | **When SAM registration expires** |
| `uei_status` | str | explicit_schemas.py:564 | UEI status (Active/Inactive) |
| `uei_creation_date` | date | explicit_schemas.py:558 | UEI assigned date |
| `uei_expiration_date` | date | explicit_schemas.py:561 | UEI expiration date |
| **Exclusion & Compliance** | | | |
| `exclusion_status_flag` | str | explicit_schemas.py:480 | SAM exclusion status (debarred, etc.) |
| `exclusion_url` | str | explicit_schemas.py:483 | Link to SAM exclusions database |
| **Ownership & Hierarchy** | | | |
| `highest_owner` | dict | explicit_schemas.py:490 | Ultimate parent company (expandable) |
| `immediate_owner` | dict | explicit_schemas.py:491 | Direct parent company (expandable) |
| `relationships` | list[str] | explicit_schemas.py:535 | Affiliate relationships (list of relationship types) |
| **Structure & Location** | | | |
| `entity_type_code` | str | explicit_schemas.py:472 | Business entity type (Corporation, LLC, etc.) |
| `entity_type_desc` | str | explicit_schemas.py:475 | Human-readable entity type |
| `entity_structure_code` | str | explicit_schemas.py:466 | Organization structure (parent, subsidiary, etc.) |
| `entity_structure_desc` | str | explicit_schemas.py:469 | Description of structure |
| `physical_address` | Location | explicit_schemas.py:511 | Address (expandable) |
| `mailing_address` | Location | explicit_schemas.py:501 | Mailing address (expandable) |
| `congressional_district` | str | explicit_schemas.py:444 | Congressional district (geo-derived) |
| **Federal Engagement** | | | |
| `federal_obligations` | dict | explicit_schemas.py:484 | Aggregated award data by year (expandable) |
| `capabilities` | str | explicit_schemas.py:443 | Business capabilities/services offered |
| `keywords` | str | explicit_schemas.py:494 | Entity-provided keywords |
| `description` | str | explicit_schemas.py:454 | Entity-provided business description |

**Key Sources:**
- Entity schema: `explicit_schemas.py:438-565`
- Models.py Entity definition: `models.py:475-485`

---

### Subawards (Prime-Sub Relationships)

| Field | Type | Location | Notes |
|-------|------|----------|-------|
| `key` | str | explicit_schemas.py:1298 | Subaward ID |
| `award_key` | str | explicit_schemas.py:1299 | Prime award key (FK to award) |
| `piid` | str | explicit_schemas.py:1300 | Prime award PIID (denormalized) |
| `usaspending_permalink` | str | explicit_schemas.py:1301 | Direct USASpending URL |
| **Prime Awardee (denormalized for filter parity)** | | | |
| `prime_awardee_name` | str | explicit_schemas.py:1305 | Prime vendor name |
| `prime_awardee_uei` | str | explicit_schemas.py:1308 | Prime vendor UEI |
| **Subawardee (denormalized)** | | | |
| `recipient_name` | str | explicit_schemas.py:1321 | Sub vendor name |
| `recipient_uei` | str | explicit_schemas.py:1333 | Sub vendor UEI |
| `recipient_dba_name` | str | explicit_schemas.py:1315 | Sub vendor DBA |
| `recipient_parent_uei` | str | explicit_schemas.py:1330 | Sub's parent UEI |
| `recipient_parent_name` | str | explicit_schemas.py:1327 | Sub's parent name |
| `recipient_business_types` | list[str] | explicit_schemas.py:1312 | Sub's business classifications |
| **Expandable Nested Objects** | | | |
| `prime_recipient` | RecipientProfile | explicit_schemas.py:1372 | Prime entity profile |
| `subaward_recipient` | RecipientProfile | explicit_schemas.py:1386 | Sub entity profile |
| `subaward_details` | SubawardDetails | explicit_schemas.py:1379 | Amount, action_date, fiscal_year, type |
| `awarding_office` | AwardOffice | explicit_schemas.py:1337 | Contracting office |
| `funding_office` | AwardOffice | explicit_schemas.py:1344 | Funding office |
| `place_of_performance` | dict | explicit_schemas.py:1365 | City, state, zip, country |
| `highly_compensated_officers` | list | explicit_schemas.py:1358 | Officers and compensation (FSRS) |
| `fsrs_details` | FsrsDetails | explicit_schemas.py:1351 | Submission provenance |

**SubawardDetails Structure:**
- `amount` (Decimal): subaward value
- `action_date` (date): transaction date
- `fiscal_year` (int): FY
- `number` (str): subaward number
- `type` (str): subaward type
- `description` (str): description

**API Filters for Subawards (list_subawards):**
- `award_key`: prime award key
- `prime_uei`: prime vendor UEI
- `sub_uei`: subawardee UEI
- `awarding_agency`: agency code
- `fiscal_year`, `fiscal_year_gte`, `fiscal_year_lte`
- `funding_agency`

**Key Sources:**
- Subaward schema: `explicit_schemas.py:1296-1393`
- SubawardDetails: `explicit_schemas.py:1261-1268`
- Highly compensated officers: `explicit_schemas.py:1291-1294`
- Client subawards method: `client.py:1249-1301`

---

### Opportunities (SAM.gov Solicitations)

| Field | Type | Location | Notes |
|-------|------|----------|-------|
| `opportunity_id` | str | explicit_schemas.py:644 | SAM.gov opportunity ID (unique) |
| `title` | str | explicit_schemas.py:667 | Solicitation title |
| `solicitation_number` | str | explicit_schemas.py:664 | Solicitation number (human-readable) |
| `description` | str | explicit_schemas.py:620 | Full solicitation description |
| `naics_code` | int | explicit_schemas.py:628 | Primary NAICS |
| `psc_code` | str | explicit_schemas.py:653 | Primary PSC |
| `response_deadline` | datetime | explicit_schemas.py:659 | Proposal deadline |
| `first_notice_date` | datetime | explicit_schemas.py:621 | Initial posting date |
| `last_notice_date` | datetime | explicit_schemas.py:624 | Latest update date |
| `active` | bool | explicit_schemas.py:611 | Whether solicitation is active |
| `award_number` | str | explicit_schemas.py:619 | Award number (if already awarded) |
| `set_aside` | dict | explicit_schemas.py:663 | Set-aside category |
| `place_of_performance` | dict | explicit_schemas.py:647 | PoP (expandable) |
| `office` | Office | explicit_schemas.py:641 | Contracting office |
| `primary_contact` | Contact | explicit_schemas.py:650 | Contact person |
| `attachments` | list | explicit_schemas.py:612 | SAM attachments |
| `notice_history` | list | explicit_schemas.py:634 | Posting history |
| `meta` | dict | explicit_schemas.py:627 | Metadata |
| `sam_url` | str | explicit_schemas.py:662 | Direct SAM.gov URL |

**Note on Opportunity-Award Linking:**
Tango exposes opportunities via `/api/opportunities/` but does **NOT provide an explicit link to awards**. Linkage is inferred via:
- Vehicles expose `solicitation_identifier` (matches Opportunity ID)
- Contracts/IDVs expose `solicitation_identifier` (matches Opportunity ID)

**Key Sources:**
- Opportunity schema: `explicit_schemas.py:610-668`

---

### Transactions (Modification History)

| Field | Type | Location | Notes |
|-------|------|----------|-------|
| `modification_number` | str | explicit_schemas.py:190 | Modification sequence number (0 = base) |
| `transaction_date` | date | explicit_schemas.py:194 | Date of modification |
| `action_type` | dict | explicit_schemas.py:188 | Action type — {code, description} (e.g., "New", "Exercise Option", "Extent", "Modify") |
| `obligated` | Decimal | explicit_schemas.py:193 | Amount obligated in this modification |
| `description` | str | explicit_schemas.py:189 | Modification description |

**Reconstruction Logic:**
- Transactions are ordered by `modification_number`
- `obligated` per-transaction can be summed to reconstruct award lifecycle
- Total is reconstructible from mod sequence
- **No explicit option-exercise flag**: must parse `action_type.description` for "Exercise" or "Option"

**Key Sources:**
- Transaction schema: `explicit_schemas.py:187-197`

---

## 2. Recompete-Relevant Fields: Complete Inventory

### Period-of-Performance End Dates

| Model | Field | Type | Location | Recompete Signal |
|-------|-------|------|----------|------------------|
| IDV | `period_of_performance.last_date_to_order` | date | explicit_schemas.py:61 | **Primary**: expiring incumbent |
| IDV | `period_of_performance.start_date` | date | explicit_schemas.py:60 | Baseline for PoP duration |
| Vehicle | `last_date_to_order` | date | explicit_schemas.py:1130 | Rollup of all IDVs under vehicle |
| Vehicle | `latest_award_date` | date | explicit_schemas.py:1127 | Most recent activity (staleness indicator) |
| Contract | *N/A* | *N/A* | *N/A* | Contracts inherit PoP from parent IDV via `parent_award` |

**Filtering Capability:**
- `list_idvs(last_date_to_order_gte=date, last_date_to_order_lte=date)`: client.py:798-799
- `list_vehicles(last_date_to_order_after=date, last_date_to_order_before=date)`: client.py:1559-1560

---

### Option Years & Exercise Status

| Signal | Model | Field(s) | Location | Status |
|--------|-------|----------|----------|--------|
| Base value | Contract | `base_and_exercised_options_value` | explicit_schemas.py:244 | Available (base + exercised only, not unexercised) |
| Total with options | Contract | `total_contract_value` | explicit_schemas.py:409 | Available (includes all potential options) |
| Option exercise flag | IDV/Contract | `transactions[].action_type.description` | explicit_schemas.py:188 | **Must parse**: no explicit discriminator; parse "Exercise Option", "Exercise", "Option" from description |
| Exercise dates | IDV/Contract | `transactions[].transaction_date` | explicit_schemas.py:194 | Available (when option was exercised) |
| Unexercised value | *Derived* | `total_contract_value - base_and_exercised_options_value` | *Calculation* | Can derive; no explicit field |

**Limitation:**
Tango does NOT expose:
- Option period count (must count distinct option exercises from transactions)
- Option period end dates individually
- Structured "remaining option value" breakdown

---

### Solicitation-Award Linkage (Recompete Inference)

| Dimension | Field | Model | Location | Linking Mechanism |
|-----------|-------|-------|----------|------------------|
| Solicitation ID | `solicitation_identifier` | Contract, IDV, Vehicle | explicit_schemas.py:396, 809, 1091 | Denormalized on award; matches Vehicle `solicitation_identifier` |
| Opportunity ID | `opportunity_id` | Vehicle | explicit_schemas.py:1156 | Denormalized from SAM.gov Opportunity |
| NAICS matching | `naics_code` | Contract, IDV, Vehicle, Opportunity | explicit_schemas.py:329, 970, 1157, 628 | Can match to infer scope continuity |
| PSC matching | `psc_code` | Contract, IDV, Vehicle, Opportunity | explicit_schemas.py:362, 971, 1163, 653 | Can match to infer scope continuity |
| Agency matching | `awarding_office` / `agency_id` | Contract, IDV, Vehicle | explicit_schemas.py:241, 797, 1097 | Can match to infer same procuring organization |

**Recompete Detection Algorithm (Vindor must implement):**
1. Query vehicles by `last_date_to_order_before=today + 6 months`
2. Identify expiring vehicles with active incumbents
3. For each expiring vehicle: capture `solicitation_identifier`, `naics_code`, `psc_code`, `agency_id`
4. Monitor `/api/opportunities/` for new postings with matching NAICS/PSC/agency within 90 days of expiration
5. If prior awardee is bidding on new opportunity: flag as recompete (incumbent)

**Limitation:**
Tango does **NOT provide**:
- Explicit field linking Opportunity to prior Awards
- "Successor contract" pointer
- No forecast-to-award connection
- No prior-award lookup in Opportunity payload

---

### Parent Award Linkage

| Field | Type | Model | Location | Use Case |
|-------|------|-------|----------|----------|
| `parent_award` | ParentAward | Contract | explicit_schemas.py:342 | Task orders know their parent IDV |
| `parent_award.key` | str | Contract | explicit_schemas.py:146 | FK to parent IDV |
| `parent_award.piid` | str | Contract | explicit_schemas.py:147 | Parent PIID (denormalized) |
| `parent_award.idv_type` | str | Contract | explicit_schemas.py:145 | Parent IDV type (e.g., "GWAC") |

**Parent IDV on Task Orders:**
Contract → `parent_award.key` → IDV.key (inverse: IDV → `awards`/`orders` expansion)

---

### Extension History

| Signal | Field | Type | Location | Availability |
|--------|-------|------|----------|----------------|
| All mods | `transactions` | list[AwardTransaction] | explicit_schemas.py:415, 1042 | Fully available (sorted by modification_number) |
| Mod sequence | `modification_number` | str | explicit_schemas.py:190 | Available (0 = base, 1+ = modifications) |
| Mod date | `transaction_date` | date | explicit_schemas.py:194 | Available |
| Mod type | `action_type` | dict | explicit_schemas.py:188 | Available (code + description); must parse for "Extend", "Exercise", etc. |
| Mod obligated | `obligated` | Decimal | explicit_schemas.py:193 | Available per-transaction |

**Extension Count Algorithm:**
Count distinct `action_type.description` values matching "Extend%" or "Modify%" across transactions.

**Limitation:**
- No explicit "extension_count" field
- No "extension_end_date" rollup
- Must reconstruct from transaction history

---

## 3. Pricing-Relevant Fields: Complete Inventory

### Base & Obligated Values

| Field | Type | Model | Location | Definition |
|-------|------|-------|----------|-----------|
| `base_and_exercised_options_value` | Decimal | Contract, IDV | explicit_schemas.py:244, 976 | Sum of base + all exercised options (NOT including unexercised) |
| `total_contract_value` | Decimal | Contract, IDV | explicit_schemas.py:409, 972 | Full potential value (base + all possible options, exercised or not) |
| `obligated` | Decimal | Contract, IDV | explicit_schemas.py:341, 980 | Currently obligated/funded amount (subset of `total_contract_value`) |

**Pricing Hierarchy:**
```
obligated (current funding) ≤ base_and_exercised_options_value (base + exercised) ≤ total_contract_value (ceiling)
```

**Difference Values (Vindor derives):**
- Unexercised potential = `total_contract_value - base_and_exercised_options_value`
- Remaining to obligate = `total_contract_value - obligated`

---

### Modification-Level Pricing

| Field | Type | Location | Use Case |
|-------|------|----------|----------|
| `transactions[].obligated` | Decimal | explicit_schemas.py:193 | Per-modification obligated amount |
| `transactions[].modification_number` | str | explicit_schemas.py:190 | Sequence order (0 = base, 1+ = mods) |
| `transactions[].transaction_date` | date | explicit_schemas.py:194 | When obligation occurred |

**Reconstruction:**
Sum all `transactions[].obligated` to get total obligation history; sort by `transaction_date` to reconstruct timeline.

---

### Vehicle/IDIQ-Level Rollups

| Field | Type | Model | Location | Definition |
|-------|------|-------|----------|-----------|
| `vehicle_obligations` | Decimal | Vehicle | explicit_schemas.py:1140 | Sum of obligated across all IDVs |
| `vehicle_contracts_value` | Decimal | Vehicle | explicit_schemas.py:1143 | Sum of contract values across all task orders |
| `total_obligated` | Decimal | Vehicle | explicit_schemas.py:1137 | Overall vehicle obligation |
| `idv_obligations` | Decimal | IDV (when queried as vehicle awardee) | explicit_schemas.py:1080 | Obligations under this specific IDV |
| `idv_contracts_value` | Decimal | IDV (when queried as vehicle awardee) | explicit_schemas.py:1083 | Contract value under this IDV |

**Note:** These are denormalized rollups computed at sync time by Tango API; Vindor should cache.

---

### Subaward Pricing

| Field | Type | Location | Definition |
|-------|------|----------|-----------|
| `subawards_summary.count` | int | explicit_schemas.py:180 | Number of subawards |
| `subawards_summary.total_amount` | Decimal | explicit_schemas.py:182 | Sum of all subaward amounts |
| `subaward_details.amount` | Decimal | explicit_schemas.py:1263 | Individual subaward value |

**Prime-Sub Flow:**
1. Query Contract/IDV with shape including `subawards_summary(*)` → get count + total
2. Query `/api/subawards/?award_key=...` → get full sub list with individual amounts

---

### Pricing Gaps in Tango

| Missing | Reason | Workaround |
|---------|--------|-----------|
| Per-unit pricing | FPDS line-item detail not exposed | N/A (Tango aggregates to award level) |
| Labor rates | FPDS detail not exposed | N/A |
| Cost breakdown (labor/material/ODC) | Not in Tango schema | N/A |
| FY-by-FY obligation breakdown | Provided only per-transaction | Reconstruct from transactions filtered by fiscal_year |
| Burn-down / velocity | Not computed | Must compute in Vindor from obligated over time |

---

## 4. Relationship & Network Fields: Traversal Patterns

### Vehicle → IDVs → Contracts (Hierarchical Traversal)

**Pattern:**
```
Vehicle (solicitation-centric grouping)
  ├─ awardees (IDV list; denormalized rollup fields)
  │   ├─ uuid, key, piid
  │   ├─ order_count (# task orders under this IDV)
  │   ├─ idv_obligations
  │   ├─ idv_contracts_value
  │   └─ recipient (awardee entity)
  └─ orders (Contract list; all task orders under any IDV on vehicle)
      ├─ key, piid, award_date
      ├─ obligated, total_contract_value
      └─ parent_award (back-reference to IDV)
```

**API Calls:**
- `client.get_vehicle(uuid, shape=...)`: returns vehicle with optional `awardees(...)` and `competition_details(...)`
- `client.list_vehicle_awardees(uuid, ...)`: returns IDVs under vehicle with rollup fields
- `client.list_vehicle_orders(uuid, ...)`: returns contracts under vehicle

**Location in Code:**
- Vehicle awardees: explicit_schemas.py:1171-1173
- Vehicle orders: IDV `awards`/`orders` expansion; explicit_schemas.py:1063-1069

---

### Prime-Sub Relationships

**Pattern:**
```
Prime Award (Contract or IDV)
  ├─ subawards_summary (count, total_amount)
  └─ Subaward (via /api/subawards/?award_key=...)
      ├─ prime_awardee_name, prime_awardee_uei (denormalized)
      ├─ recipient_name, recipient_uei (sub vendor)
      ├─ subaward_details (amount, action_date, fiscal_year)
      ├─ prime_recipient (entity profile)
      └─ subaward_recipient (entity profile)
```

**API Calls:**
- `client.list_subawards(award_key=...)`: filter subs by prime award
- `client.list_subawards(prime_uei=...)`: all subs where vendor is prime
- `client.list_subawards(sub_uei=...)`: all subs where vendor is subcontractor

**Location in Code:**
- Subaward schema: explicit_schemas.py:1296-1393
- Client method: client.py:1249-1301

---

### Entity Ownership Hierarchy

**Pattern:**
```
Entity (UEI)
  ├─ highest_owner (ultimate parent; expandable)
  │   └─ {uei, name, dba_name, ...}
  ├─ immediate_owner (direct parent; expandable)
  │   └─ {uei, name, dba_name, ...}
  └─ relationships (list of relationship types, not full entity links)
```

**Note:** Ownership links are NOT bidirectional in API; must query entities separately to find subsidiaries.

**Location:** explicit_schemas.py:490-493

---

### Teaming & Collaboration (Limited)

**What Tango Exposes:**
- Prime-sub one-level only (no multi-tier teaming)
- Subaward recipient type (JV partner, subcontractor, etc.) inferred from subaward record

**What Tango Does NOT Expose:**
- Explicit joint venture flag
- Co-prime partnerships
- Teaming agreement references

**Vindor Workaround:**
Index subawards to infer teaming: if Vendor A is prime on Award X and Vendor B is sub on X, they teamed on X.

---

### Entity & Opportunity Lookup Denormalization

**Denormalized Fields (for filter parity without expansion):**
- Contracts: `recipient` embedded as dict (but can expand for rich profile)
- Subawards: `prime_awardee_name`, `recipient_name`, `recipient_uei` (to filter without expansion)
- Vehicles: `solicitation_title`, `solicitation_date` (from SAM.gov opportunity)

**Performance Note:** Denormalized fields allow filtering without N+1 queries; Tango follows this pattern throughout.

---

## 5. Ruby Translation Notes: ActiveRecord Modeling Guidance

### 1. Contract/IDV/Vehicle Hierarchy: STI vs Separate Tables

**Tango's Approach:**
- Separate API endpoints: `/api/contracts/`, `/api/idvs/`, `/api/vehicles/`
- No explicit discriminator field in schema
- Vehicles are synthetic groupings (not FPDS entities, computed by Tango)

**Recommendation for Vindor (Rails):**

**Option A: Single Table Inheritance (STI) — RECOMMENDED for simplicity**
```ruby
class Award < ApplicationRecord
  self.inheritance_column = :award_type
  
  # award_type: 'Contract', 'IDV', 'Vehicle' (or 'DefinedContractAward', 'IDIQ', 'SyntheticVehicle')
end

class Contract < Award
  # Fields: key, piid, obligated, total_contract_value, parent_award_key, ...
  belongs_to :parent_idv, class_name: 'Award', foreign_key: 'parent_award_key', optional: true
end

class IDV < Award
  # Fields: key, piid, last_date_to_order, ...
  has_many :child_contracts, class_name: 'Contract', foreign_key: 'parent_award_key'
end

class Vehicle < Award
  # Fields: uuid (PRIMARY KEY, not id), solicitation_identifier (unique), ...
  # Note: Vehicles may not be FPDS awards; they're Tango synthetics
  has_many :idvs
  has_many :task_orders, through: :idvs, source: :child_contracts
end
```

**Pros:**
- Single search/filter logic in base class
- Shared pricing, PoP, transaction tables via FK
- Simpler UI queries

**Cons:**
- Need to null-check IDV-only fields in Contract queries
- Vehicle is synthetic (not FPDS); may confuse downstream joins

---

**Option B: Separate Tables with Polymorphic Has-Many**
```ruby
class Awardee < ApplicationRecord
  # Base: key, piid, obligated, total_contract_value, ...
  has_many :transactions, as: :awardable
end

class Contract < Awardee
  belongs_to :parent_idv, class_name: 'IDV', foreign_key: 'parent_award_key', optional: true
end

class IDV < Awardee
  has_many :contracts, class_name: 'Contract', foreign_key: 'parent_award_key', primary_key: 'key'
  has_many :transactions, as: :awardable
end

class Vehicle < ApplicationRecord
  # Synthetic grouping: uuid, solicitation_identifier, ...
  has_many :idvs, foreign_key: 'vehicle_uuid', primary_key: 'uuid'
  has_many :task_orders, through: :idvs, source: :contracts
end
```

**Pros:**
- Cleaner schema (no nulls for IDV-specific fields)
- Vehicles can be separate (they're not FPDS)

**Cons:**
- More tables, more joins
- Harder to query across types

---

**Vindor Guidance:**
Use **Option A (STI)** initially. Tango's separation is API-level; Vindor's DB can be unified. If `Vehicle` becomes too much overhead (many nulls), migrate to Option B with `Awardee` as base.

---

### 2. Modification History: Separate Table vs JSONB

**Tango Pattern:**
- `transactions` is a list expansion on Contract/IDV
- Each transaction: {modification_number, transaction_date, action_type, obligated, description}

**Rails Options:**

**Option A: Separate `AwardTransaction` Table — RECOMMENDED**
```ruby
class Award < ApplicationRecord
  has_many :transactions, class_name: 'AwardTransaction', foreign_key: 'award_key', primary_key: 'key'
end

class AwardTransaction < ApplicationRecord
  belongs_to :award, foreign_key: 'award_key', primary_key: 'key'
  
  validates :modification_number, :transaction_date, :obligated, presence: true
  
  # Indexes for scoring queries
  index [:award_key, :modification_number]
  index [:award_key, :transaction_date]
end
```

**Pros:**
- Queryable: find all options exercised by date, all extensions, etc.
- Indexes enable recompete scoring (e.g., `Award.joins(:transactions).where(transactions: {action_type: 'Exercise %'})`)
- Can compute burned, remaining, velocity

**Cons:**
- More storage
- Requires sync of transaction history (denormalization burden)

---

**Option B: JSONB Column on Award**
```ruby
class Award < ApplicationRecord
  # transactions: [{modification_number, transaction_date, action_type, obligated, ...}]
  store :transactions, accessors: [:transactions_list], coder: JSON
end
```

**Pros:**
- Single record to fetch
- No join penalty
- Easier sync from Tango (just store JSON blob)

**Cons:**
- Hard to query (can use PostgreSQL `@>` operator, but clunky)
- No indexes on nested fields
- Difficult to compute aggregate stats (burned, velocity)

---

**Recommendation:** **Use Option A (separate table)**. Vindor's scoring needs queryable history (e.g., "IDVs with >3 option exercises in last 2 years"). JSONB won't scale.

---

### 3. Entity Model: Denormalize UEI or Foreign Key?

**Tango's Approach:**
- Vendors are denormalized on awards: `recipient{uei, name, cage, business_types, ...}`
- Separate `/api/entities/` endpoint for full profile

**Rails Options:**

**Option A: Denormalize into Award (matches Tango) — RECOMMENDED for indexing**
```ruby
class Award < ApplicationRecord
  # Denormalized recipient fields:
  # recipient_uei, recipient_name, recipient_dba, recipient_cage, recipient_business_types (jsonb)
  
  index :recipient_uei  # For recompete: "who won before?"
end

class Entity < ApplicationRecord
  # Canonical entity record: uei, legal_name, cage, naics_codes, ...
  has_many :awards, foreign_key: 'recipient_uei', primary_key: 'uei'
end
```

**Pros:**
- Fast award queries by vendor (index on recipient_uei)
- Tango alignment (denormalization matches API)
- Can fetch award list without joining Entity

**Cons:**
- Duplication: same vendor name may be spelled differently
- Sync burden: update Entity, must update all Awards

---

**Option B: Foreign Key Only**
```ruby
class Award < ApplicationRecord
  belongs_to :awardee, class_name: 'Entity', foreign_key: 'awardee_uei', primary_key: 'uei'
end

class Entity < ApplicationRecord
  has_many :awards, foreign_key: 'awardee_uei', primary_key: 'uei'
end
```

**Pros:**
- Single source of truth for entity data
- Easy to update vendor profile (one row)

**Cons:**
- Always need to join Entity to get recipient details
- Slower (especially for scoring on vendor name)

---

**Recommendation:** **Use Option A (denormalize)**. Tango does it for filter parity; Vindor should too. Index `recipient_uei` for recompete queries ("find awards to this vendor in last 5 years"). Keep Entity as canonical, but denormalize onto Awards for query speed.

---

### 4. Opportunity ↔ Award Linking

**Challenge:** Tango does NOT explicitly link Opportunity to Awards.

**Linkage Mechanism (Vindor must implement):**
- Opportunity has `opportunity_id` (SAM.gov)
- Vehicle has `opportunity_id` + `solicitation_identifier` (matches)
- IDV/Contract has `solicitation_identifier` (matches Vehicle)

**Rails Model:**
```ruby
class Opportunity < ApplicationRecord
  # Sam.gov source
  # opportunity_id, title, solicitation_number, naics_code, psc_code, ...
  
  has_many :vehicles, foreign_key: 'opportunity_id', primary_key: 'opportunity_id'
  has_many :idvs, through: :vehicles
  has_many :contracts, through: :idvs, source: :child_contracts
end

class Vehicle < ApplicationRecord
  belongs_to :opportunity, foreign_key: 'opportunity_id', primary_key: 'opportunity_id', optional: true
end
```

**Index Strategy:**
```ruby
add_index :opportunities, :opportunity_id, unique: true
add_index :vehicles, :opportunity_id
add_index :awards, :solicitation_identifier  # For denorm contract/IDV search
```

---

### 5. Vehicle ↔ Holders ↔ TaskOrders

**Tango Hierarchy:**
```
Vehicle (uuid)
  → awardees (list of IDVs under this vehicle)
  → awards/orders (list of all contracts under any IDV)
```

**Rails Model:**
```ruby
class Vehicle < ApplicationRecord
  self.primary_key = :uuid  # Important: Tango uses uuid, not auto-incrementing id
  
  has_many :idvs, foreign_key: 'vehicle_uuid', primary_key: 'uuid'
  has_many :task_orders, through: :idvs, source: :child_contracts
end

class IDV < Award
  belongs_to :vehicle, foreign_key: 'vehicle_uuid', primary_key: 'uuid', optional: true
  has_many :task_orders, class_name: 'Contract', foreign_key: 'parent_award_key', primary_key: 'key'
end

class Contract < Award
  belongs_to :parent_idv, class_name: 'IDV', foreign_key: 'parent_award_key', primary_key: 'key', optional: true
  belongs_to :vehicle, through: :parent_idv
end
```

**Index Strategy:**
```ruby
add_index :idvs, :vehicle_uuid
add_index :contracts, :parent_award_key  # For parent IDV lookup
add_index :vehicles, :solicitation_identifier, unique: true
```

---

### 6. Subawards: Separate Table with FK

**Rails Model:**
```ruby
class Subaward < ApplicationRecord
  belongs_to :prime_award, foreign_key: 'award_key', primary_key: 'key', class_name: 'Award'
  belongs_to :prime, foreign_key: 'prime_awardee_uei', primary_key: 'uei', class_name: 'Entity'
  belongs_to :sub, foreign_key: 'recipient_uei', primary_key: 'uei', class_name: 'Entity'
  
  validates :key, :award_key, presence: true
end

class Entity < ApplicationRecord
  has_many :primes, class_name: 'Subaward', foreign_key: 'prime_awardee_uei', primary_key: 'uei'
  has_many :subs, class_name: 'Subaward', foreign_key: 'recipient_uei', primary_key: 'uei'
end
```

**Index Strategy:**
```ruby
add_index :subawards, :award_key         # Find subs under a prime
add_index :subawards, :prime_awardee_uei # Find all primes by vendor
add_index :subawards, :recipient_uei     # Find all subs by vendor
```

**Teaming Index (for Vindor's "who partners with whom" analysis):**
```ruby
create_table :teaming_pairs do |t|
  t.string :vendor_a_uei
  t.string :vendor_b_uei
  t.integer :sub_count    # How many times A subbed to B (or vice versa)
  t.timestamps
end

add_index :teaming_pairs, [:vendor_a_uei, :vendor_b_uei], unique: true
```

**Population Logic:**
```ruby
# After syncing subawards
Subaward.select('DISTINCT prime_awardee_uei, recipient_uei')
  .group_by { |s| [s.prime_awardee_uei, s.recipient_uei].sort }
  .each do |pair, records|
    TeammingPair.find_or_create_by(vendor_a_uei: pair[0], vendor_b_uei: pair[1])
      .update(sub_count: records.size)
  end
```

---

### 7. Recompete Scoring: Which Fields to Index

**Critical Indexes for Recompete Detection:**

| Field | Model | Index Type | Use Case |
|-------|-------|-----------|----------|
| `last_date_to_order` | IDV, Vehicle | Range | "Find expiring incumbents" |
| `recipient_uei` | Award | Standard | "Find all awards to vendor X" |
| `solicitation_identifier` | Award, Vehicle | Standard | "Link awards to solicitations" |
| `naics_code` | Award, Vehicle, Opportunity | Standard | "Find scope-equivalent solicitations" |
| `psc_code` | Award, Vehicle, Opportunity | Standard | "Find scope-equivalent solicitations" |
| `award_date` | Award | Range | "Find recent awards (activity signal)" |
| `obligated` | Award | Range | "Find large awards (incumbent strength)" |
| `parent_award_key` | Contract | Standard | "Find task orders under IDV" |
| `award_key` | Subaward | Standard | "Find subawards of award" |
| `prime_awardee_uei` | Subaward | Standard | "Find what vendor typically subs to" |
| `recipient_uei` | Subaward | Standard | "Find what vendor subs on" |

**Composite Indexes (High-Value):**
```ruby
# Recompete query: "Find all awards to vendor X in specific NAICS/PSC expiring in next 6 months"
add_index :awards, [:recipient_uei, :naics_code, :last_date_to_order]

# Vehicle rollup: "Find all vehicles by agency with metrics"
add_index :vehicles, [:agency_id, :last_date_to_order]
```

---

## 6. Gaps Analysis

### 6a. Fields Tango Exposes that Vindor CAN'T Derive from SAM.gov + USASpending Alone

These are from FPDS or Tango proprietary enrichment:

| Field | Model | Source | Reason |
|-------|-------|--------|--------|
| `base_and_exercised_options_value` | Contract, IDV | FPDS | Line-item aggregation from FPDS; not in USASpending |
| `idv_type` {code, description} | IDV | FPDS | FPDS Type-of-Indefinite-Contract code; not in public USASpending |
| `multiple_or_single_award_idv` | IDV | FPDS | FPDS competitive set flag; not exposed in USASpending |
| `type_of_idc` | IDV | FPDS | Indefinite contract type; not in public USASpending |
| `competition.*` (full object) | Contract, IDV | FPDS | Solicitation date, number of offers, competition type; USASpending has limited competition data |
| `legislative_mandates.*` | Contract, IDV | FPDS | Clinger-Cohen, labor standards, etc.; not in USASpending |
| `parent_award` (full link) | Contract | FPDS | Explicit parent IDV key; USASpending does not expose parent award IDs |
| `vehicle_type`, `program_acronym` | Vehicle | Tango | Tango-computed vehicle classification; not in raw FPDS/USASpending |
| `vehicle metrics` (HHI, avg order value, etc.) | Vehicle | Tango | Computed aggregates; Vindor would need to compute from scratch |
| `federal_obligations` (annual breakdown) | Entity | SAM.gov or Tango enrichment | Per-fiscal-year obligated amount; SAM.gov may not expose year-by-year breakdown |
| `highly_compensated_officers` (FSRS) | Subaward | FSRS | Separate reporting system; not in core FPDS/USASpending |
| `sam_expiration_date` | Entity | SAM.gov | SAM registration expiration; may differ from UEI expiration |

**Implication:** Vindor cannot replicate Tango's models exactly from public data. Must sync from Tango's normalized feed or reconstruct from FPDS/USASpending + SAM.gov with significant enrichment.

---

### 6b. Fields Tango Does NOT Model that Vindor Needs

These are Tango gaps; Vindor must implement separately:

| Feature | Why Missing in Tango | Vindor Workaround |
|---------|----------------------|-------------------|
| **Explicit recompete flag** | Tango normalizes awards, not opportunities. Recompete inference requires external logic. | Compute in Vindor: match expiring award (last_date_to_order) to new opportunity (naics/psc/agency match) |
| **Incumbent indicator** | Not a Tango concept; would require external lookup. | Query Subawards: if vendor primed >50% on vehicle in last 3 years, flag as incumbent |
| **Option exercise status** | Tango stores transaction history but doesn't flag "exercise" vs other mods. | Parse `action_type.description` for "Exercise", "Option" |
| **Option period count** | Not pre-computed in schema. | Count distinct "Exercise" actions in transactions |
| **Contract continuity** | No "is this a follow-on to a prior award?" field. | Implement in Vindor: match incumbent + scope + agency + expiration date |
| **Protest history** | Tango exposes `/api/protests/` but doesn't link to awards. | Join via `solicitation_number` or `piid` (manual linking) |
| **Debarment status** | Not in Tango; would require SAM.gov exclusion lookup. | Query SAM.gov exclusions separately; cache in Entity record |
| **Past performance metrics** | Not in Tango core. | Would require separate contractor performance data source |
| **Forecast linkage** | Tango has `/api/forecasts/` but no link to awards. | Implement in Vindor: match forecast scope (naics/psc/agency) to expiring awards |
| **Price reasonableness** | Tango does not compute benchmarks. | Implement in Vindor: compute median unit price by NAICS/PSC/vehicle |
| **Option year ceiling growth** | Not pre-computed. | Reconstruct from modifications; calculate (obligated_in_mod_N - obligated_in_mod_N-1) / obligated_in_mod_N-1 |

---

## 7. Recommended Vindor Data Model Architecture

### Core Tables (from Tango)

```ruby
# Contracts, IDVs, Vehicles (STI or separate, per recommendation above)
create_table :awards do |t|
  t.string :award_type  # STI: Contract, IDV, Vehicle
  t.string :key, null: false, index: true  # FPDS key
  t.string :uuid, index: true  # Tango UUID (for vehicles)
  t.string :piid
  t.date :award_date
  t.date :last_date_to_order, index: true  # Critical for recompete
  t.decimal :obligated, precision: 15, scale: 2, index: true
  t.decimal :total_contract_value, precision: 15, scale: 2
  t.decimal :base_and_exercised_options_value, precision: 15, scale: 2
  t.string :recipient_uei, index: true  # Denormalized
  t.string :recipient_name
  t.string :solicitation_identifier, index: true
  t.integer :naics_code, index: true
  t.string :psc_code, index: true
  t.string :set_aside
  t.string :parent_award_key  # FK to parent IDV (for contracts)
  t.string :vehicle_uuid  # FK to vehicle (for IDVs)
  t.string :idv_type_code  # e.g., "GWAC", "IDIQ" (for IDVs)
  t.boolean :is_synthetic_solicitation  # For vehicles
  t.jsonb :transactions  # Store full transaction list (or link to separate table)
  t.jsonb :metadata  # Catch-all for optional fields
  t.timestamps
end

create_table :award_transactions do |t|
  t.string :award_key, null: false, index: true
  t.string :modification_number, null: false
  t.date :transaction_date, null: false
  t.decimal :obligated, precision: 15, scale: 2
  t.string :action_type_code
  t.string :action_type_description
  t.text :description
  t.timestamps
  
  add_index [:award_key, :modification_number], unique: true
end

# Entities
create_table :entities do |t|
  t.string :uei, null: false, primary_key: true  # Non-standard primary key
  t.string :legal_business_name
  t.string :dba_name
  t.string :cage_code
  t.date :sam_expiration_date, index: true  # Registration risk signal
  t.string :registration_status
  t.string :exclusion_status_flag
  t.jsonb :business_types
  t.jsonb :naics_codes
  t.jsonb :psc_codes
  t.jsonb :federal_obligations  # Year-by-year breakdown
  t.string :immediate_owner_uei  # FK
  t.string :highest_owner_uei  # FK
  t.timestamps
end

# Subawards
create_table :subawards do |t|
  t.string :key, null: false, index: true
  t.string :award_key, null: false, index: true
  t.string :prime_awardee_uei, null: false, index: true
  t.string :prime_awardee_name
  t.string :recipient_uei, null: false, index: true
  t.string :recipient_name
  t.decimal :amount, precision: 15, scale: 2
  t.date :action_date
  t.integer :fiscal_year
  t.timestamps
  
  add_index [:prime_awardee_uei, :recipient_uei]  # Teaming analysis
end

# Vehicles (if separate from awards)
create_table :vehicles do |t|
  t.string :uuid, null: false, primary_key: true
  t.string :solicitation_identifier, null: false, unique: true, index: true
  t.string :opportunity_id, index: true
  t.string :agency_id, index: true
  t.string :program_acronym
  t.date :last_date_to_order, index: true
  t.date :latest_award_date
  t.integer :idv_count
  t.integer :order_count
  t.decimal :total_obligated, precision: 15, scale: 2
  t.timestamps
  
  add_index [:agency_id, :last_date_to_order]
end

# Opportunities (from SAM.gov)
create_table :opportunities do |t|
  t.string :opportunity_id, null: false, primary_key: true
  t.string :title
  t.string :solicitation_number
  t.datetime :response_deadline
  t.integer :naics_code, index: true
  t.string :psc_code, index: true
  t.string :set_aside
  t.string :agency_id, index: true
  t.boolean :active
  t.datetime :first_notice_date
  t.datetime :last_notice_date
  t.timestamps
end
```

### Scoring/Enrichment Tables (Vindor-specific)

```ruby
# Recompete intelligence
create_table :recompete_indicators do |t|
  t.string :vehicle_uuid, null: false, index: true
  t.string :incumbent_uei, index: true
  t.float :recompete_likelihood  # 0.0-1.0 score
  t.text :reasoning  # Why flagged
  t.date :estimated_recompete_date
  t.timestamps
end

# Teaming patterns
create_table :teaming_pairs do |t|
  t.string :vendor_a_uei, null: false
  t.string :vendor_b_uei, null: false
  t.integer :sub_count
  t.integer :prime_count
  t.string :vehicle_types  # Vehicles they typically partner on
  t.timestamps
  
  add_index [:vendor_a_uei, :vendor_b_uei], unique: true
end

# Competitor intelligence
create_table :competitor_profiles do |t|
  t.string :uei, null: false, primary_key: true
  t.integer :award_count_24mo
  t.decimal :total_obligations_24mo, precision: 15, scale: 2
  t.decimal :avg_award_value, precision: 15, scale: 2
  t.float :focus_naics  # Primary NAICS concentration
  t.float :focus_vehicles  # Vehicle concentration
  t.integer :sub_frequency  # How often subs (as indicator of size)
  t.timestamps
end
```

---

## 8. Implementation Checklist for Vindor

- [ ] **Sync Strategy:** Define sync frequency (daily? hourly?) and scope (contracts, IDVs, vehicles, entities, subawards separately?)
- [ ] **Primary Key Strategy:** Use Tango's `key` + `uuid` as PK/index; auto-increment `id` secondary for Rails
- [ ] **Type Discriminator:** Choose STI (single type column) or separate tables for Contract/IDV/Vehicle
- [ ] **Modification Sync:** Full history (all transactions) vs summarized (current obligated only)?
- [ ] **Entity Enrichment:** SAM.gov lookup for exclusion status, registration expiration; cache in Entity table
- [ ] **Recompete Scoring:** Implement algorithm (PoP expiration → opportunity match → incumbent check)
- [ ] **Performance Optimization:** Index on `recipient_uei`, `naics_code`, `psc_code`, `last_date_to_order` for scoring queries
- [ ] **Testing:** Verify PoP dates, option counts, transaction history reconstruction
- [ ] **Documentation:** Map Tango field names to Vindor column names for team reference

---

## Citation Manifest

**All facts claim sources in format `file:line-range` within Tango SDK:**

- Models: `/home/charlesgude/github/bidflow/tango-python/tango/models.py` (dataclass definitions)
- Schemas: `/home/charlesgude/github/bidflow/tango-python/tango/shapes/explicit_schemas.py` (FieldSchema definitions)
- Client: `/home/charlesgude/github/bidflow/tango-python/tango/client.py` (API method signatures & filter parameters)

**Example citations:**
- "Contract has obligated field" → `explicit_schemas.py:341` (FieldSchema definition for "obligated" in CONTRACT_SCHEMA)
- "IDVs expose last_date_to_order filter" → `client.py:798-799` (list_idvs method parameter)
- "Vehicle metrics include HHI" → `explicit_schemas.py:928-929` (award_concentration_hhi in VEHICLE_METRICS_SCHEMA)

