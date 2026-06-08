
# ===============================================================

# -----------------------------
# 0) Packages
# -----------------------------
library(readxl)
library(dplyr)
library(tidyr)
library(stringr)
library(metafor)
library(clubSandwich)
library(ggplot2)

# -----------------------------
# 1) Read data
# -----------------------------
dat <- read_excel(
  "C:/Users/Hana/Desktop/AI_primary.xlsx",
  na = c("NA", "na", "NR", "nr", "", " ")
)

# -----------------------------
# 2) Ensure required columns exist
# -----------------------------
required_cols <- c(
  "title", "apa_citation", "study_id", "effect_id",
  "int_n", "con_n", "N",
  "int_mean_t1", "int_sd_t1", "int_mean_t2", "int_sd_t2",
  "con_mean_t1", "con_sd_t1", "con_mean_t2", "con_sd_t2",
  "effect_type", "effect_size", "p_val", "smd",
  "outcome_domain", "outcome_subdomain",
  "female_per", "Technology Category", "Technology_Category",
  "Grade Level", "Grade_Level",
  "Learning Subject", "Learning_Subject",
  "design"
)

for (cc in required_cols) {
  if (!cc %in% names(dat)) dat[[cc]] <- NA
}

# -----------------------------
# 3) Clean data and standardize fields
# -----------------------------
r_assumed <- 0.70

clean_dat <- dat %>%
  mutate(
    row_id = row_number(),
    
    apa_citation = ifelse(
      is.na(apa_citation) | apa_citation == "",
      as.character(title),
      as.character(apa_citation)
    ),
    study_id = ifelse(
      is.na(study_id) | study_id == "",
      as.character(apa_citation),
      as.character(study_id)
    ),
    effect_id = ifelse(
      is.na(effect_id) | effect_id == "",
      paste0("e", row_id),
      as.character(effect_id)
    ),
    
    outcome_domain = str_trim(as.character(outcome_domain)),
    outcome_domain = case_when(
      outcome_domain == "Needs" ~ "Needs",
      outcome_domain == "Motivation" ~ "Motivation",
      TRUE ~ outcome_domain
    ),
    
    outcome_subdomain = str_trim(as.character(outcome_subdomain)),
    outcome_subdomain = case_when(
      outcome_subdomain == "General Motivation" ~ "General Motivation",
      outcome_subdomain == "Intrinsic Motivation" ~ "Intrinsic Motivation",
      outcome_subdomain == "Identified Regulation" ~ "Identified Regulation",
      outcome_subdomain == "External Regulation" ~ "External Regulation",
      outcome_subdomain == "Amotivation" ~ "Amotivation",
      outcome_subdomain == "Competence" ~ "Competence",
      outcome_subdomain == "Autonomy" ~ "Autonomy",
      outcome_subdomain == "Relatedness" ~ "Relatedness",
      TRUE ~ outcome_subdomain
    ),
    
    Learning_Subject = coalesce(
      as.character(`Learning Subject`),
      as.character(Learning_Subject)
    ),
    Learning_Subject = str_trim(Learning_Subject),
    Learning_Subject = case_when(
      Learning_Subject == "STEM & Computing" ~ "STEM & Computing",
      Learning_Subject == "Language & Literacy" ~ "Language & Literacy",
      Learning_Subject == "Arts & Humanities" ~ "Arts & Humanities",
      TRUE ~ Learning_Subject
    ),
    
    effect_type_raw = str_trim(as.character(effect_type)),
    effect_type_std = case_when(
      effect_type_raw %in% c("η²", "η2", "η^2", "eta2", "eta squared",
                             "partial eta squared", "partial η²") ~ "eta2",
      str_to_lower(effect_type_raw) == "t" ~ "t",
      str_to_lower(effect_type_raw) == "f" ~ "f",
      str_to_lower(effect_type_raw) == "r" ~ "r",
      str_to_lower(effect_type_raw) == "d" ~ "d",
      is.na(effect_type_raw) | effect_type_raw == "" ~ NA_character_,
      TRUE ~ str_to_lower(effect_type_raw)
    ),
    
    int_n = suppressWarnings(as.numeric(int_n)),
    con_n = suppressWarnings(as.numeric(con_n)),
    N     = suppressWarnings(as.numeric(N)),
    
    int_mean_t1 = suppressWarnings(as.numeric(int_mean_t1)),
    int_sd_t1   = suppressWarnings(as.numeric(int_sd_t1)),
    int_mean_t2 = suppressWarnings(as.numeric(int_mean_t2)),
    int_sd_t2   = suppressWarnings(as.numeric(int_sd_t2)),
    
    con_mean_t1 = suppressWarnings(as.numeric(con_mean_t1)),
    con_sd_t1   = suppressWarnings(as.numeric(con_sd_t1)),
    con_mean_t2 = suppressWarnings(as.numeric(con_mean_t2)),
    con_sd_t2   = suppressWarnings(as.numeric(con_sd_t2)),
    
    effect_size = suppressWarnings(as.numeric(effect_size)),
    smd         = suppressWarnings(as.numeric(smd)),
    female_per  = suppressWarnings(as.numeric(female_per)),
    
    design = str_trim(as.character(design))
  )

# -----------------------------
# 4) Identify/control-check design
# design is already classified as:
# one_group / two_group / RCT
# has_control is only kept as a check variable
# -----------------------------
clean_dat <- clean_dat %>%
  mutate(
    has_control = !is.na(con_n) |
      !is.na(con_mean_t1) | !is.na(con_mean_t2) |
      !is.na(con_sd_t1)   | !is.na(con_sd_t2)
  )

cat("\n================ DESIGN CHECK ================\n")
print(table(clean_dat$design, useNA = "ifany"))

# -----------------------------
# 5) Fill sample sizes where possible
# -----------------------------
clean_dat <- clean_dat %>%
  mutate(
    N = ifelse(
      is.na(N) & design %in% c("two_group", "RCT") &
        !is.na(int_n) & !is.na(con_n),
      int_n + con_n,
      N
    ),
    N = ifelse(
      is.na(N) & design == "one_group" & !is.na(int_n),
      int_n,
      N
    )
  )

# -----------------------------
# 5.5) Impute missing SDs for Dong et al. (2024)
# Priority:
# 1) same outcome_domain + outcome_subdomain
# 2) same outcome_domain
# Only for one-group rows in Needs / Motivation
# -----------------------------
dong_need_impute <- clean_dat %>%
  filter(
    apa_citation == "Dong et al. (2024)",
    design == "one_group",
    outcome_domain %in% c("Needs", "Motivation"),
    (is.na(int_sd_t1) | !is.finite(int_sd_t1) | int_sd_t1 <= 0)
  ) %>%
  select(
    row_id, apa_citation, study_id, effect_id,
    outcome_domain, outcome_subdomain,
    int_n, int_mean_t1, int_mean_t2,
    int_sd_t1, int_sd_t2
  )

cat("\n================ DONG SD IMPUTATION: ROWS NEEDING IMPUTATION ================\n")
print(dong_need_impute, n = Inf)

# donor pool 1: same domain + same subdomain
sd_pool_subdomain <- clean_dat %>%
  filter(
    apa_citation != "Dong et al. (2024)",
    design == "one_group",
    !is.na(int_sd_t1),
    is.finite(int_sd_t1),
    int_sd_t1 > 0,
    outcome_domain %in% c("Needs", "Motivation")
  ) %>%
  group_by(outcome_domain, outcome_subdomain) %>%
  summarise(
    donor_sd_sub = median(int_sd_t1, na.rm = TRUE),
    donor_k_sub = n(),
    .groups = "drop"
  )

# donor pool 2: same domain only
sd_pool_domain <- clean_dat %>%
  filter(
    apa_citation != "Dong et al. (2024)",
    design == "one_group",
    !is.na(int_sd_t1),
    is.finite(int_sd_t1),
    int_sd_t1 > 0,
    outcome_domain %in% c("Needs", "Motivation")
  ) %>%
  group_by(outcome_domain) %>%
  summarise(
    donor_sd_dom = median(int_sd_t1, na.rm = TRUE),
    donor_k_dom = n(),
    .groups = "drop"
  )

dong_imputed <- dong_need_impute %>%
  left_join(sd_pool_subdomain, by = c("outcome_domain", "outcome_subdomain")) %>%
  left_join(sd_pool_domain, by = "outcome_domain") %>%
  mutate(
    impute_source = case_when(
      !is.na(donor_sd_sub) ~ "subdomain",
      is.na(donor_sd_sub) & !is.na(donor_sd_dom) ~ "domain",
      TRUE ~ "none"
    ),
    imputed_sd_t1 = case_when(
      !is.na(donor_sd_sub) ~ donor_sd_sub,
      is.na(donor_sd_sub) & !is.na(donor_sd_dom) ~ donor_sd_dom,
      TRUE ~ NA_real_
    ),
    imputed_sd_t2 = imputed_sd_t1
  )

cat("\n================ DONG SD IMPUTATION: RESULTS ================\n")
print(
  dong_imputed %>%
    select(
      row_id, effect_id, outcome_domain, outcome_subdomain,
      donor_sd_sub, donor_k_sub, donor_sd_dom, donor_k_dom,
      impute_source, imputed_sd_t1
    ),
  n = Inf
)

# write imputed SDs back into clean_dat
if (nrow(dong_imputed) > 0) {
  clean_dat <- clean_dat %>%
    left_join(
      dong_imputed %>%
        select(row_id, impute_source, imputed_sd_t1, imputed_sd_t2),
      by = "row_id"
    ) %>%
    mutate(
      int_sd_t1 = ifelse(
        apa_citation == "Dong et al. (2024)" &
          (is.na(int_sd_t1) | !is.finite(int_sd_t1) | int_sd_t1 <= 0) &
          !is.na(imputed_sd_t1),
        imputed_sd_t1,
        int_sd_t1
      ),
      int_sd_t2 = ifelse(
        apa_citation == "Dong et al. (2024)" &
          (is.na(int_sd_t2) | !is.finite(int_sd_t2) | int_sd_t2 <= 0) &
          !is.na(imputed_sd_t2),
        imputed_sd_t2,
        int_sd_t2
      )
    )
}

cat("\n================ DONG SD IMPUTATION: UPDATED ROWS IN CLEAN_DAT ================\n")
print(
  clean_dat %>%
    filter(apa_citation == "Dong et al. (2024)") %>%
    select(
      row_id, effect_id, outcome_domain, outcome_subdomain,
      int_mean_t1, int_mean_t2, int_sd_t1, int_sd_t2
    ),
  n = Inf
)

# -----------------------------
# 6) Compute fallback effect sizes from means and SDs
# -----------------------------

# 6A) One-group fallback: SMCR
clean_dat$SMCR <- NA_real_
clean_dat$SMCR_var <- NA_real_

one_idx <- which(
  clean_dat$design == "one_group" &
    !is.na(clean_dat$int_mean_t1) &
    !is.na(clean_dat$int_mean_t2) &
    !is.na(clean_dat$int_sd_t1) &
    !is.na(clean_dat$int_n) &
    clean_dat$int_n > 0
)

if (length(one_idx) > 0) {
  esc_one <- metafor::escalc(
    measure = "SMCR",
    m1i  = clean_dat$int_mean_t2[one_idx],
    m2i  = clean_dat$int_mean_t1[one_idx],
    sd1i = clean_dat$int_sd_t1[one_idx],
    ni   = clean_dat$int_n[one_idx],
    ri   = r_assumed
  )
  clean_dat$SMCR[one_idx] <- esc_one$yi
  clean_dat$SMCR_var[one_idx] <- esc_one$vi
}

# 6B) Two-group fallback: change-score d
clean_dat <- clean_dat %>%
  mutate(
    change_treat = ifelse(
      design %in% c("two_group", "RCT"),
      int_mean_t2 - int_mean_t1,
      NA_real_
    ),
    change_ctrl = ifelse(
      design %in% c("two_group", "RCT"),
      con_mean_t2 - con_mean_t1,
      NA_real_
    ),
    baseline_sd_pooled = ifelse(
      design %in% c("two_group", "RCT") &
        !is.na(int_sd_t1) & !is.na(con_sd_t1) &
        !is.na(int_n) & !is.na(con_n) &
        (int_n + con_n - 2) > 0,
      sqrt(((int_n - 1) * int_sd_t1^2 + (con_n - 1) * con_sd_t1^2) / (int_n + con_n - 2)),
      NA_real_
    ),
    d_change = ifelse(
      design %in% c("two_group", "RCT") &
        !is.na(change_treat) & !is.na(change_ctrl) &
        !is.na(baseline_sd_pooled) & baseline_sd_pooled > 0,
      (change_treat - change_ctrl) / baseline_sd_pooled,
      NA_real_
    )
  )

# 6B.5) Special handling for Qian et al. (2023)
# Qian reports CHANGE scores (post - pre), not raw posttest means.
# The change values were entered in:
# int_mean_t2, int_sd_t2, con_mean_t2, con_sd_t2
# Therefore, compute between-group SMD directly from change scores.
clean_dat$SMD_change_special <- NA_real_
clean_dat$SMD_change_special_var <- NA_real_

qian_idx <- which(
  clean_dat$apa_citation == "Qian et al. (2023)" &
    clean_dat$design %in% c("two_group", "RCT") &
    !is.na(clean_dat$int_mean_t2) & !is.na(clean_dat$int_sd_t2) &
    !is.na(clean_dat$con_mean_t2) & !is.na(clean_dat$con_sd_t2) &
    !is.na(clean_dat$int_n) & !is.na(clean_dat$con_n) &
    clean_dat$int_n > 1 & clean_dat$con_n > 1
)

if (length(qian_idx) > 0) {
  esc_qian <- metafor::escalc(
    measure = "SMD",
    m1i  = clean_dat$int_mean_t2[qian_idx],   # change mean
    sd1i = clean_dat$int_sd_t2[qian_idx],     # change SD
    n1i  = clean_dat$int_n[qian_idx],
    m2i  = clean_dat$con_mean_t2[qian_idx],   # change mean
    sd2i = clean_dat$con_sd_t2[qian_idx],     # change SD
    n2i  = clean_dat$con_n[qian_idx]
  )
  
  clean_dat$SMD_change_special[qian_idx] <- esc_qian$yi
  clean_dat$SMD_change_special_var[qian_idx] <- esc_qian$vi
}

cat("\n================ QIAN CHANGE-SCORE CHECK ================\n")
print(
  clean_dat %>%
    filter(apa_citation == "Qian et al. (2023)") %>%
    select(
      apa_citation, effect_id, design,
      int_n, con_n,
      int_mean_t2, int_sd_t2, con_mean_t2, con_sd_t2,
      SMD_change_special, SMD_change_special_var
    ),
  n = Inf
)

# 6C) Two-group posttest-only fallback: Hedges' g / SMD
clean_dat$SMD_post <- NA_real_
clean_dat$SMD_post_var <- NA_real_

post_idx <- which(
  clean_dat$design %in% c("two_group", "RCT") &
    is.na(clean_dat$smd) &
    !is.na(clean_dat$int_mean_t2) & !is.na(clean_dat$int_sd_t2) &
    !is.na(clean_dat$con_mean_t2) & !is.na(clean_dat$con_sd_t2) &
    !is.na(clean_dat$int_n) & !is.na(clean_dat$con_n) &
    clean_dat$int_n > 1 & clean_dat$con_n > 1
)

if (length(post_idx) > 0) {
  esc_post <- metafor::escalc(
    measure = "SMD",
    m1i  = clean_dat$int_mean_t2[post_idx],
    sd1i = clean_dat$int_sd_t2[post_idx],
    n1i  = clean_dat$int_n[post_idx],
    m2i  = clean_dat$con_mean_t2[post_idx],
    sd2i = clean_dat$con_sd_t2[post_idx],
    n2i  = clean_dat$con_n[post_idx]
  )
  clean_dat$SMD_post[post_idx] <- esc_post$yi
  clean_dat$SMD_post_var[post_idx] <- esc_post$vi
}

# -----------------------------
# 7) Convert reported statistics to Cohen's d
# Priority:
# direct d/smd -> t -> F -> eta2 -> r
# Fallbacks handled later
# -----------------------------
clean_dat <- clean_dat %>%
  mutate(
    d_direct = case_when(
      !is.na(smd) ~ smd,
      effect_type_std == "d" & !is.na(effect_size) ~ effect_size,
      TRUE ~ NA_real_
    ),
    
    d_from_t = case_when(
      # two-group / RCT
      effect_type_std == "t" & !is.na(effect_size) &
        design %in% c("two_group", "RCT") &
        !is.na(int_n) & !is.na(con_n) & int_n > 0 & con_n > 0 ~
        effect_size * sqrt((int_n + con_n) / (int_n * con_n)),
      
      # one-group pre-post
      effect_type_std == "t" & !is.na(effect_size) &
        design == "one_group" &
        !is.na(int_n) & int_n > 0 ~
        effect_size * sqrt(2 * (1 - r_assumed) / int_n),
      
      TRUE ~ NA_real_
    ),
    
    d_from_f = case_when(
      effect_type_std == "f" & !is.na(effect_size) & effect_size >= 0 &
        apa_citation != "Qian et al. (2023)" &
        design %in% c("two_group", "RCT") &
        !is.na(int_n) & !is.na(con_n) & int_n > 0 & con_n > 0 ~
        sqrt(effect_size) * sqrt((int_n + con_n) / (int_n * con_n)),
      
      effect_type_std == "f" & !is.na(effect_size) & effect_size >= 0 &
        apa_citation != "Qian et al. (2023)" &
        design == "one_group" &
        !is.na(int_n) & int_n > 0 ~
        sqrt(effect_size) * sqrt(2 * (1 - r_assumed) / int_n),
      
      TRUE ~ NA_real_
    ),
    
    d_from_eta2 = case_when(
      effect_type_std == "eta2" & !is.na(effect_size) & effect_size < 1 &
        !is.na(N) & N > 1 ~
        sqrt(((N - 1) / N) * effect_size / (1 - effect_size)),
      TRUE ~ NA_real_
    ),
    
    d_from_r = case_when(
      effect_type_std == "r" & !is.na(effect_size) & abs(effect_size) < 1 ~
        2 * effect_size / sqrt(1 - effect_size^2),
      TRUE ~ NA_real_
    )
  )

# -----------------------------
# 8) Final effect size assembly
# Recommended priority:
# two_group / RCT: direct -> t -> F -> eta2 -> r -> SMD_post -> d_change
# one_group       : direct -> t -> F -> eta2 -> r -> SMCR
# -----------------------------
clean_dat <- clean_dat %>%
  mutate(
    effect_source = case_when(
      # two-group / RCT
      design %in% c("two_group", "RCT") & !is.na(d_direct)    ~ "direct_d",
      design %in% c("two_group", "RCT") &  is.na(d_direct) & !is.na(d_from_t)    ~ "t",
      design %in% c("two_group", "RCT") &  is.na(d_direct) &  is.na(d_from_t) & !is.na(d_from_f)    ~ "f",
      design %in% c("two_group", "RCT") &  is.na(d_direct) &  is.na(d_from_t) &  is.na(d_from_f) & !is.na(d_from_eta2) ~ "eta2",
      design %in% c("two_group", "RCT") &  is.na(d_direct) &  is.na(d_from_t) &  is.na(d_from_f) &  is.na(d_from_eta2) & !is.na(d_from_r) ~ "r",
      design %in% c("two_group", "RCT") &  is.na(d_direct) &  is.na(d_from_t) &  is.na(d_from_f) &  is.na(d_from_eta2) &  is.na(d_from_r) & !is.na(SMD_change_special) ~ "smd_change_special",
      design %in% c("two_group", "RCT") &  is.na(d_direct) &  is.na(d_from_t) &  is.na(d_from_f) &  is.na(d_from_eta2) &  is.na(d_from_r) &  is.na(SMD_change_special) & !is.na(SMD_post) ~ "smd_post",
      design %in% c("two_group", "RCT") &  is.na(d_direct) &  is.na(d_from_t) &  is.na(d_from_f) &  is.na(d_from_eta2) &  is.na(d_from_r) &  is.na(SMD_change_special) &  is.na(SMD_post) & !is.na(d_change) ~ "d_change",
      
      # one-group
      design == "one_group" & !is.na(d_direct)    ~ "direct_d",
      design == "one_group" &  is.na(d_direct) & !is.na(d_from_t)    ~ "t",
      design == "one_group" &  is.na(d_direct) &  is.na(d_from_t) & !is.na(d_from_f)    ~ "f",
      design == "one_group" &  is.na(d_direct) &  is.na(d_from_t) &  is.na(d_from_f) & !is.na(d_from_eta2) ~ "eta2",
      design == "one_group" &  is.na(d_direct) &  is.na(d_from_t) &  is.na(d_from_f) &  is.na(d_from_eta2) & !is.na(d_from_r) ~ "r",
      design == "one_group" &  is.na(d_direct) &  is.na(d_from_t) &  is.na(d_from_f) &  is.na(d_from_eta2) &  is.na(d_from_r) & !is.na(SMCR) ~ "smcr",
      
      TRUE ~ NA_character_
    ),
    
    d_priority = case_when(
      effect_source == "direct_d"           ~ d_direct,
      effect_source == "t"                  ~ d_from_t,
      effect_source == "f"                  ~ d_from_f,
      effect_source == "eta2"               ~ d_from_eta2,
      effect_source == "r"                  ~ d_from_r,
      effect_source == "smd_change_special" ~ SMD_change_special,
      effect_source == "smd_post"           ~ SMD_post,
      effect_source == "d_change"           ~ d_change,
      effect_source == "smcr"               ~ SMCR,
      TRUE ~ NA_real_
    )
  )

# -----------------------------
# 9) Convert to yi/vi
# - If source is SMD_post or SMCR, use metafor-computed yi/vi directly
# - Otherwise, convert d to Hedges' g and compute variance
# -----------------------------
clean_dat <- clean_dat %>%
  mutate(
    df_used = case_when(
      design %in% c("two_group", "RCT") & !is.na(int_n) & !is.na(con_n) ~ int_n + con_n - 2,
      design == "one_group" & !is.na(int_n) ~ int_n - 1,
      TRUE ~ NA_real_
    ),
    
    J = case_when(
      !is.na(df_used) & (4 * df_used - 1) > 0 ~ 1 - (3 / (4 * df_used - 1)),
      TRUE ~ NA_real_
    ),
    
    g_from_d = case_when(
      !is.na(d_priority) & !is.na(J) ~ d_priority * J,
      !is.na(d_priority) & is.na(J)  ~ d_priority,
      TRUE ~ NA_real_
    ),
    
    yi = case_when(
      effect_source == "smcr"               ~ SMCR,
      effect_source == "smd_change_special" ~ SMD_change_special,
      effect_source == "smd_post"           ~ SMD_post,
      !is.na(g_from_d)                      ~ g_from_d,
      TRUE ~ NA_real_
    ),
    
    yi = case_when(
      effect_source == "smcr"               ~ SMCR,
      effect_source == "smd_change_special" ~ SMD_change_special,
      effect_source == "smd_post"           ~ SMD_post,
      !is.na(g_from_d)                      ~ g_from_d,
      TRUE ~ NA_real_
    ),
    
    vi = case_when(
      effect_source == "smcr"               ~ SMCR_var,
      effect_source == "smd_change_special" ~ SMD_change_special_var,
      effect_source == "smd_post"           ~ SMD_post_var,
      
      design == "one_group" &
        !is.na(yi) & !is.na(int_n) & int_n > 0 ~
        (1 / int_n) + (yi^2 / (2 * int_n)) * (1 - r_assumed),
      
      design %in% c("two_group", "RCT") &
        !is.na(yi) & !is.na(int_n) & !is.na(con_n) &
        int_n > 0 & con_n > 0 ~
        (int_n + con_n) / (int_n * con_n) + (yi^2) / (2 * (int_n + con_n)),
      
      TRUE ~ NA_real_
    )
  )

cat("\n================ CHECK RCT ROWS AFTER yi/vi ================\n")
print(
  clean_dat %>%
    filter(design == "RCT") %>%
    select(
      apa_citation, effect_id, design, int_n, con_n,
      effect_source, d_priority, yi, vi
    ) %>%
    head(20),
  n = 20
)

# -----------------------------
# 10) Keep only usable rows -> meta_ready
# -----------------------------
meta_ready <- clean_dat %>%
  filter(
    outcome_domain %in% c("Needs", "Motivation"),
    !is.na(yi), !is.na(vi),
    is.finite(yi), is.finite(vi),
    vi > 0
  ) %>%
  mutate(
    study_id = as.factor(study_id),
    effect_id = as.factor(effect_id),
    apa_citation = as.character(apa_citation),
    
    Technology_Category = case_when(
      !is.na(`Technology Category`) & `Technology Category` != "" ~ as.character(`Technology Category`),
      !is.na(Technology_Category) & Technology_Category != "" ~ as.character(Technology_Category),
      TRUE ~ NA_character_
    ),
    
    Grade_Level = case_when(
      !is.na(`Grade Level`) & `Grade Level` != "" ~ as.character(`Grade Level`),
      !is.na(Grade_Level) & Grade_Level != "" ~ as.character(Grade_Level),
      TRUE ~ NA_character_
    ),
    
    Technology_Category = str_trim(Technology_Category),
    Grade_Level = str_trim(Grade_Level),
    
    Technology_Category = case_when(
      Technology_Category %in% c("Immersive AI") ~ "Immersive AI",
      Technology_Category %in% c("Intelligent Learning Systems") ~ "Intelligent Learning Systems",
      Technology_Category %in% c("Generative AI") ~ "Generative AI",
      TRUE ~ Technology_Category
    ),
    
    Grade_Level = case_when(
      Grade_Level %in% c("Mixed grades") ~ "Mixed grades",
      Grade_Level %in% c("Upper grades") ~ "Upper grades",
      Grade_Level %in% c("Lower grades") ~ "Lower grades",
      TRUE ~ Grade_Level
    )
  )

cat("\n================ META-READY DATA (BEFORE HSU MERGE) ================\n")
print(meta_ready)

# -----------------------------
# 11) Merge the two gender-specific rows of Hsu et al. (2022)
# -----------------------------
target_study <- "Hsu et al. (2022)"

hsu_rows <- meta_ready %>%
  filter(apa_citation == target_study)

if (nrow(hsu_rows) == 2) {
  
  hsu_combined <- hsu_rows %>%
    group_by(outcome_domain, outcome_subdomain) %>%
    summarise(
      yi = weighted.mean(yi, w = 1 / vi),
      vi = 1 / sum(1 / vi),
      
      int_n = sum(int_n, na.rm = TRUE),
      con_n = sum(con_n, na.rm = TRUE),
      N = sum(N, na.rm = TRUE),
      
      study_id = first(study_id),
      apa_citation = first(apa_citation),
      effect_id = "gender_combined",
      title = first(title),
      
      female_per = NA_real_,
      
      Technology_Category = first(Technology_Category),
      Grade_Level = first(Grade_Level),
      Learning_Subject = first(Learning_Subject),
      design = first(design),
      
      Authors = first(Authors),
      Technology = first(Technology),
      `Technology Category` = first(`Technology Category`),
      `Learning Subject` = first(`Learning Subject`),
      `Grade Level` = first(`Grade Level`),
      `Reaearch Method` = first(`Reaearch Method`),
      
      country = first(country),
      year = first(year),
      age = first(age),
      
      outcome_domain = first(outcome_domain),
      outcome_subdomain = first(outcome_subdomain),
      
      .groups = "drop"
    )
  
  meta_ready <- meta_ready %>%
    filter(apa_citation != target_study) %>%
    bind_rows(hsu_combined) %>%
    arrange(apa_citation, outcome_domain, outcome_subdomain, effect_id)

  cat("\n================ HSU MERGE DONE ================\n")
  print(hsu_combined)
  
} else if (nrow(hsu_rows) > 2) {
  
  cat("\n[Warning] More than 2 rows found for Hsu et al. (2022). No automatic merge applied.\n")
  print(hsu_rows)
  
} else if (nrow(hsu_rows) == 1) {
  
  cat("\n[Info] Only 1 row found for Hsu et al. (2022). No merge needed.\n")
  
} else {
  
  cat("\n[Info] No rows found for Hsu et al. (2022) in meta_ready.\n")
}

cat("\n================ META-READY DATA (AFTER HSU MERGE) ================\n")
print(meta_ready)

# -----------------------------
# 12) Overall analysis
# overall_dat = Needs + Motivation combined
# -----------------------------
overall_dat <- meta_ready %>%
  filter(outcome_domain %in% c("Needs", "Motivation"))

cat("\n====================================================\n")
cat("OVERALL ANALYSIS: Needs + Motivation combined\n")
cat("====================================================\n")
cat("Number of effects:", nrow(overall_dat), "\n")
cat("Number of unique studies:", dplyr::n_distinct(overall_dat$study_id), "\n")

fit_main_overall <- metafor::rma.mv(
  yi = yi,
  V = vi,
  random = ~ 1 | study_id/effect_id,
  data = overall_dat,
  method = "REML",
  slab = apa_citation
)

cat("\n--- Initial multilevel model ---\n")
print(fit_main_overall, digits = 3)

cat("\n--- Robust test (CR2; initial model) ---\n")
robust_main_overall <- tryCatch({
  clubSandwich::coef_test(fit_main_overall, vcov = "CR2", test = "Satterthwaite")
}, error = function(e) NULL)
if (!is.null(robust_main_overall)) print(robust_main_overall)

cat("\n--- Variance components (initial model) ---\n")
print(fit_main_overall$sigma2)

# -----------------------------
# 13) Outlier detection by Cook's distance
# -----------------------------
inf <- cooks.distance(fit_main_overall, progbar = FALSE)

# You can switch to 4 * mean(inf, na.rm = TRUE) if preferred
cutoff <- 4 / length(inf)

outlier_idx <- which(inf > cutoff)

overall_noout <- overall_dat

cat("\n================ OUTLIER CHECK ================\n")
cat("Cook's distance cutoff:", cutoff, "\n")
cat("Outliers removed:", length(outlier_idx), "\n")

if (length(outlier_idx) > 0) {
  cat("Removed rows:\n")
  print(overall_dat[outlier_idx, c("apa_citation", "effect_id", "outcome_domain", "outcome_subdomain", "yi", "vi")])
}

# -----------------------------
# 14) Final model after removing outliers
# -----------------------------
fit_noout_overall <- metafor::rma.mv(
  yi = yi,
  V = vi,
  random = ~ 1 | study_id/effect_id,
  data = overall_noout,
  method = "REML",
  slab = apa_citation
)

cat("\n--- Final model (NO-OUTLIER ONLY) ---\n")
print(fit_noout_overall, digits = 3)

cat("\n--- Robust test (CR2; NO-OUTLIER ONLY) ---\n")
robust_noout_overall <- tryCatch({
  clubSandwich::coef_test(fit_noout_overall, vcov = "CR2", test = "Satterthwaite")
}, error = function(e) NULL)
if (!is.null(robust_noout_overall)) print(robust_noout_overall)

cat("\n--- Variance components (NO-OUTLIER ONLY) ---\n")
print(fit_noout_overall$sigma2)

overall_summary <- data.frame(
  Analysis = "Overall (Needs + Motivation, NO-OUTLIER ONLY)",
  k_effects = nrow(overall_noout),
  n_studies = dplyr::n_distinct(overall_noout$study_id),
  pooled_g  = as.numeric(coef(fit_noout_overall)),
  ci_lb     = fit_noout_overall$ci.lb,
  ci_ub     = fit_noout_overall$ci.ub,
  p_value   = fit_noout_overall$pval
)

cat("\n================ FINAL SUMMARY (NO-OUTLIER ONLY) ================\n")
print(overall_summary)

# -----------------------------
# 15) Moderator analyses based on NO-OUTLIER data only
# Moderators:
# - Technology Category
# - female_per
# - Grade Level
# - outcome_domain
# -----------------------------
mod_dat <- overall_noout %>%
  mutate(
    Technology_Category = str_trim(as.character(Technology_Category)),
    Grade_Level = str_trim(as.character(Grade_Level)),
    outcome_domain = str_trim(as.character(outcome_domain)),
    Learning_Subject = str_trim(as.character(Learning_Subject)),
    
    Technology_Category = ifelse(Technology_Category == "", NA, Technology_Category),
    Grade_Level = ifelse(Grade_Level == "", NA, Grade_Level),
    outcome_domain = ifelse(outcome_domain == "", NA, outcome_domain),
    Learning_Subject = ifelse(Learning_Subject == "", NA, Learning_Subject)
  )

cat("\n================ MODERATOR DATA CHECK ================\n")
cat("Rows in moderator dataset:", nrow(mod_dat), "\n")

cat("\nTechnology Category distribution:\n")
print(table(mod_dat$Technology_Category, useNA = "ifany"))

cat("\nGrade Level distribution:\n")
print(table(mod_dat$Grade_Level, useNA = "ifany"))

cat("\noutcome_domain distribution:\n")
print(table(mod_dat$outcome_domain, useNA = "ifany"))

cat("\nfemale_per summary:\n")
print(summary(mod_dat$female_per))

cat("\ndesign distribution:\n")
print(table(mod_dat$design, useNA = "ifany"))

cat("\nLearning Subject distribution:\n")
print(table(mod_dat$Learning_Subject, useNA = "ifany"))

# ===============================================================
# Helper function for moderator models
# Output omnibus moderator test in F format
# ===============================================================

run_moderator_model <- function(data, moderator, mod_label, is_continuous = FALSE) {
  
  cat("\n====================================================\n")
  cat("Moderator:", mod_label, "\n")
  cat("====================================================\n")
  
  dat_sub <- data %>%
    dplyr::filter(!is.na(.data[[moderator]]))
  
  if (nrow(dat_sub) == 0) {
    cat("No usable rows for this moderator.\n")
    return(NULL)
  }
  
  if (!is_continuous) {
    dat_sub[[moderator]] <- as.factor(dat_sub[[moderator]])
    
    n_levels <- nlevels(dat_sub[[moderator]])
    if (n_levels < 2) {
      cat("Not enough levels for moderator analysis.\n")
      return(NULL)
    }
    
    cat("Included rows:", nrow(dat_sub), "\n")
    cat("Unique studies:", dplyr::n_distinct(dat_sub$study_id), "\n")
    cat("Levels:\n")
    print(table(dat_sub[[moderator]], useNA = "ifany"))
    
    formula_mod <- as.formula(paste0("~ factor(", moderator, ")"))
    
  } else {
    dat_sub[[moderator]] <- suppressWarnings(as.numeric(dat_sub[[moderator]]))
    dat_sub <- dat_sub %>% dplyr::filter(!is.na(.data[[moderator]]))
    
    if (nrow(dat_sub) == 0) {
      cat("No usable numeric rows for this moderator.\n")
      return(NULL)
    }
    
    cat("Included rows:", nrow(dat_sub), "\n")
    cat("Unique studies:", dplyr::n_distinct(dat_sub$study_id), "\n")
    cat("Summary of", mod_label, ":\n")
    print(summary(dat_sub[[moderator]]))
    
    formula_mod <- as.formula(paste0("~ ", moderator))
  }
  
  fit_mod <- tryCatch({
    metafor::rma.mv(
      yi = yi,
      V = vi,
      mods = formula_mod,
      random = ~ 1 | study_id/effect_id,
      data = dat_sub,
      method = "REML"
    )
  }, error = function(e) {
    cat("Model failed:\n")
    message(e$message)
    return(NULL)
  })
  
  if (is.null(fit_mod)) return(NULL)
  
  cat("\n--- Model output ---\n")
  print(fit_mod, digits = 3)
  
  cat("\n--- Robust coefficient test (CR2) ---\n")
  robust_mod <- tryCatch({
    clubSandwich::coef_test(fit_mod, vcov = "CR2", test = "Satterthwaite")
  }, error = function(e) NULL)
  if (!is.null(robust_mod)) print(robust_mod)
  
  cat("\n--- Omnibus moderator test in F format (CR2) ---\n")
  
  omnibus_F <- tryCatch({
    
    coef_names <- names(coef(fit_mod))
    
    # remove intercept, keep moderator coefficients only
    tested_coefs <- coef_names[coef_names != "intrcpt"]
    
    if (length(tested_coefs) == 0) return(NULL)
    
    W <- clubSandwich::Wald_test(
      fit_mod,
      constraints = tested_coefs,
      vcov = "CR2",
      test = "HTZ"
    )
    
    # print raw Wald_test output
    print(W)
    
    # extract F-statistic and dfs safely
    F_value <- if ("Fstat" %in% names(W)) W$Fstat else if ("F" %in% names(W)) W$F else NA
    df_num  <- if ("df_num" %in% names(W)) W$df_num else if ("df" %in% names(W)) W$df else length(tested_coefs)
    df_denom <- if ("df_denom" %in% names(W)) W$df_denom else if ("den_df" %in% names(W)) W$den_df else NA
    p_value <- if ("p_val" %in% names(W)) W$p_val else if ("p" %in% names(W)) W$p else NA
    
    cat(
      "\nF(",
      round(df_num, 2), ", ",
      round(df_denom, 2), ") = ",
      round(F_value, 3),
      ", p = ",
      format.pval(p_value, digits = 3),
      "\n",
      sep = ""
    )
    
    list(
      raw = W,
      F_value = F_value,
      df_num = df_num,
      df_denom = df_denom,
      p_value = p_value
    )
    
  }, error = function(e) {
    cat("Robust omnibus F test failed.\n")
    message(e$message)
    return(NULL)
  })
  
  return(list(
    data = dat_sub,
    fit = fit_mod,
    robust = robust_mod,
    omnibus_F = omnibus_F
  ))
}

# -----------------------------
# 15A) Technology Category (categorical)
# -----------------------------
tech_mod_results <- run_moderator_model(
  data = mod_dat,
  moderator = "Technology_Category",
  mod_label = "Technology Category",
  is_continuous = FALSE
)

# -----------------------------
# 15B) female_per (continuous)
# -----------------------------
female_mod_results <- run_moderator_model(
  data = mod_dat,
  moderator = "female_per",
  mod_label = "female_per",
  is_continuous = TRUE
)

# -----------------------------
# 15C) Grade Level (categorical)
# -----------------------------
grade_mod_results <- run_moderator_model(
  data = mod_dat,
  moderator = "Grade_Level",
  mod_label = "Grade Level",
  is_continuous = FALSE
)

# -----------------------------
# 15D) outcome_domain (categorical)
# -----------------------------
domain_mod_results <- run_moderator_model(
  data = mod_dat,
  moderator = "outcome_domain",
  mod_label = "outcome_domain",
  is_continuous = FALSE
)

# -----------------------------
# 15E) Learning_Subject (categorical)
# -----------------------------
subject_mod_results <- run_moderator_model(
  data = mod_dat,
  moderator = "Learning_Subject",
  mod_label = "Learning Subject",
  is_continuous = FALSE
)

# -----------------------------
# 15F) design (categorical)
# -----------------------------
design_mod_results <- run_moderator_model(
  data = mod_dat,
  moderator = "design",
  mod_label = "Design",
  is_continuous = FALSE
)
# -----------------------------
# Store all final results
# -----------------------------
final_results <- list(
  meta_ready = meta_ready,
  overall_dat = overall_dat,
  outlier_idx = outlier_idx,
  overall_noout = overall_noout,
  fit_main_overall = fit_main_overall,
  fit_noout_overall = fit_noout_overall,
  robust_main_overall = robust_main_overall,
  robust_noout_overall = robust_noout_overall,
  overall_summary = overall_summary,
  tech_mod_results = tech_mod_results,
  female_mod_results = female_mod_results,
  grade_mod_results = grade_mod_results,
  domain_mod_results = domain_mod_results,
  subject_mod_results = subject_mod_results,
  design_mod_results = design_mod_results
)

cat("\n================ ANALYSIS COMPLETE ================\n")
cat("Final objects available:\n")
print(names(final_results))

# ===============================================================
# Combined moderator figure
# (Technology Category + Grade Level + Outcome Domain + Learning Subject)
# Excludes female_per (continuous moderator)
# Based on NO-OUTLIER data only
# ===============================================================

if ("package:plyr" %in% search()) detach("package:plyr", unload = TRUE)

# -----------------------------
# 1) Prepare plotting data
# -----------------------------
combined_mod <- overall_noout %>%
  mutate(
    apa_citation         = as.character(apa_citation),
    study_id             = as.character(study_id),
    effect_id            = as.character(effect_id),
    Technology_Category  = as.character(Technology_Category),
    Grade_Level          = as.character(Grade_Level),
    outcome_domain       = as.character(outcome_domain),
    design               = as.character(design),
        Learning_Subject     = as.character(Learning_Subject)
  ) %>%
  mutate(
    Technology_Category = str_trim(Technology_Category),
    Grade_Level         = str_trim(Grade_Level),
    outcome_domain      = str_trim(outcome_domain),
    Learning_Subject    = str_trim(Learning_Subject),
    design              = str_trim(design),
    
    Technology_Category = ifelse(Technology_Category == "", NA, Technology_Category),
    Grade_Level         = ifelse(Grade_Level == "", NA, Grade_Level),
    outcome_domain      = ifelse(outcome_domain == "", NA, outcome_domain),
    Learning_Subject    = ifelse(Learning_Subject == "", NA, Learning_Subject),
    design              = ifelse(design == "", NA, design)
  ) %>%
  mutate(
    Technology_Category = case_when(
      str_to_lower(Technology_Category) %in% c("llm", "large language model", "large language models") ~ "LLM-based AI",
      str_to_lower(Technology_Category) %in% c("generative ai", "genai") ~ "Generative AI",
      str_to_lower(Technology_Category) %in% c("immersive ai", "vr/ar ai", "ar/vr ai") ~ "Immersive AI",
      TRUE ~ Technology_Category
    ),
    Grade_Level = case_when(
      str_to_lower(Grade_Level) %in% c("elementary", "primary") ~ "Elementary",
      str_to_lower(Grade_Level) %in% c("secondary", "middle", "high") ~ "Secondary",
      str_to_lower(Grade_Level) %in% c("mixed", "all", "multiple") ~ "Mixed",
      TRUE ~ Grade_Level
    ),
    outcome_domain = case_when(
      str_to_lower(outcome_domain) == "needs" ~ "Needs",
      str_to_lower(outcome_domain) == "motivation" ~ "Motivation",
      TRUE ~ outcome_domain
    )
  ) %>%
  mutate(
    apa_citation         = as.factor(apa_citation),
    effect_id            = as.factor(effect_id),
    Technology_Category  = droplevels(as.factor(Technology_Category)),
    Grade_Level          = droplevels(as.factor(Grade_Level)),
    outcome_domain       = droplevels(as.factor(outcome_domain)),
    design               = droplevels(as.factor(design)),
    Learning_Subject     = droplevels(as.factor(Learning_Subject))
  )

# -----------------------------
# 2) Optional minimum-k filtering
# -----------------------------
tech_keep <- combined_mod %>%
  count(Technology_Category, name = "k") %>%
  filter(!is.na(Technology_Category), k >= 2) %>%
  pull(Technology_Category)

grade_keep <- combined_mod %>%
  count(Grade_Level, name = "k") %>%
  filter(!is.na(Grade_Level), k >= 2) %>%
  pull(Grade_Level)

domain_keep <- combined_mod %>%
  count(outcome_domain, name = "k") %>%
  filter(!is.na(outcome_domain), k >= 2) %>%
  pull(outcome_domain)

subject_keep <- combined_mod %>%
  count(Learning_Subject, name = "k") %>%
  filter(!is.na(Learning_Subject), k >= 2) %>%
  pull(Learning_Subject)

design_keep <- combined_mod %>%
  count(design, name = "k") %>%
  filter(!is.na(design), k >= 2) %>%
  pull(design)

filtered_tech <- combined_mod %>%
  filter(Technology_Category %in% tech_keep) %>%
  droplevels()

filtered_grade <- combined_mod %>%
  filter(Grade_Level %in% grade_keep) %>%
  droplevels()

filtered_domain <- combined_mod %>%
  filter(outcome_domain %in% domain_keep) %>%
  droplevels()

filtered_subject <- combined_mod %>%
  filter(Learning_Subject %in% subject_keep) %>%
  droplevels()

filtered_design <- combined_mod %>%
  filter(design %in% design_keep) %>%
  droplevels()

# -----------------------------
# 3) Fit no-intercept set models
# -----------------------------
fit_tech_set <- metafor::rma.mv(
  yi = yi, V = vi,
  random = ~ 1 | study_id/effect_id,
  data = filtered_tech,
  method = "REML", test = "t",
  mods = ~ Technology_Category - 1
)

fit_grade_set <- metafor::rma.mv(
  yi = yi, V = vi,
  random = ~ 1 | study_id/effect_id,
  data = filtered_grade,
  method = "REML", test = "t",
  mods = ~ Grade_Level - 1
)

fit_domain_set <- metafor::rma.mv(
  yi = yi, V = vi,
  random = ~ 1 | study_id/effect_id,
  data = filtered_domain,
  method = "REML", test = "t",
  mods = ~ outcome_domain - 1
)

fit_subject_set <- metafor::rma.mv(
  yi = yi, V = vi,
  random = ~ 1 | study_id/effect_id,
  data = filtered_subject,
  method = "REML", test = "t",
  mods = ~ Learning_Subject - 1
)

fit_design_set <- metafor::rma.mv(
  yi = yi, V = vi,
  random = ~ 1 | study_id/effect_id,
  data = filtered_design,
  method = "REML", test = "t",
  mods = ~ design - 1
)

# -----------------------------
# 4) Extract model tables
# -----------------------------
extract_set_table <- function(fit_obj) {
  data.frame(
    estimate = as.numeric(coef(fit_obj)),
    stderror = as.numeric(fit_obj$se),
    ci.lb    = as.numeric(fit_obj$ci.lb),
    ci.ub    = as.numeric(fit_obj$ci.ub),
    row.names = names(coef(fit_obj))
  )
}

tech.set    <- extract_set_table(fit_tech_set)
grade.set   <- extract_set_table(fit_grade_set)
domain.set  <- extract_set_table(fit_domain_set)
subject.set <- extract_set_table(fit_subject_set)
design.set  <- extract_set_table(fit_design_set)

# -----------------------------
# 5) Helpers for label matching
# -----------------------------
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
    mutate(
      conditions   = clean_display(!!v),
      cond_key     = make_join_key(!!v),
      groups       = group_label,
      apa_citation = clean_display(apa_citation)
    ) %>%
    group_by(groups, conditions, cond_key) %>%
    summarise(
      k = dplyr::n(),
      n = dplyr::n_distinct(apa_citation),
      .groups = "drop"
    )
}

nk_tech    <- counts_nk(filtered_tech,    Technology_Category, "Technology Category")
nk_grade   <- counts_nk(filtered_grade,   Grade_Level,         "Grade Level")
nk_domain  <- counts_nk(filtered_domain,  outcome_domain,      "Outcome Domain")
nk_subject <- counts_nk(filtered_subject, Learning_Subject,    "Learning Subject")
nk_design  <- counts_nk(filtered_design,  design,              "Design")

arm_n_k <- bind_rows(nk_tech, nk_grade, nk_domain, nk_subject, nk_design)

build_mod_table <- function(set_df, prefix, group_label) {
  tibble::rownames_to_column(set_df, var = "coefname") %>%
    mutate(
      coef_suffix = gsub(paste0("^", prefix), "", coefname),
      conditions  = unmake_names_label(coef_suffix),
      cond_key    = make_join_key(conditions),
      groups      = group_label
    ) %>%
    select(groups, conditions, cond_key, estimate, stderror, ci.lb, ci.ub)
}

mods_tech    <- build_mod_table(tech.set,    "Technology_Category", "Technology Category")
mods_grade   <- build_mod_table(grade.set,   "Grade_Level",         "Grade Level")
mods_domain  <- build_mod_table(domain.set,  "outcome_domain",      "Outcome Domain")
mods_subject <- build_mod_table(subject.set, "Learning_Subject",    "Learning Subject")
mods_design  <- build_mod_table(design.set,  "design",              "Design")

moderators <- bind_rows(mods_tech, mods_grade, mods_domain, mods_subject, mods_design)

mods <- left_join(
  moderators,
  arm_n_k %>% select(groups, cond_key, n, k),
  by = c("groups", "cond_key")
)

bad <- mods %>%
  filter(is.na(n) | is.na(k)) %>%
  select(groups, conditions, n, k, cond_key)

if (nrow(bad) > 0) {
  print(bad)
  warning("Some levels could not be matched to n/k. Unmatched rows will be dropped from the combined moderator figure.")
  mods <- mods %>% filter(!(is.na(n) | is.na(k)))
}

# -----------------------------
# 6) Final display formatting
# -----------------------------
mods <- mods %>%
  mutate(
    conditions = case_when(
      groups == "Outcome Domain" & conditions == "Needs" ~ "Needs",
      groups == "Outcome Domain" & conditions == "Motivation" ~ "Motivation",
      
      groups == "Design" & conditions == "one_group" ~ "Single-group",
      groups == "Design" & conditions == "two_group" ~ "Experimental–control",
      
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
  mutate(
    order_top = case_when(
      groups == "Technology Category" & conditions == "LLM-based AI" ~ 1,
      groups == "Technology Category" & conditions == "Generative AI" ~ 2,
      groups == "Technology Category" & conditions == "Immersive AI" ~ 3,
      
      groups == "Grade Level" & conditions == "Elementary" ~ 1,
      groups == "Grade Level" & conditions == "Secondary"  ~ 2,
      groups == "Grade Level" & conditions == "Mixed"      ~ 3,
      
      groups == "Outcome Domain" & conditions == "Needs"      ~ 1,
      groups == "Outcome Domain" & conditions == "Motivation" ~ 2,
      
      groups == "Learning Subject" & conditions == "STEM & Computing"   ~ 1,
      groups == "Learning Subject" & conditions == "Language & Literacy" ~ 2,
      groups == "Learning Subject" & conditions == "Arts & Humanities"   ~ 3,
      
      groups == "Design" & conditions == "RCT" ~ 1,
      groups == "Design" & conditions == "Experimental–control" ~ 2,
      groups == "Design" & conditions == "Single-group"       ~ 3,
      
      TRUE ~ 999
    )
  )

# -----------------------------
# 7) Add header rows
# -----------------------------
header_labels <- mods %>%
  distinct(groups) %>%
  mutate(
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
  select(
    groups, conditions, estimate, ci.lb, ci.ub, n, k, gci,
    signif, is_header, order_top, Level, Studies, Effects, CI
  )

mods_plot <- mods %>%
  mutate(
    is_header = FALSE,
    Level   = NA_character_,
    Studies = NA_character_,
    Effects = NA_character_,
    CI      = NA_character_
  ) %>%
  bind_rows(header_labels) %>%
  mutate(
    order_plot = case_when(
      conditions == " " ~ 999,
      TRUE ~ -order_top
    )
  ) %>%
  group_by(groups) %>%
  arrange(order_plot, .by_group = TRUE) %>%
  mutate(
    y_id = paste0(groups, "___", conditions)
  ) %>%
  ungroup()

mods_plot <- mods_plot %>%
  mutate(
    groups = factor(
      groups,
      levels = c(
        "Outcome Domain",
        "Technology Category",
        "Grade Level",
        "Learning Subject",
        "Design"
      )
    )
  )

y_levels <- mods_plot %>%
  arrange(
    factor(groups, levels = c("Technology Category", "Grade Level", "Outcome Domain", "Learning Subject", "Design")),
    order_plot
  ) %>%
  pull(y_id)

mods_plot$y_id <- factor(mods_plot$y_id, levels = unique(y_levels))

# -----------------------------
# 8) Plot
# -----------------------------
geom.text.size <- 3
x_level   <- -0.45
x_studies <-  3.35
x_effects <-  4.15
x_ci      <-  5.45

m_combined_mod <- ggplot(
  data = mods_plot,
  aes(x = estimate, xmin = ci.lb, xmax = ci.ub, y = y_id)
) +
  geom_pointrange(
    data = dplyr::filter(mods_plot, !is_header),
    aes(colour = groups, size = signif)
  ) +
  scale_size_manual(values = c(plain = 0.7, bold = 1.0), guide = "none") +
  expand_limits(x = c(-1, 6.2)) +
  labs(x = "Effect Sizes", y = " ") +
  theme_minimal() %+replace%
  theme(
    axis.text.y     = element_text(size = 9, hjust = 1, colour = "black"),
    legend.position = "none",
    plot.margin     = margin(35, 240, 25, 10),
    strip.placement = "outside",
    strip.text.y    = element_text(size = 9, colour = "black", angle = 90)
  ) +
  coord_cartesian(clip = "off") +
  geom_vline(xintercept = 0) +
  facet_grid(groups ~ ., scales = "free", space = "free", switch = "both") +
  geom_text(
    data = dplyr::filter(mods_plot, !is_header),
    aes(x = x_studies, label = n, fontface = signif),
    hjust = 0.5, size = geom.text.size
  ) +
  geom_text(
    data = dplyr::filter(mods_plot, !is_header),
    aes(x = x_effects, label = format(k, big.mark = ","), fontface = signif),
    hjust = 0.5, size = geom.text.size
  ) +
  geom_text(
    data = dplyr::filter(mods_plot, !is_header),
    aes(x = x_ci, label = gci, fontface = signif),
    hjust = 0.5, size = geom.text.size
  ) +
  geom_text(
    data = dplyr::filter(mods_plot, is_header),
    aes(x = x_level, y = y_id, label = Level),
    inherit.aes = FALSE, hjust = 0, size = geom.text.size
  ) +
  geom_text(
    data = dplyr::filter(mods_plot, is_header),
    aes(x = x_studies, y = y_id, label = Studies),
    inherit.aes = FALSE, hjust = 0.5, size = geom.text.size
  ) +
  geom_text(
    data = dplyr::filter(mods_plot, is_header),
    aes(x = x_effects, y = y_id, label = Effects),
    inherit.aes = FALSE, hjust = 0.5, size = geom.text.size
  ) +
  geom_text(
    data = dplyr::filter(mods_plot, is_header),
    aes(x = x_ci, y = y_id, label = CI),
    inherit.aes = FALSE, hjust = 0.5, size = geom.text.size
  ) +
  scale_y_discrete(
    labels = function(x) {
      lab <- sub("^.*___", "", x)
      ifelse(lab == " ", "", lab)
    }
  )

print(m_combined_mod)

ggplot2::ggsave(
  filename = "combined_nooutlier_moderator_Tech_Grade_Domain_Subject_plot.png",
  plot     = m_combined_mod,
  height   = 9,
  width    = 11.5,
  dpi      = 600,
  bg       = "white"
)

# ===============================================================
# PUBLICATION BIAS — Overall (Needs + Motivation combined)
# Uses:
# - overall_dat      = with outliers
# - overall_noout_pb = without outliers
# ===============================================================

library(dplyr)
library(metafor)
library(clubSandwich)

# -----------------------------
# 1) Data with / without outliers
# -----------------------------
overall_all <- overall_dat %>%
  dplyr::mutate(
    study_id     = as.character(study_id),
    effect_id    = as.character(effect_id),
    apa_citation = as.character(apa_citation),
    yi           = as.numeric(yi),
    vi           = as.numeric(vi)
  ) %>%
  dplyr::filter(
    !is.na(apa_citation),
    !is.na(effect_id),
    !is.na(yi), !is.na(vi),
    is.finite(yi), is.finite(vi),
    vi > 0
  )

overall_noout_pb <- overall_noout %>%
  dplyr::mutate(
    study_id     = as.character(study_id),
    effect_id    = as.character(effect_id),
    apa_citation = as.character(apa_citation),
    yi           = as.numeric(yi),
    vi           = as.numeric(vi)
  ) %>%
  dplyr::filter(
    !is.na(apa_citation),
    !is.na(effect_id),
    !is.na(yi), !is.na(vi),
    is.finite(yi), is.finite(vi),
    vi > 0
  )

# -----------------------------
# 2) Multilevel models
# -----------------------------
Meta_overall_all <- metafor::rma.mv(
  yi = yi, V = vi,
  random = ~ 1 | study_id/effect_id,
  data   = overall_all,
  method = "REML",
  slab   = apa_citation
)

Meta_overall_noout <- metafor::rma.mv(
  yi = yi, V = vi,
  random = ~ 1 | study_id/effect_id,
  data   = overall_noout_pb,
  method = "REML",
  slab   = apa_citation
)

# -----------------------------
# 3) Univariate models for funnel / Egger
# -----------------------------
Meta_overall_all_uni <- metafor::rma(
  yi = yi, vi = vi,
  data = overall_all,
  method = "REML"
)

Meta_overall_noout_uni <- metafor::rma(
  yi = yi, vi = vi,
  data = overall_noout_pb,
  method = "REML"
)

# -----------------------------
# 4) Funnel plot WITH outliers
# -----------------------------
tryCatch({
  metafor::funnel(
    Meta_overall_all_uni,
    xlim  = c(-3, 3),
    ylim  = c(max(sqrt(overall_all$vi), na.rm = TRUE), 0),
    level = c(90, 95, 99),
    shade = c("white", "gray55", "gray75"),
    label = FALSE
  )
}, error = function(e) {
  message("WITH-outliers funnel plot failed: ", e$message)
})

# -----------------------------
# 5) Funnel plot WITHOUT outliers
# -----------------------------
tryCatch({
  metafor::funnel(
    Meta_overall_noout_uni,
    xlim  = c(-3, 3),
    ylim  = c(max(sqrt(overall_noout_pb$vi), na.rm = TRUE), 0),
    level = c(90, 95, 99),
    shade = c("white", "gray55", "gray75"),
    label = FALSE
  )
}, error = function(e) {
  message("WITHOUT-outliers funnel plot failed: ", e$message)
})

# -----------------------------
# 6) Egger
# -----------------------------
cat("\n================ EGGER TEST: WITH OUTLIERS ================\n")
print(metafor::regtest(Meta_overall_all_uni, model = "rma"))

cat("\n================ EGGER TEST: WITHOUT OUTLIERS ================\n")
print(metafor::regtest(Meta_overall_noout_uni, model = "rma"))

# -----------------------------
# 7) PET / PEESE + CR2 (WITH outliers)
# -----------------------------
cat("\n================ PET / PEESE: WITH OUTLIERS ================\n")

dat_pet_all <- overall_all %>%
  dplyr::mutate(sei = sqrt(vi))

PET_mv_all <- metafor::rma.mv(
  yi = yi, V = vi,
  mods = ~ sei,
  random = ~ 1 | study_id/effect_id,
  data = dat_pet_all,
  method = "REML"
)
print(clubSandwich::coef_test(PET_mv_all, vcov = "CR2", test = "Satterthwaite"))

PEESE_mv_all <- metafor::rma.mv(
  yi = yi, V = vi,
  mods = ~ I(sei^2),
  random = ~ 1 | study_id/effect_id,
  data = dat_pet_all,
  method = "REML"
)
print(clubSandwich::coef_test(PEESE_mv_all, vcov = "CR2", test = "Satterthwaite"))

# -----------------------------
# 8) PET / PEESE + CR2 (WITHOUT outliers)
# -----------------------------
cat("\n================ PET / PEESE: WITHOUT OUTLIERS ================\n")

dat_pet_noout <- overall_noout_pb %>%
  dplyr::mutate(sei = sqrt(vi))

PET_mv_noout <- metafor::rma.mv(
  yi = yi, V = vi,
  mods = ~ sei,
  random = ~ 1 | study_id/effect_id,
  data = dat_pet_noout,
  method = "REML"
)
print(clubSandwich::coef_test(PET_mv_noout, vcov = "CR2", test = "Satterthwaite"))

PEESE_mv_noout <- metafor::rma.mv(
  yi = yi, V = vi,
  mods = ~ I(sei^2),
  random = ~ 1 | study_id/effect_id,
  data = dat_pet_noout,
  method = "REML"
)
print(clubSandwich::coef_test(PEESE_mv_noout, vcov = "CR2", test = "Satterthwaite"))

# ===============================================================
# Forest plot (WITHOUT outliers; study-level: 1 row per study)
# ===============================================================

dat0 <- overall_noout_pb

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
    slab   = apa_citation,
    sei    = sqrt(vi),
    ci.lb  = yi - 1.96 * sei,
    ci.ub  = yi + 1.96 * sei,
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
  x_axis_max <- ceiling(max(dat_study$ci.ub, 0) * 10) / 10
  x_rng <- x_axis_max - x_axis_min
  if (x_rng <= 0) x_rng <- 1
  
  x_plot_left  <- x_axis_min - 1.2 * x_rng
  x_plot_right <- x_axis_max + 1.6 * x_rng
  
  x_study <- x_axis_min - 0.95 * x_rng
  x_w     <- x_plot_right - 0.55 * x_rng
  x_est   <- x_plot_right - 0.35 * x_rng
  
  tryCatch({
    par(mar = c(11, 5.5, 2.2, 12), xpd = NA)
    
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
    
    axis(1, at = pretty(c(x_axis_min, x_axis_max)), line = 4)
    
    row_step <- if (length(dat_study$rows) > 1) abs(dat_study$rows[1] - dat_study$rows[2]) else 1.5
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
    
    text(x = x_w, y = dat_study$rows, labels = sprintf("%.2f%%", dat_study$w_perc), cex = 0.95)
    text(x = x_est, y = dat_study$rows, labels = dat_study$est_ci, pos = 4, cex = 0.95)
    
    metafor::addpoly(fit_all, row = row_poly_all, mlab = "", cex = 1.05)
    text(x = x_study, y = row_poly_all, pos = 4, font = 2, "Random-Effects Model (Without outliers)")
    
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
# Forest plot (WITH outliers; study-level: 1 row per study)
# ===============================================================

dat0_with <- overall_all

dat_eff_with <- dat0_with %>%
  dplyr::mutate(
    apa_citation = as.character(apa_citation),
    effect_id    = as.character(effect_id)
  ) %>%
  dplyr::filter(
    !is.na(apa_citation),
    !is.na(effect_id),
    !is.na(yi),
    !is.na(vi),
    is.finite(yi),
    is.finite(vi),
    vi > 0
  )

dat_study_with <- dat_eff_with %>%
  dplyr::group_by(apa_citation) %>%
  dplyr::summarise(
    k_eff = dplyr::n(),
    yi    = weighted.mean(yi, w = 1 / vi),
    vi    = 1 / sum(1 / vi),
    .groups = "drop"
  ) %>%
  dplyr::mutate(
    slab   = apa_citation,
    sei    = sqrt(vi),
    ci.lb  = yi - 1.96 * sei,
    ci.ub  = yi + 1.96 * sei,
    est_ci = sprintf("%.2f [%.2f, %.2f]", yi, ci.lb, ci.ub)
  ) %>%
  dplyr::arrange(yi)

if (nrow(dat_study_with) == 0) {
  warning("WITH-outliers forest plot skipped: dat_study_with is empty after filtering.")
} else {
  
  fit_all_with <- metafor::rma(
    yi     = yi,
    vi     = vi,
    data   = dat_study_with,
    method = "REML"
  )
  
  w_with <- as.numeric(weights(fit_all_with))
  dat_study_with$w_perc <- 100 * w_with / sum(w_with)
  
  k_with       <- nrow(dat_study_with)
  top_row_with <- k_with + 6
  rows_with    <- seq(from = top_row_with, length.out = k_with, by = -1.5)
  row_poly_with <- min(rows_with) - 3
  
  dat_study_with$rows <- rows_with
  
  x_axis_min_with <- floor(min(dat_study_with$ci.lb, 0) * 10) / 10
  x_axis_max_with <- ceiling(max(dat_study_with$ci.ub, 0) * 10) / 10
  x_rng_with      <- x_axis_max_with - x_axis_min_with
  if (x_rng_with <= 0) x_rng_with <- 1
  
  x_plot_left_with  <- x_axis_min_with - 1.2 * x_rng_with
  x_plot_right_with <- x_axis_max_with + 1.6 * x_rng_with
  
  x_study_with <- x_axis_min_with - 0.95 * x_rng_with
  x_w_with     <- x_plot_right_with - 0.55 * x_rng_with
  x_est_with   <- x_plot_right_with - 0.35 * x_rng_with
  
  tryCatch({
    
    par(mar = c(8, 5.5, 2.2, 12), xpd = NA)
    
    metafor::forest(
      x         = dat_study_with$yi,
      vi        = dat_study_with$vi,
      slab      = dat_study_with$slab,
      rows      = dat_study_with$rows,
      refline   = 0,
      xlim      = c(x_plot_left_with, x_plot_right_with),
      alim      = c(x_axis_min_with, x_axis_max_with),
      textpos   = c(x_study_with, x_axis_max_with),
      xlab      = " ",
      pch       = 15,
      cex       = 0.95,
      annotate  = FALSE,
      showweights = FALSE,
      header    = " ",
      xaxt      = "n"
    )
    
    axis(1, at = pretty(c(x_axis_min_with, x_axis_max_with)), line = 4)
    
    row_step_with <- if (length(dat_study_with$rows) > 1) {
      abs(dat_study_with$rows[1] - dat_study_with$rows[2])
    } else {
      1.5
    }
    
    half_h_with <- row_step_with / 2
    stripe_col_with <- grDevices::adjustcolor(gray(0.93), alpha.f = 0.85)
    
    for (i in seq_along(dat_study_with$rows)) {
      if (i %% 2 == 0) {
        y <- dat_study_with$rows[i]
        padL <- -1.00 * x_rng_with
        padR <-  0.30 * x_rng_with
        
        rect(
          x_axis_min_with + padL,
          y - half_h_with,
          x_plot_right_with + padR,
          y + half_h_with,
          col = stripe_col_with,
          border = NA
        )
      }
    }
    
    abline(v = 0, lty = 3, col = "gray70")
    
    segments(
      dat_study_with$ci.lb,
      dat_study_with$rows,
      dat_study_with$ci.ub,
      dat_study_with$rows,
      lwd = 1.2
    )
    
    points(
      dat_study_with$yi,
      dat_study_with$rows,
      pch = 15,
      cex = 0.95
    )
    
    text(
      x = x_study_with,
      y = dat_study_with$rows,
      labels = dat_study_with$slab,
      pos = 4,
      cex = 0.95
    )
    
    text(
      x = x_study_with,
      y = top_row_with + 2,
      pos = 4,
      font = 2,
      "Author(s) and Year"
    )
    
    text(
      x = x_w_with,
      y = top_row_with + 2,
      font = 2,
      "Weight"
    )
    
    text(
      x = x_est_with,
      y = top_row_with + 2,
      pos = 4,
      font = 2,
      "Estimate [95% CI]"
    )
    
    text(
      x = x_w_with,
      y = dat_study_with$rows,
      labels = sprintf("%.2f%%", dat_study_with$w_perc),
      cex = 0.95
    )
    
    text(
      x = x_est_with,
      y = dat_study_with$rows,
      labels = dat_study_with$est_ci,
      pos = 4,
      cex = 0.95
    )
    
    metafor::addpoly(
      fit_all_with,
      row = row_poly_with,
      mlab = "",
      cex = 1.05
    )
    
    text(
      x = x_study_with,
      y = row_poly_with,
      pos = 4,
      font = 2,
      "Random-Effects Model (With outliers)"
    )
    
    pred_with <- predict(fit_all_with, level = 95)
    
    text(
      x = x_w_with,
      y = row_poly_with,
      labels = "100%",
      cex = 1.0,
      font = 2
    )
    
    text(
      x = x_est_with,
      y = row_poly_with,
      labels = sprintf("%.2f [%.2f, %.2f]", pred_with$pred, pred_with$ci.lb, pred_with$ci.ub),
      pos = 4,
      cex = 1.0,
      font = 2
    )
    
  }, error = function(e) {
    message("WITH-outliers forest plot failed: ", e$message)
  })
}

# ===============================================================
# Forest plot (WITHOUT outliers; multiple effect sizes on same row)
# ===============================================================

options(warn = 1, nwarnings = 10000)

dat0 <- overall_noout_pb

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
  ) %>%
  dplyr::arrange(apa_citation)

if (nrow(dat_eff) == 0) {
  warning("WITHOUT-outliers forest plot skipped: dat_eff is empty after filtering.")
} else {
  
  fit_mv <- metafor::rma.mv(
    yi = yi,
    V  = vi,
    random = ~ 1 | apa_citation/effect_id,
    data = dat_eff,
    method = "REML",
    slab = dat_eff$apa_citation
  )
  
  study_names <- dat_eff$apa_citation
  slab_labels <- ifelse(duplicated(study_names), "", study_names)
  
  # Assign the same row to all effect sizes from the same study
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
  
  # Fix the x-axis range to match the second figure style
  x_axis_min <- -2
  x_axis_max <- 4
  x_rng <- x_axis_max - x_axis_min
  
  x_plot_left  <- x_axis_min - 1.25 * x_rng
  x_plot_right <- x_axis_max + 0.25 * x_rng
  x_study <- x_axis_min - 0.98 * x_rng
  
  top_row  <- max(dat_eff$rows) + 2
  row_poly <- min(dat_eff$rows) - 2
  
  # Apply alternating shading by study
  shade_map <- setNames(
    rep(c(FALSE, TRUE), length.out = length(study_levels)),
    study_levels
  )
  shade_vec <- as.logical(shade_map[study_names])
  
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
    
    axis(1, at = seq(x_axis_min, x_axis_max, by = 1), line = 1)
    mtext("Standardized Mean Difference", side = 1, line = 3.5)
    abline(v = 0, lty = 3, col = "gray70")
    
    segments(
      dat_eff$ci.lb, dat_eff$rows,
      dat_eff$ci.ub, dat_eff$rows,
      lwd = 1.0
    )
    points(dat_eff$yi, dat_eff$rows, pch = 18, cex = 0.85)
    
    text(
      x = x_study, y = dat_eff$rows,
      labels = dat_eff$slab, pos = 4, cex = 0.9
    )
    text(
      x = x_study, y = top_row,
      pos = 4, font = 2, "Author(s) and Year"
    )
    
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
      pos = 4, font = 2, "Pooled Estimate"
    )
    
  }, error = function(e) {
    message("WITHOUT-outliers forest plot failed: ", e$message)
  })
}

# ===============================================================
# Forest plot (WITH outliers; multiple effect sizes on same row)
# ===============================================================

options(warn = 1, nwarnings = 10000)

dat0_with <- overall_all

dat_eff_with <- dat0_with %>%
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
  ) %>%
  dplyr::arrange(apa_citation)

if (nrow(dat_eff_with) == 0) {
  warning("WITH-outliers forest plot skipped: dat_eff_with is empty after filtering.")
} else {
  
  fit_mv_with <- metafor::rma.mv(
    yi = yi,
    V  = vi,
    random = ~ 1 | apa_citation/effect_id,
    data = dat_eff_with,
    method = "REML",
    slab = dat_eff_with$apa_citation
  )
  
  study_names_with <- dat_eff_with$apa_citation
  slab_labels_with <- ifelse(duplicated(study_names_with), "", study_names_with)
  
  # Assign the same row to all effect sizes from the same study
  study_levels_with <- unique(study_names_with)
  study_row_map_with <- setNames(
    seq(from = length(study_levels_with) + 2, to = 3, by = -1),
    study_levels_with
  )
  study_rows_with <- unname(study_row_map_with[study_names_with])
  
  dat_eff_with <- dat_eff_with %>%
    dplyr::mutate(
      rows  = study_rows_with,
      sei   = sqrt(vi),
      ci.lb = yi - 1.96 * sei,
      ci.ub = yi + 1.96 * sei,
      slab  = slab_labels_with
    )
  
  pred_mv_with <- predict(fit_mv_with)
  
  # Fix the x-axis range to match the second figure style
  x_axis_min_with <- -2
  x_axis_max_with <- 4
  x_rng_with <- x_axis_max_with - x_axis_min_with
  
  x_plot_left_with  <- x_axis_min_with - 1.25 * x_rng_with
  x_plot_right_with <- x_axis_max_with + 0.25 * x_rng_with
  x_study_with <- x_axis_min_with - 0.98 * x_rng_with
  
  top_row_with  <- max(dat_eff_with$rows) + 2
  row_poly_with <- min(dat_eff_with$rows) - 2
  
  # Apply alternating shading by study
  shade_map_with <- setNames(
    rep(c(FALSE, TRUE), length.out = length(study_levels_with)),
    study_levels_with
  )
  shade_vec_with <- as.logical(shade_map_with[study_names_with])
  
  tryCatch({
    par(mar = c(5.5, 5.5, 2.2, 4), xpd = NA)
    
    metafor::forest(
      x = dat_eff_with$yi,
      vi = dat_eff_with$vi,
      slab = rep("", nrow(dat_eff_with)),
      rows = dat_eff_with$rows,
      refline = 0,
      xlim = c(x_plot_left_with, x_plot_right_with),
      alim = c(x_axis_min_with, x_axis_max_with),
      textpos = c(x_study_with, x_axis_max_with),
      xlab = "",
      pch = 18,
      cex = 0.9,
      annotate = FALSE,
      showweights = FALSE,
      header = " ",
      xaxt = "n",
      shade = shade_vec_with,
      efac = c(0, 0.5)
    )
    
    axis(1, at = seq(x_axis_min_with, x_axis_max_with, by = 1), line = 1)
    mtext("Standardized Mean Difference", side = 1, line = 3.5)
    abline(v = 0, lty = 3, col = "gray70")
    
    segments(
      dat_eff_with$ci.lb, dat_eff_with$rows,
      dat_eff_with$ci.ub, dat_eff_with$rows,
      lwd = 1.0
    )
    points(dat_eff_with$yi, dat_eff_with$rows, pch = 18, cex = 0.85)
    
    text(
      x = x_study_with, y = dat_eff_with$rows,
      labels = dat_eff_with$slab, pos = 4, cex = 0.9
    )
    text(
      x = x_study_with, y = top_row_with,
      pos = 4, font = 2, "Author(s) and Year"
    )
    
    metafor::addpoly(
      x = pred_mv_with$pred,
      ci.lb = pred_mv_with$ci.lb,
      ci.ub = pred_mv_with$ci.ub,
      row = row_poly_with,
      mlab = "",
      cex = 1.0
    )
    text(
      x = x_study_with, y = row_poly_with,
      pos = 4, font = 2, "Pooled Estimate"
    )
    
  }, error = function(e) {
    message("WITH-outliers forest plot failed: ", e$message)
  })
}

# ===============================================================
# EXTRA RESULTS YOU STILL NEED
# 1) Separate pooled models for Needs and Motivation
# 2) Updated I² decomposition for overall / needs / motivation
# Based on FULL SAMPLE (with all effects retained)
# ===============================================================

# ---------------------------------------------------------------
# 1) Use full dataset (with all retained effects; no outlier removal)
# ---------------------------------------------------------------
overall_full <- overall_dat %>%
  mutate(
    study_id = as.factor(study_id),
    effect_id = as.factor(effect_id),
    outcome_domain = trimws(as.character(outcome_domain))
  )

cat("\n====================================================\n")
cat("FULL SAMPLE CHECK\n")
cat("====================================================\n")
cat("Rows:", nrow(overall_full), "\n")
cat("Studies:", dplyr::n_distinct(overall_full$study_id), "\n")
print(table(overall_full$outcome_domain, useNA = "ifany"))

# ---------------------------------------------------------------
# 2) Helper: multilevel I² decomposition
#    Based on sigma² / (sigma² + mean sampling variance)
# ---------------------------------------------------------------
calc_i2_ml <- function(fit, data) {
  
  mean_vi <- mean(data$vi, na.rm = TRUE)
  sigma2 <- fit$sigma2
  
  if (length(sigma2) == 1) {
    sigma2 <- c(sigma2, 0)
  }
  
  total_var <- sum(sigma2, na.rm = TRUE) + mean_vi
  
  level3_i2 <- 100 * sigma2[1] / total_var
  level2_i2 <- 100 * sigma2[2] / total_var
  total_i2  <- 100 * sum(sigma2, na.rm = TRUE) / total_var
  
  out <- data.frame(
    mean_vi   = mean_vi,
    sigma2_L3 = sigma2[1],
    sigma2_L2 = sigma2[2],
    I2_total  = total_i2,
    I2_level3 = level3_i2,
    I2_level2 = level2_i2
  )
  
  return(out)
}

# ---------------------------------------------------------------
# 3) Overall full model
# ---------------------------------------------------------------
fit_overall_full <- metafor::rma.mv(
  yi = yi,
  V = vi,
  random = ~ 1 | study_id/effect_id,
  data = overall_full,
  method = "REML",
  slab = apa_citation
)

cat("\n====================================================\n")
cat("OVERALL MODEL (FULL SAMPLE)\n")
cat("====================================================\n")
print(fit_overall_full, digits = 3)

cat("\n--- Robust test (CR2) ---\n")
print(clubSandwich::coef_test(fit_overall_full, vcov = "CR2", test = "Satterthwaite"))

cat("\n--- I2 decomposition: OVERALL ---\n")
i2_overall <- calc_i2_ml(fit_overall_full, overall_full)
print(i2_overall)

overall_summary_full <- data.frame(
  outcome_domain = "Needs + Motivation",
  k_effect_sizes = nrow(overall_full),
  n_studies      = dplyr::n_distinct(overall_full$study_id),
  g              = as.numeric(coef(fit_overall_full)),
  ci_lb          = fit_overall_full$ci.lb,
  ci_ub          = fit_overall_full$ci.ub,
  p_value        = fit_overall_full$pval
)

cat("\n--- Overall summary ---\n")
print(overall_summary_full)

# ---------------------------------------------------------------
# 4) Separate model: Needs
# ---------------------------------------------------------------
dat_needs <- overall_full %>%
  filter(outcome_domain == "Needs")

fit_needs <- metafor::rma.mv(
  yi = yi,
  V = vi,
  random = ~ 1 | study_id/effect_id,
  data = dat_needs,
  method = "REML",
  slab = apa_citation
)

cat("\n====================================================\n")
cat("NEEDS MODEL\n")
cat("====================================================\n")
print(fit_needs, digits = 3)

cat("\n--- Robust test (CR2) ---\n")
print(clubSandwich::coef_test(fit_needs, vcov = "CR2", test = "Satterthwaite"))

cat("\n--- I2 decomposition: NEEDS ---\n")
i2_needs <- calc_i2_ml(fit_needs, dat_needs)
print(i2_needs)

needs_summary <- data.frame(
  outcome_domain = "Needs",
  k_effect_sizes = nrow(dat_needs),
  n_studies      = dplyr::n_distinct(dat_needs$study_id),
  g              = as.numeric(coef(fit_needs)),
  ci_lb          = fit_needs$ci.lb,
  ci_ub          = fit_needs$ci.ub,
  p_value        = fit_needs$pval
)

cat("\n--- Needs summary ---\n")
print(needs_summary)

# ---------------------------------------------------------------
# 5) Separate model: Motivation
# ---------------------------------------------------------------
dat_motivation <- overall_full %>%
  filter(outcome_domain == "Motivation")

fit_motivation <- metafor::rma.mv(
  yi = yi,
  V = vi,
  random = ~ 1 | study_id/effect_id,
  data = dat_motivation,
  method = "REML",
  slab = apa_citation
)

cat("\n====================================================\n")
cat("MOTIVATION MODEL\n")
cat("====================================================\n")
print(fit_motivation, digits = 3)

cat("\n--- Robust test (CR2) ---\n")
print(clubSandwich::coef_test(fit_motivation, vcov = "CR2", test = "Satterthwaite"))

cat("\n--- I2 decomposition: MOTIVATION ---\n")
i2_motivation <- calc_i2_ml(fit_motivation, dat_motivation)
print(i2_motivation)

motivation_summary <- data.frame(
  outcome_domain = "Motivation",
  k_effect_sizes = nrow(dat_motivation),
  n_studies      = dplyr::n_distinct(dat_motivation$study_id),
  g              = as.numeric(coef(fit_motivation)),
  ci_lb          = fit_motivation$ci.lb,
  ci_ub          = fit_motivation$ci.ub,
  p_value        = fit_motivation$pval
)

cat("\n--- Motivation summary ---\n")
print(motivation_summary)

# ---------------------------------------------------------------
# 6) Difference test between Needs and Motivation
# ---------------------------------------------------------------
fit_domain_mod <- metafor::rma.mv(
  yi = yi,
  V = vi,
  mods = ~ factor(outcome_domain),
  random = ~ 1 | study_id/effect_id,
  data = overall_full,
  method = "REML"
)

cat("\n====================================================\n")
cat("DOMAIN DIFFERENCE TEST\n")
cat("====================================================\n")
print(fit_domain_mod, digits = 3)

cat("\n--- Robust test (CR2) ---\n")
print(clubSandwich::coef_test(fit_domain_mod, vcov = "CR2", test = "Satterthwaite"))

cat("\n--- Omnibus moderator test ---\n")
print(anova(fit_domain_mod))

# ---------------------------------------------------------------
# 7) Final table for direct reporting
# ---------------------------------------------------------------
final_domain_results <- bind_rows(
  overall_summary_full,
  needs_summary,
  motivation_summary
)

cat("\n====================================================\n")
cat("FINAL DOMAIN RESULTS TABLE\n")
cat("====================================================\n")
print(final_domain_results)

cat("\n====================================================\n")
cat("FINAL I2 TABLE\n")
cat("====================================================\n")
final_i2_table <- bind_rows(
  cbind(model = "Overall",    i2_overall),
  cbind(model = "Needs",      i2_needs),
  cbind(model = "Motivation", i2_motivation)
)
print(final_i2_table)

# ===============================================================
# Technology Category: subgroup estimates + counts + omnibus F
# Based on full sample
# ===============================================================

# 1) Full-sample tech data
dat_tech_full <- overall_full %>%
  filter(!is.na(Technology_Category)) %>%
  mutate(
    Technology_Category = trimws(as.character(Technology_Category)),
    Technology_Category = factor(Technology_Category)
  )

cat("\n====================================================\n")
cat("TECH CATEGORY COUNTS\n")
cat("====================================================\n")
print(table(dat_tech_full$Technology_Category, useNA = "ifany"))

cat("\nUnique studies by Technology Category:\n")
tech_counts <- dat_tech_full %>%
  group_by(Technology_Category) %>%
  summarise(
    n_studies = n_distinct(apa_citation),
    k_effect_sizes = n(),
    .groups = "drop"
  )
print(tech_counts)

# 2) No-intercept subgroup model: directly gives each subgroup estimate
fit_tech_set_full <- metafor::rma.mv(
  yi = yi,
  V = vi,
  random = ~ 1 | study_id/effect_id,
  data = dat_tech_full,
  method = "REML",
  mods = ~ Technology_Category - 1
)

cat("\n====================================================\n")
cat("TECH CATEGORY SET MODEL (DIRECT SUBGROUP ESTIMATES)\n")
cat("====================================================\n")
print(fit_tech_set_full, digits = 3)

tech_set_table <- data.frame(
  Technology_Category = names(coef(fit_tech_set_full)),
  g = as.numeric(coef(fit_tech_set_full)),
  ci_lb = fit_tech_set_full$ci.lb,
  ci_ub = fit_tech_set_full$ci.ub,
  p_value = fit_tech_set_full$pval
)

tech_set_table$Technology_Category <- gsub("^Technology_Category", "", tech_set_table$Technology_Category)

cat("\nDirect subgroup estimates:\n")
print(tech_set_table)

# 3) Merge subgroup estimates with n_studies and k_effect_sizes
tech_report_table <- left_join(
  tech_set_table,
  tech_counts,
  by = "Technology_Category"
)

cat("\n====================================================\n")
cat("FINAL TECH REPORT TABLE\n")
cat("====================================================\n")
print(tech_report_table)

# 4) Standard reference-group moderator model
fit_tech_mod_full <- metafor::rma.mv(
  yi = yi,
  V = vi,
  mods = ~ factor(Technology_Category),
  random = ~ 1 | study_id/effect_id,
  data = dat_tech_full,
  method = "REML"
)

cat("\n====================================================\n")
cat("TECH CATEGORY MODERATOR MODEL\n")
cat("====================================================\n")
print(fit_tech_mod_full, digits = 3)

cat("\nRobust coefficient test:\n")
rob_tech <- clubSandwich::coef_test(
  fit_tech_mod_full,
  vcov = "CR2",
  test = "Satterthwaite"
)
print(rob_tech)

# 5) Robust omnibus F test
# Try HTZ with constrain_zero()
cat("\n====================================================\n")
cat("ROBUST OMNIBUS F TEST FOR TECH CATEGORY\n")
cat("====================================================\n")

W_tech <- clubSandwich::Wald_test(
  fit_tech_mod_full,
  constraints = clubSandwich::constrain_zero(2:length(coef(fit_tech_mod_full))),
  vcov = "CR2",
  test = "HTZ"
)

print(W_tech)

# Extract robust F values safely
F_value <- if ("Fstat" %in% names(W_tech)) W_tech$Fstat else if ("F" %in% names(W_tech)) W_tech$F else NA
df_num  <- if ("df_num" %in% names(W_tech)) W_tech$df_num else if ("df" %in% names(W_tech)) W_tech$df else NA
df_denom <- if ("df_denom" %in% names(W_tech)) W_tech$df_denom else if ("den_df" %in% names(W_tech)) W_tech$den_df else NA
p_value <- if ("p_val" %in% names(W_tech)) W_tech$p_val else if ("p" %in% names(W_tech)) W_tech$p else NA

cat(
  "\nFinal omnibus F format:\n",
  "F(",
  round(df_num, 2), ", ",
  round(df_denom, 2), ") = ",
  round(F_value, 3),
  ", p = ",
  format.pval(p_value, digits = 3),
  "\n",
  sep = ""
)

# ===============================================================
# Grade Level: subgroup estimates + counts + omnibus F
# Based on full sample
# ===============================================================

# 1) Full-sample grade data
dat_grade_full <- overall_full %>%
  filter(!is.na(Grade_Level)) %>%
  mutate(
    Grade_Level = trimws(as.character(Grade_Level)),
    Grade_Level = factor(Grade_Level)
  )

cat("\n====================================================\n")
cat("GRADE LEVEL COUNTS\n")
cat("====================================================\n")
print(table(dat_grade_full$Grade_Level, useNA = "ifany"))

cat("\nUnique studies by Grade Level:\n")
grade_counts <- dat_grade_full %>%
  group_by(Grade_Level) %>%
  summarise(
    n_studies = n_distinct(apa_citation),
    k_effect_sizes = n(),
    .groups = "drop"
  )
print(grade_counts)

# 2) No-intercept subgroup model: directly gives each subgroup estimate
fit_grade_set_full <- metafor::rma.mv(
  yi = yi,
  V = vi,
  random = ~ 1 | study_id/effect_id,
  data = dat_grade_full,
  method = "REML",
  mods = ~ Grade_Level - 1
)

cat("\n====================================================\n")
cat("GRADE LEVEL SET MODEL (DIRECT SUBGROUP ESTIMATES)\n")
cat("====================================================\n")
print(fit_grade_set_full, digits = 3)

grade_set_table <- data.frame(
  Grade_Level = names(coef(fit_grade_set_full)),
  g = as.numeric(coef(fit_grade_set_full)),
  ci_lb = fit_grade_set_full$ci.lb,
  ci_ub = fit_grade_set_full$ci.ub,
  p_value = fit_grade_set_full$pval
)

grade_set_table$Grade_Level <- gsub("^Grade_Level", "", grade_set_table$Grade_Level)

cat("\nDirect subgroup estimates:\n")
print(grade_set_table)

# 3) Merge subgroup estimates with n_studies and k_effect_sizes
grade_report_table <- left_join(
  grade_set_table,
  grade_counts,
  by = "Grade_Level"
)

cat("\n====================================================\n")
cat("FINAL GRADE REPORT TABLE\n")
cat("====================================================\n")
print(grade_report_table)

# 4) Standard reference-group moderator model
fit_grade_mod_full <- metafor::rma.mv(
  yi = yi,
  V = vi,
  mods = ~ factor(Grade_Level),
  random = ~ 1 | study_id/effect_id,
  data = dat_grade_full,
  method = "REML"
)

cat("\n====================================================\n")
cat("GRADE LEVEL MODERATOR MODEL\n")
cat("====================================================\n")
print(fit_grade_mod_full, digits = 3)

cat("\nRobust coefficient test:\n")
rob_grade <- clubSandwich::coef_test(
  fit_grade_mod_full,
  vcov = "CR2",
  test = "Satterthwaite"
)
print(rob_grade)

# 5) Robust omnibus F test
cat("\n====================================================\n")
cat("ROBUST OMNIBUS F TEST FOR GRADE LEVEL\n")
cat("====================================================\n")

W_grade <- clubSandwich::Wald_test(
  fit_grade_mod_full,
  constraints = clubSandwich::constrain_zero(2:length(coef(fit_grade_mod_full))),
  vcov = "CR2",
  test = "HTZ"
)

print(W_grade)

# Extract robust F values safely
F_value <- if ("Fstat" %in% names(W_grade)) W_grade$Fstat else if ("F" %in% names(W_grade)) W_grade$F else NA
df_num  <- if ("df_num" %in% names(W_grade)) W_grade$df_num else if ("df" %in% names(W_grade)) W_grade$df else NA
df_denom <- if ("df_denom" %in% names(W_grade)) W_grade$df_denom else if ("den_df" %in% names(W_grade)) W_grade$den_df else NA
p_value <- if ("p_val" %in% names(W_grade)) W_grade$p_val else if ("p" %in% names(W_grade)) W_grade$p else NA

cat(
  "\nFinal omnibus F format:\n",
  "F(",
  round(df_num, 2), ", ",
  round(df_denom, 2), ") = ",
  round(F_value, 3),
  ", p = ",
  format.pval(p_value, digits = 3),
  "\n",
  sep = ""
)

# ===============================================================
# Learning Subject: subgroup estimates + counts + omnibus F
# Based on full sample
# ===============================================================

# 1) Full-sample subject data
dat_subject_full <- overall_full %>%
  filter(!is.na(Learning_Subject)) %>%
  mutate(
    Learning_Subject = trimws(as.character(Learning_Subject)),
    Learning_Subject = factor(Learning_Subject)
  )

cat("\n====================================================\n")
cat("LEARNING SUBJECT COUNTS\n")
cat("====================================================\n")
print(table(dat_subject_full$Learning_Subject, useNA = "ifany"))

cat("\nUnique studies by Learning Subject:\n")
subject_counts <- dat_subject_full %>%
  group_by(Learning_Subject) %>%
  summarise(
    n_studies = n_distinct(apa_citation),
    k_effect_sizes = n(),
    .groups = "drop"
  )
print(subject_counts)

# 2) No-intercept subgroup model: directly gives each subgroup estimate
fit_subject_set_full <- metafor::rma.mv(
  yi = yi,
  V = vi,
  random = ~ 1 | study_id/effect_id,
  data = dat_subject_full,
  method = "REML",
  mods = ~ Learning_Subject - 1
)

cat("\n====================================================\n")
cat("LEARNING SUBJECT SET MODEL (DIRECT SUBGROUP ESTIMATES)\n")
cat("====================================================\n")
print(fit_subject_set_full, digits = 3)

subject_set_table <- data.frame(
  Learning_Subject = names(coef(fit_subject_set_full)),
  g = as.numeric(coef(fit_subject_set_full)),
  ci_lb = fit_subject_set_full$ci.lb,
  ci_ub = fit_subject_set_full$ci.ub,
  p_value = fit_subject_set_full$pval
)

subject_set_table$Learning_Subject <- gsub("^Learning_Subject", "", subject_set_table$Learning_Subject)

cat("\nDirect subgroup estimates:\n")
print(subject_set_table)

# 3) Merge subgroup estimates with n_studies and k_effect_sizes
subject_report_table <- left_join(
  subject_set_table,
  subject_counts,
  by = "Learning_Subject"
)

cat("\n====================================================\n")
cat("FINAL SUBJECT REPORT TABLE\n")
cat("====================================================\n")
print(subject_report_table)

# 4) Standard reference-group moderator model
fit_subject_mod_full <- metafor::rma.mv(
  yi = yi,
  V = vi,
  mods = ~ factor(Learning_Subject),
  random = ~ 1 | study_id/effect_id,
  data = dat_subject_full,
  method = "REML"
)

cat("\n====================================================\n")
cat("LEARNING SUBJECT MODERATOR MODEL\n")
cat("====================================================\n")
print(fit_subject_mod_full, digits = 3)

cat("\nRobust coefficient test:\n")
rob_subject <- clubSandwich::coef_test(
  fit_subject_mod_full,
  vcov = "CR2",
  test = "Satterthwaite"
)
print(rob_subject)

# 5) Robust omnibus F test
cat("\n====================================================\n")
cat("ROBUST OMNIBUS F TEST FOR LEARNING SUBJECT\n")
cat("====================================================\n")

W_subject <- clubSandwich::Wald_test(
  fit_subject_mod_full,
  constraints = clubSandwich::constrain_zero(2:length(coef(fit_subject_mod_full))),
  vcov = "CR2",
  test = "HTZ"
)

print(W_subject)

# Extract robust F values safely
F_value <- if ("Fstat" %in% names(W_subject)) W_subject$Fstat else if ("F" %in% names(W_subject)) W_subject$F else NA
df_num  <- if ("df_num" %in% names(W_subject)) W_subject$df_num else if ("df" %in% names(W_subject)) W_subject$df else NA
df_denom <- if ("df_denom" %in% names(W_subject)) W_subject$df_denom else if ("den_df" %in% names(W_subject)) W_subject$den_df else NA
p_value <- if ("p_val" %in% names(W_subject)) W_subject$p_val else if ("p" %in% names(W_subject)) W_subject$p else NA

cat(
  "\nFinal omnibus F format:\n",
  "F(",
  round(df_num, 2), ", ",
  round(df_denom, 2), ") = ",
  round(F_value, 3),
  ", p = ",
  format.pval(p_value, digits = 3),
  "\n",
  sep = ""
)

# ===============================================================
# Design: subgroup estimates + counts + omnibus F
# Based on full sample
# ===============================================================

# 1) Full-sample design data
dat_design_full <- overall_full %>%
  filter(!is.na(design)) %>%
  mutate(
    design = trimws(as.character(design)),
    design = factor(design)
  )

cat("\n====================================================\n")
cat("DESIGN COUNTS\n")
cat("====================================================\n")
print(table(dat_design_full$design, useNA = "ifany"))

cat("\nUnique studies by design:\n")
design_counts <- dat_design_full %>%
  group_by(design) %>%
  summarise(
    n_studies = n_distinct(apa_citation),
    k_effect_sizes = n(),
    .groups = "drop"
  )
print(design_counts)

# 2) No-intercept subgroup model: directly gives each subgroup estimate
fit_design_set_full <- metafor::rma.mv(
  yi = yi,
  V = vi,
  random = ~ 1 | study_id/effect_id,
  data = dat_design_full,
  method = "REML",
  mods = ~ design - 1
)

cat("\n====================================================\n")
cat("DESIGN SET MODEL (DIRECT SUBGROUP ESTIMATES)\n")
cat("====================================================\n")
print(fit_design_set_full, digits = 3)

design_set_table <- data.frame(
  design = names(coef(fit_design_set_full)),
  g = as.numeric(coef(fit_design_set_full)),
  ci_lb = fit_design_set_full$ci.lb,
  ci_ub = fit_design_set_full$ci.ub,
  p_value = fit_design_set_full$pval
)

design_set_table$design <- gsub("^design", "", design_set_table$design)

cat("\nDirect subgroup estimates:\n")
print(design_set_table)

# 3) Merge subgroup estimates with n_studies and k_effect_sizes
design_report_table <- left_join(
  design_set_table,
  design_counts,
  by = "design"
)

cat("\n====================================================\n")
cat("FINAL DESIGN REPORT TABLE\n")
cat("====================================================\n")
print(design_report_table)

# 4) Standard reference-group moderator model
fit_design_mod_full <- metafor::rma.mv(
  yi = yi,
  V = vi,
  mods = ~ factor(design),
  random = ~ 1 | study_id/effect_id,
  data = dat_design_full,
  method = "REML"
)

cat("\n====================================================\n")
cat("DESIGN MODERATOR MODEL\n")
cat("====================================================\n")
print(fit_design_mod_full, digits = 3)

cat("\nRobust coefficient test:\n")
rob_design <- clubSandwich::coef_test(
  fit_design_mod_full,
  vcov = "CR2",
  test = "Satterthwaite"
)
print(rob_design)

# 5) Robust omnibus F test
cat("\n====================================================\n")
cat("ROBUST OMNIBUS F TEST FOR DESIGN\n")
cat("====================================================\n")

W_design <- clubSandwich::Wald_test(
  fit_design_mod_full,
  constraints = clubSandwich::constrain_zero(2:length(coef(fit_design_mod_full))),
  vcov = "CR2",
  test = "HTZ"
)

print(W_design)

# Extract robust F values safely
F_value <- if ("Fstat" %in% names(W_design)) W_design$Fstat else if ("F" %in% names(W_design)) W_design$F else NA
df_num  <- if ("df_num" %in% names(W_design)) W_design$df_num else if ("df" %in% names(W_design)) W_design$df else NA
df_denom <- if ("df_denom" %in% names(W_design)) W_design$df_denom else if ("den_df" %in% names(W_design)) W_design$den_df else NA
p_value <- if ("p_val" %in% names(W_design)) W_design$p_val else if ("p" %in% names(W_design)) W_design$p else NA

cat(
  "\nFinal omnibus F format:\n",
  "F(",
  round(df_num, 2), ", ",
  round(df_denom, 2), ") = ",
  round(F_value, 3),
  ", p = ",
  format.pval(p_value, digits = 3),
  "\n",
  sep = ""
)
