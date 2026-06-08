# Warning Triage for Adapted R Meta-analysis Scripts

Use this after running an adapted script. Classify messages before changing analysis code.

## Usually okay; record only

- `height was translated to width`: ggplot/metafor plotting compatibility message for horizontal error bars. It does not change model estimates.
- `Skipped ...`: expected optional-module behavior when a moderator, plot, or subgroup has no usable data.
- `No non-missing data for moderator ...`: expected when an old-script optional moderator is absent in the new workbook.
- `No usable cells for moderator ... plot not created`: expected when minimum-k rules leave no plot cells.
- `No subdomains met min_k...`: expected when continuous moderator data are too sparse.

## Needs a guard, not a substantive model change

- `NULL` printed after a plot/helper call: wrap `print(plot_obj)` or table exports in `if (!is.null(...))`.
- `select is not applicable to NULL`: a helper returned `NULL`; guard before piping.
- `No usable rows for moderator ...`: skip the downstream table/plot/export block.
- `Can't recycle <moderator A> (size ...) to match <moderator B> (size ...)` from `vctrs::data_frame()` or `bind_rows()`: moderator summary tables were combined while retaining original grouping columns with different level counts. Convert each moderator summary to long format first, with common columns such as `moderator`, `level`, `k_effects`, and `n_studies`, then bind only non-NULL/non-empty tables.

## Needs conversion-code inspection

- `NaNs produced` during effect-size conversion: add numeric validity checks before `sqrt()`, `log()`, or division. For chi-square conversion require finite, non-negative chi-square, positive `N`, and a valid minimum dimension. Report unconverted rows rather than forcing values.
- Any unexpected large drop in `EFFECT SIZE CONVERSION CHECK`: inspect unsupported `effect_type` labels and add synonym standardization only when the label is truly equivalent.

## Needs statistical reporting caution

- `Variance-covariance matrix of the contrast is not positive definite`: the CR2 omnibus contrast is not computable for that moderator/subset. Keep coefficient-level output if available, set omnibus to `NA`, and report the limitation.
- `sqrt(diag(vcov)) produced NaNs`: variance-covariance diagnostics are unstable for that model/subset. Treat affected inferential output as unreliable and report that the model ran with unstable variance estimates.
- Convergence warnings or singular fits: keep the model output visible but mark it as unstable; consider simplifying the model only if the user asks or if the primary model fails.

## Done criteria after warnings

- The script completes without hard errors.
- Skipped optional modules are named clearly.
- Unsupported or invalid effect-size rows are counted.
- Non-computable omnibus tests are recorded as unavailable, not silently omitted.
- Main model, domain/subdomain models, and publication-bias modules either run or have explicit skip reasons.
