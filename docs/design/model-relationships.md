# Model Relationships

> **Purpose:** Mermaid class diagram showing how the gem's typed models,
> value objects, and cross-reference layers relate to each other.
>
> **Audience:** AI agents, contributors who need to understand the object
> graph before writing code.

Related: [[data-models]], [[data-flow]], [[../domain/cross-referencing]]

---

## Class diagram

```mermaid
classDiagram
    direction TB

    class Opportunity {
        +String notice_id
        +String title
        +String solicitation_number
        +Agency agency
        +DateTime posted_at
        +DateTime response_deadline_at
        +Date archive_at
        +String notice_type
        +String naics_code
        +String psc_code
        +String set_aside_code
        +Symbol set_aside
        +PlaceOfPerformance place_of_performance
        +Hash raw
        +related_awards() Array~Award~
        +likely_incumbent() Recipient
        +to_h() Hash
    }

    class Award {
        +String award_id
        +String piid
        +String parent_piid
        +BigDecimal obligated_amount
        +BigDecimal ceiling
        +BigDecimal total_contract_value
        +BigDecimal base_and_exercised_options_value
        +BigDecimal base_and_all_options_value
        +Integer number_of_offers_received
        +CodedValue extent_competed
        +CodedValue type_of_contract_pricing
        +Recipient recipient
        +Agency awarding_agency
        +Agency funding_agency
        +Period period
        +PlaceOfPerformance place_of_performance
        +Hash raw
        +transactions() Array~Transaction~
        +subawards() Array~Subaward~
        +parent_idv() Idv
        +to_h() Hash
    }

    class Idv {
        +String piid
        +String award_type
        +Date last_date_to_order
        +Date period_end_date
        +BigDecimal obligated_amount
        +BigDecimal total_contract_value
        +Recipient recipient
        +Agency awarding_agency
        +child_awards() Array~Award~
        +transactions() Array~Transaction~
        +subawards() Array~Subaward~
    }

    class Transaction {
        +Integer id
        +String modification_number
        +Date action_date
        +BigDecimal federal_action_obligation
        +CodedValue action_type
        +CodedValue type
        +String description
    }

    class Subaward {
        +String id
        +String subaward_number
        +Date action_date
        +BigDecimal amount
        +String prime_award_id
        +String prime_recipient_uei
        +String prime_recipient_name
        +String sub_recipient_uei
        +String sub_recipient_name
        +String naics_code
        +String psc_code
    }

    class Recipient {
        +String uei
        +String duns
        +String name
        +String parent_uei
        +String parent_name
        +String cage_code
        +String registration_status
        +Date sam_expiration_date
        +Array~CodedValue~ business_types
        +Array~CodedValue~ sba_business_types
        +Array naics_list
        +Boolean exclusion_status_flag
        +OwnerReference immediate_owner
        +OwnerReference highest_owner
        +excluded?() Boolean
        +registration_expired?() Boolean
    }

    class Agency {
        +String code
        +String name
        +String cgac
        +Array~String~ aliases
        +to_h() Hash
        +normalize(input) Agency
        +canonical(code) Agency
    }

    class PlaceOfPerformance {
        +String city
        +String state
        +String zip
        +String country_code
        +domestic?() Boolean
    }

    class Period {
        +Date start_date
        +Date end_date
    }

    class CodedValue {
        +String code
        +String description
    }

    class OwnerReference {
        +String uei
        +String name
        +String cage_code
    }

    class Naics {
        +String code
        +String label
        +sector() String
        +subsector() String
        +industry_group() String
        +sector_label() String
    }

    class Psc {
        +String code
        +String label
        +category() String
        +category_label() String
        +product?() Boolean
        +service?() Boolean
    }

    class SetAside {
        +String code
        +String label
        +small_business?() Boolean
        +socioeconomic?() Boolean
        +sole_source?() Boolean
    }

    class CrossReference {
        +awards_for(opportunity) Array~Award~
        +likely_incumbent(awards) Recipient
    }

    class Recompete {
        +expiring(within) Enumerator~Match~
    }

    class Match {
        +Object award
        +Array~Opportunity~ matching_opportunities
    }

    class SearchHandle {
        +each() Enumerator
        +each_batch() Enumerator
        +first(n) Array
    }

    Opportunity "1" --> "0..1" Agency : agency
    Opportunity "1" --> "0..1" PlaceOfPerformance : place_of_performance
    Opportunity "1" --> "*" Award : related_awards()
    Opportunity "1" --> "0..1" Recipient : likely_incumbent()

    Award "1" --> "0..1" Agency : awarding_agency
    Award "1" --> "0..1" Agency : funding_agency
    Award "1" --> "0..1" Recipient : recipient
    Award "1" --> "0..1" Period : period
    Award "1" --> "0..1" PlaceOfPerformance : place_of_performance
    Award "1" --> "*" Transaction : transactions()
    Award "1" --> "*" Subaward : subawards()
    Award "1" --> "0..1" Idv : parent_idv()

    Idv "1" --> "0..1" Agency : awarding_agency
    Idv "1" --> "0..1" Recipient : recipient
    Idv "1" --> "*" Award : child_awards()
    Idv "1" --> "*" Transaction : transactions()
    Idv "1" --> "*" Subaward : subawards()

    Recipient "1" --> "0..1" OwnerReference : immediate_owner
    Recipient "1" --> "0..1" OwnerReference : highest_owner
    Recipient "1" --> "*" CodedValue : business_types
    Recipient "1" --> "*" CodedValue : sba_business_types

    CrossReference ..> Opportunity : uses
    CrossReference ..> Award : produces
    Recompete ..> Idv : produces
    Recompete ..> Award : produces
    Recompete ..> Match : yields
    Match "1" --> "0..1" Idv : award
    Match "1" --> "0..1" Award : award
    Match "1" --> "*" Opportunity : matching_opportunities

    Opportunity ..> SearchHandle : search()
    Award ..> SearchHandle : search()
    Idv ..> SearchHandle : search()
```

## Parent/child traversal

```mermaid
flowchart LR
    IDV[Idv] -->|child_awards| A1[Award]
    IDV -->|child_awards| A2[Award]
    A1 -->|parent_idv| IDV
    A2 -->|parent_idv| IDV
    IDV -->|last_date_to_order| RC[Recompete Signal]
    A1 -->|period.end_date| RC
```

## Cross-reference join keys

```mermaid
flowchart TD
    OPP[Opportunity] -->|agency.code| FILTER[USASpending Filter]
    OPP -->|naics_code| FILTER
    OPP -.->|psc_code| FILTER
    OPP -.->|place_of_performance.state| FILTER
    FILTER -->|POST spending_by_award| AWARDS[Array of Award]
    AWARDS -->|group by recipient UEI| BUCKETS[Bucketed by Recipient]
    BUCKETS -->|obligation sum| DOM[dominant > 50%?]
    DOM -->|yes| INC[Recipient]
    DOM -->|no| NIL[nil]
```

## Data source origins

```mermaid
flowchart LR
    SAM[SAM.gov] --> OPP[Opportunity]
    SAM --> ENT[Recipient enriched]
    USAS[USASpending.gov] --> AWD[Award]
    USAS --> IDV[Idv]
    USAS --> TXN[Transaction]
    USAS --> SUB[Subaward]
    USAS --> REC[Recipient basic]
    SAM -->|agency normalization| AGY[Agency]
    USAS -->|agency normalization| AGY
    SAM -->|set-aside normalization| SA[SetAside]
    USAS -->|set-aside normalization| SA
```
