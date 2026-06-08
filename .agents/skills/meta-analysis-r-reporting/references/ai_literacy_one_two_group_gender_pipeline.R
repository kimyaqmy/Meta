# ===============================================================
# One-group (Pre-post) Meta-analysis Script
# ===============================================================

# Load libraries
library(readxl)
library(metafor)
library(dplyr)
library(ggplot2)
library(weightr)
library(ggthemes)
library(MetaUtility)
library(tidyr)
library(compute.es)
library(janitor)
library(vctrs)
library(clubSandwich)
library(forcats)

# Load data
d_one <- read_excel(
  "C:/Users/Hana/Desktop/AI literacy.Data/R/One pre-post.xlsx",
  na = c("NA", "na", "NR", "nr", "")
)

################################################ Clean Data ################################################

summary(d_one)
names(d_one)

# Keep only true categorical variables as factors
d_one <- d_one %>%
  mutate(across(
    c(study_id, effect_id, apa_citation, country,
      grade_taught, career_stage, effect_type, rob1, antecedent),
    as.factor
  ))

# Store reported Cohen's d if directly provided
d_one <- d_one %>%
  mutate(
    cohen = case_when(
      effect_type == "d" & !is.na(effect_size) ~ as.numeric(effect_size),
      TRUE ~ NA_real_
    )
  )

### Filter data by research design: single-group (pre-post) intervention only
d_onegroup <- d_one %>%
  filter(Exi_intervention == 1 & Exi_control == 0) %>%
  mutate(
    # fallback: use posttest SD when pretest SD is missing
    int_sd_t1_used = case_when(
      !is.na(int_sd_t1) ~ int_sd_t1,
      is.na(int_sd_t1) & !is.na(int_sd_t2) ~ int_sd_t2,
      TRUE ~ NA_real_
    ),
    sd_t1_imputed = ifelse(is.na(int_sd_t1) & !is.na(int_sd_t1_used), 1, 0)
  )

# Priority rule:
# 1) compute SMCR from means/SDs
# 2) if reported d/t/z/r exists, convert to g and use that instead

r_assumed <- 0.7

# 1) Compute standardized mean change (SMCR)
d_onegroup <- escalc(
  measure = "SMCR",
  m1i = int_mean_t2, m2i = int_mean_t1,
  sd1i = int_sd_t1_used,
  ni  = int_n,
  ri  = r_assumed,
  data = d_onegroup
) %>%
  dplyr::rename(SMCR = yi, SMCR_var = vi)

# 2) Convert reported statistics to Cohen's d, then to Hedges' g
d_onegroup <- d_onegroup %>%
  mutate(
    effect_size_num = suppressWarnings(as.numeric(as.character(effect_size))),
    n_used = dplyr::coalesce(int_n, N),
    J = ifelse(!is.na(n_used) & (4 * n_used - 1) != 0,
               1 - 3 / (4 * n_used - 1),
               NA_real_),
    
    d_from_d = ifelse(
      effect_type == "d" & !is.na(effect_size_num),
      effect_size_num,
      NA_real_
    ),
    
    d_from_t = ifelse(
      effect_type == "t" & !is.na(effect_size_num) & !is.na(n_used),
      effect_size_num * sqrt(2 * (1 - r_assumed) / n_used),
      NA_real_
    ),
    
    d_from_z = ifelse(
      effect_type == "z" & !is.na(effect_size_num) & !is.na(n_used),
      effect_size_num / sqrt(n_used),
      NA_real_
    ),
    
    r_clean = ifelse(
      effect_type == "r" & !is.na(effect_size_num) & abs(effect_size_num) < 1,
      effect_size_num,
      NA_real_
    ),
    
    d_from_r = ifelse(
      !is.na(r_clean),
      2 * r_clean / sqrt(1 - r_clean^2),
      NA_real_
    ),
    
    d_any = dplyr::coalesce(d_from_d, d_from_t, d_from_z, d_from_r),
    g_from_stats = ifelse(!is.na(d_any) & !is.na(J), d_any * J, NA_real_),
    
    es_source = case_when(
      !is.na(g_from_stats) ~ "reported_stats",
      !is.na(SMCR) ~ "SMCR",
      TRUE ~ NA_character_
    )
  )

# 3) Final effect size (yi) and variance (vi)
d_onegroup <- d_onegroup %>%
  mutate(
    yi = dplyr::coalesce(g_from_stats, SMCR),
    
    vi_raw = case_when(
      !is.na(g_from_stats) & !is.na(n_used) ~
        (1 / n_used) + (yi^2 / (2 * n_used)) * (1 - r_assumed),
      
      is.na(g_from_stats) & !is.na(SMCR_var) ~
        SMCR_var,
      
      TRUE ~ NA_real_
    ),
    
    vi = case_when(
      !is.na(vi_raw) & is.finite(vi_raw) & vi_raw > 0 ~ vi_raw,
      
      is.na(vi_raw) & !is.na(yi) & !is.na(n_used) ~
        (1 / n_used) + (yi^2 / (2 * n_used)) * (1 - r_assumed),
      
      TRUE ~ NA_real_
    ),
    
    vi_imputed = ifelse(is.na(vi_raw) & !is.na(vi), 1, 0)
  ) %>%
  select(-vi_raw)

openxlsx::write.xlsx(d_onegroup, "onegroup_cleandataSep1.xlsx", rowNames = FALSE)

######################################################## For analysis - One group ########################################################

# Number of unique studies included
n_distinct(d_onegroup$study_id)

# Total sample size across studies (counting each study once)
d_onegroup %>%
  distinct(apa_citation, study_id, N, .keep_all = TRUE) %>%
  summarise(total_N = sum(N, na.rm = TRUE)) %>%
  pull(total_N) %>%
  format(big.mark = ",")

# Build model-ready dataset first (important: Cook's D aligns only with modeled rows)
d_onegroup_model <- d_onegroup %>%
  mutate(row_id = dplyr::row_number()) %>%
  filter(
    !is.na(yi), !is.na(vi),
    is.finite(yi), is.finite(vi),
    vi > 0
  )

# Main multilevel meta-analysis model
Meta_onegroup <- metafor::rma.mv(
  yi = yi,
  V = vi,
  random = ~ 1 | apa_citation/effect_id,
  data = d_onegroup_model,
  slab = apa_citation
)

print(Meta_onegroup, digits = 3)

# Load function to compute variance components and I² for multilevel models
source("https://raw.githubusercontent.com/MathiasHarrer/dmetar/master/R/mlm.variance.distribution.R")
i2 <- var.comp(Meta_onegroup)

##### OUTLIERS AND SENSITIVITY ANALYSIS #####

# Calculate Cook's Distance for each modeled effect size
inf <- cooks.distance(Meta_onegroup, progbar = FALSE)

# Plot Cook's Distance
plot(inf, type = "b", pch = "*", cex = 2, main = "Influential Effects by Cook's Distance")

# Threshold for influential effects: 4/k
k_eff_one <- length(inf)
cutoff_one <- 4 / k_eff_one
abline(h = cutoff_one, col = "firebrick2")

# Identify influential effect rows
flagged_idx_one <- which(inf > cutoff_one)
flagged_row_ids_one <- d_onegroup_model$row_id[flagged_idx_one]

# Label flagged effects
text(
  x = seq_along(inf),
  y = inf,
  labels = ifelse(inf > cutoff_one, as.character(d_onegroup_model$apa_citation), ""),
  col = "firebrick2",
  pos = 3,
  cex = 0.8
)

# Show which effect sizes are removed
flagged_effects_one <- d_onegroup_model %>%
  filter(row_id %in% flagged_row_ids_one) %>%
  select(row_id, study_id, effect_id, apa_citation, yi, vi)

cat("Automatically removed influential effect sizes (one-group):\n")
print(flagged_effects_one)

# Remove only flagged EFFECT rows (not whole studies)
nooutlier_onegroup <- d_onegroup %>%
  mutate(row_id = dplyr::row_number()) %>%
  filter(!row_id %in% flagged_row_ids_one) %>%
  select(-row_id)

openxlsx::write.xlsx(
  nooutlier_onegroup,
  "C:/Users/Hana/Desktop/AI literacy.Data/onegroup_nooutliers_Sep1.xlsx",
  rowNames = FALSE
)

# Number of studies after removing outliers
n_distinct(nooutlier_onegroup$study_id)

# Updated total sample size
nooutlier_onegroup %>%
  distinct(apa_citation, study_id, N, .keep_all = TRUE) %>%
  summarise(total_N = sum(N, na.rm = TRUE)) %>%
  pull(total_N) %>%
  format(big.mark = ",")

# Model-ready no-outlier dataset
nooutlier_onegroup_model <- nooutlier_onegroup %>%
  mutate(row_id = dplyr::row_number()) %>%
  filter(
    !is.na(yi), !is.na(vi),
    is.finite(yi), is.finite(vi),
    vi > 0
  ) %>%
  select(-row_id)

# Re-run multilevel meta-analysis without outliers
outlier_analysis <- rma.mv(
  yi = yi,
  V = vi,
  slab = apa_citation,
  data = nooutlier_onegroup_model,
  random = ~ 1 | apa_citation/effect_id,
  method = "REML"
)

print(outlier_analysis, digits = 3)

##### FOREST PLOT #####

# Sort effect sizes for visualization
sorted_indices <- order(nooutlier_onegroup_model$yi)
nooutlier_onegroup_sorted <- nooutlier_onegroup_model[sorted_indices, ]
apa_citation_sorted <- nooutlier_onegroup_sorted$apa_citation

Meta_nooutlier_onegroup_sorted <- metafor::rma.mv(
  yi = yi,
  V = vi,
  random = ~ 1 | apa_citation/effect_id,
  data = nooutlier_onegroup_sorted,
  slab = apa_citation_sorted
)

# Create study labels showing each study only once
study_names_sorted <- sub("\\.\\d+$", "", Meta_nooutlier_onegroup_sorted$slab)
slab_labels <- ifelse(duplicated(study_names_sorted), "", study_names_sorted)
study_rows_sorted <- as.numeric(factor(study_names_sorted, levels = unique(study_names_sorted)))

metafor::forest(
  Meta_nooutlier_onegroup_sorted,
  mlab = "Pooled Estimate",
  refline = 0,
  slab = slab_labels,
  rows = study_rows_sorted,
  showweights = FALSE,
  annotate = FALSE,
  efac = c(0.2, 0.5),
  cex = 1,
  pch = 18
)

# ===============================================================
# Two-group (Experimental-Control) Meta-analysis Script
# ===============================================================

# Load data
d_two <- read_excel(
  "C:/Users/Hana/Desktop/AI literacy.Data/R/Two pre-post.xlsx",
  na = c("NA", "na", "NR", "nr", "")
)

# Clean Data
summary(d_two)
names(d_two)

# Keep only true categorical variables as factors
# IMPORTANT: keep year and Inter_duration numeric
d_two <- d_two %>%
  mutate(across(
    c(study_id, effect_id, apa_citation, RCT, country,
      Exi_control, grade_taught, career_stage, female_per,
      effect_type, rob1, antecedent),
    as.factor
  ))

# Store directly reported effect sizes
d_two <- d_two %>%
  mutate(
    effect_size_num = suppressWarnings(as.numeric(as.character(effect_size))),
    cohen = case_when(
      effect_type == "d" & !is.na(effect_size_num) ~ effect_size_num,
      TRUE ~ NA_real_
    ),
    g_reported = case_when(
      effect_type == "g" & !is.na(effect_size_num) ~ effect_size_num,
      TRUE ~ NA_real_
    )
  )

### Filter data by research design
# Quasi-experimental / non-RCT studies with a control group
d_quasi <- d_two %>%
  filter(RCT == 0 & Exi_control == 1)

# If group sizes are missing for pre-calculated effects, assume equal groups
d_quasi <- d_quasi %>%
  mutate(
    int_n = ifelse(!is.na(effect_type) & is.na(int_n) & !is.na(N), N / 2, int_n),
    con_n = ifelse(!is.na(effect_type) & is.na(con_n) & !is.na(N), N / 2, con_n)
  )

## Convert t statistics to Cohen's d
d_quasi <- d_quasi %>%
  mutate(
    cohen = ifelse(
      effect_type == "t" & is.na(cohen) & !is.na(effect_size_num) &
        !is.na(int_n) & !is.na(con_n) & int_n != con_n,
      effect_size_num * sqrt((int_n + con_n) / (int_n * con_n)),
      cohen
    ),
    cohen = ifelse(
      effect_type == "t" & is.na(cohen) & !is.na(effect_size_num) &
        !is.na(int_n) & !is.na(con_n) & int_n == con_n,
      (2 * effect_size_num) / sqrt(int_n + con_n),
      cohen
    )
  )

## Convert F to Cohen's d
d_quasi <- d_quasi %>%
  mutate(
    cohen = ifelse(
      effect_type == "F" & is.na(cohen) & !is.na(effect_size_num) & effect_size_num >= 0 &
        !is.na(int_n) & !is.na(con_n) & int_n != con_n,
      sqrt(effect_size_num) * sqrt((int_n + con_n) / (int_n * con_n)),
      cohen
    ),
    cohen = ifelse(
      effect_type == "F" & is.na(cohen) & !is.na(effect_size_num) & effect_size_num >= 0 &
        !is.na(int_n) & !is.na(con_n) & int_n == con_n,
      2 * sqrt(effect_size_num) / sqrt(int_n + con_n),
      cohen
    )
  )

# Compute change-score effect size where pretest data are available
d_quasi <- d_quasi %>%
  mutate(
    change_treatment = int_mean_t2 - int_mean_t1,
    change_control   = con_mean_t2 - con_mean_t1,
    baseline_sd_pooled = sqrt(
      ((int_n - 1) * int_sd_t1^2 + (con_n - 1) * con_sd_t1^2) /
        (int_n + con_n - 2)
    ),
    cohens_d_change = (change_treatment - change_control) / baseline_sd_pooled
  )

# Identify rows that still do not have an effect size source
d_quasi <- d_quasi %>%
  mutate(
    sd_imputed = is.na(cohen) & is.na(g_reported) & is.na(cohens_d_change)
  )

# Use median SD within each antecedent category
d_quasi <- d_quasi %>%
  group_by(antecedent) %>%
  mutate(
    int_sd_t1 = ifelse(sd_imputed & is.na(int_sd_t1), median(int_sd_t1, na.rm = TRUE), int_sd_t1),
    int_sd_t2 = ifelse(sd_imputed & is.na(int_sd_t2), median(int_sd_t2, na.rm = TRUE), int_sd_t2),
    con_sd_t1 = ifelse(sd_imputed & is.na(con_sd_t1), median(con_sd_t1, na.rm = TRUE), con_sd_t1),
    con_sd_t2 = ifelse(sd_imputed & is.na(con_sd_t2), median(con_sd_t2, na.rm = TRUE), con_sd_t2)
  ) %>%
  ungroup()

# Final fallback: replace any remaining missing SDs with overall mean SDs
d_quasi$int_sd_t1[is.na(d_quasi$int_sd_t1)] <- mean(d_quasi$int_sd_t1, na.rm = TRUE)
d_quasi$int_sd_t2[is.na(d_quasi$int_sd_t2)] <- mean(d_quasi$int_sd_t2, na.rm = TRUE)
d_quasi$con_sd_t1[is.na(d_quasi$con_sd_t1)] <- mean(d_quasi$con_sd_t1, na.rm = TRUE)
d_quasi$con_sd_t2[is.na(d_quasi$con_sd_t2)] <- mean(d_quasi$con_sd_t2, na.rm = TRUE)

# Recompute change-score effect sizes after SD imputation
d_quasi <- d_quasi %>%
  mutate(
    baseline_sd_pooled = sqrt(
      ((int_n - 1) * int_sd_t1^2 + (con_n - 1) * con_sd_t1^2) /
        (int_n + con_n - 2)
    ),
    cohens_d_change = ifelse(
      is.na(cohen) & is.na(g_reported),
      (change_treatment - change_control) / baseline_sd_pooled,
      cohens_d_change
    )
  )

# Fallback: if pretest information is unavailable, compute posttest-only SMD
# IMPORTANT: do this AFTER all SD imputations
post_es <- metafor::escalc(
  measure = "SMD",
  m1i = d_quasi$int_mean_t2, sd1i = d_quasi$int_sd_t2, n1i = d_quasi$int_n,
  m2i = d_quasi$con_mean_t2, sd2i = d_quasi$con_sd_t2, n2i = d_quasi$con_n
)

d_quasi <- d_quasi %>%
  mutate(
    post_g = post_es$yi,
    post_v = post_es$vi
  )

# Convert Cohen's d / change-score d to Hedges' g
imputed_quasi <- d_quasi %>%
  mutate(
    df = int_n + con_n - 2,
    J = ifelse(!is.na(df) & (4 * df - 1) != 0,
               1 - (3 / (4 * df - 1)),
               NA_real_),
    
    es_source = case_when(
      !is.na(g_reported) ~ "reported_g",
      !is.na(cohen) ~ "cohen_d",
      !is.na(post_g) ~ "post_smd",
      !is.na(cohens_d_change) ~ "change_d",
      TRUE ~ NA_character_
    ),
    
    g_calc = case_when(
      !is.na(cohens_d_change) & !is.na(J) ~ cohens_d_change * J,
      !is.na(cohen) & !is.na(J) ~ cohen * J,
      TRUE ~ NA_real_
    ),
    
    g = case_when(
      es_source == "reported_g" ~ g_reported,
      es_source %in% c("change_d", "cohen_d") ~ g_calc,
      es_source == "post_smd" ~ post_g,
      TRUE ~ NA_real_
    ),
    
    smd = g
  ) %>%
  mutate(
    smd_v = case_when(
      es_source == "post_smd" ~ post_v,
      !is.na(smd) & !is.na(int_n) & !is.na(con_n) ~
        (int_n + con_n) / (int_n * con_n) + (smd^2) / (2 * (int_n + con_n)),
      TRUE ~ NA_real_
    )
  )

openxlsx::write.xlsx(
  imputed_quasi,
  "quasi_cleandata25July with baseline sd.xlsx",
  rowNames = FALSE
)

# Analysis ------------------------------------------------------------------

# Number of unique studies
n_distinct(imputed_quasi$study_id)

# Total sample size across studies (counting each study once)
imputed_quasi %>%
  distinct(apa_citation, study_id, N, .keep_all = TRUE) %>%
  summarise(total_N = sum(N, na.rm = TRUE)) %>%
  pull(total_N) %>%
  format(big.mark = ",")

# Build model-ready dataset first
imputed_quasi_model <- imputed_quasi %>%
  mutate(row_id = dplyr::row_number()) %>%
  filter(
    !is.na(smd), !is.na(smd_v),
    is.finite(smd), is.finite(smd_v),
    smd_v > 0
  )

# Main multilevel meta-analysis model
Meta_imputed_quasi <- metafor::rma.mv(
  yi = smd,
  V = smd_v,
  random = ~ 1 | apa_citation/effect_id,
  data = imputed_quasi_model,
  slab = apa_citation
)

print(Meta_imputed_quasi, digits = 3)

# Variance decomposition and I² estimation
source("https://raw.githubusercontent.com/MathiasHarrer/dmetar/master/R/mlm.variance.distribution.R")
i2 <- var.comp(Meta_imputed_quasi)

# OUTLIERS & SENSITIVITY ----------------------------------------------------

# Cook's Distance
inf <- cooks.distance(Meta_imputed_quasi, progbar = FALSE)
plot(inf, type = "b", pch = "*", cex = 2, main = "Influential Effects by Cook's Distance")

# Threshold for influential effects: 4/k
k_eff_two <- length(inf)
cutoff_two <- 4 / k_eff_two
abline(h = cutoff_two, col = "firebrick2")

# Identify influential effect rows
flagged_idx_two <- which(inf > cutoff_two)
flagged_row_ids_two <- imputed_quasi_model$row_id[flagged_idx_two]

# Label flagged effects
text(
  x = seq_along(inf),
  y = inf,
  labels = ifelse(inf > cutoff_two, as.character(imputed_quasi_model$apa_citation), ""),
  col = "firebrick2",
  pos = 3,
  cex = 0.8
)
# Show which effect sizes are removed
flagged_effects_two <- imputed_quasi_model %>%
  filter(row_id %in% flagged_row_ids_two) %>%
  select(row_id, study_id, effect_id, apa_citation, smd, smd_v)

cat("Automatically removed influential effect sizes (two-group):\n")
print(flagged_effects_two)

# Remove only flagged EFFECT rows (not whole studies)
nooutlier_quasi <- imputed_quasi %>%
  mutate(row_id = dplyr::row_number()) %>%
  filter(!row_id %in% flagged_row_ids_two) %>%
  select(-row_id)

openxlsx::write.xlsx(
  nooutlier_quasi,
  "C:/Users/Hana/Desktop/AI literacy.Data/quasi_with baseline sd_nooutliers_Sep1.xlsx",
  rowNames = FALSE
)

# Re-run meta-analysis without outliers
nooutlier_quasi_model <- nooutlier_quasi %>%
  mutate(row_id = dplyr::row_number()) %>%
  filter(
    !is.na(smd), !is.na(smd_v),
    is.finite(smd), is.finite(smd_v),
    smd_v > 0
  ) %>%
  select(-row_id)

outlier_analysis <- rma.mv(
  yi = smd,
  V = smd_v,
  slab = apa_citation,
  data = nooutlier_quasi_model,
  random = ~ 1 | apa_citation/effect_id,
  method = "REML"
)

print(outlier_analysis, digits = 3)

# Number of studies after removing outliers
n_distinct(nooutlier_quasi$study_id)

# Updated total sample size
nooutlier_quasi %>%
  distinct(apa_citation, study_id, N, .keep_all = TRUE) %>%
  summarise(total_N = sum(N, na.rm = TRUE)) %>%
  pull(total_N) %>%
  format(big.mark = ",")

# Sensitivity analysis excluding rows with imputed SDs
nonimputed <- nooutlier_quasi_model %>%
  filter(sd_imputed == FALSE)

imputation_analysis <- rma.mv(
  yi = smd,
  V = smd_v,
  slab = apa_citation,
  data = nonimputed,
  random = ~ 1 | apa_citation/effect_id,
  method = "REML"
)

print(imputation_analysis, digits = 3)

# FOREST PLOT ---------------------------------------------------------------

# Sort effect sizes for plotting
sorted_indices <- order(nooutlier_quasi_model$smd)
nooutlier_quasi_sorted <- nooutlier_quasi_model[sorted_indices, ]
apa_citation_sorted <- nooutlier_quasi_sorted$apa_citation

Meta_nooutlier_quasi_sorted <- metafor::rma.mv(
  yi = smd,
  V = smd_v,
  random = ~ 1 | apa_citation/effect_id,
  data = nooutlier_quasi_sorted,
  slab = apa_citation_sorted
)

# Create study labels showing each study only once
study_names_sorted <- sub("\\.\\d+$", "", Meta_nooutlier_quasi_sorted$slab)
slab_labels <- ifelse(duplicated(study_names_sorted), "", study_names_sorted)
study_rows_sorted <- as.numeric(factor(study_names_sorted, levels = unique(study_names_sorted)))

metafor::forest(
  Meta_nooutlier_quasi_sorted,
  mlab = "Pooled Estimate",
  refline = 0,
  slab = slab_labels,
  rows = study_rows_sorted,
  showweights = FALSE,
  annotate = FALSE,
  efac = c(0.2, 0.5),
  cex = 1,
  pch = 18
)

# ===============================================================
# Manually remove specific studies before combining
# ===============================================================

manual_remove <- c(
  "Abdulayeva et al. (2025)",
  "Chou et al. (2023)"
)

# Remove from no-outlier datasets (used for combined / moderator / no-outlier plots)
nooutlier_onegroup <- nooutlier_onegroup %>%
  dplyr::filter(!(as.character(apa_citation) %in% manual_remove))

nooutlier_quasi <- nooutlier_quasi %>%
  dplyr::filter(!(as.character(apa_citation) %in% manual_remove))

# Also remove from full datasets (used for combined_all / WITH-outliers funnel)
d_onegroup <- d_onegroup %>%
  dplyr::filter(!(as.character(apa_citation) %in% manual_remove))

imputed_quasi <- imputed_quasi %>%
  dplyr::filter(!(as.character(apa_citation) %in% manual_remove))

# Quick check
cat("Remaining in nooutlier_onegroup:\n")
print(nooutlier_onegroup %>% dplyr::count(apa_citation) %>% dplyr::filter(apa_citation %in% manual_remove))

cat("Remaining in nooutlier_quasi:\n")
print(nooutlier_quasi %>% dplyr::count(apa_citation) %>% dplyr::filter(apa_citation %in% manual_remove))

cat("Remaining in d_onegroup:\n")
print(d_onegroup %>% dplyr::count(apa_citation) %>% dplyr::filter(apa_citation %in% manual_remove))

cat("Remaining in imputed_quasi:\n")
print(imputed_quasi %>% dplyr::count(apa_citation) %>% dplyr::filter(apa_citation %in% manual_remove))

# ===============================================================
# Combine no-outlier datasets + Prepare variables for moderator models
# ===============================================================

# If the column name is "antecedent", rename it to "literacy_type"
if ("antecedent" %in% names(nooutlier_onegroup)) {
  nooutlier_onegroup <- nooutlier_onegroup %>%
    dplyr::rename(literacy_type = antecedent)
}

if ("antecedent" %in% names(nooutlier_quasi)) {
  nooutlier_quasi <- nooutlier_quasi %>%
    dplyr::rename(literacy_type = antecedent)
}

# -----------------------------
# Build harmonised datasets safely
# -----------------------------
one_ready <- nooutlier_onegroup %>%
  dplyr::transmute(
    study_id          = as.character(study_id),
    effect_id         = as.character(effect_id),
    apa_citation      = as.character(apa_citation),
    year              = suppressWarnings(as.numeric(as.character(year))),
    literacy_type     = as.character(literacy_type),
    career_stage      = as.character(career_stage),
    school_level      = as.character(school_level),
    rob1              = as.character(rob1),
    Inter_duration    = suppressWarnings(as.numeric(as.character(Inter_duration))),
    gender_proportion = suppressWarnings(as.numeric(as.character(gender_proportion))),
    yi                = as.numeric(yi),
    vi                = as.numeric(vi),
    design            = "one_group"
  ) %>%
  dplyr::ungroup() %>%
  as.data.frame()

two_ready <- nooutlier_quasi %>%
  dplyr::transmute(
    study_id          = as.character(study_id),
    effect_id         = as.character(effect_id),
    apa_citation      = as.character(apa_citation),
    year              = suppressWarnings(as.numeric(as.character(year))),
    literacy_type     = as.character(literacy_type),
    career_stage      = as.character(career_stage),
    school_level      = as.character(school_level),
    rob1              = as.character(rob1),
    Inter_duration    = suppressWarnings(as.numeric(as.character(Inter_duration))),
    gender_proportion = suppressWarnings(as.numeric(as.character(gender_proportion))),
    yi                = as.numeric(smd),
    vi                = as.numeric(smd_v),
    design            = "two_group"
  ) %>%
  dplyr::ungroup() %>%
  as.data.frame()

combined <- dplyr::bind_rows(one_ready, two_ready) %>%
  dplyr::filter(
    !is.na(apa_citation),
    !is.na(effect_id),
    !is.na(yi), !is.na(vi),
    is.finite(yi), is.finite(vi),
    vi > 0
  )

combined <- combined %>%
  dplyr::mutate(
    gender_proportion = suppressWarnings(as.numeric(as.character(gender_proportion)))
  )

print(summary(combined$gender_proportion))
print(sum(!is.na(combined$gender_proportion)))

# Convert moderator variables to factors
combined <- combined %>%
  dplyr::mutate(
    design        = factor(design, levels = c("two_group", "one_group")),
    literacy_type = droplevels(factor(literacy_type)),
    career_stage  = droplevels(factor(career_stage)),
    school_level  = droplevels(factor(school_level))
  )

# Check sample distribution
print(table(combined$design, useNA = "ifany"))
print(table(combined$career_stage, useNA = "ifany"))
print(table(combined$literacy_type, useNA = "ifany"))
print(table(combined$school_level, useNA = "ifany"))

# ===============================================================
# Main meta-analysis model on combined dataset
# ===============================================================

Meta_combined <- metafor::rma.mv(
  yi     = yi,
  V      = vi,
  random = ~ 1 | apa_citation/effect_id,
  data   = combined,
  method = "REML",
  slab   = apa_citation
)

print(Meta_combined, digits = 3)

i2_combined <- var.comp(Meta_combined)
print(i2_combined$results)
print(i2_combined$totalI2)

robust_combined <- metafor::robust(Meta_combined, cluster = combined$apa_citation)
print(robust_combined)

# ===============================================================
# Individual moderator models
# ===============================================================

# ----------------------------
# literacy_type moderator
# ----------------------------
print(table(combined$literacy_type, useNA = "ifany"))

literacy_type_counts <- combined %>%
  dplyr::group_by(literacy_type) %>%
  dplyr::tally() %>%
  dplyr::filter(n >= 4)

filtered_combined <- combined %>%
  dplyr::filter(literacy_type %in% literacy_type_counts$literacy_type) %>%
  droplevels()

literacy_type_moderator <- metafor::rma.mv(
  yi = yi, V = vi,
  random = ~ 1 | apa_citation/effect_id,
  data = filtered_combined,
  slab = apa_citation,
  test = "t",
  method = "REML",
  mods = ~ literacy_type
)
print(summary(literacy_type_moderator))

fit_literacy_set_obj <- metafor::rma.mv(
  yi = yi, V = vi,
  slab = apa_citation,
  data = filtered_combined,
  random = ~ 1 | apa_citation/effect_id,
  test = "t",
  method = "REML",
  mods = ~ literacy_type - 1
)
print(summary(fit_literacy_set_obj))

print(clubSandwich::coef_test(
  fit_literacy_set_obj,
  vcov = "CR2",
  test = "Satterthwaite"
))

literacy_type.set <- data.frame(
  estimate = as.numeric(coef(fit_literacy_set_obj)),
  stderror = as.numeric(fit_literacy_set_obj$se),
  ci.lb    = as.numeric(fit_literacy_set_obj$ci.lb),
  ci.ub    = as.numeric(fit_literacy_set_obj$ci.ub),
  row.names = names(coef(fit_literacy_set_obj))
)

# counts
k_literacy_type <- filtered_combined %>%
  dplyr::group_by(literacy_type) %>%
  dplyr::summarise(k = dplyr::n(), .groups = "drop")

n_literacy_type <- filtered_combined %>%
  dplyr::select(literacy_type, apa_citation) %>%
  dplyr::distinct() %>%
  dplyr::group_by(literacy_type) %>%
  dplyr::summarise(n = dplyr::n(), .groups = "drop")

literacy_type_tab <- dplyr::left_join(k_literacy_type, n_literacy_type, by = "literacy_type")

openxlsx::write.xlsx(
  literacy_type_tab,
  "literacy_type_moderator_4_or_more.xlsx",
  rowNames = FALSE
)

literacy_type.set2 <- tibble::rownames_to_column(literacy_type.set, var = "literacy_type")
literacy_type.set2$literacy_type <- gsub("^literacy_type", "", literacy_type.set2$literacy_type)

literacy_type_plot <- dplyr::left_join(literacy_type_tab, literacy_type.set2, by = "literacy_type") %>%
  dplyr::mutate(
    gci = paste0(
      format(round(estimate, 2), nsmall = 2),
      " [",
      format(round(ci.lb, 2), nsmall = 2),
      ", ",
      format(round(ci.ub, 2), nsmall = 2),
      "]"
    ),
    signif = ifelse(ci.lb > 0 | ci.ub < 0, "bold", "plain"),
    groups = "literacy_type"
  ) %>%
  dplyr::arrange(estimate)

header_row <- "__HEADER__"

header_labels <- literacy_type_plot %>%
  dplyr::distinct(groups) %>%
  dplyr::mutate(
    literacy_type = header_row,
    estimate = NA_real_, ci.lb = NA_real_, ci.ub = NA_real_,
    n = NA_integer_, k = NA_integer_, gci = NA_character_,
    signif = "plain",
    is_header = TRUE,
    Studies = "Studies",
    Effects = "Effects",
    CI = "[95% CI]"
  )

plot_df <- literacy_type_plot %>%
  dplyr::mutate(is_header = FALSE) %>%
  dplyr::bind_rows(header_labels) %>%
  dplyr::mutate(literacy_type = forcats::fct_expand(literacy_type, header_row)) %>%
  dplyr::mutate(literacy_type = forcats::fct_relevel(literacy_type, header_row, after = 0))

geom.text.size <- 3

m <- ggplot2::ggplot(
  data = plot_df,
  ggplot2::aes(x = estimate, xmin = ci.lb, xmax = ci.ub, y = literacy_type)
) +
  ggplot2::geom_pointrange(
    data = dplyr::filter(plot_df, !is_header),
    ggplot2::aes(colour = groups, size = signif)
  ) +
  ggplot2::scale_size_manual(values = c(plain = 0.7, bold = 1.0), guide = "none") +
  ggplot2::expand_limits(x = c(-1, 6.2)) +
  ggplot2::labs(x = "Effect Sizes", y = " ") +
  ggplot2::theme_minimal() %+replace%
  ggplot2::theme(
    axis.text.y = ggplot2::element_text(size = 9, hjust = 1, colour = "black"),
    legend.position = "none",
    plot.margin = ggplot2::margin(30, 235, 25, 5),
    strip.placement = "outside",
    strip.text.y = ggplot2::element_text(size = 9, colour = "black", angle = 90)
  ) +
  ggplot2::coord_cartesian(clip = "off") +
  ggplot2::facet_grid(groups ~ ., scales = "free", space = "free", switch = "both") +
  ggplot2::geom_vline(xintercept = 0) +
  ggplot2::geom_text(
    data = dplyr::filter(plot_df, !is_header),
    ggplot2::aes(x = 3.5, label = n, fontface = signif),
    hjust = 0.5, size = geom.text.size
  ) +
  ggplot2::geom_text(
    data = dplyr::filter(plot_df, !is_header),
    ggplot2::aes(x = 4.25, label = format(k, big.mark = ","), fontface = signif),
    hjust = 0.5, size = geom.text.size
  ) +
  ggplot2::geom_text(
    data = dplyr::filter(plot_df, !is_header),
    ggplot2::aes(x = 5.6, label = gci, fontface = signif),
    hjust = 0.5, size = geom.text.size
  ) +
  ggplot2::geom_text(
    data = dplyr::filter(plot_df, is_header),
    ggplot2::aes(x = 3.5, y = literacy_type, label = Studies),
    inherit.aes = FALSE, hjust = 0.5, size = geom.text.size
  ) +
  ggplot2::geom_text(
    data = dplyr::filter(plot_df, is_header),
    ggplot2::aes(x = 4.25, y = literacy_type, label = Effects),
    inherit.aes = FALSE, hjust = 0.5, size = geom.text.size
  ) +
  ggplot2::geom_text(
    data = dplyr::filter(plot_df, is_header),
    ggplot2::aes(x = 5.6, y = literacy_type, label = CI),
    inherit.aes = FALSE, hjust = 0.5, size = geom.text.size
  ) +
  ggplot2::scale_y_discrete(labels = function(x) ifelse(x == header_row, "", x))

print(m)

ggplot2::ggsave(
  filename = "combined_literacy_type_moderator_4_or_more_plot.png",
  plot = m, height = 8, width = 12, dpi = 600, bg = "white"
)

# ----------------------------
# gender_proportion moderator
# Continuous moderator, 0–1 scale
# ----------------------------

gender_dat <- combined %>%
  dplyr::filter(
    !is.na(gender_proportion),
    is.finite(gender_proportion)
  )

gender_moderator <- metafor::rma.mv(
  yi = yi,
  V = vi,
  random = ~ 1 | apa_citation/effect_id,
  data = gender_dat,
  slab = apa_citation,
  test = "t",
  method = "REML",
  mods = ~ gender_proportion
)

print(summary(gender_moderator))

print(clubSandwich::coef_test(
  gender_moderator,
  vcov = "CR2",
  test = "Satterthwaite"
))

gender_dat <- gender_dat %>%
  dplyr::mutate(
    gender_proportion_10 = gender_proportion * 10
  )

gender_moderator_10 <- metafor::rma.mv(
  yi = yi,
  V = vi,
  random = ~ 1 | apa_citation/effect_id,
  data = gender_dat,
  slab = apa_citation,
  test = "t",
  method = "REML",
  mods = ~ gender_proportion_10
)

print(summary(gender_moderator_10))

print(clubSandwich::coef_test(
  gender_moderator_10,
  vcov = "CR2",
  test = "Satterthwaite"
))

# ----------------------------
# design moderator
# ----------------------------
design_moderator <- metafor::rma.mv(
  yi = yi, V = vi,
  random = ~ 1 | apa_citation/effect_id,
  data = combined,
  slab = apa_citation,
  test = "t",
  method = "REML",
  mods = ~ design
)
print(summary(design_moderator))
print(coef_test(design_moderator, vcov = "CR2", test = "Satterthwaite"))

fit_design_set <- metafor::rma.mv(
  yi = yi, V = vi,
  slab = apa_citation,
  data = combined,
  random = ~ 1 | apa_citation/effect_id,
  test = "t",
  method = "REML",
  mods = ~ design - 1
)
print(summary(fit_design_set))
print(coef_test(fit_design_set, vcov = "CR2", test = "Satterthwaite"))

# ----------------------------
# career_stage moderator
# ----------------------------
career_moderator <- metafor::rma.mv(
  yi = yi, V = vi,
  random = ~ 1 | apa_citation/effect_id,
  data = combined,
  slab = apa_citation,
  test = "t",
  method = "REML",
  mods = ~ career_stage
)
print(summary(career_moderator))
print(coef_test(career_moderator, vcov = "CR2", test = "Satterthwaite"))

fit_career_set <- metafor::rma.mv(
  yi = yi, V = vi,
  slab = apa_citation,
  data = combined,
  random = ~ 1 | apa_citation/effect_id,
  test = "t",
  method = "REML",
  mods = ~ career_stage - 1
)
print(summary(fit_career_set))
print(clubSandwich::coef_test(fit_career_set, vcov = "CR2", test = "Satterthwaite"))

# ----------------------------
# school_level moderator
# ----------------------------
print(table(combined$school_level, useNA = "ifany"))

school_level_counts <- combined %>%
  dplyr::group_by(school_level) %>%
  dplyr::tally() %>%
  dplyr::filter(n >= 4)

filtered_school <- combined %>%
  dplyr::filter(school_level %in% school_level_counts$school_level) %>%
  droplevels()

school_moderator <- metafor::rma.mv(
  yi = yi, V = vi,
  random = ~ 1 | apa_citation/effect_id,
  data = filtered_school,
  slab = apa_citation,
  test = "t",
  method = "REML",
  mods = ~ school_level
)
print(summary(school_moderator))
print(clubSandwich::coef_test(school_moderator, vcov = "CR2", test = "Satterthwaite"))

fit_school_set <- metafor::rma.mv(
  yi = yi, V = vi,
  slab = apa_citation,
  data = filtered_school,
  random = ~ 1 | apa_citation/effect_id,
  test = "t",
  method = "REML",
  mods = ~ school_level - 1
)
print(summary(fit_school_set))
print(clubSandwich::coef_test(fit_school_set, vcov = "CR2", test = "Satterthwaite"))

# ===============================================================
# Combined moderator figure (AI literacy + Design + Career stage + School level)
# ===============================================================

if ("package:plyr" %in% search()) detach("package:plyr", unload = TRUE)

is_numeric_like <- function(x) {
  x2 <- as.character(x)
  all(grepl("^[0-9]+$", x2[!is.na(x2)]))
}

if (is_numeric_like(combined$literacy_type)) {
  literacy_map <- c(
    "1" = "AI skills",
    "2" = "AI knowledge",
    "3" = "AI attitude"
  )
  
  combined <- combined %>%
    dplyr::mutate(
      literacy_type = dplyr::recode(
        as.character(literacy_type),
        !!!literacy_map,
        .default = as.character(literacy_type)
      )
    )
}

combined <- combined %>%
  dplyr::mutate(
    apa_citation  = as.factor(apa_citation),
    effect_id     = as.factor(effect_id),
    literacy_type = droplevels(as.factor(literacy_type)),
    design        = droplevels(as.factor(design)),
    career_stage  = droplevels(as.factor(career_stage)),
    school_level  = droplevels(as.factor(school_level))
  )

# Refit set models for extraction
literacy_keep <- combined %>%
  dplyr::count(literacy_type, name = "k") %>%
  dplyr::filter(k >= 4) %>%
  dplyr::pull(literacy_type)

filtered_combined2 <- combined %>%
  dplyr::filter(literacy_type %in% literacy_keep) %>%
  droplevels()

fit_literacy_set <- metafor::rma.mv(
  yi = yi, V = vi,
  random = ~ 1 | apa_citation/effect_id,
  data = filtered_combined2,
  method = "REML", test = "t",
  mods = ~ literacy_type - 1
)

fit_design_set <- metafor::rma.mv(
  yi = yi, V = vi,
  random = ~ 1 | apa_citation/effect_id,
  data = combined,
  method = "REML", test = "t",
  mods = ~ design - 1
)

fit_career_set <- metafor::rma.mv(
  yi = yi, V = vi,
  random = ~ 1 | apa_citation/effect_id,
  data = combined,
  method = "REML", test = "t",
  mods = ~ career_stage - 1
)

fit_school_set <- metafor::rma.mv(
  yi = yi, V = vi,
  random = ~ 1 | apa_citation/effect_id,
  data = filtered_school,
  method = "REML", test = "t",
  mods = ~ school_level - 1
)

extract_set_table <- function(fit_obj) {
  data.frame(
    estimate = as.numeric(coef(fit_obj)),
    stderror = as.numeric(fit_obj$se),
    ci.lb    = as.numeric(fit_obj$ci.lb),
    ci.ub    = as.numeric(fit_obj$ci.ub),
    row.names = names(coef(fit_obj))
  )
}

literacy_type.set <- extract_set_table(fit_literacy_set)
design.set        <- extract_set_table(fit_design_set)
career.set        <- extract_set_table(fit_career_set)
school.set        <- extract_set_table(fit_school_set)

clean_display <- function(x) {
  x <- as.character(x)
  x <- gsub("\u00A0", " ", x, fixed = TRUE)
  x <- gsub("[\r\n\t]", " ", x)
  x <- stringr::str_trim(x)
  x <- stringr::str_replace_all(x, "\\s+", " ")
  x
}

make_join_key <- function(x) make.names(clean_display(x))

unmake_names_label <- function(x) {
  x <- as.character(x)
  x <- sub("^X(?=[0-9])", "", x, perl = TRUE)
  x <- gsub("\\.", " ", x)
  clean_display(x)
}

counts_nk <- function(dat, var, group_label) {
  v <- rlang::ensym(var)
  dat %>%
    dplyr::mutate(
      conditions   = clean_display(!!v),
      cond_key     = make_join_key(!!v),
      groups       = group_label,
      apa_citation = clean_display(apa_citation)
    ) %>%
    dplyr::group_by(groups, conditions, cond_key) %>%
    dplyr::summarise(
      k = dplyr::n(),
      n = dplyr::n_distinct(apa_citation),
      .groups = "drop"
    )
}

nk_literacy <- counts_nk(filtered_combined2, literacy_type, "AI literacy")
nk_design   <- counts_nk(combined,          design,        "Design")
nk_career   <- counts_nk(combined,          career_stage,  "Career stage")
nk_school   <- counts_nk(filtered_school,   school_level,  "School level")

arm_n_k <- dplyr::bind_rows(nk_literacy, nk_design, nk_career, nk_school)

build_mod_table <- function(set_df, prefix, group_label) {
  tibble::rownames_to_column(set_df, var = "coefname") %>%
    dplyr::mutate(
      coef_suffix = gsub(paste0("^", prefix), "", coefname),
      conditions  = unmake_names_label(coef_suffix),
      cond_key    = make_join_key(conditions),
      groups      = group_label
    ) %>%
    dplyr::select(groups, conditions, cond_key, estimate, stderror, ci.lb, ci.ub)
}

mods_literacy <- build_mod_table(literacy_type.set, "literacy_type", "AI literacy")
mods_design   <- build_mod_table(design.set,        "design",        "Design")
mods_career   <- build_mod_table(career.set,        "career_stage",  "Career stage")
mods_school   <- build_mod_table(school.set,        "school_level",  "School level")

moderators <- dplyr::bind_rows(mods_literacy, mods_design, mods_career, mods_school)

mods <- dplyr::left_join(
  moderators,
  arm_n_k %>% dplyr::select(groups, cond_key, n, k),
  by = c("groups", "cond_key")
)

bad <- mods %>%
  dplyr::filter(is.na(n) | is.na(k)) %>%
  dplyr::select(groups, conditions, n, k, cond_key)

if (nrow(bad) > 0) {
  print(bad)
  warning("Some levels could not be matched to n/k. Unmatched rows will be dropped from the combined moderator figure.")
  mods <- mods %>% dplyr::filter(!(is.na(n) | is.na(k)))
}

mods <- mods %>%
  dplyr::mutate(
    conditions = dplyr::case_when(
      groups == "Design" & conditions == "one_group" ~ "One-group",
      groups == "Design" & conditions == "two_group" ~ "Two-group",
      TRUE ~ conditions
    ),
    gci = paste0(
      format(round(estimate, 2), nsmall = 2),
      " [",
      format(round(ci.lb, 2), nsmall = 2),
      ", ",
      format(round(ci.ub, 2), nsmall = 2),
      "]"
    ),
    signif = ifelse(ci.lb > 0 | ci.ub < 0, "bold", "plain")
  ) %>%
  dplyr::mutate(
    order_top = dplyr::case_when(
      groups == "AI literacy"  & conditions == "AI knowledge" ~ 1,
      groups == "AI literacy"  & conditions == "AI skills"    ~ 2,
      groups == "AI literacy"  & conditions == "AI attitude"  ~ 3,
      groups == "Career stage" & conditions == "Pre-service"  ~ 1,
      groups == "Career stage" & conditions == "In-service"   ~ 2,
      groups == "Design"       & conditions == "One-group"    ~ 1,
      groups == "Design"       & conditions == "Two-group"    ~ 2,
      groups == "School level" & conditions == "Elementary"   ~ 1,
      groups == "School level" & conditions == "Secondary"    ~ 2,
      groups == "School level" & conditions == "Mixed"        ~ 3,
      TRUE ~ 999
    )
  )

header_labels <- mods %>%
  dplyr::distinct(groups) %>%
  dplyr::mutate(
    conditions = " ",
    estimate = NA_real_,
    ci.lb = NA_real_,
    ci.ub = NA_real_,
    n = NA_integer_,
    k = NA_integer_,
    gci = NA_character_,
    signif = "plain",
    is_header = TRUE,
    order_top = 0,
    Level   = " ",
    Studies = "Studies",
    Effects = "Effects",
    CI      = "[95% CI]"
  ) %>%
  dplyr::select(
    groups, conditions, estimate, ci.lb, ci.ub, n, k, gci,
    signif, is_header, order_top, Level, Studies, Effects, CI
  )

mods_plot <- mods %>%
  dplyr::mutate(
    is_header = FALSE,
    Level   = NA_character_,
    Studies = NA_character_,
    Effects = NA_character_,
    CI      = NA_character_
  ) %>%
  dplyr::bind_rows(header_labels) %>%
  dplyr::mutate(
    order_plot = dplyr::case_when(
      conditions == " " ~ 999,
      TRUE ~ -order_top
    )
  ) %>%
  dplyr::group_by(groups) %>%
  dplyr::arrange(order_plot, .by_group = TRUE) %>%
  dplyr::mutate(
    y_id = paste0(groups, "___", conditions)
  ) %>%
  dplyr::ungroup()

y_levels <- mods_plot %>%
  dplyr::arrange(
    factor(groups, levels = c("AI literacy", "Career stage", "Design", "School level")),
    order_plot
  ) %>%
  dplyr::pull(y_id)

mods_plot$y_id <- factor(mods_plot$y_id, levels = unique(y_levels))

geom.text.size <- 3
x_level   <- -0.55
x_studies <-  3.45
x_effects <-  4.25
x_ci      <-  5.55

m_combined <- ggplot2::ggplot(
  data = mods_plot,
  ggplot2::aes(x = estimate, xmin = ci.lb, xmax = ci.ub, y = y_id)
) +
  ggplot2::geom_pointrange(
    data = dplyr::filter(mods_plot, !is_header),
    ggplot2::aes(colour = groups, size = signif)
  ) +
  ggplot2::scale_size_manual(values = c(plain = 0.7, bold = 1.0), guide = "none") +
  ggplot2::expand_limits(x = c(-1, 6.2)) +
  ggplot2::labs(x = "Effect Sizes", y = " ") +
  ggplot2::theme_minimal() %+replace%
  ggplot2::theme(
    axis.text.y     = ggplot2::element_text(size = 9, hjust = 1, colour = "black"),
    legend.position = "none",
    plot.margin     = ggplot2::margin(35, 240, 25, 10),
    strip.placement = "outside",
    strip.text.y    = ggplot2::element_text(size = 9, colour = "black", angle = 90)
  ) +
  ggplot2::coord_cartesian(clip = "off") +
  ggplot2::geom_vline(xintercept = 0) +
  ggplot2::facet_grid(groups ~ ., scales = "free", space = "free", switch = "both") +
  ggplot2::geom_text(
    data = dplyr::filter(mods_plot, !is_header),
    ggplot2::aes(x = x_studies, label = n, fontface = signif),
    hjust = 0.5, size = geom.text.size
  ) +
  ggplot2::geom_text(
    data = dplyr::filter(mods_plot, !is_header),
    ggplot2::aes(x = x_effects, label = format(k, big.mark = ","), fontface = signif),
    hjust = 0.5, size = geom.text.size
  ) +
  ggplot2::geom_text(
    data = dplyr::filter(mods_plot, !is_header),
    ggplot2::aes(x = x_ci, label = gci, fontface = signif),
    hjust = 0.5, size = geom.text.size
  ) +
  ggplot2::geom_text(
    data = dplyr::filter(mods_plot, is_header),
    ggplot2::aes(x = x_level, y = y_id, label = Level),
    inherit.aes = FALSE, hjust = 0, size = geom.text.size
  ) +
  ggplot2::geom_text(
    data = dplyr::filter(mods_plot, is_header),
    ggplot2::aes(x = x_studies, y = y_id, label = Studies),
    inherit.aes = FALSE, hjust = 0.5, size = geom.text.size
  ) +
  ggplot2::geom_text(
    data = dplyr::filter(mods_plot, is_header),
    ggplot2::aes(x = x_effects, y = y_id, label = Effects),
    inherit.aes = FALSE, hjust = 0.5, size = geom.text.size
  ) +
  ggplot2::geom_text(
    data = dplyr::filter(mods_plot, is_header),
    ggplot2::aes(x = x_ci, y = y_id, label = CI),
    inherit.aes = FALSE, hjust = 0.5, size = geom.text.size
  ) +
  ggplot2::scale_y_discrete(
    labels = function(x) {
      lab <- sub("^.*___", "", x)
      ifelse(lab == " ", "", lab)
    }
  )

print(m_combined)

ggplot2::ggsave(
  filename = "combined_nooutlier_moderator_AI_Design_Career_School_plot.png",
  plot     = m_combined,
  height   = 8,
  width    = 12,
  dpi      = 600,
  bg       = "white"
)

# ----------------------------
# Plot for continuous gender_proportion moderator
# ----------------------------

gender_range <- seq(
  min(gender_dat$gender_proportion, na.rm = TRUE),
  max(gender_dat$gender_proportion, na.rm = TRUE),
  length.out = 100
)

pred_gender <- predict(
  gender_moderator,
  newmods = gender_range
)

gender_plot_df <- data.frame(
  gender_proportion = gender_range,
  pred = pred_gender$pred,
  ci.lb = pred_gender$ci.lb,
  ci.ub = pred_gender$ci.ub
)

p_gender <- ggplot2::ggplot(gender_plot_df, ggplot2::aes(x = gender_proportion, y = pred)) +
  ggplot2::geom_line(linewidth = 1) +
  ggplot2::geom_ribbon(
    ggplot2::aes(ymin = ci.lb, ymax = ci.ub),
    alpha = 0.20
  ) +
  ggplot2::geom_point(
    data = gender_dat,
    ggplot2::aes(x = gender_proportion, y = yi),
    alpha = 0.35,
    inherit.aes = FALSE
  ) +
  ggplot2::labs(
    x = "Gender proportion",
    y = "Predicted effect size",
    title = "Gender proportion as a continuous moderator"
  ) +
  ggplot2::theme_minimal()

print(p_gender)

ggplot2::ggsave(
  filename = "gender_proportion_continuous_moderator_plot.png",
  plot = p_gender,
  height = 5,
  width = 7,
  dpi = 600,
  bg = "white"
)

# ===============================================================
# PUBLICATION BIAS — Combined
# ===============================================================

# WITH OUTLIERS
combined_all <- dplyr::bind_rows(
  d_onegroup %>%
    dplyr::transmute(
      study_id     = as.character(study_id),
      effect_id    = as.character(effect_id),
      apa_citation = as.character(apa_citation),
      yi           = as.numeric(yi),
      vi           = as.numeric(vi),
      design       = "one_group"
    ),
  imputed_quasi %>%
    dplyr::transmute(
      study_id     = as.character(study_id),
      effect_id    = as.character(effect_id),
      apa_citation = as.character(apa_citation),
      yi           = as.numeric(smd),
      vi           = as.numeric(smd_v),
      design       = "two_group"
    )
) %>%
  dplyr::filter(
    !is.na(apa_citation),
    !is.na(effect_id),
    !is.na(yi), !is.na(vi),
    is.finite(yi), is.finite(vi),
    vi > 0
  )

Meta_combined_all <- metafor::rma.mv(
  yi = yi, V = vi,
  random = ~ 1 | apa_citation/effect_id,
  data   = combined_all,
  method = "REML",
  slab   = apa_citation
)

# Univariate models for funnel / Egger
Meta_combined_all_uni <- metafor::rma(
  yi = yi, vi = vi,
  data = combined_all,
  method = "REML"
)

Meta_combined_uni <- metafor::rma(
  yi = yi, vi = vi,
  data = combined,
  method = "REML"
)

# Funnel plot WITH outliers (show in Plots pane only)
tryCatch({
  metafor::funnel(
    Meta_combined_all_uni,
    xlim  = c(-3, 6),
    ylim  = c(1, 0),
    level = c(90, 95, 99),
    shade = c("white", "gray55", "gray75"),
    label = FALSE
  )
}, error = function(e) {
  message("WITH-outliers funnel plot failed: ", e$message)
})

# Funnel plot WITHOUT outliers (show in Plots pane only)
tryCatch({
  metafor::funnel(
    Meta_combined_uni,
    xlim  = c(-3, 6),
    ylim  = c(1, 0),
    level = c(90, 95, 99),
    shade = c("white", "gray55", "gray75"),
    label = FALSE
  )
}, error = function(e) {
  message("WITHOUT-outliers funnel plot failed: ", e$message)
})

# Egger
print(regtest(Meta_combined_all_uni, model = "rma"))
print(regtest(Meta_combined_uni, model = "rma"))

# PET / PEESE + CR2
dat_pet  <- combined_all %>% dplyr::mutate(sei = sqrt(vi))
PET_mv   <- metafor::rma.mv(
  yi = yi, V = vi,
  mods = ~ sei,
  random = ~ 1 | apa_citation/effect_id,
  data = dat_pet, method = "REML"
)
print(coef_test(PET_mv, vcov = "CR2", test = "Satterthwaite"))

PEESE_mv <- metafor::rma.mv(
  yi = yi, V = vi,
  mods = ~ I(sei^2),
  random = ~ 1 | apa_citation/effect_id,
  data = dat_pet, method = "REML"
)
print(coef_test(PEESE_mv, vcov = "CR2", test = "Satterthwaite"))

dat_pet2 <- combined %>% dplyr::mutate(sei = sqrt(vi))
PET_mv2  <- metafor::rma.mv(
  yi = yi, V = vi,
  mods = ~ sei,
  random = ~ 1 | apa_citation/effect_id,
  data = dat_pet2, method = "REML"
)
print(coef_test(PET_mv2, vcov = "CR2", test = "Satterthwaite"))

PEESE_mv2 <- metafor::rma.mv(
  yi = yi, V = vi,
  mods = ~ I(sei^2),
  random = ~ 1 | apa_citation/effect_id,
  data = dat_pet2, method = "REML"
)
print(coef_test(PEESE_mv2, vcov = "CR2", test = "Satterthwaite"))

# ===============================================================
# Forest plot (ALL studies combined; study-level: 1 row per study)
# ===============================================================

# Use combined (without outliers); switch to combined_all if needed
dat0 <- combined

dat_eff <- dat0 %>%
  dplyr::mutate(
    apa_citation = as.character(apa_citation),
    effect_id    = as.character(effect_id)
  ) %>%
  dplyr::filter(
    !is.na(apa_citation),
    !is.na(effect_id),
    !is.na(yi), !is.na(vi),
    is.finite(yi), is.finite(vi),
    vi > 0
  )

dat_study <- dat_eff %>%
  dplyr::group_by(apa_citation) %>%
  dplyr::summarise(
    k_eff = dplyr::n(),
    yi    = weighted.mean(yi, w = 1 / vi),
    vi    = 1 / sum(1 / vi),
    .groups = "drop"
  ) %>%
  dplyr::mutate(
    slab  = apa_citation,
    sei   = sqrt(vi),
    ci.lb = yi - 1.96 * sei,
    ci.ub = yi + 1.96 * sei,
    est_ci = sprintf("%.2f   [%.2f, %.2f]", yi, ci.lb, ci.ub)
  ) %>%
  dplyr::arrange(yi)

if (nrow(dat_study) == 0) {
  warning("Forest plot skipped: dat_study is empty after filtering.")
} else {
  
  fit_all <- metafor::rma(yi = yi, vi = vi, data = dat_study, method = "REML")
  
  w <- as.numeric(weights(fit_all))
  dat_study$w_perc <- 100 * w / sum(w)
  
  k <- nrow(dat_study)
  top_row <- k + 6
  rows <- seq(from = top_row, length.out = k, by = -1.5)
  row_poly_all <- min(rows) - 3
  dat_study$rows <- rows
  
  x_axis_min <- floor(min(dat_study$ci.lb, 0) * 10) / 10
  x_axis_max <- ceiling(max(dat_study$ci.ub) * 10) / 10
  x_rng <- x_axis_max - x_axis_min
  if (x_rng <= 0) x_rng <- 1
  
  x_plot_left  <- x_axis_min - 1.2 * x_rng
  x_plot_right <- x_axis_max + 1.6 * x_rng
  
  x_study <- x_axis_min - 0.95 * x_rng
  x_w     <- x_plot_right - 0.55 * x_rng
  x_est   <- x_plot_right - 0.35 * x_rng
  
  tryCatch({
    
    par(mar = c(10, 5.5, 2.2, 12), xpd = NA)
    
    metafor::forest(
      x = dat_study$yi, vi = dat_study$vi,
      slab = dat_study$slab,
      rows = dat_study$rows,
      refline = 0,
      xlim = c(x_plot_left, x_plot_right),
      alim = c(x_axis_min, x_axis_max),
      textpos = c(x_study, x_axis_max),
      xlab = " ",
      pch = 15, cex = 0.95,
      annotate = FALSE,
      showweights = FALSE,
      header = " ",
      xaxt = "n"
    )
    
    axis(1, at = pretty(c(x_axis_min, x_axis_max)), line = 6)
    
    row_step <- abs(dat_study$rows[1] - dat_study$rows[2])
    half_h   <- row_step / 2
    
    stripe_col <- grDevices::adjustcolor(gray(0.93), alpha.f = 0.85)
    for (i in seq_along(dat_study$rows)) {
      if (i %% 2 == 0) {
        y <- dat_study$rows[i]
        padL <- -1.00 * x_rng
        padR <-  0.30 * x_rng
        rect(
          x_axis_min + padL, y - half_h,
          x_plot_right + padR, y + half_h,
          col = stripe_col, border = NA
        )
      }
    }
    
    abline(v = 0, lty = 3, col = "gray70")
    
    segments(dat_study$ci.lb, dat_study$rows, dat_study$ci.ub, dat_study$rows, lwd = 1.2)
    points(dat_study$yi, dat_study$rows, pch = 15, cex = 0.95)
    
    text(x = x_study, y = dat_study$rows, labels = dat_study$slab, pos = 4, cex = 0.95)
    text(x = x_study, y = top_row + 2, pos = 4, font = 2, "Author(s) and Year")
    text(x = x_w,     y = top_row + 2, font = 2, "Weight")
    text(x = x_est,   y = top_row + 2, pos = 4, font = 2, "Estimate  [95% CI]")
    
    text(x = x_w,   y = dat_study$rows, labels = sprintf("%.2f%%", dat_study$w_perc), cex = 0.95)
    text(x = x_est, y = dat_study$rows, labels = dat_study$est_ci, pos = 4, cex = 0.95)
    
    metafor::addpoly(fit_all, row = row_poly_all, mlab = "", cex = 1.05)
    text(x = x_study, y = row_poly_all, pos = 4, font = 2, "Random-Effects Model")
    
    pred_all <- predict(fit_all, level = 95)
    text(x = x_w, y = row_poly_all, labels = "100%", cex = 1.0, font = 2)
    text(
      x = x_est, y = row_poly_all,
      labels = sprintf("%.2f   [%.2f, %.2f]", pred_all$pred, pred_all$ci.lb, pred_all$ci.ub),
      pos = 4, cex = 1.0, font = 2
    )
    
  }, error = function(e) {
    message("Forest plot failed: ", e$message)
  })
}

# ===============================================================
# Forest plot (ALL studies combined; multiple effect sizes on same row)
# Style similar to the FIRST figure
# ===============================================================

options(warn = 1, nwarnings = 10000)

# Use your actual no-outlier combined dataset here
dat0 <- combined

# -------- 1. Auto-detect effect size columns --------
if (all(c("yi", "vi") %in% names(dat0))) {
  dat_eff <- dat0 %>%
    dplyr::mutate(
      apa_citation = as.character(apa_citation),
      effect_id    = as.character(effect_id),
      yi           = as.numeric(yi),
      vi           = as.numeric(vi)
    )
} else if (all(c("g", "smd_v") %in% names(dat0))) {
  dat_eff <- dat0 %>%
    dplyr::mutate(
      apa_citation = as.character(apa_citation),
      effect_id    = as.character(effect_id),
      yi           = as.numeric(g),
      vi           = as.numeric(smd_v)
    )
} else {
  stop("No valid effect size columns found. Need either yi/vi or g/smd_v.")
}

# -------- 2. Keep valid rows --------
dat_eff <- dat_eff %>%
  dplyr::filter(
    !is.na(apa_citation),
    !is.na(effect_id),
    !is.na(yi), !is.na(vi),
    is.finite(yi), is.finite(vi),
    vi > 0
  ) %>%
  dplyr::arrange(apa_citation)

if (nrow(dat_eff) == 0) {
  warning("Forest plot skipped: dat_eff is empty after filtering.")
} else {
  
  # -------- 3. Multilevel meta-analysis on all effect sizes --------
  fit_mv <- metafor::rma.mv(
    yi = yi,
    V  = vi,
    random = ~ 1 | apa_citation/effect_id,
    data = dat_eff,
    method = "REML",
    slab = dat_eff$apa_citation
  )
  
  # -------- 4. One study label only once --------
  study_names <- dat_eff$apa_citation
  slab_labels <- ifelse(duplicated(study_names), "", study_names)
  
  # -------- 5. Put all effect sizes from same study on same row --------
  study_levels <- unique(study_names)
  study_row_map <- setNames(
    seq(from = length(study_levels) + 2, to = 3, by = -1),
    study_levels
  )
  study_rows <- unname(study_row_map[study_names])
  
  dat_eff <- dat_eff %>%
    dplyr::mutate(
      rows  = study_rows,
      sei   = sqrt(vi),
      ci.lb = yi - 1.96 * sei,
      ci.ub = yi + 1.96 * sei,
      slab  = slab_labels
    )
  
  pred_mv <- predict(fit_mv)
  
  # -------- 6. Axis/layout settings --------
  x_axis_min <- floor(min(dat_eff$ci.lb, 0) * 10) / 10
  x_axis_max <- ceiling(max(dat_eff$ci.ub, 0) * 10) / 10
  x_rng <- x_axis_max - x_axis_min
  if (x_rng <= 0) x_rng <- 1
  
  x_plot_left  <- x_axis_min - 1.25 * x_rng
  x_plot_right <- x_axis_max + 0.25 * x_rng
  x_study      <- x_axis_min - 0.98 * x_rng
  
  top_row  <- max(dat_eff$rows) + 2
  row_poly <- min(dat_eff$rows) - 2
  
  # Alternating shading by study
  shade_map <- setNames(
    rep(c(FALSE, TRUE), length.out = length(study_levels)),
    study_levels
  )
  shade_vec <- as.logical(shade_map[study_names])
  
  # -------- 7. Draw plot --------
  tryCatch({
    
    par(mar = c(5.5, 5.5, 2.2, 4), xpd = NA)
    
    metafor::forest(
      x = dat_eff$yi,
      vi = dat_eff$vi,
      slab = rep("", nrow(dat_eff)),
      rows = dat_eff$rows,
      refline = 0,
      xlim = c(x_plot_left, x_plot_right),
      alim = c(x_axis_min, x_axis_max),
      textpos = c(x_study, x_axis_max),
      xlab = "",
      pch = 18,
      cex = 0.9,
      annotate = FALSE,
      showweights = FALSE,
      header = " ",
      xaxt = "n",
      shade = shade_vec,
      efac = c(0, 0.5)
    )
    
    axis(1, at = pretty(c(x_axis_min, x_axis_max)), line = 1)
    mtext("Standardized Mean Difference", side = 1, line = 3.5)
    abline(v = 0, lty = 3, col = "gray70")
    
    # Effect-size CI lines and points
    segments(
      dat_eff$ci.lb, dat_eff$rows,
      dat_eff$ci.ub, dat_eff$rows,
      lwd = 1.0
    )
    points(dat_eff$yi, dat_eff$rows, pch = 18, cex = 0.85)
    
    # Study labels
    text(
      x = x_study, y = dat_eff$rows,
      labels = dat_eff$slab, pos = 4, cex = 0.9
    )
    text(
      x = x_study, y = top_row,
      pos = 4, font = 2, labels = "Author(s) and Year"
    )
    
    # Pooled estimate
    metafor::addpoly(
      x = pred_mv$pred,
      ci.lb = pred_mv$ci.lb,
      ci.ub = pred_mv$ci.ub,
      row = row_poly,
      mlab = "",
      cex = 1.0
    )
    text(
      x = x_study, y = row_poly,
      pos = 4, font = 2, labels = "Pooled Estimate"
    )
    
  }, error = function(e) {
    message("Forest plot failed: ", e$message)
  })
}