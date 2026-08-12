# Bank Adapter Fixtures

The repository contains one anonymized reference adapter:

```text
institution: reference-bank-fixture
source_package: com.example.reference.bank
adapter_version: fixture-1
patterns: "Outgoing 55.25 THB" / "Incoming 55 THB"
```

It is test-only and must never be described as real bank support. A real adapter remains blocked until the user supplies a redacted notification example and the verified Android package name. Fixtures must not contain names, account numbers, addresses, tokens, or real transaction references.
