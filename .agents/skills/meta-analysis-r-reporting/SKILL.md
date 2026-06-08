---
name: meta-analysis-r-reporting
description: Build reusable R meta-analysis pipelines and R Markdown reports after study data or effect-size data have already been extracted into Excel/CSV files. Use when Codex needs to adapt, generate, audit, or run an R/Rmd script for psychological, education, health, or social-science meta-analysis datasets, especially workflows involving Pearson r/Fisher z, intervention or pre-post SMD/Hedges g, one-group/two-group/RCT designs, separate one-pre-post and two-pre-post workbooks, t/F/z/eta2/r-to-d conversion, gender-proportion moderators, multilevel metafor models, cluster-robust CR2 tests, influence/outlier diagnostics, subgroup/domain/moderator analysis, manuscript-ready effect-size and moderator tables, forest/funnel/scatter figures, publication-bias checks, Word/HTML/PDF R Markdown reports, and portable code that can be reused across projects.
---

# Meta-analysis R

## Workflow

1. Inspect the live data file before writing code.
   - Read sheet names, row count, column names, and a few example values.
   - Identify the effect-size source columns, sample-size column, study/effect identifiers, outcome/domain columns, and any moderators.
   - If the file is Excel, prefer `readxl::read_excel()` and let the user choose a sheet only when multiple plausible sheets exist.

2. Standardize similar column names before analysis.
   - Compare the live workbook's column names to `references/column_name_harmonization.md`.
   - Rename synonymous columns to the canonical names expected by the R template before converting effect sizes.
   - Do this as an explicit preprocessing step in the project script; do not manually edit the user's original workbook unless asked.
   - If two columns map to the same canonical field, prefer the more complete column and record the choice in the report.

3. Decide which full reference pipeline or portable template to use.
   - If the user wants code "like my current R code", "all the code", "same as before", or a manuscript-ready IP/wellbeing-style analysis, use `references/ip_wellbeing_reference_pipeline.R` as the main source.
   - If the dataset has intervention/control fields, pre/post means and SDs, `one_group`/`two_group`/`RCT` designs, or SMD/Hedges g outcomes, use `references/primary_students_intervention_smd_pipeline.R` as the main source.
   - If the project has separate one-group and two-group pre/post workbooks, `Exi_intervention`/`Exi_control` flags, RCT/quasi-experimental filtering, `antecedent` recoded to `literacy_type`, or a `gender_proportion` moderator, use `references/ai_literacy_one_two_group_gender_pipeline.R` as the main source.
   - Copy the matching reference pipeline into the project folder and adapt only the required project-specific blocks listed in `references/adapting_reference_pipeline.md`, `references/adapting_intervention_smd_pipeline.md`, or `references/adapting_ai_literacy_gender_pipeline.md`.
   - Use `scripts/meta_analysis_pipeline.R` only when the user wants a shorter general starter script or when the full reference pipeline is too project-specific for the new dataset.

4. Compare the standardized dataset to `references/meta_analysis_columns.md`.
   - Treat that file as the schema map and vocabulary guide.
   - Add missing optional columns as `NA`; do not invent values for missing required analysis fields.
   - Keep user-provided variable definitions literal. Do not reverse-score or recode conceptual variables unless the user explicitly defines the direction.

5. Discover constructs, domains, subdomains, and moderators from the new workbook.
   - Read `references/discovering_constructs_and_moderators.md` before adapting any project-specific labels.
   - Do not reuse old project levels or variables such as well-being, ill-being, Needs, Motivation, adaptive functioning, literacy type, antecedent, technology category, learning subject, gender proportion, or grade level unless those exact columns/values appear in the new workbook or the user defines them.
   - Generate model calls, subgroup splits, figure labels, and output filenames from the new dataset's actual column names and observed levels.

6. Add guards for optional modules before running them.
   - Read `references/optional_module_guards.md` before adapting moderator, scatter/facet plot, forest, funnel, publication-bias, or PET/PEESE blocks.
   - Creating an optional column as `NA` is not enough to justify running its module.
   - Skip optional modules with a clear `message()` when the required column is missing, all values are missing, there are too few model-ready rows, or a facet/group variable has no levels.
   - If a helper or `tryCatch()` returns `NULL`, do not pipe the result into `select()`, `mutate()`, `print()`, `ggplot()`, or file export. Check `!is.null(res) && nrow(res) > 0` first.
   - When combining moderator count/summary outputs across different moderators, export a long table with explicit `moderator` and `level` columns. Do not bind grouped summaries that still retain original moderator column names such as `design_inferred` and `country`, because different level counts can trigger vctrs recycling errors.

7. Use `scripts/meta_analysis_pipeline.R` as the fallback starter template.
   - Copy it into the user's project folder or create a project-specific script beside the data file.
   - Edit only the `CONFIG` block first: `data_path`, `sheet`, id columns, domain/subgroup columns, direction handling, and output directory.
   - Keep the template's three-stage naming pattern:
     - `dat_domain_full`: full cleaned analysis base.
     - `dat_domain_clean`: full base minus influential effects.
     - `dat_domain_use`: downstream dataset selected by `exclude_influential`.

8. Run the script and verify the outputs.
   - Confirm how many rows were read, retained, converted to `r`, and included in each model.
   - Check the conversion log before interpreting results.
   - Verify that the overall/main model actually fit before interpreting `main_summary`; if the table contains only `NA` estimates, inspect and report the model error instead of treating it as a result.
   - When reproducing or comparing against a published article, treat the article's main analytic sample as the primary target. Do not make influence-excluded data the main result unless the article also excluded those cases from the main analysis.
   - Align counting units before interpreting differences: report `k_effects`, `n_studies` or records, and when available `n_subsamples` or sample groups. A mismatch between article subsamples and script effect counts is not necessarily a statistical mismatch.
   - Keep non-convergent, underpowered, empty subgroup, or missing-field analyses visible in the report instead of silently skipping them.
   - After a run, read `references/warning_triage.md` to decide which warnings are harmless, which need guards, and which need statistical caveats.

9. Generate an R Markdown report when the user asks for results, outcomes, Word/PDF output, summary tables, or figures.
   - Read `references/rmarkdown_reporting.md` before creating `.Rmd` output.
   - The Rmd should rerun the analysis or source a deterministic analysis script, then render summary text, effect-size conversion tables, model tables, moderator tables, robust/omnibus test tables, and figures in one document.
   - Include `html_document`, `word_document`, and `pdf_document` in YAML unless the user asks for only one format. Always keep the Word version as a practical fallback for PDF, because users can export the `.docx` to PDF even when LaTeX is missing. For Word output, use table-ready formatting (`knitr::kable` at minimum; `flextable` preferred when available). For PDF output, note that R Markdown needs a LaTeX engine such as TinyTeX/MiKTeX.
   - Keep Word/PDF reports readable: do not print very large row-level audit or diagnostic tables in the document. Export large tables such as effect-size audit, influence diagnostics, moderator counts, and full CR2 coefficient output to CSV files, then mention the CSV path in the report.
   - Save every generated table, figure, diagnostic, and report into one clearly named output folder beside the data file. Include at minimum CSV tables, optional XLSX workbook, PNG figures, HTML report, Word report, model-status table, and a plain-text or CSV output manifest.
   - When producing Word summaries, create two separate summary documents by default: (1) a manuscript-style `Results` summary with narrative text and only the necessary figures/tables that support that narrative, and (2) an `all_tables_figures_summary` Word file that includes all generated result tables plus every generated figure with short labels/captions for checking.
   - Add a short description before each major analysis section explaining what the analysis tests, which dataset it uses, and any key assumptions or caveats.
   - Write narrative descriptions as plain Markdown text, not inside `{r}` chunks. Inline expressions such as `` `r nrow(dat)` `` belong in Markdown prose; only executable R statements belong inside R chunks.
   - Do not rely on a previously exported workbook if it might be incomplete; recompute model objects inside the Rmd or source the script and assert objects exist.
   - Include a manuscript-style moderator table using the same main-result header style when requested or when building Word-ready tables: `Correlate`, `k`, `n`, `r [95% CI]` or `g [95% CI]`, `SE`, `p`, heterogeneity components such as `tau^2`, optional `R^2`, and `Robust Test`. Use moderator names as section rows and indented moderator levels as result rows.
   - Include an effect-size audit table listing study/effect ids, source statistic, original effect, converted effect, variance, direction handling, and inclusion status.
   - Include a manuscript-style overall/main effect table with `Correlate`, `k`, `n`, `yi`, `vi`, `r [95% CI]` or `g [95% CI]`, `SE`, `p`, heterogeneity components such as `tau^2(2)` and `tau^2(3)`, optional `R^2(2)`/`R^2(3)`, and `Robust Test` when available. Do not include a separate `z` column unless the user explicitly asks for it.
   - If the report is intended to check consistency with an article, put the full-data main model first and label it as the article-comparison result. Put influence-cleaned or no-outlier models in a separate sensitivity-analysis section with the exclusion rule and flagged counts.
   - Include a model-status table whenever the main model, CR2 model, moderator model, PET/PEESE model, or figure model fails; do not let failures appear only as blank cells or all-`NA` rows.
   - When the user asks for a Word summary, a result summary, or a report "like the article/PDF Results section", generate a manuscript-style `Results` document rather than a technical dump. Start with sample descriptives, then overall effect, moderator analyses, sensitivity/influence checks, and publication-bias diagnostics. Write explanatory paragraphs before tables, in the style of journal Results prose.
   - Results prose must report the dataset's unique findings, not generic template descriptions. Avoid filler such as "Moderator analyses were used to evaluate whether..." unless it is immediately followed by substantive findings. State which effects were significant, which levels were strongest/weakest, the direction of continuous moderators, and what bias/sensitivity checks imply.
   - If the user provides a manuscript DOCX/PDF as a style example, use it to learn the desired Results-style format, prose level, and figure/table inclusion logic; do not mechanically copy that manuscript's exact Results structure when the new dataset calls for different sections. For the new summary, include the kinds of tables and figures that would normally appear in the manuscript body Results, and exclude Supplementary Materials/SM items such as `Table S...`, `Figure S...`, or figures/tables only mentioned as being in the Supplementary Materials unless the user explicitly asks for them.
   - Do not paste unrelated CSV outputs into one large Word table. Split tables by analysis family: overall/main effects, omnibus moderator tests, level-specific moderator estimates, continuous moderators, multilevel Egger, PET/PEESE, and influence diagnostics should be separate small tables with short captions/notes.
   - In `results_summary.docx`, include the full manuscript-facing `moderator_table.csv` for Moderator Analyses, including moderator header rows and level rows. Do not shrink it to only omnibus/header rows unless the user explicitly asks for a shorter table.
   - Order Word content as narrative -> corresponding table -> corresponding figure. For example, put the full moderator table directly under Moderator Analyses, followed by the combined moderator estimate figure; put continuous moderator tables beside/above their scatter plots; put Egger/PET-PEESE tables in the publication-bias section before the funnel plot.
   - In the manuscript-style `Results` summary, include only figures that directly support the written narrative. For categorical moderators, prefer a combined moderator estimate plot showing point estimates, confidence intervals, study counts, effect counts, and CI labels over many separate boxplots. Include a scatter plot only for a significant/central continuous moderator, and include a funnel plot only for publication-bias interpretation. Do not include dense forest plots or non-significant moderator figures in this short Word summary unless the user explicitly requests all figures there.
   - Round manuscript-facing values: estimates/SE/t/df usually to 2-3 decimals, p values as `<.001` or three decimals, and avoid long raw numeric strings from CSV exports.
   - For manuscript-facing tables, CR2 omnibus results should display as `F(df1, df2) = value, p = ...`, not `Robust F(...) = ...`. It is fine to explain in the methods/note that CR2 robust tests were used, but do not repeat `Robust` inside every table cell.
   - If a categorical moderator's level estimates are available but the omnibus cell says unavailable, debug the CR2 Wald contrast before interpreting it as a statistical result. With `clubSandwich::Wald_test()`, pass an explicit contrast matrix rather than coefficient index numbers, because some `clubSandwich` versions require a matrix and name-parsing helpers can fail on coefficient names.

10. Give the user a run-and-return workflow.
   - If R/Rscript is available in the current environment, run the analysis and render reports directly, then inspect the output folder before answering.
   - If R is not available, provide concise RStudio commands for the user to run: set the working directory, source the script, render Word/HTML, and optionally render PDF with a guarded TinyTeX fallback.
   - Tell the user that after R finishes, they can send the generated output folder or report file back. Then read the saved CSV/XLSX/HTML/PNG files, inspect the figures, verify model-status and warning outputs, and give a short results summary.
   - When reviewing a completed output folder, start with `model_status`, `main_summary`, `moderator_table`, `influence_summary`, `egger`/publication-bias outputs, and the generated figures. Flag any all-`NA` model, failed robust test, blank figure, missing report, or sample-count mismatch.
   - If Codex can run R locally, do not stop after writing code. Run the R script, save all tables/figures into the output folder, inspect key figures, and create both Word summaries: a `Results` summary with narrative text plus only necessary figures/tables, and an all-tables-and-figures summary containing every generated result table and figure. If R Markdown rendering hangs or LaTeX is missing, build the Word summaries directly from the saved CSV/XLSX/PNG outputs and state the fallback.

11. Report results with source-aware caution.
   - State whether results use the full dataset or influence-excluded dataset.
   - When the user's goal is article replication, compare like with like: full-data results to article main results; influence-cleaned results only to article sensitivity/outlier results.
   - If the article says outliers were checked but not excluded, keep the full-data analysis as the primary model and describe influence-cleaned output as an additional sensitivity check.
   - Report `k` effects and `n` studies for every main/domain/subgroup result.
   - If the source article reports records, reports, studies, subsamples, groups, and effects separately, preserve those labels and do not collapse them into one generic `n`.
   - Prefer CR2 results when multiple effects are nested within studies.
   - Include model-based results only as a fallback or supplemental result when CR2 is unavailable.

## R Template

There are four bundled code sources:

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

Read this before adapting optional moderator, scatter/facet plot, forest, funnel, publication-bias, or PET/PEESE blocks.

```text
references/warning_triage.md
```

Read this after running an adapted script and before deciding whether warnings require code changes.

```text
references/rmarkdown_reporting.md
```

Read this when generating `.Rmd`, Word/HTML/PDF reports, manuscript-ready summary tables, effect-size audit tables, moderator tables, robust-test tables, or figures from a meta-analysis pipeline.

Use this shorter bundled script only as a general fallback:

```text
scripts/meta_analysis_pipeline.R
```

The shorter script is designed to be general rather than tied to one project. It supports:

- Excel or CSV input.
- Column-name harmonization through `CONFIG$column_map`.
- NA-like string normalization.
- Safe creation of optional columns.
- Conversion to Pearson `r` from common statistics: Pearson/Spearman r, latent r, phi, Kendall tau, standardized beta, unstandardized beta with CI, t, F, odds ratio, prevalence/risk ratio, chi-square/Cramer's V, and Cohen's d.
- Fisher z and sampling variance computation.
- Optional within-study aggregation.
- Multilevel `metafor::rma.mv()` models.
- `clubSandwich` CR2 coefficient tests.
- Leave-one-effect-out influence diagnostics.
- Domain and subgroup models.
- CSV outputs and a text report.

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
- Moderator summaries across multiple variables must be normalized before `bind_rows()`: use columns like `moderator`, `level`, `k_effects`, and `n_studies`, plus numeric summary columns for continuous moderators. Avoid wide per-moderator summary columns that rely on vector recycling.
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
