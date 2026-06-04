---
name: Wiki update
description: docs/wiki の修正提案
title: "docs: "
labels: ["docs"]
body:
  - type: markdown
    attributes:
      value: |
        docs/wiki は project memory です。source code と衝突する場合、source code / design tokens / guardrails が優先です。
  - type: input
    id: page
    attributes:
      label: Wiki page
      description: 例 `docs/wiki/features/timeline.md`
    validations:
      required: true
  - type: textarea
    id: issue
    attributes:
      label: What should change?
      description: 追加・修正・Open Questions 化したい内容を書いてください。
    validations:
      required: true
  - type: textarea
    id: source
    attributes:
      label: Source references
      description: 根拠になる source file / ADR / issue / PR / design token を書いてください。
    validations:
      required: false
  - type: checkboxes
    id: checks
    attributes:
      label: Checks
      options:
        - label: I separated uncertain claims into Open Questions, or explained why none are uncertain.
          required: true
        - label: I will update docs/wiki/log.md if this is a meaningful architecture / feature / NIP / security / parity change.
          required: false
