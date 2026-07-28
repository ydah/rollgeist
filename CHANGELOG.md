# Changelog

## 0.1.0

- Initial release.
- Detect records left stale after create or update rollbacks.
- Report serialization and GlobalID conversion, with optional resave reports.
- Keep serialization for never-marked records on Active Record's original path.
- Limit reports per Rails executor and support suppression and ignore filters.
