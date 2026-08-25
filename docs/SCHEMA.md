# Output schema

## Versioning policy

The initial output schema has numeric compatibility version `1` and semantic version `1.0.0`. The tool version, target map, rule catalog, and output schema are independently represented so fleet ingestion can reject unsupported breaking changes while accepting compatible rule updates.

- Patch: corrections that do not remove or reinterpret fields
- Minor: additive fields or enum values
- Major: removed fields, incompatible type changes, or changed semantic meaning

Consumers should ignore unknown properties and preserve `null` as distinct from an empty value or a zero count.

## Summary.json

`Summary.json` is the stable fleet-ingestion contract. Top-level content includes:

The machine-readable draft 2020-12 contract is distributed as `Data/Summary.schema.json`. Consumers should pin the schema `$id` they support and still ignore unknown additive properties.

| Property | Meaning |
|---|---|
| `SchemaVersion` | Numeric major compatibility version (`1`). |
| `SchemaSemanticVersion` | Full semantic contract version (`1.0.0`). |
| `ToolVersion` | Win11UpgradeDiag engine version. |
| `RuleCatalogVersion` | Rule data version. |
| `TargetMapVersion` | Target metadata version. |
| `Run` | Run ID, mode/phase, timestamps, and computer identity. |
| `Device` | Manufacturer, model, serial, architecture, and normalized OS identity. |
| `SourceOs` | Baseline/source display version and build where available. |
| `CurrentOs` | OS identity at the time the finalized report was captured. |
| `TargetOs` | Requested display version and expected build family. |
| `Outcome` | Current normalized outcome. |
| `ExitCode` | Fleet-friendly integer result. |
| `PrimaryFinding` | Highest-ranked active causal finding or `null`. |
| `Findings` | Complete normalized findings, including historical entries. |
| `FindingCounts` | Counts by severity/status. |
| `CollectionCoverage` | Collector completion, errors, skips, timeouts, and completeness. |
| `CollectionGaps` | Missing, inaccessible, skipped, expired, or timed-out evidence and diagnostics. |
| `Attempts` | Segmented setup-attempt inventory. |
| `ArtifactHashes` | Final artifact name, size, and SHA-256. |
| `Persistence` | Cross-reboot state and deferred-copy status where applicable. |
| `Timestamps` | Start, completion, and relevant attempt times in ISO 8601. |

Valid outcomes are:

```text
Ready
Attention Required
Blocked
Upgrade Succeeded
Rolled Back
Failed
Unknown
```

## Finding object

Every finding contains enough information to resolve its evidence without relying on prose order:

| Property | Meaning |
|---|---|
| `FindingId` | Run-unique stable identifier. |
| `RuleId` | Versioned catalog rule or analyzer identifier. |
| `Title` | Concise display title. |
| `Severity` | `Blocker`, `Error`, `Warning`, or `Information`. |
| `Confidence` | `High`, `Medium`, or `Low`. |
| `Status` | Normally `Active` or `Historical`. |
| `Category` | Compatibility, setup, driver, servicing, storage, policy, and related grouping. |
| `Phase` | Normalized setup phase when known. |
| `Operation` | Normalized setup operation when known. |
| `Codes` | Canonical HRESULT/Win32/NTSTATUS/MoSetup codes. |
| `AffectedEntity` | Application, driver, device, file, package, policy, or endpoint. |
| `Summary` | Deterministic interpretation. |
| `WhyItMatters` | Impact explanation. |
| `Evidence` | One or more exact evidence references. |
| `Recommendation` | Copyable explanatory next step; never executable. |
| `MicrosoftReferences` | Relevant Microsoft documentation URLs. |

Evidence references identify source path, timestamp, line/event/record when available, code, and a bounded excerpt. A causal finding must have at least one resolvable evidence reference. Findings based only on temporal proximity are limited to low confidence.

## Inventory.json

`Inventory.json` contains normalized collector output and provenance. It is intentionally broader and less stable than `Summary.json`; ingestion systems should use it only when they understand the named collector schema. Typical branches include identity, hardware, storage, software, packages/features/languages, drivers/devices, management/policy, update history, servicing, connectivity, events, diagnostics, pre/post diff, and collector records.

Collector records provide name, phase, start/end, duration, status, timeout/error text, and generated evidence. Status values can include completed, warning, failed, skipped, unavailable, and timed out.

## Findings.csv

Each row represents one finding. Array-valued codes, evidence, and references are flattened using a consistent delimiter and excerpts are bounded. CSV is intended for technician triage; use `Summary.json` when lossless types and nested evidence matter.

## Timeline.csv

Each row is a normalized event ordered by UTC time where time is available:

```text
TimestampUtc, LocalOffset, TimestampAmbiguous, AttemptId, Phase, Operation,
Code, Component, Event, Message, Severity, SourceRef, EvidenceReference,
Entity, CorrelationId
```

Rows without a trustworthy timestamp remain represented and sort after timestamped records. Displayed local time is derived from the source and captured time-zone context; ingestion should prefer UTC.

## Manifest.json and Checksums.sha256

`Manifest.json` indexes raw evidence and finalized artifacts with staged paths, archive-relative paths, size, timestamps, and SHA-256 where readable. Its `SourceMappings` branch maps original evidence sources to archive prefixes and collection state; `CollectionGaps` records sources that were missing, inaccessible, timed out, or intentionally metadata-only. `Checksums.sha256` provides conventional hashes for validating the finalized output set after transfer.

`Summary.json` lists hashes for the nonrecursive core artifacts that exist before the summary and report are written. Use `Manifest.json` and `Checksums.sha256` for the finalized output set, because a document cannot safely contain its own final hash.

The manifest can represent missing, locked, cleaned, oversized, metadata-only, or copy-failed evidence. Absence from `Evidence.zip` must not be interpreted as proof that the source never existed.

## Exit precedence

Exit-code selection uses this precedence:

1. Materially incomplete output: `30`
2. Active blocker, failed attempt, or rollback: `20`
3. Active warning requiring attention: `10`
4. Complete ready/success result: `0`

Fatal startup/report failure (`40`) and unsupported platform/privilege (`50`) occur outside normal report classification. Historical findings do not drive exit status.
