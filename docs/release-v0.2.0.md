# Contractkit v0.2.0 Release Tasks

## Current State

- `lib/contractkit/version.rb` says `0.1.0`
- No git tag exists for any release (v0.1.0 was prepared but never tagged)
- M4 work (recompete, pricing, IDVs, transactions, entities, subawards, FPDS) is all merged to `main` but unreleased
- README still says "0.1.0 release candidate" in status section
- Changelog has [Unreleased] section with all the M4 additions
- Gemspec points to `gudetimes1234/contractkit` repo (should be `VindorIO/contractkit`)

## Version Bump

`0.1.0` → `0.2.0`

SemVer: MINOR because this adds new public methods, new models (Idv, Transaction, Subaward), new data sources (FPDS client, SAM Entities client), and new modules (Recompete). Per the changelog's own policy:
> Pre-1.0 (0.x.y): MINOR may make breaking changes; PATCH won't.

## Tasks

### Task 1 — Bump version and finalize CHANGELOG

**Files:** `lib/contractkit/version.rb`, `CHANGELOG.md`

- Change VERSION from `"0.1.0"` to `"0.2.0"`
- In CHANGELOG.md, change `[Unreleased]` to `[0.2.0] - 2026-05-30`
- Add a new `[Unreleased]` section heading above it
- Update the compare links at the bottom:
  - `[Unreleased]: https://github.com/VindorIO/contractkit/compare/v0.2.0...HEAD`
  - `[0.2.0]: https://github.com/VindorIO/contractkit/compare/v0.1.0...v0.2.0`
  - `[0.1.0]: https://github.com/VindorIO/contractkit/releases/tag/v0.1.0`

### Task 2 — Update README.md status section

The README currently says "0.1.0 release candidate" on line 64. Change to:
> **0.2.0 released.** Public repo under MIT license. Published to rubygems.org.
> See [CHANGELOG.md](CHANGELOG.md) for version history.

Also update all GitHub badge URLs from `gudetimes1234` to `VindorIO`.

Update the user-agent string in the Configuration defaults from `contractkit/0.1.0` to `contractkit/0.2.0`.

### Task 3 — Update gemspec for new repo

**File:** `contractkit.gemspec`

Change:
```ruby
spec.homepage = "https://github.com/gudetimes1234/contractkit"
```
To:
```ruby
spec.homepage = "https://github.com/VindorIO/contractkit"
```

Update all metadata URIs to match.

### Task 4 — Verify nothing is broken

- Run `bundle exec ruby -c` on all .rb files that were changed
- Run `bundle exec rspec` to check tests pass
- Verify `bundle exec rake build` works
- Check that all `TODO`/`FIXME` markers in the diff are intentional (not stale)

### Task 5 — Tag and push the release

```bash
git tag -a v0.2.0 -m "v0.2.0 — FPDS, Entities, Transactions, IDVs, Recompete, Subawards"
git push origin main
git push origin v0.2.0
```

### Task 6 — Create GitHub Release

```bash
gh release create v0.2.0 --title "v0.2.0 — FPDS, Entities, Transactions, IDVs, Recompete, Subawards" --notes "$(cat CHANGELOG.md | awk '/^## \[0.2.0\]/{flag=1; next} /^## \[/{flag=0} flag')"
```

### Task 7 — Build and push to RubyGems

At minimum, ensure the gem builds cleanly:
```bash
gem build contractkit.gemspec
```
If RubyGems push is desired (requires OIDC trusted publisher setup), that's a separate infra task.

---

## Summary

| Task | Description | Effort |
|------|-------------|--------|
| 1 | Version bump + CHANGELOG finalize | 5 min |
| 2 | README status update + badge URLs | 5 min |
| 3 | Gemspec repo URL update | 2 min |
| 4 | Verify tests/build | 10 min |
| 5 | Tag and push | 2 min |
| 6 | GitHub Release | 2 min |
| 7 | Build gem | 2 min |

**Total: manageable as one focused session.**
