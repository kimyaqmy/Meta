# Column Name Harmonization

Use this reference before running meta-analysis code on a new workbook.

## Principle

Different extraction sheets often use different names for the same analytic field. Standardize them in code before analysis. Do not edit the source workbook unless the user asks.

Use the canonical names below (shared by the bundled reference pipelines), then keep all downstream code using those canonical names.

## Canonical fields and common synonyms

### Study identifiers

- `study_id`: `study`, `studyid`, `paper_id`, `article_id`, `source_id`, `citation_id`, `record_id`
- `effect_id`: `effect`, `effectid`, `row_id`, `es_id`, `effect_size_id`
- `study_title`: `title`, `paper_title`, `article_title`
- `apa_citation`: `citation`, `reference`, `apa`, `full_citation`
- `year`: `publication_year`, `pub_year`

### Effect-size inputs

- `N`: `n`, `sample_size`, `total_n`, `participants`, `n_total`
- `effect_type`: `statistic_type`, `es_type`, `type`, `reported_statistic`, `effect_size_type`
- `effect_size`: `r`, `effect`, `es`, `value`, `converted_effect`, `converted_r`
- `effect_size_original`: `original_effect`, `reported_effect`, `reported_value`, `raw_effect`, `statistic_value`
- `df1`: `df_num`, `df_between`, `numerator_df`
- `df2`: `df_den`, `df_within`, `denominator_df`, `df`, `degrees_freedom`
- `ci_low`: `lower_ci`, `ci_lower`, `ll`, `lcl`, `lower_95ci`
- `ci_high`: `upper_ci`, `ci_upper`, `ul`, `ucl`, `upper_95ci`

### Intervention/pre-post SMD inputs

- `int_n`: `intervention_n`, `treatment_n`, `experimental_n`, `exp_n`, `group1_n`
- `con_n`: `control_n`, `comparison_n`, `business_as_usual_n`, `group2_n`
- `int_mean_t1`: `int_pre_mean`, `intervention_pre_mean`, `treatment_pre_mean`, `pre_mean_int`
- `int_sd_t1`: `int_pre_sd`, `intervention_pre_sd`, `treatment_pre_sd`, `pre_sd_int`
- `int_mean_t2`: `int_post_mean`, `intervention_post_mean`, `treatment_post_mean`, `post_mean_int`
- `int_sd_t2`: `int_post_sd`, `intervention_post_sd`, `treatment_post_sd`, `post_sd_int`
- `con_mean_t1`: `con_pre_mean`, `control_pre_mean`, `comparison_pre_mean`, `pre_mean_con`
- `con_sd_t1`: `con_pre_sd`, `control_pre_sd`, `comparison_pre_sd`, `pre_sd_con`
- `con_mean_t2`: `con_post_mean`, `control_post_mean`, `comparison_post_mean`, `post_mean_con`
- `con_sd_t2`: `con_post_sd`, `control_post_sd`, `comparison_post_sd`, `post_sd_con`
- `smd`: `hedges_g`, `cohens_d`, `d`, `standardized_mean_difference`, `g`
- `p_val`: `p`, `p_value`, `pvalue`
- `design`: `study_design`, `trial_design`, `group_design`
- `Exi_intervention`: `has_intervention`, `intervention_exists`, `intervention`, `intervention_group_exists`
- `Exi_control`: `has_control`, `control_exists`, `control`, `control_group_exists`
- `RCT`: `is_rct`, `randomized`, `randomised`, `random_assignment`

### Construct and moderator fields

- `construct_outcome`: `outcome`, `outcome_name`, `dependent_variable`, `dv`
- `construct_category`: `domain`, `outcome_domain`, `category`, `construct_domain`
- `construct_subcategory`: `subdomain`, `subcategory`, `construct_type`, `outcome_type`
- `outcome_domain`: `domain`, `construct_category`, `outcome_category`
- `outcome_subdomain`: `subdomain`, `construct_subcategory`, `outcome_type`
- `measure_questionairs`: `measure`, `scale`, `instrument`, `questionnaire`, `outcome_measure`
- `measure_IP`: `ip_measure`, `predictor_measure`, `iv_measure`
- `effect_direction`: `direction`, `coding_direction`, `association_direction`

### Sample and study descriptors

- `country`: `nation`, `location`
- `region`: `world_region`, `geographic_region`
- `sample_type`: `population`, `sample`
- `study_design`: `design`, `research_design`
- `age_mean`: `mean_age`, `m_age`
- `age_sd`: `sd_age`
- `gender_proportion`: `female_proportion`, `percent_female`, `female_pct`
- `educational_stage`: `education_stage`, `school_stage`, `grade_level`
- `Technology_Category`: `Technology Category`, `technology_category`, `technology`, `tech_category`, `ai_type`
- `Grade_Level`: `Grade Level`, `grade`, `grade_level`, `school_grade`
- `Learning_Subject`: `Learning Subject`, `subject`, `learning_area`, `course_subject`
- `literacy_type`: `antecedent`, `ai_literacy_type`, `literacy_construct`, `literacy_domain`
- `gender_proportion`: `female_per`, `female_percent`, `percent_female`, `female_pct`, `gender_per`, `gender_percent`

## Collision rules

If multiple columns map to one canonical name:

1. Prefer the column with more non-missing values.
2. Prefer already-converted analytic fields over raw descriptive fields only when the field is intended to be converted, such as `effect_size`.
3. Keep a note in the run report naming the original column used.
4. Preserve the unused duplicate columns with their original names unless the user asks for a cleaned workbook.

## Implementation pattern in R

Use a named list where names are canonical columns and values are possible synonyms:

```r
column_map <- list(
  study_id = c("study_id", "study", "paper_id"),
  N = c("N", "n", "sample_size", "total_n"),
  effect_type = c("effect_type", "statistic_type", "es_type"),
  effect_size = c("effect_size", "r", "es", "value"),
  effect_size_original = c("effect_size_original", "reported_effect", "raw_effect"),
  construct_category = c("construct_category", "domain", "outcome_domain"),
  construct_subcategory = c("construct_subcategory", "subdomain", "outcome_type")
)
```

Then choose the first available synonym or the synonym with the most complete data.
