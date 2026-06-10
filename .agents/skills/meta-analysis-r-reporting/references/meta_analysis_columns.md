# Meta-analysis Data Columns

Use this reference as the schema map when adapting any of the bundled reference pipelines or writing a fresh project script.

## Required for most analyses

- `study_id`: stable study-level cluster id.
- `effect_id`: stable effect-level id. If missing, create from row number.
- `N`: sample size used for the effect.
- `effect_type`: statistic type used to compute the analyzable effect.
- `effect_size` or `effect_size_original`: reported effect value.

## Effect-size conversion inputs

Supported `effect_type` values:

- Already correlation-like: `r`, `pearson_r`, `r_Pearson`, `spearman_r`, `r_Spearman`, `latent_r`, `phi`, `phi_coefficient`.
- `kendalls_tau`: converts with `sin(pi * tau / 2)`.
- `std_beta`, `standardized_beta`: treated as approximately `r` unless the user requests a different conversion.
- `unstd_beta`: needs `ci_low`, `ci_high`, and `df2`; converts beta/SE to t, then partial r.
- `t`, `t_value`: needs `df2`.
- `f`, `f_test`: needs `df1` and `df2`.
- `odds_ratio`, `or`: converts log OR to Cohen d, then r.
- `prevalence_ratio`, `risk_ratio`, `rr`: converts log ratio to Cohen d, then r.
- `chi_square`, `chisq`: needs `N`; uses a Cramer's V approximation.
- `cohens_d`, `d`: converts d to r.

## Optional but useful columns

- Citation and labels: `study_title`, `apa_citation`, `year`.
- Grouping/moderator columns: `construct_category`, `construct_subcategory`, `construct_outcome`, `domain`, `subdomain`, `measure_questionairs`, `measure_IP`.
- Direction columns: `effect_direction`, or a user-defined direction map in `CONFIG`.
- Method/sample columns: `effect_method`, `sample_type`, `study_design`, `country`, `region`, `discipline`, `subject`, `educational_stage`, `measurement_language`.
- Risk-of-bias columns: `rob1`, `rob_item01`, `rob_item02`, `rob_item04`, `rob_item06`, `rob_item16`.

## Direction handling

Direction recoding is analysis-specific. Do not assume all negative effects should be reversed.

Use risk-coded effects only when the user defines which construct levels should point in the same conceptual direction. In the template, configure:

- `direction_col`
- `reverse_direction_values`

Rows whose direction value is in `reverse_direction_values` get `yi_risk = -yi`; all others keep `yi_risk = yi`.

## Minimum checks

Before interpreting results, verify:

- Number of raw rows.
- Number of rows dropped for missing or invalid `N`.
- Number of rows with convertible effect sizes.
- Number of rows with valid `r` in `(-1, 1)`.
- Number of included effects and distinct studies for each model.
- Whether outputs use full or influence-excluded data.
