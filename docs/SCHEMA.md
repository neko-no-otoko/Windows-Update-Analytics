# Output schema

## Versioning policy

Version 2 advances the fleet schema to numeric version `2` and semantic version `2.0.0` because the outcome contract is intentionally split and persistent-recorder records are now first-class. Consumers should ignore unknown properties and preserve `null` as distinct from empty or zero. The tool, target map, legacy rule catalog, and output schema are versioned independently.

## Summary.json

`Summary.json` remains the stable fleet-ingestion contract. Its machine-readable draft 2020-12 schema is `Data/Summary.schema.json`.

Core v2 properties are:

| Property | Meaning |
|---|---|
| `AnalysisMode` | `FactOnly` for the v2 default engine. |
| `Device`, `SourceOs`, `CurrentOs`, `TargetOs` | Normalized device and Windows identities. |
| `Outcome` | Human-readable banner derived from the explicit status fields; never `Unknown`. |
| `StatusModel` | Separate `CurrentOsState`, `BuildTransition`, `AttemptOutcome`, and `DeploymentSource` values. |
| `Recorder` | Sampling window, state boundaries, and Delivery Optimization observation rollups. |
| `Facts`, `FactCounts` | Direct records and rollups by fact type and scope. |
| `Attempts`, `AttemptScope` | Setup candidates, exact gates, classifications, and validated/excluded counts. |
| `ExcludedEvidence` | Candidate evidence prevented from entering upgrade conclusions and the exact reason. |
| `CollectionCoverage`, `CollectionGaps` | Collector state and known limitations. |
| `ArtifactHashes`, `ReviewBundle` | Output metadata and compact-review-package hash. |
| `PrimaryFinding`, `Findings`, `FindingCounts` | Compatibility fields retained for 1.x consumers. They are `null`/empty/zero in fact-only mode. |

V2 can emit `Monitoring Armed`, `Target OS Present`, `Upgrade In Progress`, `Upgrade Succeeded`, `Rolled Back`, `Failed`, or `No Upgrade Outcome Observed`. Compatibility values `Ready`, `Attention Required`, and `Blocked` remain accepted by the schema. A banner is not deployment provenance; use `StatusModel.DeploymentSource` for that question.

The status dimensions are:

```text
CurrentOsState   = TargetPresent | TargetNotPresent | Unreadable
BuildTransition  = Observed | NotObserved
AttemptOutcome   = Succeeded | Failed | RolledBack | InProgress | NotObserved
DeploymentSource = WindowsUpdateConfirmed | OtherConfirmed | Unattributed
```

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
RecorderSummary.json
ProgressSamples.jsonl
StateTransitions.jsonl
Checkpoints.json
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

Setup rows must originate in a validated Windows Update attempt. Windows Update history rows are retained as source-reported context and are not attached to a setup attempt merely because their timestamps are nearby. Recorder boundary rows use event type `RecorderState`, remain context-only, and do not receive an attempt ID by temporal proximity.

## Findings.csv

The file is retained for compatibility with v1.0 workflows. It contains only its header in fact-only mode. Consumers should migrate to `Facts.csv` or `ReviewBundle.zip/Facts.jsonl`.

## Inventory and integrity

`ProgressSamples.jsonl` is append-only. Each valid line is an independent JSON object; a truncated final line is reported and ignored without losing earlier records. `StateTransitions.jsonl` contains signature boundaries. `Checkpoints.json` rolls up the native checkpoint manifests whose full files remain in `Evidence.zip`.

`Inventory.json` contains baseline/current normalized snapshots and a transparent section-level diff. `Manifest.json` indexes raw evidence and finalized artifacts with paths, sizes, timestamps, SHA-256, source mappings, gaps, and archive verification. `Checksums.sha256` hashes the finalized top-level artifacts. The review bundle has its own internal `Manifest.sha256`.

## Exit precedence

1. Materially incomplete report: `30`.
2. Validated rollback or source-reported failed Windows Update attempt: `20`.
3. Direct attention state reserved for supported future checks: `10`.
4. Complete fact report without a failed/rollback outcome: `0`.

`0` is not a guarantee that an upgrade is ready or will succeed. Fatal startup/report failure (`40`) and unsupported platform/privilege (`50`) occur outside normal report classification.
