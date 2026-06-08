# Adapting the Full Reference Pipeline

Use `ip_wellbeing_reference_pipeline.R` when the user wants the same full code style as the existing IP and wellbeing script.

## Default adaptation rule

Copy the full reference pipeline first. Change only the project-specific parts needed for the new dataset. Keep the validated helper functions, model structure, influence workflow, CR2 extraction, and plotting logic unchanged unless the user explicitly asks for a different analysis design.

## Must-change blocks

### 1. Packages

Keep these unless the environment lacks a package:

```r
library(readxl)
library(metafor)
library(dplyr)
library(stringr)
library(clubSandwich)
library(tidyr)
library(ggplot2)
```

Add packages only when the new output genuinely needs them.

### 2. User switches

Usually keep the same switch names:

```r
EXCLUDE_INFLUENTIAL <- FALSE
COOK_RULE_4_OVER_K <- FALSE
DFBETAS_CUT <- 1
```

Change values only when the user requests influence-excluded analyses or a different diagnostic threshold.

### 3. Data path and sheet

Replace the original `read_excel()` path with the new workbook path. If the workbook has multiple sheets, specify the sheet.

```r
dat_raw <- read_excel("PATH/TO/NEW/DATA.xlsx", sheet = "Sheet1")
```

Do not leave the original IP/wellbeing path in a project-specific copy.

### 4. Column harmonization

Before `cols_needed`, add or keep a column-standardization step if the new workbook uses different names. Use `column_name_harmonization.md` for synonyms.

Example:

```r
dat_raw <- harmonize_columns(dat_raw, column_map)
```

If no harmonization function is copied into the full reference script, rename columns explicitly with `dplyr::rename()` in one block near the top.

### 5. Required columns

Update `cols_needed` only when the new analysis needs different moderators or construct labels. Keep the core fields:

```r
study_id
N
effect_type
effect_size
effect_size_original
df1
df2
ci_low
ci_high
construct_outcome
construct_category
construct_subcategory
effect_direction
```

Optional descriptors can stay in `cols_needed`; they will be created as `NA` if absent.

### 6. Numeric columns

Update `num_cols` if the new workbook has additional numeric moderators. Keep the core conversion fields:

```r
N
effect_size
effect_size_original
df1
df2
ci_low
ci_high
```

### 7. Construct/domain coding

Treat project-specific labels such as psychological health, psychological functioning, well-being, ill-being, adaptive functioning, and maladaptive functioning as old-script examples only.

Before adapting these blocks, read `discovering_constructs_and_moderators.md` and inspect the new workbook's actual construct, domain, and subdomain columns and values. Generate subgroup filters, moderator calls, plot labels, and output names from the new workbook.

Do not collapse, reverse, or relabel constructs just because names look similar. Use the user's exact coding definitions or the values already coded in the new extraction sheet.

### 8. Risk-direction coding

Edit only the mapping that creates `yi_risk`. Keep both raw-direction `yi` and risk-coded `yi_risk` when the script reports both.

If no direction mapping is defined for the new project, use raw `yi` and state that no risk-direction harmonization was applied.

### 9. Plot labels and output file names

Update:

- forest plot titles
- combined figure labels
- axis labels
- output image/file names
- manuscript-ready printed labels

Do not change model inputs while only changing display labels.

### 10. Optional moderator and plot guards

Before adapting optional blocks such as `white_proportion`, `gender_proportion`, scatter plots, moderator plots, funnel plots, PET/PEESE, or subgroup forest plots, read `optional_module_guards.md`.

If a column is only present because `cols_needed` created it as `NA`, skip its analysis block with a clear message. Do not let all-NA optional columns flow into `facet_wrap()`, `rma.mv()`, funnel plots, or PET/PEESE models.

Also guard the printed example blocks at the end of the reference script. If helpers such as `summarise_categorical_levels_CR2_p()` return `NULL`, skip the example instead of piping the `NULL` object into `dplyr::select()` or `print()`.

### 11. Warning triage

After running the adapted script, read `warning_triage.md`. Do not treat all warnings as errors. In particular, skip/NULL optional-module messages usually mean the new workbook lacks that moderator; contrast non-positive-definite warnings mean the CR2 omnibus is unavailable for that subset; and NaNs during effect-size conversion require validity checks and a conversion-count audit.

## Usually keep unchanged

- NA-like string cleanup.
- `effect_id` creation.
- Effect-size conversion blocks.
- Fisher z and variance computation.
- FULL/CLEAN/USE naming and influence-exclusion toggle.
- Influence diagnostics helper functions.
- `compute_ml_I2()`.
- `collapse_by_studyid()` helpers.
- `rma.mv()` random-effects structure unless the nesting structure changes.
- CR2 extraction helpers.
- Existing forest plot mechanics.
- Moderator helper functions, after updating the moderator variable names.
- Guard helper functions for optional plots/models.

## Verification after adaptation

Before calling the code finished, run or inspect for:

- New data path is present; old IP/wellbeing path is gone.
- All canonical required columns exist after harmonization.
- Row counts are printed for raw, cleaned, full, clean, and used datasets.
- Every domain/subdomain model reports `k` effects and distinct studies.
- Domain/subdomain/moderator levels come from the new workbook, not from old IP/wellbeing labels.
- Optional moderators and plots are skipped when their columns are missing or all NA.
- Influence-exclusion status is clear.
- Empty or underpowered subgroup models are recorded rather than silently skipped.
