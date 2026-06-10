---
name: meta-analysis-r-reporting
description: Build, adapt, audit, or run R meta-analysis pipelines and reports from already-extracted Excel/CSV effect-size data in psychology, education, health, or social science. Covers effect-size conversion (Pearson r/Fisher z, SMD/Hedges g, t/F/z/eta2-to-d), multilevel metafor models, cluster-robust CR2 tests, moderator/subgroup analyses, influence and outlier diagnostics, publication-bias checks, forest/funnel figures, and manuscript-ready Word reports. Use whenever the task involves writing or running R/Rmd code for a meta-analysis dataset, reproducing published meta-analytic results, or generating results summaries, tables, and figures from such an analysis.
---

# Meta-analysis R

## Workflow

1. Inspect the live data file before writing code.
   - Read sheet names, row count, column names, and a few example values.
   - Identify the effect-size source columns, sample-size column, study/effect identifiers, outcome/domain columns, and any moderators.
   - If the file is Excel, prefer `readxl::read_excel()` and let the user choose a sheet only when multiple plausible sheets exist.

2. Standardize similar column names before analysis.
   - Compare the live workbook's column names to `references/column_name_harmonization.md`.
   - Rename synonymous columns to the canonical names used by the chosen reference pipeline before converting effect sizes.
   - Do this as an explicit preprocessing step in the project script; do not manually edit the user's original workbook unless asked.
   - If two columns map to the same canonical field, prefer the more complete column and record the choice in the report.

3. Decide which full reference pipeline or portable template to use.
   - If the user wants code "like my current R code", "all the code", "same as before", or a manuscript-ready IP/wellbeing-style analysis, use `references/ip_wellbeing_reference_pipeline.R` as the main source.
   - If the dataset has intervention/control fields, pre/post means and SDs, `one_group`/`two_group`/`RCT` designs, or SMD/Hedges g outcomes, use `references/primary_students_intervention_smd_pipeline.R` as the main source.
   - If the project has separate one-group and two-group pre/post workbooks, `Exi_intervention`/`Exi_control` flags, RCT/quasi-experimental filtering, `antecedent` recoded to `literacy_type`, or a `gender_proportion` moderator, use `references/ai_literacy_one_two_group_gender_pipeline.R` as the main source.
   - Copy the matching reference pipeline into the project folder and adapt only the required project-specific blocks listed in `references/adapting_reference_pipeline.md`, `references/adapting_intervention_smd_pipeline.md`, or `references/adapting_ai_literacy_gender_pipeline.md`.
   - The reference pipelines are long. Do not read an entire pipeline into context at once; read the matching adapting guide first, then open only the blocks it says need project-specific changes (config, data loading, moderator definitions, labels), keeping validated helper/model/plot blocks unchanged.
   - If no reference pipeline matches the dataset structure, write a fresh project script that follows the same conventions: explicit config block at the top, `metafor::rma.mv()` multilevel models, `clubSandwich` CR2 tests, guarded optional modules, status tables, and one output folder.

4. Compare the standardized dataset to `references/meta_analysis_columns.md`.
   - Treat that file as the schema map and vocabulary guide.
   - Add missing optional columns as `NA`; do not invent values for missing required analysis fields.
   - Keep user-provided variable definitions literal. Do not reverse-score or recode conceptual variables unless the user explicitly defines the direction.

5. Discover constructs, domains, subdomains, and moderators from the new workbook.
   - Read `references/discovering_constructs_and_moderators.md` before adapting any project-specific labels.
   - Do not reuse old project levels or variables such as well-being, ill-being, Needs, Motivation, adaptive functioning, literacy type, antecedent, technology category, learning subject, gender proportion, or grade level unless those exact columns/values appear in the new workbook or the user defines them.
   - Generate model calls, subgroup splits, figure labels, and output filenames from the new dataset's actual column names and observed levels.

6. Add guards for optional modules before running them.
   - Read `references/optional_module_guards.md` before adapting moderator, scatter/facet plot, forest, funnel, or publication-bias blocks.
   - Publication bias defaults to a single multilevel Egger test: regress effect sizes on their standard errors in the same multilevel model with CR2 robust inference. Do not also fit PET (it is mathematically identical to Egger-on-SE) or PEESE unless the user explicitly asks for them; never present the same regression twice under different names.
   - Creating an optional column as `NA` is not enough to justify running its module.
   - Skip optional modules with a clear `message()` when the required column is missing, all values are missing, there are too few model-ready rows, or a facet/group variable has no levels.
   - If a helper or `tryCatch()` returns `NULL`, do not pipe the result into `select()`, `mutate()`, `print()`, `ggplot()`, or file export. Check `!is.null(res) && nrow(res) > 0` first.
   - When combining moderator count/summary outputs across different moderators, export a long table with explicit `moderator` and `level` columns. Do not bind grouped summaries that still retain original moderator column names such as `design_inferred` and `country`, because different level counts can trigger vctrs recycling errors.

7. Run the script and verify the outputs.
   - Confirm how many rows were read, retained, converted to `r`, and included in each model.
   - Check the conversion log before interpreting results.
   - Verify that the overall/main model actually fit before interpreting `main_summary`; if the table contains only `NA` estimates, inspect and report the model error instead of treating it as a result.
   - When reproducing or comparing against a published article, treat the article's main analytic sample as the primary target. Do not make influence-excluded data the main result unless the article also excluded those cases from the main analysis.
   - Align counting units before interpreting differences: report `k_effects`, `n_studies` or records, and when available `n_subsamples` or sample groups. A mismatch between article subsamples and script effect counts is not necessarily a statistical mismatch.
   - Keep non-convergent, underpowered, empty subgroup, or missing-field analyses visible in the report instead of silently skipping them.
   - After a run, read `references/warning_triage.md` to decide which warnings are harmless, which need guards, and which need statistical caveats.

8. Generate an R Markdown report when the user asks for results, outcomes, Word/PDF output, summary tables, or figures.
   - Read `references/rmarkdown_reporting.md` before creating `.Rmd` output. That file is the canonical source for all report-formatting detail: deliverable structure, output-folder layout, effect-size audit / main-effect / moderator table column specs, rounding conventions, CR2 `F(df1, df2)` display, funnel/forest plot styling, and figure-selection rules. Follow it instead of reproducing those rules here.
   - The Rmd should rerun the analysis or source a deterministic analysis script, then render summary text, tables, and figures in one document. Recompute or assert that model objects exist; do not depend on a previously exported workbook that might be incomplete.
   - By default, produce two Word deliverables: `results_summary.docx` (manuscript-style Results — overview, executive summary, key results, and only the figures/tables that support the narrative) and `all_tables_figures_summary.docx` (every generated result table and figure with short captions, for checking). Create HTML/PDF/Rmd reports only when the user explicitly asks. Keep Word as the PDF fallback, since a `.docx` can be exported to PDF even when LaTeX is missing.
   - Write the manuscript-style Results as journal prose, not a technical dump: sample descriptives -> overall effect -> moderator analyses -> sensitivity/influence checks -> publication bias, with an explanatory paragraph before each table and the dataset's actual findings (which effects were significant, strongest/weakest levels, direction of continuous moderators), not template filler. Order content as narrative -> matching table -> matching figure.
   - Keep large row-level audit/diagnostic tables out of the document: export them to CSV beside the report and cite the path. Split report tables by analysis family (overall effect, omnibus moderator tests, level estimates, continuous moderators, Egger, influence) instead of pasting unrelated CSVs into one table.
   - For article-comparison reports, put the full-data main model first as the article-comparison result and place influence-cleaned/no-outlier models in a separate sensitivity section with the exclusion rule and flagged counts. Do not repeat the main-model row as a "sensitivity" row when no effects were flagged.
   - When the sensitivity analysis flags influential effects (for example Cook's D > 4/k), include a dedicated table of those flagged effects in the manuscript-facing summary, not just a count: one row per flagged effect with study/effect ids, identifying descriptors, effect size, SE, Cook's D, the cutoff, and the ratio to the cutoff, sorted by Cook's D. See `references/rmarkdown_reporting.md`.
   - Write narrative as plain Markdown; only executable R belongs in `{r}` chunks, and inline `` `r ...` `` expressions stay in prose. A sentence inside a chunk causes parse errors such as `unexpected symbol`.
   - Include a model-status table whenever any model (main, CR2, moderator, publication-bias) or figure fails; never let a failure show up only as blank or all-`NA` cells.
   - After generating Word reports, visually verify them: render each `.docx` to PDF or page PNGs (for example LibreOffice headless) and fix truncated tables, overflowing columns, missing figures, or broken layout before delivering.

9. Give the user a run-and-return workflow.
   - If R/Rscript is available in the current environment, run the analysis and render reports directly, then inspect the output folder before answering.
   - If R is not available, provide concise RStudio commands for the user to run: set the working directory, source the script, render Word/HTML, and optionally render PDF with a guarded TinyTeX fallback.
   - Tell the user that after R finishes, they can send the generated output folder or report file back. Then read the saved CSV/XLSX/HTML/PNG files, inspect the figures, verify model-status and warning outputs, and give a short results summary.
   - When reviewing a completed output folder, start with `model_status`, `main_summary`, `moderator_table`, `influence_summary`, `egger`/publication-bias outputs, and the generated figures. Flag any all-`NA` model, failed robust test, blank figure, missing report, or sample-count mismatch.
   - If the agent can run R locally, do not stop after writing code. Run the R script, save all tables/figures into the output folder, inspect key figures, and create the two default Word reports: `results_summary.docx` with overview, executive summary, key results, and only necessary figures/tables; and `all_tables_figures_summary.docx` containing every generated result table and figure. If R Markdown rendering hangs or LaTeX is missing, build the Word summaries directly from the saved CSV/XLSX/PNG outputs and state the fallback.
   - After generating Word reports, visually verify them: render each `.docx` to PDF or page PNGs (for example with LibreOffice headless), then inspect the pages for truncated tables, overflowing columns, missing figures, or broken layout before delivering. Fix and re-render if any page is unreadable.

10. Report results with source-aware caution.
   - State whether results use the full dataset or influence-excluded dataset.
   - When the user's goal is article replication, compare like with like: full-data results to article main results; influence-cleaned results only to article sensitivity/outlier results.
   - If the article says outliers were checked but not excluded, keep the full-data analysis as the primary model and describe influence-cleaned output as an additional sensitivity check.
   - Report `k` effects and `n` studies for every main/domain/subgroup result.
   - If the source article reports records, reports, studies, subsamples, groups, and effects separately, preserve those labels and do not collapse them into one generic `n`.
   - Prefer CR2 results when multiple effects are nested within studies.
   - Include model-based results only as a fallback or supplemental result when CR2 is unavailable.

## R Template

There are three bundled reference pipelines, each with an adapting guide:

```text
references/ip_wellbeing_reference_pipeline.R
```

Use this when the user wants a complete script modeled on the existing IP and wellbeing analysis. Prefer this file for full analyses because it preserves the user's mature code structure, plots, CR2 outputs, subdomain models, moderator helpers, and final reporting logic.

```text
references/primary_students_intervention_smd_pipeline.R
```

Use this when the data are intervention/pre-post meta-analysis data with treatment/control sample sizes, pre/post means and SDs, one-group/two-group/RCT designs, SMD/Hedges g, or reported statistics that need conversion to Cohen's d. Prefer this file for education intervention analyses because it preserves the user's mature effect-size fallback priority, outlier workflow, CR2 moderator functions, publication-bias checks, and forest plots.

```text
references/ai_literacy_one_two_group_gender_pipeline.R
```

Use this when the project separates one-group pre-post data and two-group pre-post/control data into different workbooks, then combines no-outlier datasets for literacy-type and gender-proportion moderator analyses. Prefer this file for AI-literacy-style analyses because it preserves the user's mature one-group SMCR logic, quasi-experimental/RCT filtering, SD imputation logic, manual exclusion block, combined dataset harmonization, gender moderator, literacy-type moderator, publication-bias checks, and forest plots.

```text
references/adapting_reference_pipeline.md
```

Read this before adapting the IP/wellbeing full reference pipeline.

```text
references/adapting_intervention_smd_pipeline.md
```

Read this before adapting the primary-students intervention SMD pipeline.

```text
references/adapting_ai_literacy_gender_pipeline.md
```

Read this before adapting the AI-literacy one/two-group gender-moderator pipeline.

```text
references/discovering_constructs_and_moderators.md
```

Read this before carrying over any domain, subdomain, construct, moderator, or plot-label logic from a reference pipeline.

```text
references/optional_module_guards.md
```

Read this before adapting optional moderator, scatter/facet plot, forest, funnel, or publication-bias blocks.

```text
references/warning_triage.md
```

Read this after running an adapted script and before deciding whether warnings require code changes.

```text
references/rmarkdown_reporting.md
```

Read this when generating `.Rmd`, Word/HTML/PDF reports, manuscript-ready summary tables, effect-size audit tables, moderator tables, robust-test tables, or figures from a meta-analysis pipeline.

If no reference pipeline matches the dataset, write a fresh project-specific script following the conventions in step 3 instead of looking for a generic starter template; none is bundled.

## Guardrails

- Preserve the user's extraction and coding definitions. For example, if the user defines a domain as "adaptive only" or "maladaptive only", do not reverse or combine it.
- Never inherit construct/domain/subdomain/moderator values from a reference script. Reference-script labels are examples only; extract the new project's analytic groups from the live workbook or from explicit user instructions.
- Select the effect-size family before coding: use Fisher-z/r pipelines for association meta-analyses, and SMD/Hedges-g pipelines for intervention/pre-post designs.
- When adapting the full reference pipeline, keep validated helper functions and model/plot blocks unchanged unless the new research question requires a real structural change.
- Do not generalize study-specific imputations or special-case corrections across datasets. Keep them only when the same study/source condition exists, otherwise remove or rewrite them explicitly.
- Prefer a small project-specific edits section at the top over scattering changes through the script.
- Do not treat two analysis variants as equivalent because they share a similar label. Verify the exact model definition from the data or script.
- Do not treat influence/outlier-cleaned estimates as the manuscript main result unless the source article's main model used the same exclusions. If the article retained outliers after diagnostics, the skill-generated main table should also retain them.
- Do not call the analysis complete until the output files and row/model counts are checked.
- If a model cannot run because `k` is too small, ids are missing, variance is invalid, or the model fails to converge, record that limitation in the report.
- Optional analyses must be data-gated. If a variable was created as an all-NA placeholder, skip its moderator or plot block instead of running it.
- Optional helper outputs must be guarded. Never pipe or print a possibly `NULL` object.
- Main model helpers should return both a fit object and a status/error table. When there is no moderator formula, omit `mods` from `metafor::rma.mv()` rather than passing `mods = NULL`.
- Pseudo-R2 for a moderator must compare the moderator model to a null model refitted on the same analytic subset (rows with non-missing moderator and usable levels), never to the full-data null model.
- Leave-one-study-out diagnostics must refit the same multilevel model after omitting each study so delta values are on the same scale as the reported pooled effect; do not substitute a simple inverse-variance mean.
- Expensive diagnostics that refit the model many times (leave-one-study-out, large bootstraps) should be controlled by an explicit config switch and default to off (opt-in), so a run stays fast on large datasets and during quick iterations. When skipped, record a `skipped` row with the reason in the model-status table and guard any figure/report block that consumes their output, rather than failing.
- If residual or influence diagnostics fail, capture and record the error message in the model-status table and use a documented fallback (for example manual marginal standardized residuals); never let diagnostics fail silently.
- In dplyr filters comparing a data column to a function argument with the same name, use `.env$` (for example `filter(.data$term == .env$target_term)`) to avoid data-masking bugs that silently select the wrong coefficient row.
- Moderator summaries across multiple variables must be normalized before `bind_rows()`: use columns like `moderator`, `level`, `k_effects`, and `n_studies`, plus numeric summary columns for continuous moderators. Avoid wide per-moderator summary columns that rely on vector recycling.
- A study-level forest plot must have exactly one row per study. Aggregate to the study id (not a subsample- or sample-name-unique label, which a multi-subsample study splits into several rows), keep a single representative label, and assert the plotted row count equals the number of distinct studies. Joining effects back to a study-order table that has multiple rows per study silently duplicates effect rows.
- Clear or version the output figures folder at the start of each run, and build the report's figure list from the paths actually written by the run, not a directory glob. Otherwise stale panels from a previous panel size or moderator set linger and get inserted into the all-figures report.
- Constrain Word tables to the page: when building `.docx` directly with `flextable`/`officer`, set table width to the page (`set_table_properties(layout = "autofit", width = 1)` / `fit_to_width()`), avoid a bare `autofit()` that overruns the margin, and use a landscape default section for wide manuscript tables. Column clipping is invisible in the `.docx` XML, so always render to PDF/PNG and check before delivering.
- R Markdown reports should be self-contained and reproducible: use relative paths when the Rmd lives beside the data; recompute or source model objects; print all required tables/figures inside chunks; guard every optional table/figure before printing.
- R Markdown prose must not be wrapped in R chunks. A common parse error is `unexpected symbol: The full...`, which means a narrative sentence was placed inside ```{r}``` fences.
- R Markdown reports should separate manuscript-facing content from audit files: show concise summaries and core results in Word/PDF, export large supporting tables to CSV beside the report.
- When PDF rendering fails with `pdflatex not found` or another LaTeX error, do not treat the report as unusable if Word rendered successfully. Report the Word `.docx` path and explain that it can be saved/exported as PDF, then provide TinyTeX install commands for direct PDF rendering.
- For Fisher-z/r analyses, distinguish per-effect `yi`/`vi` from overall model `yi`/`vi`: per-effect `yi`/`vi` go in the effect-size audit table; the overall row's `yi` is the pooled Fisher-z estimate and `vi` is the pooled estimate variance (`SE^2`).
- For article-comparison reports, include a short "consistency check" table when the article PDF/results are available: source article value, generated full-data value, generated sensitivity value if applicable, and a brief explanation for differences caused by rounding, effect metric labels, nesting level, robust method, or exclusions.
- When adapting the template, prefer configuration changes over rewriting core functions.

## Common User Requests

- "I collected the data; write the R analysis code."
- "Make my R meta-analysis script reusable for another extracted workbook."
- "Run the data analysis after extraction."
- "Convert these effect sizes and run metafor/CR2 models."
- "Use my previous IP and wellbeing R code as a general template."
- "Use my primary school students intervention R code as a general template."
- "Use my AI literacy one/two group gender moderator R code as a general template."
- "Use R Markdown to generate the results, including summary, tables, effect-size table, and figures."
- "Generate a Word/HTML/PDF report from the meta-analysis results."
