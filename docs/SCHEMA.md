# Output schema

## Versioning policy

The fleet schema keeps numeric compatibility version `1` and advances its additive semantic version to `1.1.0`. Consumers should ignore unknown properties and preserve `null` as distinct from empty or zero. The tool, target map, legacy rule catalog, and output schema are versioned independently.

## Summary.json

`Summary.json` remains the stable fleet-ingestion contract. Its machine-readable draft 2020-12 schema is `Data/Summary.schema.json`.

Core v1.1 properties are:

| Property | Meaning |
|---|---|
| `AnalysisMode` | `FactOnly` for the v1.1 default engine. |
| `Device`, `SourceOs`, `CurrentOs`, `TargetOs` | Normalized device and Windows identities. |
| `Outcome` | Directly observable current outcome; `Unknown` when the evidence does not establish one. |
| `Facts`, `FactCounts` | Direct records and rollups by fact type and scope. |
| `Attempts`, `AttemptScope` | Setup candidates, exact gates, classifications, and validated/excluded counts. |
| `ExcludedEvidence` | Candidate evidence prevented from entering upgrade conclusions and the exact reason. |
| `CollectionCoverage`, `CollectionGaps` | Collector state and known limitations. |
| `ArtifactHashes`, `ReviewBundle` | Output metadata and compact-review-package hash. |
| `PrimaryFinding`, `Findings`, `FindingCounts` | Compatibility fields retained for 1.x consumers. They are `null`/empty/zero in fact-only mode. |

Valid outcomes remain `Ready`, `Attention Required`, `Blocked`, `Upgrade Succeeded`, `Rolled Back`, `Failed`, and `Unknown`. Fact-only mode normally emits only the latter four outcome states that can be established from current build, an owned rollback marker, or source-reported Windows Update history.

## Fact object

| Property | Meaning |
|---|---|
| `FactId` | Run-unique sequential identifier. |
| `FactType` | `Observed`, `SourceReported`, `Decoded`, or `Computed`. |
| `Category` | Identity, attempt scope, Setup, Windows Update history, code, coverage, or collector execution. |
| `Statement` | Neutral statement of record. |
| `Value` | Scalar or structured source value. |
| `TimestampUtc` | Source timestamp when available. |
| `AttemptId` | Validated setup candidate identifier when directly attached. |
| `Code`, `Phase`, `Operation` | Source code and deterministic Setup decode, when available. |
| `ScopeStatus` | `Included`, `ContextOnly`, or `Excluded`. |
| `EvidenceRef` | Archive-relative path plus line, array index, event ID, or JSON property locator. |
| `Excerpt`, `ExcerptFile` | Bounded source text and its file inside `ReviewBundle.zip`. |

The types have deliberately narrow meaning:

- `Observed`: directly read by the collector.
- `SourceReported`: emitted by Windows Update, Windows Setup, or scoped SetupDiag.
- `Decoded`: deterministic numeric/symbolic or phase/operation lookup.
- `Computed`: transparent diff or Boolean scope gate; never a root-cause assertion.

## Attempt object

Every `setupact*.log` candidate is inventoried. Important fields include source path/hash, time window, source/target build, parsed codes, content signals, corroborating evidence, classification, and `IncludedForUpgradeReview`.

The `Gates` object exposes every Boolean decision:

```text
UniqueEvidence
NotDiagnosticScan
NotToolGenerated
NotInitialDeploymentOrImaging
FeatureUpgradeSemantics
WindowsUpdateOwnership
TemporalOverlap
TargetVersionOrBuild
CompletedWindowsImageState
```

Only an attempt for which every gate is true receives `WindowsUpdateFeatureUpgrade`. Other classifications are `NonWindowsUpdateFeatureUpgrade`, `DiagnosticCompatibilityScan`, `CurrentHealthDiagnostic`, `GeneralWindowsServicing`, `InitialDeploymentOrImaging`, `UnclassifiedSetupEvidence`, and `ToolGenerated`.

## ReviewBundle.zip

The provider-neutral review bundle contains:

```text
READ_ME_FIRST.md
REVIEW_PROMPT.md
Case.json
Attempts.json
Facts.jsonl
Facts.csv
Timeline.jsonl
Timeline.csv
UpdateHistory.jsonl
Inventory.json
InventoryDiff.json
CollectionCoverage.json
ExcludedEvidence.json
EvidenceIndex.jsonl
Excerpts/FACT-*.txt
Manifest.sha256
```

`ReviewBundle.zip` intentionally contains bounded excerpts and normalized records rather than duplicating all raw logs. Use `Evidence.zip` when the reviewer needs complete source content. Both artifacts remain local unless the operator explicitly copies or uploads them.

## Timeline.csv and Timeline.jsonl

The fact-only timeline contains only:

```text
TimestampUtc, AttemptId, FactId, EventType, Code, Phase, Operation,
Message, EvidenceReference
```

Setup rows must originate in a validated Windows Update attempt. Windows Update history rows are retained as source-reported context and are not attached to a setup attempt merely because their timestamps are nearby.

## Findings.csv

The file is retained for compatibility with v1.0 workflows. It contains only its header in fact-only mode. Consumers should migrate to `Facts.csv` or `ReviewBundle.zip/Facts.jsonl`.

## Inventory and integrity

`Inventory.json` contains baseline/current normalized snapshots and a transparent section-level diff. `Manifest.json` indexes raw evidence and finalized artifacts with paths, sizes, timestamps, SHA-256, source mappings, gaps, and archive verification. `Checksums.sha256` hashes the finalized top-level artifacts. The review bundle has its own internal `Manifest.sha256`.

## Exit precedence

1. Materially incomplete report: `30`.
2. Validated rollback or source-reported failed Windows Update attempt: `20`.
3. Direct attention state reserved for supported future checks: `10`.
4. Complete fact report without a failed/rollback outcome: `0`.

`0` is not a guarantee that an upgrade is ready or will succeed. Fatal startup/report failure (`40`) and unsupported platform/privilege (`50`) occur outside normal report classification.
