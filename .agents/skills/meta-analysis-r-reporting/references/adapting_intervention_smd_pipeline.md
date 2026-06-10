# Adapting the Intervention SMD Pipeline

Use `primary_students_intervention_smd_pipeline.R` when the user has an intervention or pre-post meta-analysis dataset with one-group, two-group, or RCT designs and wants the same full code style as the primary-school-students analysis.

## When this pipeline fits

Use it when the dataset includes fields like:

- `int_n`, `con_n`, `N`
- `int_mean_t1`, `int_sd_t1`, `int_mean_t2`, `int_sd_t2`
- `con_mean_t1`, `con_sd_t1`, `con_mean_t2`, `con_sd_t2`
- `design` coded as `one_group`, `two_group`, or `RCT`
- `smd`, `effect_type`, `effect_size`, `p_val`
- moderator columns coded in the new workbook, such as technology category, grade level, learning subject, outcome domain, or continuous sample descriptors

## Default adaptation rule

Copy the full pipeline first. Change only project-specific blocks. Keep the validated effect-size priority, `metafor::escalc()` fallback logic, multilevel models, CR2 moderator helper, publication-bias checks, and forest-plot blocks unless the new design truly requires a structural change.

## Must-change blocks

### 1. Data path and NA codes

Replace the workbook path:

```r
dat <- read_excel("PATH/TO/NEW/DATA.xlsx", na = c("NA", "na", "NR", "nr", "", " "))
```

Specify `sheet =` if needed.

### 2. Column harmonization

Standardize incoming column names before `required_cols`.

Common mappings:

- `intervention_n`, `treatment_n`, `experimental_n` -> `int_n`
- `control_n`, `comparison_n` -> `con_n`
- `pre_mean_int`, `int_pre_mean` -> `int_mean_t1`
- `post_mean_int`, `int_post_mean` -> `int_mean_t2`
- `pre_sd_int`, `int_pre_sd` -> `int_sd_t1`
- `post_sd_int`, `int_post_sd` -> `int_sd_t2`
- same pattern for `con_mean_t1`, `con_sd_t1`, `con_mean_t2`, `con_sd_t2`
- `domain`, `construct_category` -> `outcome_domain`
- `subdomain`, `construct_subcategory` -> `outcome_subdomain`
- `technology_category`, `Technology Category` -> `Technology_Category`
- `grade`, `Grade Level` -> `Grade_Level`
- `subject`, `Learning Subject` -> `Learning_Subject`

Keep all renaming in one early block. Do not edit the original workbook unless the user asks.

### 3. Required columns

Keep core effect-size and design columns:

```r
title
apa_citation
study_id
effect_id
int_n
con_n
N
int_mean_t1
int_sd_t1
int_mean_t2
int_sd_t2
con_mean_t1
con_sd_t1
con_mean_t2
con_sd_t2
effect_type
effect_size
smd
outcome_domain
outcome_subdomain
design
```

Add or remove moderator columns only to match the user's workbook and research questions.

### 4. Repeated-measures correlation

The reference pipeline uses:

```r
r_assumed <- 0.70
```

Keep this only if the user has no better within-person pre-post correlation. If the user provides a value or sensitivity plan, implement it exactly and report it.

### 5. Study-specific imputation and special cases

The reference pipeline includes examples such as:

- Dong et al. SD imputation.
- Qian et al. change-score handling.
- Hsu et al. gender-row merge.

These are not universal rules. For a new project:

- Keep a block only when the same study/source condition exists.
- Otherwise remove it, or replace it with a clearly named project-specific block.
- Always print which rows were imputed, merged, or specially handled.

### 6. Effect-size priority

Preserve the priority unless the user requests a different method:

- two-group/RCT: direct d/SMD -> t -> F -> eta2 -> r -> special change-score SMD -> posttest SMD -> change-score d
- one-group: direct d/SMD -> t -> F -> eta2 -> r -> SMCR

Do not silently mix association-effect logic from the Fisher-z/r pipeline into this SMD pipeline.

### 7. Moderators, constructs, domains, and labels

Treat old-script constructs, domains, subdomains, and moderators as examples of structure, not categories to inherit:

- `Technology_Category`
- `female_per`
- `Grade_Level`
- `outcome_domain`
- `outcome_subdomain`
- `Learning_Subject`
- `design`

Before adapting moderator or subgroup blocks, read `discovering_constructs_and_moderators.md` and inspect the new workbook's actual construct/domain/subdomain/moderator columns and observed levels. If the new project has different variables, keep `run_moderator_model()` but change the calls and plot labels. If these old variables do not exist in the new workbook, do not create them unless the user defines them.

For every new intervention meta-analysis, add an early inspection block that prints tables for candidate grouping columns in the new workbook. Use those discovered values for model calls and figures.

### 8. Outlier handling

The reference pipeline fits an initial model, detects outliers, then fits a no-outlier final model. Keep both full and no-outlier states visible. Do not report only the no-outlier result unless the user requests that reporting strategy.

### 9. Optional moderator and plot guards

Before adapting optional moderator plots, subgroup plots, funnel plots, or publication-bias blocks, read `optional_module_guards.md`. If the reference script contains PET/PEESE blocks, drop them when adapting: the default publication-bias check is a single multilevel Egger test.

If a moderator or plot variable is missing or all NA in the new workbook, skip that block with a clear message. Do not run old `Technology_Category`, `Grade_Level`, `Learning_Subject`, `female_per`, or `outcome_domain` blocks just because the old script had them.

If any helper, `tryCatch()`, moderator summary, publication-bias function, or plot constructor returns `NULL` or an empty result, skip downstream `select()`, `mutate()`, `print()`, `ggsave()`, or `write.xlsx()` calls. Guard outputs with `if (!is.null(res) && nrow(res) > 0)` for tables, and `if (!is.null(plot_obj))` for plots.

### 10. Output checks

Before calling the adapted script complete, verify:

- Old data path is gone.
- All required columns exist after harmonization.
- Design counts are printed.
- SMD source counts are printed or inspectable.
- `meta_ready` row count and distinct-study count are available.
- Domain, subdomain, and moderator values come from the new workbook rather than old primary-students labels.
- Optional moderators and plots are skipped when their columns are missing or all NA.
- Helper outputs are checked for `NULL` or empty results before printing, exporting, or plotting.
- Overall model, no-outlier model, moderator models, publication-bias checks, and forest plots either run or have explicit skip reasons.
