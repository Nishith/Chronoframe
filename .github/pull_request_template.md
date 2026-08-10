## Summary

-

## Verification

-

## Safety Checklist

- [ ] Source files remain read-only.
- [ ] Destination collisions cannot overwrite existing files.
- [ ] Destructive operations are receipt-backed and reversible where applicable.
- [ ] User-facing errors remain plain and nontechnical.
- [ ] Any new `ui/Xcode/UITests/` file is registered in `project.pbxproj` and confirmed to run — no CI lane catches this. (`ui/Sources/` and `ui/Tests/` need no project edit.)
- [ ] Tests or documented manual checks cover the changed behavior.
