# Adapting the AI Literacy One/Two-Group Gender Pipeline

Use `ai_literacy_one_two_group_gender_pipeline.R` when the project has separate one-group pre-post and two-group pre-post/control workbooks, then combines the cleaned/no-outlier datasets for moderator analyses.

## When this pipeline fits

Use it when the dataset has patterns like:

- One-group workbook such as `One pre-post.xlsx`.
- Two-group/control workbook such as `Two pre-post.xlsx`.
- `Exi_intervention`, `Exi_control`, and/or `RCT` design indicators.
- Pre/post intervention columns: `int_n`, `int_mean_t1`, `int_sd_t1`, `int_mean_t2`, `int_sd_t2`.
- Control columns for the two-group file: `con_n`, `con_mean_t1`, `con_sd_t1`, `con_mean_t2`, `con_sd_t2`.
- Reported statistics in `effect_type`/`effect_size`, including `d`, `g`, `t`, `z`, or `r`.
- A construct or moderator variable like `antecedent` that the new workbook or user instructions define as the main construct grouping column.
- A continuous gender moderator such as `gender_proportion`.

## Default adaptation rule

Copy the full pipeline first. Keep the two-stage structure:

1. Analyze one-group pre-post data.
2. Analyze two-group/quasi/RCT data.
3. Remove outliers within each stream.
4. Harmonize and combine both streams.
5. Run combined main model, literacy-type moderator, gender moderator, publication-bias checks, and forest plots.

Do not collapse this into the simpler primary-students intervention pipeline unless the user has only one combined workbook and no separate one/two-group workflow.

## Must-change blocks

### 1. Data paths

Replace both workbook paths:

```r
d_one <- read_excel("PATH/TO/ONE_PRE_POST.xlsx", na = c("NA", "na", "NR", "nr", ""))
d_two <- read_excel("PATH/TO/TWO_PRE_POST.xlsx", na = c("NA", "na", "NR", "nr", ""))
```

Specify `sheet =` when needed. Remove old AI-literacy paths from adapted scripts.

### 2. Column harmonization

Standardize names separately for the one-group and two-group files before filtering.

Common mappings:

- `intervention_exists`, `has_intervention` -> `Exi_intervention`
- `control_exists`, `has_control` -> `Exi_control`
- `is_rct`, `randomized`, `randomised` -> `RCT`
- `antecedent`, `ai_literacy_type`, `literacy_construct` -> a new-project construct grouping name such as `literacy_type`, only when that is the user's intended construct variable
- `female_per`, `female_percent`, `percent_female`, `gender_per` -> `gender_proportion`
- one/two-group mean and SD synonyms from `column_name_harmonization.md`

Keep renaming in one early block and keep source workbooks unchanged unless the user asks for cleaned workbooks.

### 3. Design filters

Preserve the meaning of the filters:

- one-group: `Exi_intervention == 1 & Exi_control == 0`
- two-group quasi/control: `RCT == 0 & Exi_control == 1`

If the new project includes RCTs in the two-group analysis, explicitly revise the filter and report that choice. Do not mix RCT and non-RCT just because both have controls without checking the user's design plan.

### 4. Repeated-measures correlation

The one-group SMCR code uses:

```r
r_assumed <- 0.7
```

Use the user's value if provided. If not provided, keep the assumption visible and report it.

### 5. Effect-size priority

Preserve the one-group priority:

- compute SMCR from means/SDs
- override with reported d/t/z/r converted to Hedges g when available

Preserve the two-group priority:

- direct d/g
- t/F conversions
- change-score SMD when pre/post data are available
- posttest-only SMD after SD imputation as fallback

Do not use Fisher-z association logic for this pipeline.

### 6. SD imputation

The two-group pipeline imputes missing SDs using within-category medians and overall means. Keep this only when appropriate for the new project, and always print or save which rows used imputed SDs. Add sensitivity analyses excluding imputed SDs when the imputation affects model-ready rows.

### 7. Manual removal block

The reference pipeline contains a manual removal section. Treat it as project-specific.

- Keep it only when the user explicitly names studies/effects to remove.
- Otherwise set the removal list to empty or remove the block.
- Always print a before/after check for manually removed studies.

### 8. Combined dataset harmonization

When combining streams, keep a common schema:

- `study_id`
- `effect_id`
- `apa_citation`
- the new construct/moderator grouping column, such as `literacy_type` only when defined by the new workbook
- `gender_proportion`
- `yi`
- `vi`
- `design`

For the two-group stream, map `smd`/`smd_v` to `yi`/`vi` before binding.

### 9. Moderators, constructs, domains, and labels

Treat `literacy_type`, `antecedent`, and `gender_proportion` as AI-literacy examples, not universal construct or moderator fields. Before adapting moderator or subgroup blocks, read `discovering_constructs_and_moderators.md` and inspect the new workbook's actual construct/domain/subdomain/moderator columns and observed levels in both the one-group and two-group workbooks.

Keep `literacy_type` and `gender_proportion` moderator logic only when these variables exist in the new workbook or the user defines them.

If the project uses different moderators, preserve the model pattern but replace:

- moderator variable
- level-count filters
- labels
- output filenames

For gender, verify scale before modeling. If values are 0-100 percentages, convert to 0-1 or clearly label the unit.

For every new AI-literacy-style meta-analysis, add early inspection blocks for `d_one` and `d_two` separately, then inspect the harmonized combined dataset again. Use the newly discovered values for model calls and figures.

### 10. Verification

Before adapting optional moderator plots, subgroup plots, funnel plots, or publication-bias blocks, read `optional_module_guards.md`. If the reference script contains PET/PEESE blocks, drop them when adapting: the default publication-bias check is a single multilevel Egger test. If `literacy_type`, `gender_proportion`, or any replacement moderator is missing or all NA, skip that block with a clear message rather than running an empty model or plot.

If any helper, `tryCatch()`, moderator summary, publication-bias function, or plot constructor returns `NULL` or an empty result, skip downstream `select()`, `mutate()`, `print()`, `ggsave()`, or `write.xlsx()` calls. Guard outputs with `if (!is.null(res) && nrow(res) > 0)` for tables, and `if (!is.null(plot_obj))` for plots.

Before calling the adapted script complete, verify:

- Both old workbook paths are gone.
- One-group and two-group row counts are printed.
- Cook's distance removal is effect-level, not whole-study removal.
- No-outlier one-group and two-group datasets are saved or inspectable.
- Combined dataset reports `k`, distinct studies, design distribution, literacy-type distribution, and non-missing gender count.
- Construct and moderator levels come from the new workbook rather than old AI-literacy labels.
- Optional moderators and plots are skipped when their columns are missing or all NA.
- Helper outputs are checked for `NULL` or empty results before printing, exporting, or plotting.
- Main model, moderator models, publication-bias checks, and forest plots either run or have explicit skip reasons.
