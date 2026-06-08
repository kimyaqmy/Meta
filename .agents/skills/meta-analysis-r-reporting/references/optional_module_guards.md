# Optional Module Guards

Use this when adapting any reference pipeline block that is not required for the main model.

## Core rule

Optional modules must be gated by real data availability. A column that was created as `NA` by `cols_needed` is only a placeholder; it does not mean the corresponding moderator, scatter plot, funnel plot, or subgroup model can run.

## Optional modules that need guards

- Continuous moderator models, such as `gender_proportion` or `white_proportion`.
- Categorical moderator models, such as region, subject, education stage, measure type, construct, technology category, grade level, or literacy type.
- Scatter plots with `facet_wrap()`.
- Forest plots for subsets or subdomains.
- Funnel plots and publication-bias analyses.
- PET/PEESE models.
- Trim-and-fill or selection models.

## Minimum checks

Before running an optional block, check:

- Required columns exist.
- Required numeric columns have non-missing finite values.
- Required categorical/facet columns have at least one non-missing value.
- Categorical moderator models have at least two usable levels.
- Subgroup/forest/facet plots have at least one row after filtering.
- Model blocks have enough effects and enough distinct studies for the intended method.

## Reusable R helpers

Add helpers near the top of an adapted project script:

```r
has_real_values <- function(dat, col) {
  col %in% names(dat) &&
    any(!is.na(dat[[col]]) & trimws(as.character(dat[[col]])) != "")
}

has_numeric_values <- function(dat, col) {
  col %in% names(dat) &&
    any(is.finite(suppressWarnings(as.numeric(dat[[col]]))))
}

has_min_levels <- function(dat, col, min_levels = 2) {
  col %in% names(dat) &&
    length(unique(na.omit(as.character(dat[[col]])))) >= min_levels
}

skip_optional <- function(label, reason) {
  message("Skipped ", label, ": ", reason)
}
```

## Scatter/facet plot pattern

Use this pattern for any `facet_wrap()` plot:

```r
plot_data <- dat %>%
  dplyr::filter(
    !is.na(x_var),
    !is.na(y_var),
    !is.na(facet_var)
  )

if (nrow(plot_data) > 0 && dplyr::n_distinct(plot_data$facet_var) > 0) {
  ggplot2::ggplot(plot_data, ggplot2::aes(x = x_var, y = y_var)) +
    ggplot2::geom_point() +
    ggplot2::facet_wrap(~ facet_var)
} else {
  skip_optional("scatter/facet plot", "no rows after filtering or no facet levels")
}
```

## Continuous moderator pattern

```r
if (has_numeric_values(dat, "white_proportion")) {
  dat_mod <- dat %>%
    dplyr::mutate(white_proportion = suppressWarnings(as.numeric(white_proportion))) %>%
    dplyr::filter(!is.na(white_proportion), is.finite(white_proportion))

  if (nrow(dat_mod) >= 3 && dplyr::n_distinct(dat_mod$study_id) >= 2) {
    # fit continuous moderator model
  } else {
    skip_optional("white_proportion moderator", "too few model-ready rows or studies")
  }
} else {
  skip_optional("white_proportion moderator", "column missing or all NA")
}
```

## Categorical moderator pattern

```r
if (has_min_levels(dat, "educational_stage", min_levels = 2)) {
  dat_mod <- dat %>% dplyr::filter(!is.na(educational_stage))
  # fit categorical moderator model with minimum-k checks
} else {
  skip_optional("educational_stage moderator", "fewer than two non-missing levels")
}
```

## Guard helper outputs before piping

Some reference helpers return `NULL` when no usable rows or levels are available. Never pipe a possibly-`NULL` result into `dplyr::select()`, `print()`, `mutate()`, or plotting code.

This also applies to objects created by `tryCatch()`, model helpers, publication-bias helpers, moderator-summary helpers, and plot constructors. If the helper may return `NULL`, an empty data frame, or a failed model object, check it before downstream use.

For model helpers, prefer returning a list with both a result and a status table. This prevents reports where the user only sees `NA` estimates without knowing whether the model failed, had too few rows, or had a package/version issue.

```r
safe_model <- function(label, expr) {
  tryCatch(
    list(
      result = expr,
      status = tibble::tibble(model = label, status = "ok", message = "")
    ),
    error = function(e) {
      list(
        result = NULL,
        status = tibble::tibble(model = label, status = "failed", message = e$message)
      )
    }
  )
}
```

Print or export the combined status table when any model failed:

```r
model_status <- dplyr::bind_rows(main_status, moderator_status, bias_status)

if (!is.null(model_status) && nrow(model_status) > 0 && any(model_status$status != "ok")) {
  knitr::kable(model_status, caption = "Model status and skipped analyses")
}
```

Use this pattern:

```r
res <- summarise_categorical_levels_CR2_p(
  dat_sub = dat_health_ill_use,
  moderator = "subject",
  min_k_effect = 2L
)

if (!is.null(res) && nrow(res) > 0) {
  print(res %>%
    dplyr::select(level, n_studies, n_effects, est_r, ci_lb_r, ci_ub_r, p_value, r_ci))
} else {
  skip_optional("subject level-specific pooled r", "no usable rows")
}
```

For model or plot objects:

```r
plot_obj <- make_moderator_plot(dat_sub_all, moderator = "subject")

if (!is.null(plot_obj)) {
  print(plot_obj)
} else {
  skip_optional("subject moderator plot", "helper returned NULL")
}
```

For exports:

```r
if (!is.null(res) && nrow(res) > 0) {
  openxlsx::write.xlsx(res, "moderator_results.xlsx", rowNames = FALSE)
} else {
  skip_optional("moderator results export", "no results to write")
}
```

This is especially important for example blocks at the end of reference scripts, because they often target one old-project moderator/subdomain combination that may not exist in a new workbook.

## Combine moderator summaries in long format

When summarising several moderators, each moderator can have a different number of levels. Do not create one summary where the original grouping columns remain side by side, such as `design_inferred` plus `country`. That can cause errors like `Can't recycle design_inferred (size 3) to match country (size 9)`.

Always convert categorical moderator summaries to a common long schema before `bind_rows()`:

```r
summarise_categorical_counts <- function(dat, moderator) {
  if (!has_min_levels(dat, moderator, min_levels = 2)) return(NULL)

  dat %>%
    dplyr::filter(!is.na(.data[[moderator]])) %>%
    dplyr::mutate(moderator_level = as.character(.data[[moderator]])) %>%
    dplyr::group_by(moderator_level) %>%
    dplyr::summarise(
      k_effects = dplyr::n(),
      n_studies = dplyr::n_distinct(study_id),
      .groups = "drop"
    ) %>%
    dplyr::transmute(
      moderator = moderator,
      level = moderator_level,
      k_effects = as.integer(k_effects),
      n_studies = as.integer(n_studies),
      mean = NA_real_,
      sd = NA_real_,
      min = NA_real_,
      max = NA_real_
    )
}
```

For continuous moderators, use the same columns and set `level = "continuous"`:

```r
summarise_continuous_counts <- function(dat, moderator) {
  if (!has_numeric_values(dat, moderator)) return(NULL)

  dat_mod <- dat %>%
    dplyr::mutate(value = suppressWarnings(as.numeric(as.character(.data[[moderator]])))) %>%
    dplyr::filter(!is.na(value), is.finite(value))

  if (nrow(dat_mod) == 0) return(NULL)

  tibble::tibble(
    moderator = moderator,
    level = "continuous",
    k_effects = nrow(dat_mod),
    n_studies = dplyr::n_distinct(dat_mod$study_id),
    mean = mean(dat_mod$value, na.rm = TRUE),
    sd = stats::sd(dat_mod$value, na.rm = TRUE),
    min = min(dat_mod$value, na.rm = TRUE),
    max = max(dat_mod$value, na.rm = TRUE)
  )
}
```

Guard the combined export:

```r
count_tables <- purrr::keep(count_tables, ~ !is.null(.x) && is.data.frame(.x) && nrow(.x) > 0)

if (length(count_tables) > 0) {
  moderator_counts <- dplyr::bind_rows(count_tables)
  openxlsx::write.xlsx(moderator_counts, "moderator_counts.xlsx", rowNames = FALSE)
} else {
  skip_optional("moderator counts export", "no moderator count tables")
}
```

## Reporting

Skipped modules are not failures when the data do not support them. Record them in the console output or report so the user can see which analyses were not applicable to the current workbook.
