---
name: Bug report
description: バグ報告 / Report a bug
title: "bug: "
labels: ["bug"]
body:
  - type: markdown
    attributes:
      value: |
        バグ報告ありがとうございます。

        **Security note:** 秘密鍵、nsec、seed、passkey、署名、暗号化、account takeover に関わる詳細は公開 Issue に書かないでください。先に SECURITY.md を読んでください。
  - type: dropdown
    id: platform
    attributes:
      label: Platform
      options:
        - Web
        - Android
        - iOS
        - Rust / FFI
        - docs/wiki
        - Unknown / multiple
    validations:
      required: true
  - type: textarea
    id: summary
    attributes:
      label: Summary
      description: 何が起きたかを1〜3行で書いてください。
    validations:
      required: true
  - type: textarea
    id: steps
    attributes:
      label: Steps to reproduce
      description: 再現手順。security-sensitive details は書かないでください。
      placeholder: |
        1. ...
        2. ...
        3. ...
    validations:
      required: false
  - type: textarea
    id: expected
    attributes:
      label: Expected behavior
    validations:
      required: false
  - type: textarea
    id: actual
    attributes:
      label: Actual behavior
    validations:
      required: false
  - type: textarea
    id: environment
    attributes:
      label: Environment
      description: OS / device / browser / app version / relay if relevant
    validations:
      required: false
  - type: checkboxes
    id: checks
    attributes:
      label: Checks
      options:
        - label: I did not include private keys, nsec, seed, passkey material, signatures, or exploit details.
          required: true
        - label: I checked whether this may be a private security report and read SECURITY.md if needed.
          required: true
