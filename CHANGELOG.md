## Unreleased

- Added `gitrinth downgrade` to re-resolve every entry (or a named
  subset) to the oldest version compatible with its constraint.
- Added `gitrinth outdated` to report locked entries whose constraint
  allows a newer compatible version, with optional JSON output.
- Added `gitrinth deps` to print the resolved dependency tree, in
  `tree` (default), `list`, or `compact` styles, plus JSON.

## 1.0.0

- Initial version.
