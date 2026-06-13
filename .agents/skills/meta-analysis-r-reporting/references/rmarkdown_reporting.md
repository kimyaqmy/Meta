# R Markdown Reporting for Meta-analysis

Use this when the user asks for R Markdown, Word/HTML/PDF output, outcome documents, results reports, summary tables, effect-size tables, moderator tables, or figures.

## Default deliverables

Create an `.Rmd` beside the data file or beside the adapted R script. Prefer relative paths inside the Rmd when possible:

```r
DATA_PATH <- "test_data.csv"
```

By default produce only the two Word deliverables (`results_summary.docx` and `all_tables_figures_summary.docx`); create HTML, PDF, or Rmd technical reports only when the user explicitly asks for them. When the user does request multiple formats, use YAML like:

```yaml
geometry: landscape,margin=0.45in
output:
  html_document:
    toc: true
    toc_depth: 3
    number_sections: true
    df_print: paged
  word_document:
    toc: true
    toc_depth: 3
    reference_docx: landscape_reference.docx
  pdf_document:
    toc: true
    toc_depth: 3
    number_sections: true
    latex_engine: xelatex
```

For wide manuscript tables, prefer landscape output. Create a small `landscape_reference.docx` beside the Rmd and point `word_document.reference_docx` to it. Set the Word reference document to landscape orientation with narrow margins; for PDF, use `geometry: landscape,margin=0.45in`.

Use landscape/narrow-margin report geometry whenever a Word or PDF report contains meta-analysis tables wider than about eight columns, long moderator tables, model-status tables with messages, or multi-column publication-bias output. Do not let Word/PDF print raw 10-18 column CSVs in portrait layout. Keep full technical detail in CSV/XLSX exports, and display compact manuscript-facing or checking columns in the report.

PDF rendering requires a LaTeX engine. Always keep the Word output as a fallback because the `.docx` can be exported/saved as PDF from Word when LaTeX is missing. If `rmarkdown::render(..., "pdf_document")` fails because LaTeX is missing, tell the user that the Word file is still usable and can be saved as PDF, then provide TinyTeX installation commands:

```r
install.packages("tinytex")
tinytex::install_tinytex()
```

The Rmd should either:

- rerun the analysis directly, or
- source a project script and verify required objects exist.

Do not depend on an exported workbook as the only source of results unless the workbook has been checked to contain real rows. If the workbook is empty/header-only, recompute inside the Rmd.

## Output-folder workflow

Every generated analysis should use one explicit output folder, for example:

```r
OUTPUT_DIR <- "meta_analysis_outputs_project_name"
dir.create(OUTPUT_DIR, showWarnings = FALSE, recursive = TRUE)
```

Clear previously generated figures (and any panel-numbered images) at the start of each run, for example `file.remove(list.files(figdir, pattern = "\\.png$", full.names = TRUE))`. Otherwise stale panels from an earlier panel size or moderator set linger in the folder and get picked up by the all-figures report (e.g. a `..._part_05.png` left behind after switching from 30 to 40 rows per panel). Build the report's figure list from the paths actually written by this run, not from a directory glob.

Save all generated artifacts into that folder or beside the Rmd when the file type is a rendered report:

- CSV tables: `main_summary.csv`, `model_status.csv`, `effect_size_audit.csv`, `moderator_table.csv`, `moderator_counts.csv`, `influence_summary.csv`, `influence_diagnostics.csv`, `publication_bias.csv` (multilevel Egger slope + PET/PEESE intercepts), and `pet_peese_summary.csv` (conditional PET-PEESE selection).
- Optional XLSX workbook: `meta_analysis_results.xlsx`.
- Figures: forest plots, funnel plots, subgroup plots, and moderator scatter plots as `.png`.
- Saved source files: copy the main analysis `.R` script plus any helper `.R` or generated `.Rmd` files used for the run into `scripts/` or `source/` under the output folder.
- Source manifest: `script_manifest.csv` listing source path, saved path, run timestamp, checksum, and file size for every saved R/Rmd source file.
- Text manifest: `output_manifest.csv` or `meta_analysis_report.txt` listing every output path, row count/status, date-time generated, and saved source files.
- Word reports: create two files by default when the user asks for a summary/report:
  - `results_summary.docx`: overview, executive summary, key results, and only relevant text-matched figures/tables.
  - `all_tables_figures_summary.docx`: a checking document containing all generated result tables and every generated figure with short captions.
- Optional technical reports: create HTML, PDF, or Rmd reports only when the user explicitly asks for them.

When R is not available to the agent, provide RStudio commands and ask the user to run them. After the user returns the output folder or rendered report, inspect the folder directly: read the CSV/XLSX summaries, open or view figure files, check model-status rows, and then give a concise summary of the results and any warnings.

## Required report sections

Every Rmd report should include:

1. Data and conversion summary.
2. Effect-size audit export to CSV, plus a brief in-document note and row count.
3. Main meta-analysis summary table.
4. Robust/CR2 table when available.
5. Moderator analyses table in manuscript-ready format.
6. Moderator count table in long format exported to CSV.
7. Publication-bias tables: (a) the publication-bias suite — the multilevel Egger slope, the PET intercept, and the PEESE intercept (all CR2-robust within the multilevel model); and (b) the conditional PET-PEESE estimate, which selects the PEESE intercept when the PET intercept is significant one-tailed in the pooled-effect direction and otherwise reports the PET intercept with the conclusion that the bias-adjusted effect is not distinguishable from zero.
8. Figures: forest plot, funnel plot, and any requested moderator scatter/subgroup figures.
9. Interpretation notes and limitations, including direction handling and whether results use full or influence-excluded data.

Each major analysis section should begin with 1-3 sentences describing what is being tested, whether the full or influence-cleaned dataset is used, and how to interpret the table. Keep large diagnostic/audit data out of Word/PDF; export it as CSV and mention the path.

For display safety, Word/PDF report tables should usually use compact columns:

- main effects: model, dataset, k, n/studies or samples, effect with CI, SE, p, and robust test;
- moderator omnibus: moderator, status, omnibus test, p, and message;
- moderator level estimates: moderator or level, k, n/studies, effect with CI, p, robust test, status, and message;
- publication bias: model, term, k, n/studies, estimate, SE, t/df, p, ci_lb, ci_ub (or a formatted `estimate_ci`), status, and message — `term` distinguishes the Egger `SE slope` from the PET and PEESE `intercept` rows; intercepts may be back-transformed (e.g. Fisher z to r) for display while the Egger slope stays on its native per-SE scale;
- conditional PET-PEESE (`pet_peese_summary`): pet intercept, two-tailed p, one-tailed p (pooled-effect direction), decision rule, selected model (PET or PEESE), adjusted estimate with CI, a plain-language `conclusion`, and status;
- model status: model, status, short message, k, and n/studies.

If a full table is too wide or too long for Word/PDF, show a readable compact view or split it by moderator/analysis family, then point to the complete CSV/XLSX file. Do not squeeze all raw columns into one tiny portrait table.

## Results-style Word summary

When the user asks for a Word summary, a "summary like the paper/PDF", or a report similar to a journal Results section, do not produce a generic technical summary. Produce a manuscript-style `Results` document with narrative paragraphs and selective tables/figures.

If the user provides a manuscript DOCX/PDF as a style example, inspect the main-text `Results` section to learn the desired reporting format, prose level, and figure/table inclusion logic. Do not mechanically copy that manuscript's exact Results structure when the new dataset calls for different sections. Use the example to decide what kind of content belongs in a manuscript-body summary rather than Supplementary Materials. In practice:

- include the kinds of figures/tables that would normally be shown or directly discussed in the manuscript body Results for the new analysis;
- exclude items labeled `Table S...`, `Figure S...`, `Fig. S...`, `Supplementary`, `SM`, or only mentioned as being in the Supplementary Materials;
- use a comparable result flow when relevant, such as final-sample descriptives, RQ-specific result subsections, sensitivity analyses, and publication-bias/robustness checks, but adapt section order and emphasis to the new dataset's actual analyses;
- use the manuscript's body-text figure/table density as the guide. If the example body has only selected figures/tables, do not include every generated output figure/table in the Word summary.

Use this default structure:

1. `Results`
2. `Descriptives for the Final Sample`
3. `Summary of Findings` (executive synthesis: key-findings table + synthesizing narrative)
4. `Overall Effect` or `Overall Meta-analysis`
5. `Moderator Analyses`
6. Central moderator subsections, such as `Academic Domain`, `Construct`, `Outcome Type`, `Implementation`, or the dataset's actual moderator names.
7. `Influence and Sensitivity Analyses`
8. `Publication Bias`
9. `Files for Full Checking` only if helpful; keep it short.

The `Descriptives for the Final Sample` section should report the analytic counts in article-like prose:

- number of effect sizes (`k`);
- number of studies/records (`n`);
- number of subsamples/groups when available;
- distribution of central categorical variables, such as intervention type, domain, educational level, publication status, design, duration, or construct.

For example:

```text
The final analytic dataset consisted of 288 effect sizes from 132 studies and 139 subsamples. PBL was investigated most often (...), followed by PjBL (...) and CBL (...).
```

### Summary of Findings (executive synthesis)

Open the Results, right after the descriptives, with a `Summary of Findings` section. This is the concrete form of the "executive summary / key results" the `results_summary.docx` deliverable calls for: an at-a-glance synthesis before the detailed sections, so a reader sees every headline result in one place. It is especially valuable when the analysis has multiple sets or families (for example adaptive vs maladaptive outcomes, or several outcome domains); for a single-set analysis it is one row (or full-data plus sensitivity rows).

The section has two parts:

1. A compact **key-findings table**, one row per analysis set / family / main model, with columns:
   - set/model label, `k`, `n`;
   - pooled effect `[95% CI]` (back-transformed to `r` or on the `g` scale, as appropriate) and `p`;
   - 95% prediction interval;
   - `I2` total / between / within;
   - significant moderators (names, or `none`);
   - publication-bias summary: the Egger `p` and the conditional PET-PEESE adjusted estimate, worded `not distinguishable from 0` when the PET test is not significant.

2. A short **synthesizing narrative**, one paragraph per set, in plain manuscript prose that pulls together: the pooled effect with a direction/magnitude interpretation; the prediction interval in plain language; heterogeneity (the `Q` test and the `I2` decomposition); the significant omnibus moderators with their CR2 `F` statistics (or an explicit statement that none reached significance); the influence/outlier outcome; and the publication-bias result (Egger slope plus the conditional PET-PEESE estimate, using the `not distinguishable from zero` wording for a non-significant PET and the high-`I2` caveat).

Example narrative paragraph for one set:

```text
Maladaptive social functioning. The pooled correlation was r = 0.18 [0.12, 0.24] (Fisher z = 0.184, CR2 robust p < .001), based on 205 effect sizes from 42 studies; because IPC is coded as a destructive construct, this positive association indicates that higher interparental conflict was associated with more maladaptive social-functioning outcomes. The 95% prediction interval on the r scale was [-0.21, 0.51], the range in which the true correlation of a new comparable study is expected to fall. Heterogeneity was substantial relative to sampling error (Q(204) = 980.4, p < .001; I2 total = 86.1%, of which 41.2% between studies and 44.9% within studies). Significant omnibus moderators (p < .05): sf_domain_cat (F(2, 18.4) = 5.10, p = .017). Cook's D screening flagged 3 effects from 2 studies; the no-outlier sensitivity pooled r was 0.16 [0.11, 0.22]. Publication-bias checks: the multilevel Egger funnel-asymmetry test gave slope = -0.02, p = .956; the conditional PET-PEESE bias-adjusted estimate was not distinguishable from zero (PET selected; intercept r = 0.14 [-0.05, 0.32] shown for reference, one-tailed p = .101).
```

Assemble both parts entirely from the result objects already computed for the detailed sections (the pooled fit, the moderator omnibus table, the influence summary, `publication_bias`, and `pet_peese_summary`); never refit models for the summary, so the headline numbers cannot drift from the tables they summarize. A working implementation is `key_findings` and `summary_findings_par()` in `testing_2/run_ipc_sf_meta_analysis.R`.

Write the `Overall Effect` section as prose first, then table:

- identify the model type, such as three-level multilevel meta-analysis;
- state whether the result is full data or influence-cleaned;
- report `g [95% CI]` or `r [95% CI]`, the 95% prediction interval, SE, p, and CR2 robust test;
- interpret direction and magnitude cautiously;
- put influence-cleaned/no-outlier results in a sensitivity paragraph unless it is the user's defined main model.

Write `Moderator Analyses` like an article Results section:

- explain what moderators test before showing the table;
- prioritize unique findings over template prose: name the significant moderators, report the direction or strongest/weakest levels, and briefly state what nonsignificant core moderators imply;
- report omnibus CR2 tests in one compact table;
- write separate paragraphs for significant or theoretically central moderators;
- include level-specific tables only for the moderator currently being discussed;
- do not discuss every nonsignificant moderator at equal length.
- In `results_summary.docx` and `all_tables_figures_summary.docx`, include the full manuscript-facing `moderator_table.csv` unless the user explicitly asks for a shorter table. Keep technical row markers such as `row_type` internal; do not display or export them in manuscript-facing moderator tables. Likewise, do not display a separate `moderator` column beside the level label in the manuscript table: when the raw table carries both a `moderator` and a `level` column they overlap (the omnibus/header row already shows the moderator name), so collapse them into one label column — moderator name on the header row, the level (optionally indented) on level rows — exactly as the `Moderation` pattern does. Keep the `moderator` column only in the `moderator_table.csv`/XLSX exports, where it groups level rows by their moderator. For categorical moderators, display CR2 omnibus `F(df1, df2)` details only on omnibus/header rows under `Omnibus Test`. Level rows should show estimates, CIs, counts, p values, and status, but not per-level `t(...)` robust-test strings or technical message columns. Continuous moderators belong in this same table as an omnibus/header row plus `Intercept` and `Slope (per unit)` rows; see "Continuous moderators in the same moderation table".
- Keep the local order as narrative -> table -> matching figure. The combined moderator estimate figure should follow the moderator table, not be delayed until the end of the document.

Split tables by analysis family. Do not combine unrelated outputs into one large table just because they are adjacent in the CSV exports:

- Table: overall/main effect.
- Table: omnibus moderator tests.
- Table: selected level-specific moderator estimates.
- Table: continuous moderators (full CR2 slope detail; the omnibus + Intercept + Slope rows also appear inline in the main moderator table).
- Table: publication-bias checks (Egger slope, PET intercept, PEESE intercept) plus the conditional PET-PEESE estimate.
- Table: influence diagnostics or excluded/flagged studies, only if needed.

For publication bias, use a short prose paragraph, then the suite table, then a sentence stating the conditional PET-PEESE result and its table:

```text
Three checks were estimated within the multilevel model with CR2 robust inference: a multilevel Egger regression (slope of effect sizes on their standard errors, a funnel-asymmetry test), PET, and PEESE. PET-PEESE is a two-step conditional procedure (Stanley & Doucouliagos, 2014): PET regresses effect sizes on their standard errors and its intercept estimates the effect of an ideal, infinitely precise study (SE = 0); this intercept is first tested one-tailed in the direction of the pooled effect. If the test is not significant, the bias-adjusted effect is reported as not distinguishable from zero (the PET intercept and CI are shown for reference, not as a point estimate of the true effect). If it is significant, the PEESE intercept (a regression on the sampling variance) is reported instead, because PET underestimates true nonzero effects while PEESE is less biased in that case. Here the Egger slope was ..., and the conditional PET-PEESE result was ... . Because dependent effect sizes are nested within studies, these checks should be interpreted cautiously; with very high heterogeneity (total I^2 > ~90%), PET-PEESE adjustments are unreliable (Stanley, 2017) and should be read qualitatively.
```

The suite table should include `model`, `term`, `k`, `n`, `estimate`, `SE`, `t`, `df`, `p`, a CI (`ci_lb`/`ci_ub` or `estimate_ci`), and `status`, with one row each for the Egger slope, the PET intercept, and the PEESE intercept. Add a small conditional `pet_peese_summary` table (PET intercept, one/two-tailed p, decision rule, selected model, adjusted estimate + CI, conclusion). Extract the Egger slope and the PET/PEESE intercepts by coefficient name, never by row position, and do not relabel the slope and the intercept as the same quantity.

Use clean manuscript formatting:

- estimates, SE, t, and df: round to 2-3 decimals;
- p values: `<.001` or three decimals;
- do not print long raw numeric strings from CSV files;
- do not include a separate `z` column unless explicitly requested;
- use `tau^2` and `R^2`, not tau/R labels that look like unsquared values.
- for CR2 omnibus cells, display `F(df1, df2) = value, p = ...`; do not display `Robust F(...) = ...` in manuscript tables, even when the underlying test is cluster-robust.

Select figures to match the text:

- include a moderator plot only when that moderator is significant or central to the narrative;
- include a scatter plot only for a significant or theoretically important continuous moderator;
- include a funnel plot only in the publication-bias section;
- avoid dense forest plots in short Word summaries unless the user asks for all figures;
- avoid figures for nonsignificant moderators unless needed to explain a null finding.

For categorical moderator figures, prefer a combined moderator estimate plot over many separate boxplots. The combined plot should resemble a manuscript forest/table hybrid: moderator sections, level labels, point estimates, 95% CIs, a reference line at zero, and right-side columns for study count, effect count, and formatted CI.

Lay this hybrid out so the numbers never overlap the data:

- Group by moderator with `facet_grid(moderator ~ ., scales = "free_y", space = "free_y", switch = "y")` and left-placed bold strip labels, so each moderator is a clearly separated section.
- Place the numeric columns (`g [95% CI]`, `k / n`) as text in a reserved strip to the right of the data range, using fixed x positions beyond `max(ci_ub)` with `coord_cartesian(clip = "off")` and a right plot margin. Do not print the labels next to each point with `hjust`, because they then sit on top of the dots and CIs and run off the panel edge.
- Encode significance by fill (filled dot when the 95% CI excludes 0, hollow dot otherwise) rather than by a rainbow color-per-moderator legend.
- Keep the bottom caption short enough to fit the plot width; a long single-line caption is clipped at the right edge. Reserve the right strip generously (for example up to ~0.9 x the data span) so the widest `g [95% CI]` and `k / n` strings fit.

Also create an all-tables-and-figures summary document. This second document is not the manuscript-style Results summary. It should include all generated result tables plus every generated figure in the output folder, including dense forest plots, funnel plots, moderator plots, scatter plots, influence plots, and any other PNG/JPG figures. Keep captions short and file-based, optionally grouped by type:

- `Forest plots`
- `Funnel and publication-bias plots`
- `Moderator plots`
- `Continuous moderator scatter plots`
- `Influence/sensitivity plots`
- `Other generated figures`

The all-tables-and-figures summary is for checking completeness and visual QA, so do not exclude nonsignificant results from it. If a table is very large or too wide for Word, show a readable preview and link/note the full CSV/XLSX output path. If a figure is blank, unreadable, or too dense, include it and add a short note that it needs checking or may be better kept as a separate file.

If R Markdown rendering is unavailable, hangs, or fails because LaTeX/Pandoc/Word conversion is unavailable, build the Word summary directly from saved CSV/XLSX/PNG outputs (for example with `officer` + `flextable`). The direct Word summary should follow the same Results structure and should still be verified structurally or through Word/LibreOffice rendering when possible.

When building Word tables directly with `flextable`/`officer`, constrain every table to the page width: `set_table_properties(layout = "autofit", width = 1)` (and/or `flextable::fit_to_width(max_width = ...)`). Do not finish with a bare `autofit()`, which sizes columns to content and can push a wide manuscript table past the right page margin so the leftmost columns are clipped off the page. For wide tables (overall-effect, full moderator table), set the document's default section to landscape with narrow margins via `officer::body_set_default_section(doc, officer::prop_section(page_size = officer::page_size(orient = "landscape"), page_margins = officer::page_mar(left = 0.5, right = 0.5)))`. Always render the finished `.docx` to PDF/PNG and confirm no table is clipped before delivering — column clipping is invisible in the `.docx` XML and only shows on render.

When the report is meant to reproduce or compare against a published article, add a short consistency-check section near the beginning. The primary comparison should use the full-data model unless the article explicitly excluded outliers/influential cases from its main analysis. Put no-outlier or influence-cleaned results in a sensitivity-analysis section, not as the primary article-comparison result.

The consistency-check section should align counting units before comparing estimates:

- `k_effects`: row-level effect sizes used in the model.
- `n_studies` or `n_records`: reports/studies/records, depending on the article's label.
- `n_subsamples` or `n_groups`: independent subsamples, cohorts, classrooms, or groups when the article reports them separately.

If the article reports records, subsamples, and effect sizes separately, show all available counts. Do not compare article subsamples to script effect counts as if they were the same quantity.

## Publication-bias diagnostics

For dependent effect-size datasets fitted with `metafor::rma.mv()`, fit two multilevel meta-regressions and read three coefficients from them. Egger and PET share the `yi ~ SE` model: the Egger test is its **slope** (funnel asymmetry), PET is its **intercept** (bias-adjusted effect at SE = 0). PEESE is the **intercept** of `yi ~ variance` (`I(sei^2)`, which equals `vi`). Extract every coefficient by name (`names(coef(fit))`), never by row position, so the `sei` slope is not accidentally exported as the intercept or as `NA`.

```r
dat_bias <- dat %>% dplyr::mutate(sei_mod = sqrt(vi))

# Egger (slope of sei_mod) and PET (intercept) come from this model:
fit_pet <- metafor::rma.mv(
  yi = yi, V = vi,
  random = ~ 1 | study_id_clean/effect_id_clean,
  mods = ~ sei_mod, data = dat_bias, method = "REML", test = "t"
)
# PEESE (intercept) regresses on the sampling variance:
fit_peese <- metafor::rma.mv(
  yi = yi, V = vi,
  random = ~ 1 | study_id_clean/effect_id_clean,
  mods = ~ I(sei_mod^2), data = dat_bias, method = "REML", test = "t"
)

# Pull one named coefficient with a CR2 Satterthwaite-df 95% CI.
bias_row <- function(fit, model_label, term_label, coef_name) {
  cn <- names(coef(fit)); i <- which(cn == coef_name)
  ct <- clubSandwich::coef_test(fit, vcov = "CR2",
          cluster = dat_bias$study_id_clean, test = "Satterthwaite")
  est <- as.numeric(fit$beta[i]); se <- ct$SE[i]; df <- ct$df_Satt[i]
  crit <- if (is.na(df) || df <= 0) qnorm(.975) else qt(.975, df)
  tibble::tibble(model = model_label, term = term_label,
    k = nrow(dat_bias), n = dplyr::n_distinct(dat_bias$study_id_clean),
    estimate = est, SE = se, t = ct$tstat[i], df = df, p = ct$p_Satt[i],
    ci_lb = est - crit * se, ci_ub = est + crit * se, status = "ok")
}

publication_bias <- dplyr::bind_rows(
  bias_row(fit_pet,   "Multilevel Egger", "SE slope",  "sei_mod"),
  bias_row(fit_pet,   "PET",              "Intercept", "intrcpt"),
  bias_row(fit_peese, "PEESE",            "Intercept", "intrcpt")
)

# Conditional PET-PEESE (Stanley & Doucouliagos, 2014): one-tailed PET test
# in the direction of the pooled effect (sign of fit_full's intercept).
pet  <- publication_bias[publication_bias$model == "PET", ]
peese <- publication_bias[publication_bias$model == "PEESE", ]
pooled_dir <- sign(as.numeric(fit_full$beta[1]))
pet_p_one <- if (sign(pet$estimate) == pooled_dir) pet$p / 2 else 1 - pet$p / 2
selected  <- if (pet_p_one < .05) peese else pet
pet_peese_summary <- tibble::tibble(
  pet_intercept = pet$estimate, pet_p_one_tailed = pet_p_one,
  decision_rule = "PET one-tailed p < .05 -> report PEESE intercept; else report PET intercept",
  selected_model = if (pet_p_one < .05) "PEESE" else "PET",
  adjusted_estimate = selected$estimate, adjusted_ci_lb = selected$ci_lb,
  adjusted_ci_ub = selected$ci_ub,
  conclusion = if (pet_p_one < .05)
    "PET significant: genuine nonzero effect indicated; PEESE intercept is the bias-adjusted estimate."
  else
    "PET not significant: bias-adjusted effect not distinguishable from zero; intercept and CI shown for reference."
)
```

Report the `sei_mod` slope as the multilevel Egger test and the two `intrcpt` rows as PET and PEESE. For Fisher-z/r analyses, back-transform the PET/PEESE **intercepts** to r for display (the Egger slope is per-SE and stays on the z scale). Follow the conditional `conclusion` in the narrative: when PET is not significant, state that the bias-adjusted effect is not distinguishable from zero rather than reporting the intercept as a point estimate, and add the high-I^2 caveat (Stanley, 2017). Working implementations of this exact pattern live in `testing/run_testing_meta_analysis.R` (`fit_bias_model` + the `pet_peese_summary` block) and `testing_2/run_ipc_sf_meta_analysis.R` (`bias_coef_row` + `pet_peese`).

## Rmd Prose vs Code Chunks

Narrative descriptions must be plain Markdown text, not R code chunks. Use inline R only inside Markdown prose:

```markdown
The full-data model includes `r nrow(meta_ready_full)` effects from
`r dplyr::n_distinct(meta_ready_full$study_id_clean)` studies.
```

Do not wrap prose in an R chunk:

````markdown
```{r influence-description}
The full-data model includes `r nrow(meta_ready_full)` effects.
```
````

That pattern causes parse errors such as `unexpected symbol: The full` because knitr sends the sentence to R as executable code. Put only executable R statements inside `{r}` chunks, such as table creation, model fitting, plotting, or `cat()` calls.

## Effect-size audit table

Always create an audit table like this, using the dataset's real column names, but export it to CSV instead of printing the full table in Word/PDF when it has many rows:

```r
effect_size_table <- conversion_log %>%
  dplyr::transmute(
    study_id = study_id_clean,
    effect_id = effect_id_clean,
    author = dplyr::coalesce(author, apa_citation, title),
    source_type = effect_size_type,
    original_effect = effect_size,
    converted_effect = r_for_analysis, # or yi/g/r depending on metric
    yi = yi,
    vi = vi,
    n = n_total,
    direction = dplyr::if_else(direction_reversed, "reversed", "kept"),
    included = !is.na(yi) & !is.na(vi) & is.finite(yi) & is.finite(vi) & vi > 0
  )

readr::write_csv(effect_size_table, file.path(OUTPUT_DIR, "effect_size_audit.csv"), na = "")
cat(sprintf(
  "The full effect-size audit table was exported to `%s` (%s rows).",
  file.path(OUTPUT_DIR, "effect_size_audit.csv"),
  nrow(effect_size_table)
))
```

For SMD pipelines, replace `converted_effect` with `g` or `smd_final`; for Fisher-z/r pipelines, show both `r` and Fisher `z` when possible.

## Main model summary table

Use manuscript-ready columns, not only a minimal estimate table. For Fisher-z models:

- per-effect `yi` and `vi` belong in the effect-size audit table;
- the overall row's `yi` is the pooled Fisher-z estimate;
- the overall row's `vi` is the squared SE of the pooled estimate;
- report the interpretable effect as `r [95% CI]` after back-transforming from Fisher z.

Recommended columns for the overall/main table:

- `model`
- `dataset`
- `k_effects`
- `n_studies`
- `n_samples` when available
- `r [95% CI]` or `g [95% CI]`
- `SE`
- `p`
- `Q_statistics`, formatted as `Q(df) = value, p < .001`
- `I2_total`
- `I2_between`
- `I2_within`

Do not include separate `robust_test` or `z` columns in manuscript-facing overall-effect tables unless the user explicitly asks for them. For Fisher-z models, use `r [95% CI]` for interpretation and keep Fisher-z details in the audit table if needed.

```r
format_p <- function(p) {
  dplyr::case_when(
    is.na(p) ~ "",
    p < .001 ~ "<.001",
    TRUE ~ sprintf("%.3f", p)
  )
}

format_ci <- function(lb, ub) {
  ifelse(is.na(lb) | is.na(ub), "", sprintf("[%.2f, %.2f]", lb, ub))
}

main_summary_raw <- dplyr::bind_rows(
  model_summary_row(fit_full, "Overall: full data", dat_full),
  model_summary_row(fit_clean, "Overall: no-outlier data", dat_clean)
)

main_summary <- main_summary_raw %>%
  dplyr::mutate(
    Q_statistics = format_q_statistic(fit),
    I2_total = i2$total,
    I2_between = i2$between_study,
    I2_within = i2$within_study
  )
```

For multilevel `rma.mv()` objects, extract coefficients with `stats::coef(fit)` and `stats::vcov(fit)` rather than relying only on `summary(fit)$beta`, because the summary object can differ across `metafor` versions or fail silently when the model did not fit.

Do not let model failures turn into all-`NA` result rows without explanation. In R Markdown reports, use a model helper that returns both `fit` and a `status` table, and print the status table whenever a model fails.

Describe influence cleaning explicitly. Use a transparent rule, such as Cook's distance from the full model with influential effects flagged at `Cook's D > 4/k`, where `k` is the number of model-ready effects. State that this is effect-level screening, not manual study deletion, and report both the number of flagged effects and the number of studies represented among those effects. Export the full influence diagnostic table to CSV.

When any effects are flagged, also include a dedicated table of the flagged influential effects in the manuscript-facing sensitivity section of `results_summary.docx` (not only the all-tables document). List one row per flagged effect with its study and effect ids, a few identifying descriptors (the central moderators, e.g. intervention type, domain, level), the effect size and SE, its Cook's D, the cutoff, and how far it exceeds the cutoff (a `ratio = Cook's D / cutoff`), sorted by Cook's D descending. This lets a reader see exactly which effects drove the sensitivity analysis. Export the same table to CSV (for example `influence_flagged_effects.csv`).

For article replication, include both model rows but label their role clearly:

- `Overall: full data (article-comparison main result)`.
- `Overall: influence-cleaned sensitivity result`.

If the article checked outliers but retained them, set moderator analyses to use the full-data dataset by default. Only use the influence-cleaned dataset for moderators when the user asks for sensitivity analyses or when the source article's moderator models used the same exclusion rule.

```r
safe_rma_mv_status <- function(dat, mods_formula = NULL, label = "model") {
  if (is.null(dat) || nrow(dat) < 3 || dplyr::n_distinct(dat$study_id_clean) < 2) {
    return(list(
      fit = NULL,
      status = tibble::tibble(
        model = label,
        status = "failed",
        message = "too few model-ready rows or studies"
      )
    ))
  }

  tryCatch({
    fit <- if (is.null(mods_formula)) {
      metafor::rma.mv(
        yi = yi,
        V = vi,
        random = ~ 1 | study_id_clean/effect_id_clean,
        data = dat,
        method = "REML",
        test = "t"
      )
    } else {
      metafor::rma.mv(
        yi = yi,
        V = vi,
        random = ~ 1 | study_id_clean/effect_id_clean,
        data = dat,
        method = "REML",
        test = "t",
        mods = mods_formula
      )
    }

    list(
      fit = fit,
      status = tibble::tibble(model = label, status = "ok", message = "")
    )
  }, error = function(e) {
    list(
      fit = NULL,
      status = tibble::tibble(model = label, status = "failed", message = e$message)
    )
  })
}
```

When `mods_formula` is `NULL`, omit the `mods` argument entirely. Do not call `metafor::rma.mv(..., mods = NULL)`, because some `metafor` versions/environments can fail or behave inconsistently.

```r
fit_full_out <- safe_rma_mv_status(meta_ready_full, label = "Overall: full data")
fit_full <- fit_full_out$fit

model_status <- dplyr::bind_rows(fit_full_out$status, fit_clean_out$status)

if (any(model_status$status != "ok")) {
  knitr::kable(model_status, caption = "Overall model status")
}
```

For CR2 robust tests, do not assume the intercept row is always named the same way. Accept `intrcpt`, `Intercept`, or `(Intercept)` when building internal robust-test labels, but do not put those labels in manuscript-facing overall-effect tables unless the user asks.

For manuscript-facing labels, strip the word `Robust` from CR2 omnibus display cells. Keep CR2/robust wording in table notes or methods prose, but not in each cell. Use a formatter like:

```r
format_omnibus_label <- function(label) {
  label <- stringr::str_replace_all(label, "^\\s*Robust\\s+", "")
  label <- stringr::str_replace_all(label, "^\\s*robust\\s+", "")
  label <- stringr::str_replace_all(label, "p\\s*=\\s*<\\.001", "p = <.001")
  label
}
```

For example, `Robust F(5, 16.02) = 9.46, p = <.001` should be displayed as `F(5, 16.02) = 9.46, p = <.001`.

## Manuscript-style moderator table

The moderator table should resemble manuscript tables, not just raw coefficient output. By default, use the same visible header style as the overall/main effect table. Use one section/header row per moderator and one indented row per level.

Recommended APA-style columns:

- `Moderation`
- `k`
- `n`
- `Estimate [95% CI]`
- `SE`
- `p`
- `R2_between`
- `R2_within`
- `Omnibus Test`
- `status`

For correlation/Fisher-z analyses, report back-transformed `r [95% CI]` values inside `Estimate [95% CI]`. For SMD analyses, report Hedges `g [95% CI]` or SMD on the model scale. Use `k` for effect sizes and `n` for distinct studies unless the source workbook has a reliable participant `N` column and the user asks for participant counts.

Pattern:

```r
make_level_rows <- function(dat, moderator, fit_set = NULL, metric = "r") {
  if (!has_min_levels(dat, moderator, 2)) return(NULL)

  dat_mod <- dat %>%
    dplyr::filter(!is.na(.data[[moderator]])) %>%
    dplyr::mutate(level = as.character(.data[[moderator]]))

  counts <- dat_mod %>%
    dplyr::group_by(level) %>%
    dplyr::summarise(
      n_studies = dplyr::n_distinct(study_id_clean),
      k_effects = dplyr::n(),
      .groups = "drop"
    )

  if (is.null(fit_set)) {
    fit_set <- tryCatch(
      metafor::rma.mv(
        yi = yi, V = vi,
        random = ~ 1 | study_id_clean/effect_id_clean,
        data = dat_mod,
        method = "REML",
        test = "t",
        mods = stats::as.formula(paste0("~ ", moderator, " - 1"))
      ),
      error = function(e) NULL
    )
  }

  if (is.null(fit_set)) return(NULL)

  est <- tibble::tibble(
    coef = names(stats::coef(fit_set)),
    estimate = as.numeric(stats::coef(fit_set)),
    se = as.numeric(fit_set$se),
    ci_lb = as.numeric(fit_set$ci.lb),
    ci_ub = as.numeric(fit_set$ci.ub),
    p_value = as.numeric(fit_set$pval)
  ) %>%
    dplyr::mutate(
      level = gsub(paste0("^", moderator), "", coef),
      level = gsub("^", "", level),
      level = trimws(gsub("\\.", " ", level))
    )

  # For Fisher z models only.
  if (metric == "r") {
    est <- est %>%
      dplyr::mutate(
        estimate = metafor::transf.ztor(estimate),
        ci_lb = metafor::transf.ztor(ci_lb),
        ci_ub = metafor::transf.ztor(ci_ub)
      )
  }

  dplyr::left_join(counts, est, by = "level") %>%
    dplyr::transmute(
      Moderation = paste0("  ", level),
      k = k_effects,
      n = n_studies,
      `Estimate [95% CI]` = sprintf("%.2f [%.2f, %.2f]", estimate, ci_lb, ci_ub),
      SE = sprintf("%.2f", se),
      p = format_p(p_value),
      `R2_between` = "",
      `R2_within` = "",
      `Omnibus Test` = "",
      status = "ok"
    )
}
```

Add a header row for each moderator showing the omnibus result when available:

```r
make_moderator_section <- function(dat, moderator, omnibus_label = "") {
  rows <- make_level_rows(dat, moderator)
  if (is.null(rows) || nrow(rows) == 0) return(NULL)
  omnibus_label <- format_omnibus_label(omnibus_label)

  header <- tibble::tibble(
    Moderation = moderator,
    k = nrow(dat),
    n = dplyr::n_distinct(dat$study_id_clean),
    `Estimate [95% CI]` = "",
    SE = "",
    p = "",
    `R2_between` = "",
    `R2_within` = "",
    `Omnibus Test` = omnibus_label,
    status = "ok"
  )

  dplyr::bind_rows(header, rows)
}
```

For CR2 robust omnibus tests, use `clubSandwich::Wald_test()` when the contrast is estimable. If it fails or is not positive definite, keep the coefficient-level rows and set the omnibus column to `NA` or a text note such as `Robust omnibus unavailable`.

Do not pass raw coefficient index numbers as `constraints` to `clubSandwich::Wald_test()`. Some `clubSandwich` versions require a contrast matrix and will fail even though the moderator model and level estimates are valid. Build the matrix explicitly:

```r
coef_names <- names(stats::coef(fit))
moderator_coef_idx <- grep("^mod", coef_names)
constraints <- matrix(0, nrow = length(moderator_coef_idx), ncol = length(coef_names))
constraints[cbind(seq_along(moderator_coef_idx), moderator_coef_idx)] <- 1
colnames(constraints) <- coef_names
W <- clubSandwich::Wald_test(
  fit,
  constraints = constraints,
  vcov = "CR2",
  cluster = dat_mod$study_id_clean,
  test = "HTZ"
)
```

If level-specific estimates appear but the omnibus label is unavailable, this is not multilevel Egger. It means the categorical moderator omnibus CR2/Wald test failed or was not extractable. Egger belongs in the publication-bias section and is the `yi ~ sqrt(vi)` model.

When the user wants to compare with an article table, build the moderator table from the same analytic sample used by the article. If the article main moderator models retained all effects, generate `moderator_table_full` for the manuscript comparison and optionally generate `moderator_table_influence_cleaned` as a separate sensitivity table. Avoid a single ambiguous `moderator_table` when both versions exist.

For article-style reporting, use table captions that reveal the analytic sample, for example:

- `Moderator analyses for overall effect: full data, article-comparison model`.
- `Moderator analyses for overall effect: influence-cleaned sensitivity model`.

Before `dplyr::bind_rows()` combines moderator header rows and level rows, make display-only columns the same type. Header rows often contain pseudo-R2 values and blank estimate cells, while level rows contain numeric estimates and blank omnibus-test cells. Convert manuscript-display columns such as `Estimate [95% CI]`, `SE`, `p`, `R2_between`, `R2_within`, and `Omnibus Test` to character strings before binding; keep count columns such as `k` and `n` numeric.

### Continuous moderators in the same moderation table

Report continuous moderators in the same moderation table as the categorical ones, using the identical schema, not only as a separate slope-only table. Each continuous moderator contributes three rows in the same `moderator_table` columns (`Moderation`/`moderator`, `level`, `k`, `n`, `Estimate [95% CI]`, `SE`, `p`, `R2_between`, `R2_within`, `Omnibus Test`, `status`). If the raw table keeps separate `moderator` and `level` columns (as below), collapse them to the single label column at display time and drop the redundant `moderator` column, per the manuscript-table rule above:

- one **omnibus/header** row (like a categorical moderator header) carrying `k`, `n`, pseudo-R2, and a CR2 robust slope test in `Omnibus Test`;
- an **Intercept** row (model-based estimate, 95% CI, SE, p);
- a **Slope (per unit)** row (model-based estimate, 95% CI, SE, p).

Use model-based estimate/CI/SE/p for the Intercept and Slope rows, exactly as categorical cell-means level rows are model-based; reserve the CR2 robust test for the omnibus row. The single-predictor omnibus is the CR2 Wald test on the slope, displayed as `F(df1, df2) = value, p = ...` to match categorical omnibus cells. Compute pseudo-R2 against a null model refitted on the same numeric analytic subset (see the pseudo-R2 rule), and floor each component at 0 with `max(0, .)`; for a non-significant continuous moderator both components are normally ~0 (often slightly negative before flooring), which is correct, not a bug.

```r
analyse_continuous_moderator <- function(dat, moderator) {
  dcm <- dat %>% dplyr::mutate(.x = suppressWarnings(as.numeric(.data[[moderator]]))) %>%
    dplyr::filter(is.finite(.x))
  if (nrow(dcm) < 10 || dplyr::n_distinct(dcm$.x) < 5) return(NULL)

  fit_cm <- metafor::rma.mv(yi, V = vi, random = ~ 1 | study_id_clean/effect_id_clean,
                            data = dcm, method = "REML", test = "t", mods = ~ .x)
  slope_i <- 2L
  est <- as.numeric(fit_cm$beta); se <- as.numeric(fit_cm$se)
  ci_lb <- as.numeric(fit_cm$ci.lb); ci_ub <- as.numeric(fit_cm$ci.ub); pv <- as.numeric(fit_cm$pval)

  # CR2 robust omnibus on the slope (explicit contrast matrix, not a coef index).
  C <- matrix(0, nrow = 1, ncol = length(est)); C[1, slope_i] <- 1
  W <- clubSandwich::Wald_test(fit_cm, constraints = C, vcov = "CR2",
                               cluster = dcm$study_id_clean, test = "HTZ")
  omnibus_label <- sprintf("F(%.0f, %.2f) = %.2f, %s", W$df_num[1], W$df_denom[1], W$Fstat[1],
                           ifelse(W$p_val[1] < .001, "p < .001", sprintf("p = %.3f", W$p_val[1])))

  # Pseudo-R2 vs null refit on the SAME numeric subset.
  f0 <- metafor::rma.mv(yi, V = vi, random = ~ 1 | study_id_clean/effect_id_clean,
                        data = dcm, method = "REML", test = "t")
  s0 <- f0$sigma2; s1 <- fit_cm$sigma2
  r2b <- max(0, 100 * (s0[1] - s1[1]) / s0[1]); r2w <- max(0, 100 * (s0[2] - s1[2]) / s0[2])

  header <- tibble::tibble(
    moderator = moderator, level = moderator, row_type = "omnibus",
    k = nrow(dcm), n = dplyr::n_distinct(dcm$study_id_clean),
    `Estimate [95% CI]` = "", SE = "", p = "",
    R2_between = sprintf("%.1f", r2b), R2_within = sprintf("%.1f", r2w),
    `Omnibus Test` = omnibus_label, status = "ok")
  coefs <- tibble::tibble(
    moderator = moderator, level = c("Intercept", "Slope (per unit)"), row_type = "level",
    k = NA_integer_, n = NA_integer_,
    `Estimate [95% CI]` = sprintf("%.2f [%.2f, %.2f]", est, ci_lb, ci_ub),
    SE = sprintf("%.2f", se), p = format_p(pv),
    R2_between = "", R2_within = "", `Omnibus Test` = "", status = "ok")
  dplyr::bind_rows(header, coefs)
}
```

Append these rows to `moderator_table` (and a matching one-row-per-moderator entry to `moderator_omnibus`) so categorical and continuous moderators render in one manuscript table. Keep the separate slope-only `continuous_moderators.csv` for full CR2 detail (intercept, slope, SE, df, t, p); add the intercept estimate to it so "intercept and slope" are both reported. Leave `k`/`n` blank on the Intercept/Slope rows (the header carries the totals), mirroring how categorical level rows carry per-level counts while the header carries the moderator total.

## Table rendering

Use `knitr::kable()` at minimum:

```r
knitr::kable(moderator_table, caption = "Moderator analyses for overall effect")
```

For Word/HTML output, prefer `flextable` if available; for PDF/LaTeX output, use `knitr::kable()` because `flextable` is not the safest default for PDF.

```r
render_meta_table <- function(dat, caption = NULL, bold_rows = integer()) {
  if (is.null(dat) || !is.data.frame(dat) || nrow(dat) == 0) {
    return(cat("No table rows available."))
  }

  if (!knitr::is_latex_output() && requireNamespace("flextable", quietly = TRUE)) {
    tab <- flextable::flextable(dat)
    if (length(bold_rows) > 0) {
      tab <- flextable::bold(tab, i = bold_rows, bold = TRUE)
    }
    tab <- flextable::fontsize(tab, size = 8, part = "all")
    tab <- flextable::padding(tab, padding = 2, part = "all")
    tab <- flextable::set_table_properties(
      tab,
      layout = "autofit",
      width = 1,
      opts_word = list(split = TRUE, repeat_headers = TRUE)
    )
    tab <- flextable::autofit(tab)
    return(flextable::fit_to_width(tab, max_width = 10.1))
  }

  knitr::kable(dat, caption = caption)
}

render_meta_table(
  moderator_table,
  caption = "Moderator analyses for overall effect",
  bold_rows = which(moderator_table$Moderation %in% categorical_moderators)
)
```

Do not use screenshots as table content. Screenshots can guide formatting, but tables must be generated from model objects and conversion logs.

Before printing a table in Word/PDF, reduce it to display columns and format long fields. For moderator tables, drop technical `message` columns from manuscript-facing CSV/XLSX/Word outputs, keep CR2 `F(...)` strings only in `Omnibus Test` on moderator/header rows, and round numeric columns. Preserve complete technical diagnostics in `model_status.csv` or a separate audit table when needed.

## Figures

Use R chunks for generated figures, not only pre-existing image files. For study-level forest plots, preserve dependent effect-size structure by placing multiple effect-size dots/CIs on the same study row when one study reports multiple effects. Do not silently collapse each study to one dot unless the user explicitly asks for aggregation. Example chunk content:

```r
# Aggregate to ONE row per study. Group by the study id only and pick a single
# representative label; do NOT group by a subsample- or sample-name-unique label,
# or a study that spans several subsamples becomes several rows. After building
# this table, assert nrow(study_order) == dplyr::n_distinct(dat_use$study_id_clean):
# if study_order has more than one row per study, the join below (by study_id_clean)
# silently duplicates effect rows and the forest shows more rows than studies.
study_order <- dat_use %>%
  dplyr::mutate(w = 1 / vi) %>%
  dplyr::group_by(study_id_clean) %>%
  dplyr::summarise(
    k_effects = dplyr::n(),
    study_mean = sum(w * yi) / sum(w),
    study_label = dplyr::first(study_label),
    .groups = "drop"
  ) %>%
  dplyr::arrange(study_mean) %>%
  dplyr::mutate(
    study_row = dplyr::row_number(),
    label = paste0(study_label, " (k=", k_effects, ")")
  )
stopifnot(nrow(study_order) == dplyr::n_distinct(dat_use$study_id_clean))

forest_dat <- dat_use %>%
  dplyr::mutate(
    ci_lb = yi - 1.96 * sqrt(vi),
    ci_ub = yi + 1.96 * sqrt(vi),
    effect_significant = !is.na(ci_lb) & !is.na(ci_ub) & (ci_lb > 0 | ci_ub < 0)
  ) %>%
  dplyr::left_join(
    study_order %>% dplyr::select(study_id_clean, study_row, label, k_effects),
    by = "study_id_clean"
  ) %>%
  dplyr::group_by(study_id_clean) %>%
  dplyr::arrange(yi, .by_group = TRUE) %>%
  dplyr::mutate(
    effect_offset = ifelse(dplyr::n() == 1, 0, seq(-0.28, 0.28, length.out = dplyr::n())),
    y_pos = study_row + effect_offset
  ) %>%
  dplyr::ungroup()

if (nrow(forest_dat) >= 2) {
  ggplot2::ggplot(forest_dat, ggplot2::aes(x = yi, y = y_pos)) +
    ggplot2::geom_vline(xintercept = 0, color = "grey55") +
    ggplot2::geom_errorbarh(ggplot2::aes(xmin = ci_lb, xmax = ci_ub), height = 0) +
    ggplot2::geom_point(ggplot2::aes(fill = effect_significant), shape = 21, color = "#1f78b4", size = 1.4, stroke = 0.35) +
    ggplot2::scale_fill_manual(values = c("FALSE" = "#ffffff", "TRUE" = "#1f78b4"), guide = "none") +
    ggplot2::scale_y_continuous(breaks = study_order$study_row, labels = study_order$label) +
    ggplot2::labs(
      x = "Effect size",
      y = NULL,
      caption = "Note. Study-level forest plot with effect-size CIs. Filled blue dots have 95% CIs excluding 0; empty dots include 0."
    ) +
    ggplot2::theme(plot.caption = ggplot2::element_text(hjust = 0))
} else {
  plot.new()
  text(.5, .5, "Forest plot skipped: fewer than two studies.")
}
```

In the actual Rmd, wrap it in an R chunk named `forest-plot` with a figure caption and `fig.height = 8`, then place the code above in the chunk.

For report and presentation exports, save study-level forest plots as high-resolution PNGs with a white background before inserting them into Word. When the study-level forest plot has more than about 30-40 study rows, split it into multiple readable panels (about 30-40 study rows per image, configurable) rather than one oversized vertical PNG. Each chunk should keep multiple effect-size dots/CIs on the same study row, retain the zero and pooled-effect reference lines, and use clear Word headings such as `Study-level forest plot, studies 1-40`. Put titles/subtitles inside figure notes rather than top-of-plot text: standalone PNGs should use a bottom caption such as `labs(caption = "Note. Study-level forest plot with effect-size CIs. Studies 1-40 of 132; ...")`, and Word reports should repeat the same note below the inserted image. A good export default for a chunked dense forest plot is at least 450-600 dpi with a wider canvas than the inserted Word size, rendered through a high-quality device such as `ragg::agg_png` for crisp text, for example `ggsave("study_level_forest_full_data_part_01.png", plot = forest_plot, width = 12, height = max(6, 0.28 * n_studies_in_chunk + 1.8), dpi = 600, limitsize = FALSE, bg = "white", device = ragg::agg_png)`.

Also include funnel plots and key moderator plots when data permit:

- `funnel_full_data`
- `funnel_no_outliers`
- continuous moderator scatter plots such as gender/female proportion
- subgroup forest plots only when each subgroup has enough rows

Funnel plots should use a classic publication-bias display by default: black points, grey panel, reversed standard-error axis, pooled-effect center line, and pseudo 95% funnel guides. Use metric-specific x-axis labels, such as `Effect size (Fisher's z)` for Fisher-z/r analyses and `Effect size (Hedges g)` for SMD analyses. If extreme effects flatten the display, use a readable zoomed funnel and disclose the number of effects outside the displayed window. Example pattern:

```r
funnel_center <- main_summary$estimate[1]
funnel_se_max <- as.numeric(stats::quantile(dat_use$sei, 0.99, na.rm = TRUE))
funnel_x_quantile <- as.numeric(stats::quantile(dat_use$yi, c(0.025, 0.975), na.rm = TRUE))
funnel_x_min <- min(funnel_x_quantile[1], funnel_center - 1.96 * funnel_se_max)
funnel_x_max <- max(funnel_x_quantile[2], funnel_center + 1.96 * funnel_se_max)
funnel_x_pad <- 0.08 * diff(c(funnel_x_min, funnel_x_max))
funnel_x_min <- funnel_x_min - funnel_x_pad
funnel_x_max <- funnel_x_max + funnel_x_pad

funnel_plot_dat <- dat_use %>%
  dplyr::mutate(in_funnel_view = yi >= funnel_x_min & yi <= funnel_x_max & sei <= funnel_se_max) %>%
  dplyr::filter(in_funnel_view)

funnel_se_grid <- tibble::tibble(sei = seq(0, funnel_se_max, length.out = 200)) %>%
  dplyr::mutate(
    ci_left = funnel_center - 1.96 * sei,
    ci_right = funnel_center + 1.96 * sei
  )

funnel_core <- dplyr::bind_rows(
  tibble::tibble(yi = funnel_center, sei = 0),
  funnel_se_grid %>% dplyr::transmute(yi = ci_left, sei = sei),
  funnel_se_grid %>% dplyr::arrange(dplyr::desc(sei)) %>% dplyr::transmute(yi = ci_right, sei = sei)
)

ggplot2::ggplot() +
  ggplot2::geom_polygon(data = funnel_core, ggplot2::aes(x = yi, y = sei), fill = "white", color = NA) +
  ggplot2::geom_line(data = funnel_se_grid, ggplot2::aes(x = ci_left, y = sei), color = "grey35") +
  ggplot2::geom_line(data = funnel_se_grid, ggplot2::aes(x = ci_right, y = sei), color = "grey35") +
  ggplot2::geom_vline(xintercept = funnel_center, color = "grey20") +
  ggplot2::geom_point(data = funnel_plot_dat, ggplot2::aes(x = yi, y = sei), color = "black", size = 1.6) +
  ggplot2::scale_y_reverse() +
  ggplot2::coord_cartesian(xlim = c(funnel_x_min, funnel_x_max), ylim = c(funnel_se_max, 0)) +
  ggplot2::labs(
    x = "Effect size (Hedges g)",
    y = "Standard Error",
    caption = paste0("Note. Funnel plot. ", nrow(dat_use) - nrow(funnel_plot_dat), " effects outside the displayed zoom window.")
  ) +
  ggplot2::theme(
    panel.background = ggplot2::element_rect(fill = "#c9c9c9", color = NA),
    plot.background = ggplot2::element_rect(fill = "white", color = NA),
    panel.grid.major = ggplot2::element_line(color = "white"),
    panel.grid.minor = ggplot2::element_blank(),
    plot.caption = ggplot2::element_text(hjust = 0)
  )
```

Bound figure size in Word/PDF. Tall PNGs such as forest plots and leave-one-study influence plots should be inserted with a maximum height that fits the landscape page body, not only a large `out.width`. If a source figure is vertical, reduce output width or use an explicit helper that preserves aspect ratio while capping both width and height. A good default for landscape Letter with 0.45 inch margins is maximum width 10.1 inches and maximum height 6.6 inches.

## Export and knit commands

At the end of a script or in the final answer, provide commands:

```r
rmarkdown::render("meta_analysis_results_report.Rmd", output_format = "word_document")
rmarkdown::render("meta_analysis_results_report.Rmd", output_format = "html_document")
rmarkdown::render("meta_analysis_results_report.Rmd", output_format = "pdf_document")
```

If direct PDF rendering is optional or LaTeX may be unavailable, use a guarded command so Word/HTML still render:

```r
rmarkdown::render("meta_analysis_results_report.Rmd", output_format = "word_document")
rmarkdown::render("meta_analysis_results_report.Rmd", output_format = "html_document")

tryCatch(
  rmarkdown::render("meta_analysis_results_report.Rmd", output_format = "pdf_document"),
  error = function(e) {
    message("PDF render failed: ", e$message)
    message("Use the generated Word .docx as the fallback and save/export it as PDF, or install TinyTeX.")
  }
)
```

If the user's path contains non-ASCII characters, prefer placing the Rmd beside the data and using relative paths. This avoids Windows console encoding problems with absolute paths.

For user-run workflows, give a compact command block like:

```r
setwd("C:/path/to/data-folder")
source("meta_analysis_project_full.R")
rmarkdown::render("meta_analysis_project_report.Rmd", output_format = "word_document")
rmarkdown::render("meta_analysis_project_report.Rmd", output_format = "html_document")
```

Then tell the user to send the generated output folder or final HTML/Word report back for review. On review, summarize:

- whether models fitted or failed;
- overall effect and sensitivity effect;
- key moderator results;
- influence/outlier findings;
- publication-bias diagnostics;
- whether figures are present and readable;
- any mismatch with article/source counts or target model.

## Checks before calling the Rmd complete

- Rmd uses the correct effect-size family: Fisher-z/r or SMD/Hedges g.
- Rmd contains a data/conversion summary table.
- Rmd contains an effect-size audit table.
- Rmd contains main model and CR2 tables.
- Rmd contains manuscript-style moderator table with n/k/estimate/SE/p/CI/omnibus or robust test columns.
- Rmd contains long-format moderator count table to avoid vctrs recycling errors.
- Rmd contains forest/funnel/moderator figures with guards for empty data.
- Output folder contains saved CSV/XLSX tables, saved PNG figures, rendered HTML/Word reports, and a status/manifest file.
- Rmd includes direction handling and full-vs-clean data notes.
- Rmd narrative descriptions are plain Markdown, not wrapped in `{r}` chunks; inline `` `r ...` `` expressions stay in prose.
- Rmd uses relative paths when the data path has non-ASCII characters.
- Rmd YAML includes `pdf_document` when the user asks for reports/outcomes generally, or when they specifically asks for PDF.
- If PDF cannot be rendered in the current environment, the response includes the exact PDF render command, the Word `.docx` fallback, and the likely LaTeX/TinyTeX requirement.
