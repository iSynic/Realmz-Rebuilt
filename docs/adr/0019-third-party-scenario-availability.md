# ADR 0019: Scenario availability is independent of certification

Status: accepted

Third-party scenarios have multiple revisions and may intentionally or accidentally contain unfinished content. A tested source snapshot identifies evidence; it does not define the set of acceptable imports.

Every scenario Providence can import must remain exportable. Preserve authored content and reproduce Castle behavior without source-hash allowlists or clean-campaign prerequisites. Hashes continue to protect package integrity and bind saves to exact revisions. Import, export, runtime support, and completion certification remain separate claims.

Providence owns any representation changes needed to carry incomplete content through compilation. The runtime must distinguish malformed package encoding from authored defects and must not silently normalize those defects. Implementation and evidence requirements are in `../classic-scenario-import.md`.
