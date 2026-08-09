## Summary

-

## Verification

-

## Safety Checklist

- [ ] Source files remain read-only.
- [ ] Destination collisions cannot overwrite existing files.
- [ ] Destructive operations are receipt-backed and reversible where applicable.
- [ ] User-facing errors remain plain and nontechnical.
- [ ] New files in the `ChronoframeAppTests`/`ChronoframeUITests` Xcode targets are added to `project.pbxproj` (sources under `ui/Sources/` are auto-discovered and need no project edit).
- [ ] Tests or documented manual checks cover the changed behavior.
