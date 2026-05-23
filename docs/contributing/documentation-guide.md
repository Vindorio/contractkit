# Code Documentation Guide

> **Purpose:** Defines how we document the gem's code so it stays maintainable as it grows and as contributors rotate through.
>
> **Audience:** Anyone writing or reviewing contractkit code.

Related: [[architecture-overview]]

---

## The two-question test

Before writing a comment or docstring, ask:

1. **Does the code already answer the WHAT?** If the names and structure already show what's happening, don't restate it.
2. **Is the WHY non-obvious?** If a future reader would be surprised by the code's behavior or the choice that led to it, document the why.

Most well-written Ruby methods need a YARD docstring on the signature and zero inline comments. Some need one or two carefully placed comments to capture a constraint that isn't visible in the code itself. Very few need more than that.

## What gets a YARD docstring

**Required:**
- Every public method (anything not under `private`).
- Every public class and module.
- Every public constant whose value isn't self-explanatory.
- Every custom exception class.

**Not required:**
- Private methods (a one-line `# why` comment is fine where useful).
- `attr_reader`/`attr_accessor` declarations on plain value classes (the reader's name + the class's purpose carries it).
- Test code — RSpec descriptions are the documentation.

## YARD tags we use

A small, opinionated set. Don't introduce tags outside this list without discussion.

| Tag | When to use |
|---|---|
| `@param` | Every parameter on every public method. |
| `@return` | Every public method, including methods returning `nil`. |
| `@raise` | Every exception the method can raise *that callers should be prepared for*. (Don't document `ArgumentError` from `nil.foo` — that's a bug, not a contract.) |
| `@example` | At least one for every non-trivial public method. Use realistic examples, not `foo`/`bar`. |
| `@note` | API quirks, performance gotchas, anything the reader needs to know but that doesn't fit param/return semantics. Link to the relevant domain doc with a markdown link. |
| `@see` | Cross-reference to another method, the relevant external API endpoint, or a domain doc. |
| `@deprecated` | Replaces inline `# TODO deprecate` comments. Include the version it'll be removed in. |

Tags we **don't** use:
- `@author` — git blame is authoritative.
- `@version` — the gem version covers this; per-method versions are noise.
- `@since` — only useful when versioning matters, and even then `CHANGELOG.md` covers it.
- `@todo` — file an issue instead. Untracked TODOs rot.

## Example: good and bad YARD

### Good

```ruby
# Searches SAM.gov opportunities matching the given filters.
#
# Pagination is lazy — the returned object only fetches additional pages
# as you iterate. To bound memory or API usage on broad queries, use
# +#take+ or break out of the iteration early.
#
# @param naics [String, Array<String>, nil] one or more 6-digit NAICS codes
# @param set_aside [Symbol, Array<Symbol>, nil] normalized set-aside type(s)
# @param agency [String, nil] free-form agency name; normalized internally
# @param keyword [String, nil] free-text search across title and description
# @param posted_after [Date, nil] inclusive lower bound on posted date
# @param posted_before [Date, nil] inclusive upper bound on posted date
# @return [Contractkit::Pagination::Lazy<Opportunity>] enumerable result
# @raise [Contractkit::AuthenticationError] if no SAM.gov API key is configured
# @raise [Contractkit::RateLimitError] if SAM.gov returns 429 after retries
# @example Find recent 8(a) IT-services opportunities
#   Contractkit::Opportunity.search(
#     naics:     "541512",
#     set_aside: :sba_8a,
#     posted_after: Date.today - 30
#   ).take(50)
# @note SAM.gov accepts only one NAICS per query. Passing an array results
#   in multiple sequential requests; consider this for rate-limit planning.
#   See [SAM.gov pagination behavior](../domain/sam-gov.md#pagination).
def search(naics: nil, set_aside: nil, agency: nil, keyword: nil,
           posted_after: nil, posted_before: nil)
  # ...
end
```

This works because:
- The summary line states the contract in one sentence.
- The `@note` captures a non-obvious behavior (multiple NAICS = multiple requests) that no reader could infer from the signature.
- The example is realistic, not `search(naics: "foo")`.
- The cross-link to the domain doc means a reader debugging unexpected behavior knows where to learn more.

### Bad

```ruby
# Searches opportunities.
#
# @param naics [String] the naics
# @param set_aside [Symbol] the set aside
# @return [Object] the results
def search(naics: nil, set_aside: nil)
  # ...
end
```

This is worse than no doc at all. It restates the obvious, lies about return type, and gives a reader nothing they didn't already have from the method name. **If a YARD doc adds no information, delete it.** A reader who finds an undocumented method knows to read the code; a reader who finds a useless doc may stop reading there.

## Inline comments

The default is **zero**. Add an inline comment only when one of these is true:

1. The code works around a known external bug (link to it, with date).
2. The code makes a non-obvious correctness choice (e.g. "we use BigDecimal here because Float loses cents on amounts >$10M").
3. The code is deliberately ugly to satisfy a constraint (rare; document why).
4. There's a hidden invariant the next reader could break by "tidying up" (e.g. "this loop runs in this order because USASpending's response is sort-unstable").

**Never** add inline comments that:
- Restate what the next line does (`# increment counter` above `counter += 1`).
- Reference the current task or PR (`# fix for #1234` — the PR description has this; the comment rots).
- Explain something a better variable name would explain.
- Are noise headers like `# === setup ===`. Use methods to break up logic, not comment banners.

### Example: a comment that earns its place

```ruby
def parse_state(value)
  # SAM.gov returns place_of_performance.state either as a string ("VA") or as
  # an object with code/name keys. Observed since at least 2024. Treat both.
  # See docs/domain/sam-gov.md "placeOfPerformance.state polymorphism".
  case value
  when String then value
  when Hash   then value["code"] || value[:code]
  end
end
```

This comment captures a real upstream quirk that a future reader, otherwise, would assume is a bug in our code.

## The 3-lines-of-comments rule

If a method needs more than 3 lines of comments inside its body to be understandable, refactor. The smell is usually:

- Multiple unrelated responsibilities in one method (extract methods).
- A non-obvious algorithm without a name (extract to a named method, comment the *signature*).
- Magic numbers or unclear conditionals (extract a constant or a predicate method).

The exception: state machines, parser-style code, and intentional micro-optimizations. These are rare enough that you can recognize them and don't need a rule.

## Domain links

When the WHY is in a domain doc, link to it from the code rather than restating it inline:

```ruby
# @note Recompete detection uses agency + NAICS by default. See
#   [cross-referencing](../docs/domain/cross-referencing.md) for why
#   solicitation number is unreliable as a join key.
def related_awards(...)
```

Domain docs are the source of truth for "how the federal procurement world works." Code comments shouldn't try to be that source — they should defer to it.

## Reviewing docs in PRs

When reviewing a PR, treat docs as code. Specifically:

- A YARD comment that's wrong is worse than no comment. Flag it for fixing or deletion.
- A new public method without a YARD doc is a blocker.
- A new inline comment that restates the code is a request-changes.
- A useful inline comment with no link to the domain doc is a nudge.

Documentation drift is one of the most common sources of "the code says one thing and the docstring says another" bugs. Tight reviewing prevents most of it.

## Open questions for the maintainer

> ⚠️ FILL IN: Pick a YARD theme for generated docs (default, RedCloth, etc.) and pin it in the gemspec.
>
> ⚠️ FILL IN: Decide whether to wire YARD coverage into CI (`yard stats --list-undoc`) and what threshold to enforce.
