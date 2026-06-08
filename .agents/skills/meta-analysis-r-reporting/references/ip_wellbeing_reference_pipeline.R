############################################################
# Meta-analysis pipeline for IP × psychological outcomes
# (FINAL naming + single-pass logic)
#
# Naming (stable 3-stage):
#   1) dat_domain_full   = FULL base (after all cleaning + coding)
#   2) dat_domain_clean  = FULL minus influential effects (computed once)
#   3) dat_domain_use    = downstream dataset chosen by toggle
#
# Guarantees:
# - FULL is created once
# - Influence diagnostics run once (on FULL domain model)
# - CLEAN is created once (based on influence flags)
# - USE is ALWAYS controlled by EXCLUDE_INFLUENTIAL
############################################################

library(readxl)
library(metafor)
library(dplyr)
library(stringr)
library(clubSandwich)
library(tidyr)
library(ggplot2)

############################################################
# A. USER SWITCHES (IMPORTANT)
############################################################

# If TRUE: all downstream analyses use dat_domain_clean (influence-excluded)
# If FALSE: all downstream analyses use dat_domain_full
EXCLUDE_INFLUENTIAL <- FALSE

# Influence thresholds
COOK_RULE_4_OVER_K <- FALSE # if TRUE: Cook cutoff = 4/k (k = number of effects in the fitted model)
DFBETAS_CUT        <- 1       # abs(DFBETAS) > 1 flags

############################################################
# 0. Read data
############################################################

dat_raw <- read_excel("C:/Users/Hana/Desktop/IP/IP and wellbeing/Study1/R/(calculated 4) table.xlsx")

############################################################
# 0.1 Ensure that all key columns exist (create as NA if missing)
############################################################

cols_needed <- c(
  # Basic study information
  "study_title",
  "study_id",
  "apa_citation",
  "year",
  "country",
  "region",
  "discipline",
  "subject",
  
  # Sample and effect information
  "N",
  "effect_type",
  "effect_method",
  "effect_size",
  "effect_size_original",
  "df1",
  "df2",
  "ci_low",
  "ci_high",
  
  # Construct and measurement information
  "measure_IP",
  "sample_type",
  "white_proportion",
  "study_design",
  "age_mean",
  "age_sd",
  "measurement_language",
  "measure_questionairs",
  "construct_outcome",
  "construct_subcategory",
  "construct_category",
  "gender_proportion",
  "gender_majority",
  "educational_stage",
  "cultural_cluster",
  "measurement_reliability_IP",
  "measurement_reliability_outcome",
  "effect_direction",
  "Journal_source",
  
  # Risk of Bias
  "rob1",
  "rob_item01",
  "rob_item02",
  "rob_item04",
  "rob_item06",
  "rob_item16"
)

missing_cols <- setdiff(cols_needed, names(dat_raw))
if (length(missing_cols) > 0) {
  dat_raw[missing_cols] <- NA
}

############################################################
# 0.2 Replace NA-like strings with true NA (character columns only)
############################################################

to_na <- c("NA","N/A","NR",""," ")
dat_raw <- dat_raw %>%
  mutate(
    across(where(is.character), ~{
      x <- trimws(.x)
      ifelse(x %in% to_na, NA, x)
    })
  )

############################################################
# 0.3 Ensure effect_id exists
############################################################

if (!"effect_id" %in% names(dat_raw)) {
  dat_raw <- dat_raw %>% mutate(effect_id = dplyr::row_number())
}

############################################################
# 1. Basic numeric conversion
############################################################

num_cols <- c(
  "N","effect_size","effect_size_original","df1","df2","ci_low","ci_high",
  "age_mean","age_sd","gender_proportion",
  "rob_item01","rob_item02","rob_item04","rob_item06","rob_item16"
)

dat_clean <- dat_raw %>%
  mutate(across(all_of(num_cols), ~ suppressWarnings(as.numeric(.x))))

############################################################
# 2. Convert original statistics to Pearson r (index assignment)
# - Truly only computes within eligible rows
# - Robust to missing columns (e.g., N/df1/df2/ci_low/ci_high)
############################################################

# --- helper: safe numeric column (creates if missing) ---
safe_num_col <- function(dat, col) {
  if (!col %in% names(dat)) {
    dat[[col]] <- NA_real_
  }
  suppressWarnings(as.numeric(dat[[col]]))
}

# create numeric helpers (always created)
dat_clean$effect_size_num <- safe_num_col(dat_clean, "effect_size")
dat_clean$eso_num         <- safe_num_col(dat_clean, "effect_size_original")
dat_clean$N_num           <- safe_num_col(dat_clean, "N")
dat_clean$df1_num         <- safe_num_col(dat_clean, "df1")
dat_clean$df2_num         <- safe_num_col(dat_clean, "df2")
dat_clean$ci_low_num      <- safe_num_col(dat_clean, "ci_low")
dat_clean$ci_high_num     <- safe_num_col(dat_clean, "ci_high")

# initialize output
dat_clean$es_r <- NA_real_

# -------------------------
# 1) already r
# -------------------------
idx <- dat_clean$effect_type %in% c("r_Pearson", "r_Spearman") &
  !is.na(dat_clean$effect_size_num)
dat_clean$es_r[idx] <- dat_clean$effect_size_num[idx]

# -------------------------
# 2) latent_r, phi_coefficient treated as r
# -------------------------
idx <- dat_clean$effect_type %in% c("latent_r", "phi_coefficient") &
  !is.na(dat_clean$eso_num)
dat_clean$es_r[idx] <- dat_clean$eso_num[idx]

# -------------------------
# 3) Kendall's tau -> r
# -------------------------
idx <- dat_clean$effect_type == "kendalls_tau" &
  !is.na(dat_clean$eso_num)
dat_clean$es_r[idx] <- sin(pi * dat_clean$eso_num[idx] / 2)

# -------------------------
# 4) std_beta treated as r
# -------------------------
idx <- dat_clean$effect_type == "std_beta" &
  !is.na(dat_clean$eso_num)
dat_clean$es_r[idx] <- dat_clean$eso_num[idx]

# -------------------------
# 5) unstd_beta + CI -> partial r (needs df2)
# -------------------------
idx <- dat_clean$effect_type == "unstd_beta" &
  !is.na(dat_clean$eso_num) &
  !is.na(dat_clean$ci_low_num) & !is.na(dat_clean$ci_high_num) &
  !is.na(dat_clean$df2_num) & dat_clean$df2_num > 0

if (any(idx)) {
  se_unstd <- (dat_clean$ci_high_num[idx] - dat_clean$ci_low_num[idx]) / (2 * 1.96)
  ok <- !is.na(se_unstd) & is.finite(se_unstd) & se_unstd > 0
  
  idx2 <- which(idx)[ok]
  if (length(idx2) > 0) {
    t_unstd <- dat_clean$eso_num[idx2] / se_unstd[ok]
    dat_clean$es_r[idx2] <- sign(t_unstd) * sqrt(t_unstd^2 / (t_unstd^2 + dat_clean$df2_num[idx2]))
  }
}

# -------------------------
# 6) t_value -> r (needs df2)
# -------------------------
idx <- dat_clean$effect_type == "t_value" &
  !is.na(dat_clean$eso_num) &
  !is.na(dat_clean$df2_num) & dat_clean$df2_num > 0

if (any(idx)) {
  tval <- dat_clean$eso_num[idx]
  df2v <- dat_clean$df2_num[idx]
  dat_clean$es_r[idx] <- tval / sqrt(tval^2 + df2v)
}

# -------------------------
# 7) f_test -> r
# -------------------------
idx_base <- dat_clean$effect_type == "f_test" &
  !is.na(dat_clean$eso_num) &
  !is.na(dat_clean$df1_num) &
  !is.na(dat_clean$df2_num) &
  dat_clean$df2_num > 0 &
  is.finite(dat_clean$eso_num) &
  dat_clean$eso_num >= 0

idx1 <- idx_base & dat_clean$df1_num == 1
if (any(idx1)) {
  Fv  <- dat_clean$eso_num[idx1]
  df2 <- dat_clean$df2_num[idx1]
  dat_clean$es_r[idx1] <- sqrt(pmax(Fv / (Fv + df2), 0))
}

idxm <- idx_base & dat_clean$df1_num > 1
if (any(idxm)) {
  Fv  <- dat_clean$eso_num[idxm]
  df1 <- dat_clean$df1_num[idxm]
  df2 <- dat_clean$df2_num[idxm]
  dat_clean$es_r[idxm] <- sqrt(pmax((Fv * df1) / (Fv * df1 + df2), 0))
}

# -------------------------
# 8) odds_ratio -> d -> r
# -------------------------
idx <- dat_clean$effect_type == "odds_ratio" &
  !is.na(dat_clean$eso_num) &
  is.finite(dat_clean$eso_num) &
  dat_clean$eso_num > 0

if (any(idx)) {
  log_or <- log(dat_clean$eso_num[idx])
  d_or   <- log_or * sqrt(3) / pi
  dat_clean$es_r[idx] <- d_or / sqrt(d_or^2 + 4)
}

# -------------------------
# 9) prevalence_ratio -> d -> r
# -------------------------
idx <- dat_clean$effect_type == "prevalence_ratio" &
  !is.na(dat_clean$eso_num) &
  is.finite(dat_clean$eso_num) &
  dat_clean$eso_num > 0

if (any(idx)) {
  log_pr <- log(dat_clean$eso_num[idx])
  d_pr   <- log_pr * sqrt(3) / pi
  dat_clean$es_r[idx] <- d_pr / sqrt(d_pr^2 + 4)
}

# -------------------------
# 10) chi-square -> Cramer's V -> r
# (df1==2 -> min_dim=1; df1==4 -> min_dim=2)
# -------------------------
idx_base <- dat_clean$effect_type == "chi-square" &
  !is.na(dat_clean$eso_num) &
  !is.na(dat_clean$N_num) & dat_clean$N_num > 0 &
  !is.na(dat_clean$df1_num) &
  is.finite(dat_clean$eso_num) &
  dat_clean$eso_num >= 0

if (any(idx_base)) {
  md <- rep(NA_real_, sum(idx_base))
  df1v <- dat_clean$df1_num[idx_base]
  md[df1v == 2] <- 1
  md[df1v == 4] <- 2
  
  ok <- !is.na(md) & md > 0
  idx2 <- which(idx_base)[ok]
  if (length(idx2) > 0) {
    chi <- dat_clean$eso_num[idx2]
    Nn  <- dat_clean$N_num[idx2]
    dat_clean$es_r[idx2] <- sqrt(chi / (Nn * md[ok]))
  }
}

# -------------------------
# 11) Cohen's d -> r
# -------------------------
idx <- dat_clean$effect_type == "cohens_d" &
  !is.na(dat_clean$eso_num)

if (any(idx)) {
  d <- dat_clean$eso_num[idx]
  dat_clean$es_r[idx] <- d / sqrt(d^2 + 4)
}

# -------------------------
# cleanup (won't error if you use any_of)
# -------------------------
dat_clean <- dat_clean %>%
  dplyr::select(-dplyr::any_of(c(
    "effect_size_num","eso_num","N_num","df1_num","df2_num","ci_low_num","ci_high_num"
  )))

############################################################
# 3. Remove rows with missing N or r and check r in (-1, 1)
############################################################

dat_clean <- dat_clean %>%
  filter(!is.na(N)) %>%
  filter(!is.na(es_r)) %>%
  mutate(r_out_of_range = abs(es_r) >= 1)

invalid_r_rows <- dat_clean %>% filter(r_out_of_range)
if (nrow(invalid_r_rows) > 0) {
  message("Rows with r outside (-1, 1) will be removed:")
  print(invalid_r_rows[, c("study_id","effect_id","es_r")])
}

dat_clean <- dat_clean %>%
  filter(!r_out_of_range | is.na(r_out_of_range)) %>%
  filter(N > 3)

############################################################
# 4. Compute Fisher's z (yi) and sampling variance (vi)
############################################################

dat_clean <- dat_clean %>%
  mutate(
    yi = atanh(es_r),
    vi = 1 / (N - 3)
  )

############################################################
# 5. Unified merge within-study by measure_questionairs
#    (restricted to selected studies only)
############################################################

study_ids_sumN <- c(
  "Kumar2006","Cokley2015","Robinson2025","Pákozdy2024","Blondeau2018",
  "Cokley2013","Henning1998","Cokley2017","Holden2021"
)
study_ids_maxN <- c("Liu2023","Kolligian1991_S1")
study_ids_merge <- c(study_ids_sumN, study_ids_maxN)

dat_cand <- dat_clean %>%
  filter(
    study_id %in% study_ids_merge,
    !is.na(measure_questionairs),
    !is.na(N), N > 3,
    !is.na(es_r)
  ) %>%
  mutate(
    w        = pmax(N - 3, 1),
    gp_num   = gender_proportion,
    female_n = ifelse(is.na(gp_num), NA_real_, gp_num * N)
  )

if (nrow(dat_cand) > 0) {
  
  cell_tbl <- dat_cand %>%
    count(study_id, measure_questionairs, name = "k_rows") %>%
    filter(k_rows >= 2) %>%
    mutate(
      n_rule = case_when(
        study_id %in% study_ids_sumN ~ "sum",
        study_id %in% study_ids_maxN ~ "max",
        TRUE                         ~ "max"
      )
    )
  
  if (nrow(cell_tbl) > 0) {
    
    dat_to_merge <- dat_cand %>%
      inner_join(cell_tbl %>% select(study_id, measure_questionairs, n_rule),
                 by = c("study_id","measure_questionairs"))
    
    merged_vals <- dat_to_merge %>%
      group_by(study_id, measure_questionairs) %>%
      summarise(
        n_rule_group = first(n_rule),
        
        # merge r on z scale
        z_combined  = stats::weighted.mean(atanh(es_r), w = w, na.rm = TRUE),
        es_r_merged = tanh(z_combined),
        
        # N sum/max
        N_sum = sum(N, na.rm = TRUE),
        N_max = max(N, na.rm = TRUE),
        
        # gender
        female_total_sum = if (!all(is.na(female_n))) sum(female_n, na.rm = TRUE) else NA_real_,
        gp_weighted      = if (all(is.na(gp_num))) NA_real_
        else stats::weighted.mean(gp_num, w = N, na.rm = TRUE),
        
        .groups = "drop"
      ) %>%
      mutate(
        N_out = ifelse(n_rule_group == "sum", N_sum, N_max),
        yi_merged = atanh(es_r_merged),
        vi_merged = 1 / pmax(N_out - 3, 1),
        
        gender_prop_new = ifelse(
          n_rule_group == "sum",
          ifelse(is.na(female_total_sum), NA_real_, female_total_sum / N_out),
          gp_weighted
        ),
        gender_majority_new = case_when(
          is.na(gender_prop_new) ~ NA_character_,
          gender_prop_new > 0.5  ~ "female",
          gender_prop_new < 0.5  ~ "male",
          TRUE                   ~ "balanced"
        )
      )
    
    template_rows <- dat_to_merge %>%
      group_by(study_id, measure_questionairs) %>%
      slice(1) %>%
      ungroup() %>%
      select(-w, -gp_num, -female_n)
    
    merged_rows <- template_rows %>%
      left_join(merged_vals, by = c("study_id","measure_questionairs")) %>%
      mutate(
        N                 = N_out,
        es_r              = es_r_merged,
        yi                = yi_merged,
        vi                = vi_merged,
        gender_proportion = gender_prop_new,
        gender_majority   = gender_majority_new
      ) %>%
      select(all_of(colnames(dat_clean)))
    
    dat_clean <- dat_clean %>%
      anti_join(dat_to_merge %>% select(study_id, effect_id),
                by = c("study_id","effect_id")) %>%
      bind_rows(merged_rows)
  }
}

############################################################
# 5.8 Create study labels and final analysis dataset 'dat'
############################################################

dat_clean <- dat_clean %>%
  mutate(
    slab = case_when(
      !is.na(apa_citation) ~ as.character(apa_citation),
      !is.na(study_title) & !is.na(year) ~ paste0(study_title," (",year,")"),
      !is.na(study_title) ~ as.character(study_title),
      TRUE ~ paste0("Study_", dplyr::row_number())
    ),
    study_id  = as.factor(study_id),
    effect_id = as.factor(effect_id)
  )

dat <- dat_clean %>%
  select(
    study_id, effect_id, slab, N, es_r, yi, vi, everything()
  )

cat("Number of usable effect sizes k =", nrow(dat), "\n")

############################################################
# 6. Prepare constructs and risk-direction coding
############################################################

dat$construct_category    <- as.character(dat$construct_category)
dat$construct_outcome     <- as.character(dat$construct_outcome)
dat$construct_subcategory <- as.character(dat$construct_subcategory)

# Ensure optional helper columns exist
if (!"domain_psych"    %in% names(dat)) dat$domain_psych    <- NA_character_
if (!"func_adaptivity" %in% names(dat)) dat$func_adaptivity <- NA_character_
if (!"health_valence"  %in% names(dat)) dat$health_valence  <- NA_character_

dat <- dat %>%
  mutate(
    domain_psych_chr    = tolower(trimws(as.character(domain_psych))),
    func_adaptivity_chr = tolower(trimws(as.character(func_adaptivity))),
    health_valence_chr  = tolower(trimws(as.character(health_valence))),
    
    dom_raw = tolower(trimws(as.character(construct_category))),
    sub_raw = tolower(trimws(as.character(construct_subcategory))),
    
    domain_psych = dplyr::coalesce(
      domain_psych_chr,
      dplyr::case_when(
        grepl("health",   dom_raw) ~ "psychological_health",
        grepl("function", dom_raw) ~ "psychological_functioning",
        TRUE ~ NA_character_
      )
    ),
    
    func_adaptivity = dplyr::coalesce(
      func_adaptivity_chr,
      dplyr::case_when(
        grepl("maladaptive", sub_raw) ~ "maladaptive_functioning",
        grepl("adaptive",    sub_raw) ~ "adaptive_functioning",
        TRUE ~ NA_character_
      )
    ),
    
    health_valence = dplyr::coalesce(
      health_valence_chr,
      dplyr::case_when(
        grepl("well", sub_raw) ~ "wellbeing",
        grepl("ill",  sub_raw) ~ "illbeing",
        TRUE ~ NA_character_
      )
    )
  ) %>%
  mutate(
    domain_psych    = factor(domain_psych,
                             levels = c("psychological_health","psychological_functioning")),
    func_adaptivity = factor(func_adaptivity,
                             levels = c("adaptive_functioning","maladaptive_functioning")),
    health_valence  = factor(health_valence,
                             levels = c("wellbeing","illbeing"))
  )

table(dat$domain_psych,    useNA = "ifany")
table(dat$func_adaptivity, useNA = "ifany")
table(dat$health_valence,  useNA = "ifany")

############################################################
# 6.2 Create unified risk-direction effect: yi_risk, vi_risk
############################################################

dat <- dat %>%
  mutate(
    good_higher = dplyr::case_when(
      domain_psych == "psychological_health" &
        health_valence == "wellbeing" ~ 1L,
      domain_psych == "psychological_health" &
        health_valence == "illbeing"  ~ 0L,
      domain_psych == "psychological_functioning" &
        func_adaptivity == "adaptive_functioning" ~ 1L,
      domain_psych == "psychological_functioning" &
        func_adaptivity == "maladaptive_functioning" ~ 0L,
      TRUE ~ NA_integer_
    ),
    yi_risk = dplyr::case_when(
      good_higher == 1L ~ yi,
      good_higher == 0L ~ -yi,
      TRUE ~ NA_real_
    ),
    vi_risk = vi
  )

table(dat$good_higher, useNA = "ifany")

############################################################
# Overall meta-analytic model (all psychological outcomes)
############################################################

dat_overall_use <- dat %>%
  dplyr::mutate(
    yi_risk_use = dplyr::if_else(is.na(yi_risk), yi, yi_risk),
    vi_risk_use = dplyr::if_else(is.na(vi_risk), vi, vi_risk)
  )

res_overall <- metafor::rma.mv(
  yi     = yi_risk_use,
  V      = vi_risk_use,
  random = ~ 1 | study_id/effect_id,
  data   = dat_overall_use,
  method = "REML"
)
summary(res_overall)

overall_r <- predict(res_overall, transf = transf.ztor, digits = 3)
overall_r

############################################################
# 6.3 Keep only the two psychological domains (FULL base)
# ---> dat_domain_full (created ONCE)
############################################################

dat_domain_full <- dat %>%
  dplyr::filter(domain_psych %in% c("psychological_health","psychological_functioning")) %>%
  dplyr::filter(!is.na(yi_risk), !is.na(vi_risk), vi_risk > 0) %>%
  droplevels()

table(dat_domain_full$domain_psych, useNA = "ifany")

############################################################
# 6.5 Multi-level I² (helper)  -- for rma.mv
############################################################

compute_ml_I2 <- function(res, dat_effects, vi_col = "vi_risk") {
  
  if (!inherits(res, "rma.mv")) stop("res must be an rma.mv object.")
  if (!is.data.frame(dat_effects)) stop("dat_effects must be a data.frame.")
  if (!vi_col %in% names(dat_effects)) {
    stop("Column '", vi_col, "' not found in dat_effects.")
  }
  
  # sigma2 order follows the order of random terms in rma.mv
  sigma2 <- res$sigma2
  if (length(sigma2) < 1) stop("No variance components found in res$sigma2.")
  
  # Common 3-level: sigma2[1]=between-study, sigma2[2]=within-study (effect)
  tau2_L2 <- sigma2[1]
  tau2_L3 <- ifelse(length(sigma2) > 1, sigma2[2], 0)
  
  V_bar <- mean(dat_effects[[vi_col]], na.rm = TRUE)
  
  denom <- tau2_L2 + tau2_L3 + V_bar
  if (!is.finite(denom) || denom <= 0) {
    stop("Invalid denominator when computing I2. Check tau2 and vi.")
  }
  
  I2_total <- (tau2_L2 + tau2_L3) / denom
  I2_L2    <- tau2_L2 / denom
  I2_L3    <- tau2_L3 / denom
  
  list(
    Q                = res$QE,
    Q_df             = res$k - res$p,
    Q_p              = res$QEp,
    I2_total         = I2_total,
    I2_between_study = I2_L2,
    I2_within_study  = I2_L3,
    V_bar            = V_bar,
    tau2_L2          = tau2_L2,
    tau2_L3          = tau2_L3
  )
}

############################################################
# 6.6 Influence diagnostics (single-pass, effect-level LOO)
############################################################

# ---- Global knobs (define once earlier; keep your existing ones) ----
# EXCLUDE_INFLUENTIAL <- FALSE
# COOK_RULE_4_OVER_K  <- FALSE
# DFBETAS_CUT         <- 1

# Add this if you didn't define it earlier:
# If TRUE: run influence and PRINT results even if not excluding
if (!exists("PRINT_INFLUENCE", inherits = TRUE)) PRINT_INFLUENCE <- FALSE


############################################################
# 6.6.1 Influence core: leave-one-EFFECT-out for rma.mv
############################################################

get_influence_flags_mvLOO_effect <- function(dat_used,
                                             mods,
                                             random,
                                             method = "REML",
                                             dfbetas_cut = 1,
                                             use_cook_4_over_k = TRUE,
                                             verbose_every = 25) {
  
  if (!requireNamespace("metafor", quietly = TRUE)) stop("Package 'metafor' is required.")
  if (!requireNamespace("dplyr", quietly = TRUE))   stop("Package 'dplyr' is required.")
  if (!requireNamespace("MASS", quietly = TRUE))    stop("Package 'MASS' is required (for ginv).")
  
  if (!is.data.frame(dat_used)) stop("dat_used must be a data.frame.")
  if (!("yi_risk" %in% names(dat_used))) stop("dat_used must contain 'yi_risk'.")
  if (!("vi_risk" %in% names(dat_used))) stop("dat_used must contain 'vi_risk'.")
  
  # stable row id
  dat_used <- dat_used %>%
    dplyr::mutate(.row_id__ = dplyr::row_number())
  
  # FULL model (fit once)
  res_full <- metafor::rma.mv(
    yi     = yi_risk,
    V      = vi_risk,
    mods   = mods,
    random = random,
    data   = dat_used,
    method = method
  )
  
  b_full  <- as.numeric(metafor::coef.rma(res_full))
  V_full  <- try(metafor::vcov.rma(res_full), silent = TRUE)
  if (inherits(V_full, "try-error")) stop("vcov(res_full) failed.")
  
  se_full <- sqrt(diag(V_full))
  se_full <- pmax(se_full, 1e-12)
  
  p <- length(b_full)
  if (p < 1) stop("No coefficients found in FULL model.")
  
  cook_cut <- NA_real_
  if (isTRUE(use_cook_4_over_k) && is.finite(res_full$k) && res_full$k > 0) {
    cook_cut <- 4 / res_full$k
  }
  
  V_inv <- try(solve(V_full), silent = TRUE)
  if (inherits(V_inv, "try-error")) {
    V_inv <- try(MASS::ginv(V_full), silent = TRUE)
    if (inherits(V_inv, "try-error")) stop("Cannot invert vcov matrix (solve & ginv failed).")
  }
  
  k <- nrow(dat_used)
  cook_eff   <- rep(NA_real_, k)
  maxabs_dfb <- rep(NA_real_, k)
  
  skipped_fit_fail   <- 0L
  skipped_len_change <- 0L
  skipped_too_small  <- 0L
  
  for (i in seq_len(k)) {
    if (!is.null(verbose_every) && verbose_every > 0 && (i %% verbose_every == 0)) {
      message("LOO (effect-level): ", i, " / ", k)
    }
    
    dat_loo <- dat_used[dat_used$.row_id__ != i, , drop = FALSE]
    if (nrow(dat_loo) < 3) {
      skipped_too_small <- skipped_too_small + 1L
      next
    }
    
    res_loo <- try(
      metafor::rma.mv(
        yi     = yi_risk,
        V      = vi_risk,
        mods   = mods,
        random = random,
        data   = dat_loo,
        method = method
      ),
      silent = TRUE
    )
    if (inherits(res_loo, "try-error")) {
      skipped_fit_fail <- skipped_fit_fail + 1L
      next
    }
    
    b_loo <- as.numeric(metafor::coef.rma(res_loo))
    if (length(b_loo) != p) {
      skipped_len_change <- skipped_len_change + 1L
      next
    }
    
    delta <- b_full - b_loo
    
    dfb_vec <- delta / se_full
    maxabs_dfb[i] <- max(abs(dfb_vec), na.rm = TRUE)
    
    cook_eff[i] <- as.numeric(t(delta) %*% V_inv %*% delta)
  }
  
  cook_flag <- rep(FALSE, k)
  if (!is.na(cook_cut)) cook_flag <- !is.na(cook_eff) & (cook_eff > cook_cut)
  
  dfb_flag <- !is.na(maxabs_dfb) & (maxabs_dfb > dfbetas_cut)
  
  idx_any <- which(cook_flag | dfb_flag)
  
  flagged_table <- dat_used %>%
    dplyr::mutate(
      cooks_d     = cook_eff,
      cook_cut    = cook_cut,
      cook_flag   = cook_flag,
      max_abs_dfb = maxabs_dfb,
      dfb_cut     = dfbetas_cut,
      dfb_flag    = dfb_flag,
      flagged_any = cook_flag | dfb_flag
    ) %>%
    dplyr::select(-.row_id__)
  
  summary_list <- list(
    k_effects          = k,
    p_coef             = p,
    cook_cut           = cook_cut,
    dfbetas_cut        = dfbetas_cut,
    flagged_n_any      = length(idx_any),
    flagged_prop_any   = length(idx_any) / k,
    cooks_na_n         = sum(is.na(cook_eff)),
    dfbetas_na_n       = sum(is.na(maxabs_dfb)),
    skipped_fit_fail   = skipped_fit_fail,
    skipped_len_change = skipped_len_change,
    skipped_too_small  = skipped_too_small
  )
  
  list(
    res_full      = res_full,
    cook_cut      = cook_cut,
    dfbetas_cut   = dfbetas_cut,
    flagged_table = flagged_table,
    idx_any       = idx_any,
    summary       = summary_list
  )
}


############################################################
# 6.6.2 Run influence ONLY if needed (single-pass switch)
############################################################

run_influence_if_needed <- function(dat_used,
                                    mods,
                                    random,
                                    method = "REML",
                                    verbose_every = 25,
                                    PRINT_INFLUENCE = FALSE) {
  
  need_run <- isTRUE(EXCLUDE_INFLUENTIAL) || isTRUE(PRINT_INFLUENCE)
  
  if (!need_run) {
    return(list(
      ran_influence = FALSE,
      res_full      = NULL,
      flagged_table = NULL,
      idx_any       = integer(0),
      cook_cut      = NA_real_,
      dfbetas_cut   = DFBETAS_CUT,
      summary       = NULL
    ))
  }
  
  infl <- get_influence_flags_mvLOO_effect(
    dat_used          = dat_used,
    mods              = mods,
    random            = random,
    method            = method,
    dfbetas_cut       = DFBETAS_CUT,
    use_cook_4_over_k = COOK_RULE_4_OVER_K,
    verbose_every     = verbose_every
  )
  infl$ran_influence <- TRUE
  
  if (isTRUE(PRINT_INFLUENCE)) {
    cat("\n================ Influence Diagnostics (MV LOO; EFFECT-level) ================\n")
    cat("k (effects) in model:", infl$res_full$k, "\n")
    cat("Cook's cutoff used  :", infl$cook_cut, "\n")
    cat("DFBETAS cut used    :", infl$dfbetas_cut, "\n")
    cat("Flagged effects (any):", length(infl$idx_any), "\n")
    cat("=============================================================================\n\n")
    
    if (length(infl$idx_any) > 0) {
      flagged_show <- infl$flagged_table %>%
        dplyr::filter(flagged_any) %>%
        dplyr::select(study_id, effect_id, domain_psych, cooks_d, max_abs_dfb, cook_flag, dfb_flag) %>%
        dplyr::arrange(dplyr::desc(cooks_d))
      print(flagged_show)
    }
  }
  
  infl
}

############################################################
# 6.6.3 Apply exclusion (only when EXCLUDE_INFLUENTIAL == TRUE)
############################################################

apply_influence_exclusion <- function(infl_obj) {
  if (is.null(infl_obj) || !isTRUE(infl_obj$ran_influence)) return(NULL)
  if (!isTRUE(EXCLUDE_INFLUENTIAL)) return(NULL)
  if (is.null(infl_obj$flagged_table)) return(NULL)
  
  dat_clean <- infl_obj$flagged_table
  if (length(infl_obj$idx_any) > 0) {
    dat_clean <- infl_obj$flagged_table %>%
      dplyr::filter(!flagged_any)
  }
  dat_clean
}


############################################################
# 6.6.4 Build FULL / (optional) CLEAN / USED  (single-pass)
############################################################

dat_dom_full <- dat_domain_full %>%
  dplyr::filter(!is.na(domain_psych)) %>%
  droplevels()

dat_dom_full$domain_psych <- stats::relevel(dat_dom_full$domain_psych,
                                            ref = "psychological_health")

infl_domain <- run_influence_if_needed(
  dat_used        = dat_dom_full,
  mods            = ~ domain_psych,
  random          = ~ 1 | study_id/effect_id,
  method          = "REML",
  verbose_every   = 25,
  PRINT_INFLUENCE = PRINT_INFLUENCE
)

dat_domain_clean <- apply_influence_exclusion(infl_domain)

dat_domain_use <- if (isTRUE(EXCLUDE_INFLUENTIAL) && !is.null(dat_domain_clean)) {
  dat_domain_clean
} else {
  dat_dom_full
}

cat("\n================ Dataset Choice (Domain) ================\n")
cat("EXCLUDE_INFLUENTIAL =", EXCLUDE_INFLUENTIAL, "\n")
cat("PRINT_INFLUENCE     =", PRINT_INFLUENCE, "\n")
cat("N effects (FULL)    =", nrow(dat_dom_full), "\n")
cat("N effects (CLEAN)   =", ifelse(is.null(dat_domain_clean), NA_integer_, nrow(dat_domain_clean)), "\n")
cat("N effects (USED)    =", nrow(dat_domain_use), "\n")
cat("=========================================================\n\n")


############################################################
# 6.7 Domain-level models on USED data (CR2 cluster-robust)
############################################################

# Domain moderator model (USED data)
dat_domain_use$domain_psych <- stats::relevel(dat_domain_use$domain_psych, ref = "psychological_health")

res_domain_use <- metafor::rma.mv(
  yi     = yi_risk,
  V      = vi_risk,
  mods   = ~ domain_psych,
  random = ~ 1 | study_id/effect_id,
  data   = dat_domain_use,
  method = "REML"
)
summary(res_domain_use)

# CR2 coefficient tests
res_domain_use_cr2 <- clubSandwich::coef_test(
  res_domain_use,
  vcov    = "CR2",
  cluster = dat_domain_use$study_id
)
res_domain_use_cr2

# CR2 omnibus (moderator) test
b_names <- names(stats::coef(res_domain_use))
idx_mod <- which(!b_names %in% c("intrcpt","(Intercept)","Intercept"))
res_domain_use_omnibus_cr2 <- NULL
if (length(idx_mod) > 0) {
  L <- diag(length(b_names))[idx_mod, , drop = FALSE]
  res_domain_use_omnibus_cr2 <- clubSandwich::Wald_test(
    res_domain_use,
    constraints = L,
    vcov        = "CR2",
    cluster     = dat_domain_use$study_id
  )
}
res_domain_use_omnibus_cr2

# --- CR2 95% CI for each coefficient (robust to df column name differences)
cr2_tab <- as.data.frame(res_domain_use_cr2)
df_candidates <- c("df_Satt","df","df_satt","df_Satterthwaite","dfs","df_denom")
df_col <- df_candidates[df_candidates %in% names(cr2_tab)][1]

if (is.na(df_col) || length(df_col) == 0) {
  stop("No df column found in coef_test output. Available columns: ",
       paste(names(cr2_tab), collapse = ", "))
}

cr2_tab$df_num <- suppressWarnings(as.numeric(cr2_tab[[df_col]]))
cr2_tab$t_crit <- stats::qt(0.975, df = cr2_tab$df_num)
cr2_tab$CI_LB  <- cr2_tab$beta - cr2_tab$t_crit * cr2_tab$SE
cr2_tab$CI_UB  <- cr2_tab$beta + cr2_tab$t_crit * cr2_tab$SE
res_domain_use_cr2_ci <- cr2_tab
res_domain_use_cr2_ci

# No-intercept model: domain-specific pooled means (USED)
res_domain_means_use <- metafor::rma.mv(
  yi     = yi_risk,
  V      = vi_risk,
  mods   = ~ domain_psych - 1,
  random = ~ 1 | study_id/effect_id,
  data   = dat_domain_use,
  method = "REML"
)
summary(res_domain_means_use)

res_domain_means_use_cr2 <- clubSandwich::coef_test(
  res_domain_means_use,
  vcov    = "CR2",
  cluster = dat_domain_use$study_id
)
res_domain_means_use_cr2

dom_means_r_use <- metafor::transf.ztor(stats::coef(res_domain_means_use))
dom_means_r_use

# Multilevel I² (model-based)
het_domain_use <- compute_ml_I2(res_domain_use, dat_domain_use, vi_col = "vi_risk")
het_domain_use

############################################################
# 6.8 Domain-specific main models (health & functioning) + splits (USED)
############################################################

dat_health_use <- dat_domain_use %>%
  dplyr::filter(domain_psych == "psychological_health") %>%
  droplevels()

dat_functioning_use <- dat_domain_use %>%
  dplyr::filter(domain_psych == "psychological_functioning") %>%
  droplevels()

# 6.8.1 Psychological health: main 3-level model (USED)
res_health_use <- metafor::rma.mv(
  yi     = yi_risk,
  V      = vi_risk,
  random = ~ 1 | study_id/effect_id,
  data   = dat_health_use,
  method = "REML"
)
summary(res_health_use)

res_health_use_cr2 <- clubSandwich::coef_test(
  res_health_use,
  vcov    = "CR2",
  cluster = dat_health_use$study_id
)
res_health_use_cr2

overall_health_r_use <- predict(res_health_use, transf = transf.ztor, digits = 3)
overall_health_r_use

# 6.8.2 Psychological functioning: main 3-level model (USED)
res_functioning_use <- metafor::rma.mv(
  yi     = yi_risk,
  V      = vi_risk,
  random = ~ 1 | study_id/effect_id,
  data   = dat_functioning_use,
  method = "REML"
)
summary(res_functioning_use)

res_functioning_use_cr2 <- clubSandwich::coef_test(
  res_functioning_use,
  vcov    = "CR2",
  cluster = dat_functioning_use$study_id
)
res_functioning_use_cr2

overall_functioning_r_use <- predict(res_functioning_use, transf = transf.ztor, digits = 3)
overall_functioning_r_use

# 6.8.3 Multi-level I² within health & functioning (USED)
het_health_use      <- compute_ml_I2(res_health_use,      dat_health_use)
het_functioning_use <- compute_ml_I2(res_functioning_use, dat_functioning_use)

het_health_use
het_functioning_use

############################################################
# Helpers: collapse effects -> 1 per study_id (for forest plots)
############################################################

collapse_by_studyid <- function(dat_sub) {
  
  dat_sub <- dat_sub %>%
    mutate(study_key = as.character(study_id))
  
  dat_sub$study_key[is.na(dat_sub$study_key) | dat_sub$study_key == ""] <-
    paste0("Study_", which(is.na(dat_sub$study_key) | dat_sub$study_key == ""))
  
  dat_study <- dat_sub %>%
    filter(!is.na(study_key), !is.na(yi_risk), !is.na(vi_risk), vi_risk > 0) %>%
    group_by(study_key) %>%
    summarise(
      k_eff   = n(),
      yi_risk = sum(yi_risk / vi_risk) / sum(1 / vi_risk),
      vi_risk = 1 / sum(1 / vi_risk),
      .groups = "drop"
    ) %>%
    mutate(
      slab = ifelse(k_eff > 1, paste0(study_key," [k=",k_eff,"]"), study_key)
    )
  
  dat_study
}

collapse_by_studyid_raw <- function(dat_sub) {
  
  dat_sub <- dat_sub %>%
    dplyr::mutate(study_key = as.character(study_id))
  
  dat_sub$study_key[is.na(dat_sub$study_key) | dat_sub$study_key == ""] <-
    paste0("Study_", which(is.na(dat_sub$study_key) | dat_sub$study_key == ""))
  
  dat_study <- dat_sub %>%
    dplyr::filter(!is.na(study_key), !is.na(yi), !is.na(vi), vi > 0) %>%
    dplyr::group_by(study_key) %>%
    dplyr::summarise(
      k_eff = n(),
      yi    = sum(yi / vi) / sum(1 / vi),
      vi    = 1 / sum(1 / vi),
      .groups = "drop"
    ) %>%
    dplyr::mutate(
      slab = ifelse(k_eff > 1, paste0(study_key," [k=",k_eff,"]"), study_key)
    )
  
  dat_study
}

############################################################
# Build study-level datasets (one effect per study_id)
############################################################

# Health (risk-coded)
dat_health_study <- collapse_by_studyid(dat_health_use)
dat_health_study <- dat_health_study[order(dat_health_study$study_key), ]

# Functioning (risk-coded)
dat_functioning_study <- collapse_by_studyid(dat_functioning_use)
dat_functioning_study <- dat_functioning_study[order(dat_functioning_study$study_key), ]

# Fit study-level model (health)
res_health_study <- metafor::rma.uni(
  yi     = yi_risk,
  vi     = vi_risk,
  data   = dat_health_study,
  method = "REML"
)

res_functioning_study <- metafor::rma.uni(
  yi     = yi_risk,
  vi     = vi_risk,
  data   = dat_functioning_study,
  method = "REML"
)

############################################################
# Forest plots (USED; risk-coded) for health & functioning
############################################################

par(mar = c(4.5, 4.5, 2.5, 2))

ticks_r <- c(-0.5,-0.3,-0.1,0,0.1,0.3,0.5)
at_z    <- transf.rtoz(ticks_r)

tp_left  <- transf.rtoz(-0.8)
tp_right <- transf.rtoz( 0.8)
xlim_use <- c(tp_left - 0.15, tp_right + 0.15)

# Health: per study_id (USED; yi_risk)
k_health <- nrow(dat_health_study)
rows_h   <- k_health:1  # explicit rows used by forest()

forest(
  x       = dat_health_study$yi_risk,
  vi      = dat_health_study$vi_risk,
  slab    = dat_health_study$slab,
  xlab    = "Correlation (r)",
  transf  = transf.ztor,
  at      = at_z,
  xlim    = xlim_use,
  textpos = c(tp_left, tp_right),
  refline = 0,
  cex     = 0.25,
  
  # zebra stripes (alternating row shading)
  rows     = rows_h,
  shade    = rows_h[seq(2, k_health, by = 2)],  # every second row
  colshade = "grey95"
)

addpoly(
  res_health_study,
  transf = transf.ztor,
  row    = 0,
  mlab   = "Overall (psychological health; per study_id; USED)",
  col    = "red",
  border = "red",
  cex    = 0.30
)

# Functioning: per study_id (USED; yi_risk)
k_func <- nrow(dat_functioning_study)
rows_f <- k_func:1

forest(
  x       = dat_functioning_study$yi_risk,
  vi      = dat_functioning_study$vi_risk,
  slab    = dat_functioning_study$slab,
  xlab    = "Correlation (r)",
  transf  = transf.ztor,
  at      = at_z,
  xlim    = xlim_use,
  textpos = c(tp_left, tp_right),
  refline = 0,
  cex     = 0.25,
  
  # zebra stripes (alternating row shading)
  rows     = rows_f,
  shade    = rows_f[seq(2, k_func, by = 2)],
  colshade = "grey95"
)

addpoly(
  res_functioning_study,
  transf = transf.ztor,
  row    = 0,
  mlab   = "Overall (psychological functioning; per study_id; USED)",
  col    = "red",
  border = "red",
  cex    = 0.30
)

############################################################
# 6.9 Within functioning: adaptive vs maladaptive (USED; CR2)
# Outputs:
# - Counts: keffects + nstudies per subdomain
# - Moderator model: metafor summary + CR2 coef tests + CR2 omnibus F
# - No-intercept means model: pooled means per level + CR2
# - Subdomain main models: pooled r (CI + PI) + CR2 intercept + Q(df)
############################################################

# -----------------------------
# A) Prepare subdomain dataset
# -----------------------------
dat_func_adapt_use <- dat_functioning_use %>%
  dplyr::filter(!is.na(func_adaptivity)) %>%
  droplevels()

# Guard
if (nrow(dat_func_adapt_use) < 2) stop("Not enough effects in dat_func_adapt_use.")

# Set reference level (adaptive as reference)
dat_func_adapt_use$func_adaptivity <- stats::relevel(
  dat_func_adapt_use$func_adaptivity,
  ref = "adaptive_functioning"
)

# Print counts (effects + distinct studies)
cat("\n===============================\n")
cat("COUNTS (Functioning by Adaptivity)\n")
cat("===============================\n")

counts_func <- dat_func_adapt_use %>%
  dplyr::group_by(func_adaptivity) %>%
  dplyr::summarise(
    keffect_sizes = dplyr::n(),
    nstudies      = dplyr::n_distinct(study_id),
    .groups = "drop"
  )
print(counts_func)

# -----------------------------
# B) Moderator model: maladaptive vs adaptive (risk-coded)
# -----------------------------
cat("\n=============================================\n")
cat("MODERATOR MODEL (yi_risk; CR2 inference)\n")
cat("Moderator: maladaptive vs adaptive\n")
cat("=============================================\n")

res_func_use <- metafor::rma.mv(
  yi     = yi_risk,
  V      = vi_risk,
  mods   = ~ func_adaptivity,
  random = ~ 1 | study_id/effect_id,
  data   = dat_func_adapt_use,
  method = "REML"
)

cat("\n--- metafor::summary() ---\n")
print(summary(res_func_use))

cat("\n--- CR2 coefficient tests (clubSandwich::coef_test) ---\n")
res_func_use_CR2 <- clubSandwich::coef_test(
  res_func_use,
  vcov    = "CR2",
  cluster = dat_func_adapt_use$study_id
)
print(res_func_use_CR2)

# CR2 omnibus (Wald) test for moderator
cat("\n--- CR2 omnibus test (clubSandwich::Wald_test) ---\n")
b_names <- names(coef(res_func_use))
idx_mod <- which(!b_names %in% c("intrcpt","(Intercept)","Intercept"))
L <- diag(length(b_names))[idx_mod, , drop = FALSE]

res_func_use_omni_CR2 <- tryCatch(
  clubSandwich::Wald_test(
    res_func_use,
    constraints = L,
    vcov        = "CR2",
    cluster     = dat_func_adapt_use$study_id
  ),
  error = function(e) e
)
print(res_func_use_omni_CR2)

# Optional: sentence-ready CR2 omnibus line
if (inherits(res_func_use_omni_CR2, "data.frame")) {
  Fval <- res_func_use_omni_CR2$Fstat
  df1  <- res_func_use_omni_CR2$df_num
  df2  <- res_func_use_omni_CR2$df_denom
  pval <- res_func_use_omni_CR2$p_val
  
  cat(sprintf("\nCR2 omnibus (adaptivity): F(%s, %.2f) = %.2f, p %s\n",
              df1, df2, Fval,
              ifelse(pval < .001, "< .001", paste0("= ", sprintf("%.3f", pval)))))
}

# -----------------------------
# C) No-intercept means model: pooled mean per level
# -----------------------------
cat("\n=============================================\n")
cat("NO-INTERCEPT MEANS MODEL (yi_risk; CR2)\n")
cat("Pooled mean for each subdomain (adaptive/maladaptive)\n")
cat("=============================================\n")

res_func_means_use <- metafor::rma.mv(
  yi     = yi_risk,
  V      = vi_risk,
  mods   = ~ func_adaptivity - 1,
  random = ~ 1 | study_id/effect_id,
  data   = dat_func_adapt_use,
  method = "REML"
)

cat("\n--- metafor::summary() ---\n")
print(summary(res_func_means_use))

cat("\n--- CR2 coefficient tests (means model) ---\n")
res_func_means_use_CR2 <- clubSandwich::coef_test(
  res_func_means_use,
  vcov    = "CR2",
  cluster = dat_func_adapt_use$study_id
)
print(res_func_means_use_CR2)

# Pooled means: transform z -> r (risk-coded direction)
cat("\n--- Transformed pooled means (risk-coded; z->r) ---\n")
func_means_r_use <- metafor::transf.ztor(stats::coef(res_func_means_use))
print(func_means_r_use)

# IMPORTANT: predict() without newmods prints fitted values for every row.
# Provide newmods so we get exactly two rows (adaptive + maladaptive).
cat("\n--- Pooled r + 95% CI (risk-coded; via predict(newmods=...)) ---\n")
newdat <- data.frame(
  func_adaptivity = factor(c("adaptive_functioning","maladaptive_functioning"),
                           levels = levels(dat_func_adapt_use$func_adaptivity))
)
X_new <- model.matrix(~ func_adaptivity - 1, data = newdat)
pred_means <- predict(res_func_means_use, newmods = X_new, transf = transf.ztor, digits = 3)
print(cbind(level = newdat$func_adaptivity, pred_means))

# -----------------------------
# D) Subdomain main models: adaptive + maladaptive
#     + pooled r (CI + PI), CR2 intercept, Q(df), optional I2
# -----------------------------
cat("\n=============================================\n")
cat("SUBDOMAIN MAIN MODELS (yi_risk) + Q(df)\n")
cat("=============================================\n")

fit_and_print <- function(dat_sub, label) {
  
  if (nrow(dat_sub) < 2) {
    cat(sprintf("\n[%s] Not enough effects (n=%d). Skipping.\n", label, nrow(dat_sub)))
    return(invisible(NULL))
  }
  
  res_sub <- metafor::rma.mv(
    yi     = yi_risk,
    V      = vi_risk,
    random = ~ 1 | study_id/effect_id,
    data   = dat_sub,
    method = "REML"
  )
  
  cat(sprintf("\n--- %s: metafor::summary() ---\n", label))
  print(summary(res_sub))
  
  cat(sprintf("\n--- %s: pooled r (CI + PI) via predict() ---\n", label))
  pred_r <- predict(res_sub, transf = transf.ztor, digits = 3)
  print(pred_r)
  
  cat(sprintf("\n--- %s: CR2 intercept test ---\n", label))
  ct <- clubSandwich::coef_test(res_sub, vcov = "CR2", cluster = dat_sub$study_id)
  print(ct)
  
  # Heterogeneity Q(df) (metafor uses QE for rma.mv)
  Q_val <- res_sub$QE
  Q_df  <- res_sub$k - res_sub$p
  Q_p   <- res_sub$QEp
  cat(sprintf("\n--- %s: heterogeneity ---\n", label))
  cat(sprintf("Q(%d) = %.2f, p %s\n",
              Q_df, Q_val,
              ifelse(Q_p < .001, "< .001", paste0("= ", sprintf("%.3f", Q_p)))))
  
  # Optional: model-based multilevel I2 if helper exists
  if (exists("compute_ml_I2", inherits = TRUE)) {
    het <- compute_ml_I2(res_sub, dat_sub, vi_col = "vi_risk")
    cat(sprintf("\n--- %s: model-based multilevel I2 ---\n", label))
    cat(sprintf("I2_total=%.3f | I2_between=%.3f | I2_within=%.3f\n",
                het$I2_total, het$I2_between_study, het$I2_within_study))
  }
  
  invisible(list(res = res_sub, pred = pred_r, cr2 = ct))
}

# Adaptive subset
dat_func_adapt_only_use <- dat_func_adapt_use %>%
  dplyr::filter(func_adaptivity == "adaptive_functioning") %>%
  droplevels()

cat(sprintf("\nAdaptive subset: nstudies=%d, keffects=%d\n",
            dplyr::n_distinct(dat_func_adapt_only_use$study_id), nrow(dat_func_adapt_only_use)))

out_adapt <- fit_and_print(dat_func_adapt_only_use, "Adaptive functioning (risk-coded)")

# Maladaptive subset
dat_func_maladapt_use <- dat_func_adapt_use %>%
  dplyr::filter(func_adaptivity == "maladaptive_functioning") %>%
  droplevels()

cat(sprintf("\nMaladaptive subset: nstudies=%d, keffects=%d\n",
            dplyr::n_distinct(dat_func_maladapt_use$study_id), nrow(dat_func_maladapt_use)))

out_maladapt <- fit_and_print(dat_func_maladapt_use, "Maladaptive functioning (risk-coded)")

############################################################
# 6.10 Within health: well-being vs ill-being (USED; CR2)
############################################################

# -----------------------------
# A) Prepare valence dataset
# -----------------------------
cat("\n====================================\n")
cat("6.10 HEALTH VALENCE (well-being vs ill-being)\n")
cat("====================================\n")

dat_health_valence_use <- dat_health_use %>%
  dplyr::filter(!is.na(health_valence)) %>%
  droplevels()

if (nrow(dat_health_valence_use) < 2) {
  stop("Not enough effects in dat_health_valence_use.")
}

# Ensure factor + set reference (well-being as reference)
dat_health_valence_use$health_valence <- as.factor(dat_health_valence_use$health_valence)
if (!all(c("wellbeing", "illbeing") %in% levels(dat_health_valence_use$health_valence))) {
  stop("health_valence must include levels 'wellbeing' and 'illbeing'. Current levels: ",
       paste(levels(dat_health_valence_use$health_valence), collapse = ", "))
}
dat_health_valence_use$health_valence <- stats::relevel(dat_health_valence_use$health_valence,
                                                        ref = "wellbeing")

# Print counts: effects + distinct studies
cat("\n-----------------------------\n")
cat("A) COUNTS (Health by Valence)\n")
cat("-----------------------------\n")

counts_val <- dat_health_valence_use %>%
  dplyr::group_by(health_valence) %>%
  dplyr::summarise(
    keffect_sizes = dplyr::n(),
    nstudies      = dplyr::n_distinct(study_id),
    .groups = "drop"
  )

print(counts_val)

# -----------------------------
# B) Moderator model (risk-coded): ill-being vs well-being
# -----------------------------
cat("\n-----------------------------------------------\n")
cat("B) MODERATOR MODEL (yi_risk) + CR2 inference\n")
cat("-----------------------------------------------\n")

res_health_val_use <- metafor::rma.mv(
  yi     = yi_risk,
  V      = vi_risk,
  mods   = ~ health_valence,
  random = ~ 1 | study_id/effect_id,
  data   = dat_health_valence_use,
  method = "REML"
)

cat("\n--- metafor::summary() ---\n")
print(summary(res_health_val_use))

# CR2 coefficient tests
cat("\n--- CR2 coefficient tests (clubSandwich::coef_test) ---\n")
res_health_val_use_CR2 <- clubSandwich::coef_test(
  res_health_val_use,
  vcov    = "CR2",
  cluster = dat_health_valence_use$study_id
)
print(res_health_val_use_CR2)

# CR2 omnibus (Wald) test for the moderator
cat("\n--- CR2 omnibus test (clubSandwich::Wald_test) ---\n")
b_names <- names(stats::coef(res_health_val_use))
idx_mod <- which(!b_names %in% c("intrcpt","(Intercept)","Intercept"))
L <- diag(length(b_names))[idx_mod, , drop = FALSE]

res_health_val_use_omni_CR2 <- clubSandwich::Wald_test(
  res_health_val_use,
  constraints = L,
  vcov        = "CR2",
  cluster     = dat_health_valence_use$study_id
)
print(res_health_val_use_omni_CR2)

# Sentence-ready line
if (inherits(res_health_val_use_omni_CR2, "data.frame")) {
  Fval <- res_health_val_use_omni_CR2$Fstat
  df1  <- res_health_val_use_omni_CR2$df_num
  df2  <- res_health_val_use_omni_CR2$df_denom
  pval <- res_health_val_use_omni_CR2$p_val
  
  cat(sprintf("\nCR2 omnibus (valence): F(%s, %.2f) = %.2f, p %s\n",
              df1, df2, Fval,
              ifelse(pval < .001, "< .001", paste0("= ", sprintf("%.3f", pval)))))
}

# -----------------------------
# C) No-intercept means model: pooled means for each valence level
#    + clean 2-row predict() output using newmods
# -----------------------------
cat("\n------------------------------------------------------\n")
cat("C) NO-INTERCEPT MEANS MODEL (yi_risk) + clean predict\n")
cat("------------------------------------------------------\n")

res_health_val_means_use <- metafor::rma.mv(
  yi     = yi_risk,
  V      = vi_risk,
  mods   = ~ health_valence - 1,
  random = ~ 1 | study_id/effect_id,
  data   = dat_health_valence_use,
  method = "REML"
)

cat("\n--- metafor::summary() ---\n")
print(summary(res_health_val_means_use))

cat("\n--- CR2 coefficient tests (means model) ---\n")
res_health_val_means_use_CR2 <- clubSandwich::coef_test(
  res_health_val_means_use,
  vcov    = "CR2",
  cluster = dat_health_valence_use$study_id
)
print(res_health_val_means_use_CR2)

# Pooled r (based on yi_risk direction) via coef (z -> r)
cat("\n--- Transformed pooled means (risk-coded; z->r) via coef() ---\n")
health_means_r_use <- metafor::transf.ztor(stats::coef(res_health_val_means_use))
print(health_means_r_use)

# Clean 2-row pooled r + CI (+ PI) using predict(newmods)
cat("\n--- Pooled r + 95% CI (+ PI) for each level (clean 2-row output) ---\n")

lvl_order <- levels(dat_health_valence_use$health_valence)

X_new <- stats::model.matrix(
  ~ health_valence - 1,
  data = data.frame(
    health_valence = factor(c("wellbeing","illbeing"), levels = lvl_order)
  )
)

pred_levels <- predict(
  res_health_val_means_use,
  newmods = X_new,
  transf  = metafor::transf.ztor,
  digits  = 3
)

pred_levels_df <- data.frame(
  health_valence = c("wellbeing","illbeing"),
  pred  = pred_levels$pred,
  ci.lb = pred_levels$ci.lb,
  ci.ub = pred_levels$ci.ub,
  pi.lb = pred_levels$pi.lb,
  pi.ub = pred_levels$pi.ub,
  row.names = NULL
)
print(pred_levels_df)

# -----------------------------
# D) Subdomain main-effect models (risk-coded)
#    + pooled r (CI + PI) + CR2 intercept + Q(df) + optional multilevel I2
# -----------------------------
cat("\n------------------------------------------------------\n")
cat("D) SUBDOMAIN MAIN MODELS (yi_risk) + CR2 + Q(df)\n")
cat("------------------------------------------------------\n")

fit_and_print_risk <- function(dat_sub, label) {
  
  if (nrow(dat_sub) < 2) {
    cat(sprintf("\n[%s] Not enough effects (n=%d). Skipping.\n", label, nrow(dat_sub)))
    return(invisible(NULL))
  }
  
  res_sub <- metafor::rma.mv(
    yi     = yi_risk,
    V      = vi_risk,
    random = ~ 1 | study_id/effect_id,
    data   = dat_sub,
    method = "REML"
  )
  
  cat(sprintf("\n--- %s: metafor::summary() ---\n", label))
  print(summary(res_sub))
  
  cat(sprintf("\n--- %s: pooled r (CI + PI) via predict() ---\n", label))
  pred_r <- predict(res_sub, transf = metafor::transf.ztor, digits = 3)
  print(pred_r)
  
  cat(sprintf("\n--- %s: CR2 intercept test ---\n", label))
  ct <- clubSandwich::coef_test(res_sub, vcov = "CR2", cluster = dat_sub$study_id)
  print(ct)
  
  Q_val <- res_sub$QE
  Q_df  <- res_sub$k - res_sub$p
  Q_p   <- res_sub$QEp
  cat(sprintf("\n--- %s: heterogeneity ---\n", label))
  cat(sprintf("Q(%d) = %.2f, p %s\n",
              Q_df, Q_val,
              ifelse(Q_p < .001, "< .001", paste0("= ", sprintf("%.3f", Q_p)))))
  
  if (exists("compute_ml_I2", inherits = TRUE)) {
    het <- compute_ml_I2(res_sub, dat_sub, vi_col = "vi_risk")
    cat(sprintf("\n--- %s: model-based multilevel I2 ---\n", label))
    cat(sprintf("I2_total=%.3f | I2_between=%.3f | I2_within=%.3f\n",
                het$I2_total, het$I2_between_study, het$I2_within_study))
  }
  
  invisible(list(res = res_sub, pred = pred_r, Q = c(Q = Q_val, df = Q_df, p = Q_p)))
}

# Split datasets
dat_health_wb_use <- dat_health_valence_use %>%
  dplyr::filter(health_valence == "wellbeing") %>%
  droplevels()

dat_health_ill_use <- dat_health_valence_use %>%
  dplyr::filter(health_valence == "illbeing") %>%
  droplevels()

cat(sprintf("\nWell-being subset:  nstudies=%d, keffects=%d\n",
            dplyr::n_distinct(dat_health_wb_use$study_id), nrow(dat_health_wb_use)))
cat(sprintf("Ill-being subset:   nstudies=%d, keffects=%d\n",
            dplyr::n_distinct(dat_health_ill_use$study_id), nrow(dat_health_ill_use)))

out_wb  <- fit_and_print_risk(dat_health_wb_use,  "Well-being (risk-coded)")
out_ill <- fit_and_print_risk(dat_health_ill_use, "Ill-being (risk-coded)")

# -----------------------------
# E) Optional raw-direction subdomain models (original yi/vi signs)
#    Useful if you want to write "well-being negative; ill-being positive"
# -----------------------------
cat("\n------------------------------------------------------\n")
cat("E) OPTIONAL: SUBDOMAIN MODELS (raw yi/vi; original sign)\n")
cat("------------------------------------------------------\n")

if (!all(c("yi","vi") %in% names(dat_health_valence_use))) {
  cat("\n[Skip raw-direction models] Columns 'yi'/'vi' not found.\n")
} else {
  
  fit_and_print_raw <- function(dat_sub, label) {
    
    if (nrow(dat_sub) < 2) {
      cat(sprintf("\n[%s] Not enough effects (n=%d). Skipping.\n", label, nrow(dat_sub)))
      return(invisible(NULL))
    }
    
    res_sub <- metafor::rma.mv(
      yi     = yi,
      V      = vi,
      random = ~ 1 | study_id/effect_id,
      data   = dat_sub,
      method = "REML"
    )
    
    cat(sprintf("\n--- %s: metafor::summary() ---\n", label))
    print(summary(res_sub))
    
    cat(sprintf("\n--- %s: pooled r (CI + PI) via predict() ---\n", label))
    pred_r <- predict(res_sub, transf = metafor::transf.ztor, digits = 3)
    print(pred_r)
    
    Q_val <- res_sub$QE
    Q_df  <- res_sub$k - res_sub$p
    Q_p   <- res_sub$QEp
    cat(sprintf("\n--- %s: heterogeneity ---\n", label))
    cat(sprintf("Q(%d) = %.2f, p %s\n",
                Q_df, Q_val,
                ifelse(Q_p < .001, "< .001", paste0("= ", sprintf("%.3f", Q_p)))))
    
    invisible(list(res = res_sub, pred = pred_r))
  }
  
  out_wb_raw  <- fit_and_print_raw(dat_health_wb_use,  "Well-being (raw)")
  out_ill_raw <- fit_and_print_raw(dat_health_ill_use, "Ill-being (raw)")
}

############################################################
# Helper: extract estimate + 95% CI for no-intercept models (CR2)
############################################################

get_summary_df_CR2 <- function(res, cluster, prefix) {
  
  ct <- clubSandwich::coef_test(res, vcov = "CR2", cluster = cluster)
  
  b  <- as.numeric(ct$beta)
  se <- as.numeric(ct$SE)
  
  # df column name differs across versions
  df_candidates <- c("df_Satt","df","df_satt","df_Satterthwaite","dfs","df_denom")
  df_col <- df_candidates[df_candidates %in% names(ct)][1]
  
  if (is.na(df_col) || length(df_col) == 0) {
    stop("No df column in coef_test output. Available columns: ",
         paste(names(ct), collapse = ", "))
  }
  
  df <- suppressWarnings(as.numeric(ct[[df_col]]))
  tcrit <- qt(0.975, df)
  
  ci_lb <- b - tcrit * se
  ci_ub <- b + tcrit * se
  
  data.frame(
    level = gsub(paste0("^", prefix), "", rownames(ct)),
    yi    = b,
    ci_lb = ci_lb,
    ci_ub = ci_ub,
    df    = df,
    row.names = NULL
  )
}

############################################################
# Helper: extract estimate + 95% CI for no-intercept models (MODEL-BASED)
############################################################
get_summary_df_model <- function(res, prefix) {
  
  b <- stats::coef(res)
  V <- stats::vcov(res)
  se <- sqrt(diag(V))
  
  ci_lb <- b - 1.96 * se
  ci_ub <- b + 1.96 * se
  
  data.frame(
    level = gsub(paste0("^", prefix), "", names(b)),
    yi    = as.numeric(b),
    ci_lb = as.numeric(ci_lb),
    ci_ub = as.numeric(ci_ub),
    row.names = NULL
  )
}

############################################################
# Combined summary figure (USED) --- Scheme A (robust)
############################################################

# ---- Domain ----
dom_sum_use <- get_summary_df_model(
  res    = res_domain_means_use,
  prefix = "domain_psych"
)

dom_counts_use <- dat_domain_use %>%
  dplyr::group_by(domain_psych) %>%
  dplyr::summarise(
    n_studies = dplyr::n_distinct(study_id),
    n_effects = dplyr::n(),
    .groups   = "drop"
  ) %>%
  dplyr::mutate(level = as.character(domain_psych)) %>%
  dplyr::select(level, n_studies, n_effects)

dom_plot_df_use <- dom_sum_use %>%
  dplyr::mutate(level = as.character(level)) %>%  
  dplyr::left_join(dom_counts_use, by = "level") %>%
  dplyr::mutate(
    group   = "Domain",
    est_r   = metafor::transf.ztor(yi),
    ci_lb_r = metafor::transf.ztor(ci_lb),
    ci_ub_r = metafor::transf.ztor(ci_ub)
  )


# ---- Health valence ----
hv_plot_df_use <- NULL
if (exists("res_health_val_means_use") && exists("dat_health_valence_use")) {
  
  hv_sum_use <- get_summary_df_model(
    res    = res_health_val_means_use,
    prefix = "health_valence"
  )
  
  hv_counts_use <- dat_health_valence_use %>%
    dplyr::group_by(health_valence) %>%
    dplyr::summarise(
      n_studies = dplyr::n_distinct(study_id),
      n_effects = dplyr::n(),
      .groups   = "drop"
    ) %>%
    dplyr::mutate(level = as.character(health_valence)) %>%
    dplyr::select(level, n_studies, n_effects)
  
  hv_plot_df_use <- hv_sum_use %>%
    dplyr::mutate(level = as.character(level)) %>%
    dplyr::left_join(hv_counts_use, by = "level") %>%
    dplyr::mutate(
      group   = "Health valence",
      est_r   = metafor::transf.ztor(yi),
      ci_lb_r = metafor::transf.ztor(ci_lb),
      ci_ub_r = metafor::transf.ztor(ci_ub)
    )
}

# ---- Functioning type ----
func_plot_df_use <- NULL
if (exists("res_func_means_use") && exists("dat_func_adapt_use")) {
  
  func_sum_use <- get_summary_df_model(
    res    = res_func_means_use,
    prefix = "func_adaptivity"
  )
  
  func_counts_use <- dat_func_adapt_use %>%
    dplyr::group_by(func_adaptivity) %>%
    dplyr::summarise(
      n_studies = dplyr::n_distinct(study_id),
      n_effects = dplyr::n(),
      .groups   = "drop"
    ) %>%
    dplyr::mutate(level = as.character(func_adaptivity)) %>%
    dplyr::select(level, n_studies, n_effects)
  
  func_plot_df_use <- func_sum_use %>%
    dplyr::mutate(level = as.character(level)) %>%
    dplyr::left_join(func_counts_use, by = "level") %>%
    dplyr::mutate(
      group   = "Functioning type",
      est_r   = metafor::transf.ztor(yi),
      ci_lb_r = metafor::transf.ztor(ci_lb),
      ci_ub_r = metafor::transf.ztor(ci_ub)
    )
}


plot_df_use <- bind_rows(dom_plot_df_use, hv_plot_df_use, func_plot_df_use) %>%
  mutate(
    group = factor(
      group,
      levels = c("Domain","Health valence","Functioning type"),
      labels = c("Psychological Domain","Psychological Health","Psychological Functioning")
    ),
    level_pretty = dplyr::recode(
      level,
      "psychological_health"      = "Psychological health",
      "psychological_functioning" = "Psychological functioning",
      "wellbeing"                 = "Well-being",
      "illbeing"                  = "Ill-being",
      "adaptive_functioning"      = "Adaptive functioning",
      "maladaptive_functioning"   = "Maladaptive functioning"
    ),
    ci_label = sprintf("%.2f [%.2f, %.2f]", est_r, ci_lb_r, ci_ub_r)
  )

level_order <- c(
  "Domain","Psychological health","Psychological functioning",
  "Health valence","Well-being","Ill-being",
  "Functioning type","Adaptive functioning","Maladaptive functioning"
)

header_keys   <- c("Domain","Health valence","Functioning type")
header_labels <- c("Psychological domain","Health","Functioning")

header_df <- data.frame(
  group        = NA_character_,
  level        = NA_character_,
  level_pretty = header_keys,
  header_label = header_labels,
  n_studies    = NA_integer_,
  n_effects    = NA_integer_,
  est_r        = NA_real_,
  ci_lb_r      = NA_real_,
  ci_ub_r      = NA_real_,
  ci_label     = "",
  stringsAsFactors = FALSE
)

plot_df2_use <- plot_df_use %>% mutate(header_label = "")

combined_df_use <- dplyr::bind_rows(
  header_df %>% dplyr::mutate(row_type = "header"),
  plot_df2_use %>% dplyr::mutate(row_type = "effect")
) %>%
  dplyr::mutate(level_pretty = factor(level_pretty, levels = rev(level_order)))

effects_plot_df_use <- combined_df_use %>% dplyr::filter(row_type == "effect")
headers_plot_df_use <- combined_df_use %>% dplyr::filter(row_type == "header")

heading_shift <- 0.18

range_data <- range(effects_plot_df_use$ci_lb_r, effects_plot_df_use$ci_ub_r, 0, na.rm = TRUE)
x_min_data <- min(range_data[1] - 0.02, -0.6)
x_max_data <- max(range_data[2] + 0.05,  0.6)

stud_x <- x_max_data + 0.10
eff_x  <- x_max_data + 0.18
ci_x   <- x_max_data + 0.30

x_min <- (x_min_data - heading_shift) - 0.05
x_max <- ci_x + 0.15

ggplot() +
  geom_vline(xintercept = 0, colour = "grey30") +
  geom_errorbarh(
    data  = effects_plot_df_use,
    aes(y = level_pretty, xmin = ci_lb_r, xmax = ci_ub_r, colour = group),
    height = 0.15, linewidth = 0.6
  ) +
  geom_point(
    data = effects_plot_df_use,
    aes(y = level_pretty, x = est_r, colour = group),
    size = 3
  ) +
  geom_text(
    data = effects_plot_df_use,
    aes(y = level_pretty, x = stud_x, label = n_studies),
    size = 3
  ) +
  geom_text(
    data = effects_plot_df_use,
    aes(y = level_pretty, x = eff_x, label = n_effects),
    size = 3
  ) +
  geom_text(
    data = effects_plot_df_use,
    aes(y = level_pretty, x = ci_x, label = ci_label),
    hjust = 0.5, size = 3
  ) +
  geom_text(
    data = headers_plot_df_use,
    aes(y = level_pretty, x = x_min_data - heading_shift, label = header_label),
    fontface = "bold",
    size     = 3.2,
    hjust    = 1.00,
    vjust    = 0.5
  ) +
  scale_x_continuous(
    limits = c(x_min, x_max),
    breaks = seq(-0.6, 0.6, by = 0.2),
    labels = function(x) sprintf("%.1f", x)
  ) +
  scale_y_discrete(
    limits = rev(level_order),
    labels = function(x) ifelse(x %in% header_keys, "", x),
    expand = c(0, 0)
  ) +
  labs(x = "Correlation", y = NULL) +
  annotate("text", x = stud_x, y = Inf, label = "Studies", vjust = 1.5, size = 3) +
  annotate("text", x = eff_x,  y = Inf, label = "Effects", vjust = 1.5, size = 3) +
  annotate("text", x = ci_x,   y = Inf, label = "95% CI",  vjust = 1.5, size = 3) +
  theme_bw() +
  coord_cartesian(clip = "off") +
  theme(
    panel.grid.major.y = element_blank(),
    legend.position    = "none",
    plot.margin        = margin(5.5, 40, 5.5, 80),
    panel.border       = element_blank(),
    axis.ticks.y       = element_blank()
  )

############################################################
# 6.11 Forest plots by subdomain (per study_id; USED base)
# Notes:
# - Plotting uses ORIGINAL yi/vi (not risk recoding), but subsets follow dat_domain_use
############################################################

# Base for plotting is ALWAYS USED (toggle-controlled)
dat_plot_base <- dat_domain_use

ticks_r <- c(-0.5,-0.3,-0.1,0,0.1,0.3,0.5)
at_z    <- transf.rtoz(ticks_r)

tp_left  <- transf.rtoz(-0.8)
tp_right <- transf.rtoz( 0.8)
xlim_use <- c(tp_left - 0.15, tp_right + 0.15)

par(mar = c(4.5, 4.5, 2.5, 2))

# Build USED subsets for subdomain plots
dat_health_valence_plot <- dat_plot_base %>%
  dplyr::filter(domain_psych == "psychological_health", !is.na(health_valence)) %>%
  droplevels()

dat_func_adapt_plot <- dat_plot_base %>%
  dplyr::filter(domain_psych == "psychological_functioning", !is.na(func_adaptivity)) %>%
  droplevels()

##########################
# 6.11.1 Well-being (USED)
##########################
dat_health_wb_plot <- dat_health_valence_plot %>%
  dplyr::filter(health_valence == "wellbeing")

if (nrow(dat_health_wb_plot) > 0) {
  
  dat_health_wb_study <- collapse_by_studyid_raw(dat_health_wb_plot)
  dat_health_wb_study <- dat_health_wb_study[order(dat_health_wb_study$study_key), ]
  
  res_health_wb_study <- rma.uni(yi = yi, vi = vi, data = dat_health_wb_study, method = "REML")
  
  k_wb    <- nrow(dat_health_wb_study)
  rows_wb <- k_wb:1
  ylim_wb <- c(-1, k_wb + 3)
  
  forest(
    x       = dat_health_wb_study$yi,
    vi      = dat_health_wb_study$vi,
    slab    = dat_health_wb_study$slab,
    rows    = rows_wb,
    ylim    = ylim_wb,
    xlab    = "Psychological well-being",
    transf  = transf.ztor,
    at      = at_z,
    textpos = c(tp_left, tp_right),
    xlim    = xlim_use,
    refline = 0,
    cex     = 0.75,
    cex.lab = 1.0,
    cex.axis= 0.75,
    # Zebra stripes (alternate row shading)
    shade    = rows_wb[seq(2, k_wb, by = 2)],
    colshade = "grey95"
  )
  
  addpoly(
    res_health_wb_study,
    transf = transf.ztor,
    row    = 0,
    mlab   = "Overall",
    col    = "red",
    border = "red",
    cex    = 0.75
  )
}

##########################
# 6.11.2 Ill-being (USED)
##########################
dat_health_ill_plot <- dat_health_valence_plot %>%
  dplyr::filter(health_valence == "illbeing")

if (nrow(dat_health_ill_plot) > 0) {
  
  dat_health_ill_study <- collapse_by_studyid_raw(dat_health_ill_plot)
  dat_health_ill_study <- dat_health_ill_study[order(dat_health_ill_study$study_key), ]
  
  res_health_ill_study <- rma.uni(yi = yi, vi = vi, data = dat_health_ill_study, method = "REML")
  
  k_ill    <- nrow(dat_health_ill_study)
  rows_ill <- k_ill:1
  ylim_ill <- c(-1, k_ill + 3)
  
  forest(
    x       = dat_health_ill_study$yi,
    vi      = dat_health_ill_study$vi,
    slab    = dat_health_ill_study$slab,
    rows    = rows_ill,
    ylim    = ylim_ill,
    xlab    = "Psychological ill-being",
    transf  = transf.ztor,
    at      = at_z,
    textpos = c(tp_left, tp_right),
    xlim    = xlim_use,
    refline = 0,
    cex     = 0.40,
    cex.lab = 1.0,
    cex.axis= 0.40,
    # Zebra stripes (alternate row shading)
    shade    = rows_ill[seq(2, k_ill, by = 2)],
    colshade = "grey95"
  )
  
  addpoly(
    res_health_ill_study,
    transf = transf.ztor,
    row    = 0,
    mlab   = "Overall",
    col    = "red",
    border = "red",
    cex    = 0.40
  )
}

##########################
# 6.11.3 Adaptive functioning (USED)
##########################
dat_func_adapt_plot2 <- dat_func_adapt_plot %>%
  dplyr::filter(func_adaptivity == "adaptive_functioning")

if (nrow(dat_func_adapt_plot2) > 0) {
  
  dat_func_adapt_study <- collapse_by_studyid_raw(dat_func_adapt_plot2)
  dat_func_adapt_study <- dat_func_adapt_study[order(dat_func_adapt_study$study_key), ]
  
  res_func_adapt_study <- rma.uni(yi = yi, vi = vi, data = dat_func_adapt_study, method = "REML")
  
  k_ad    <- nrow(dat_func_adapt_study)
  rows_ad <- k_ad:1
  ylim_ad <- c(-1, k_ad + 3)
  
  forest(
    x       = dat_func_adapt_study$yi,
    vi      = dat_func_adapt_study$vi,
    slab    = dat_func_adapt_study$slab,
    rows    = rows_ad,
    ylim    = ylim_ad,
    xlab    = "Adaptive functioning",
    transf  = transf.ztor,
    at      = at_z,
    textpos = c(tp_left, tp_right),
    xlim    = xlim_use,
    refline = 0,
    cex     = 0.60,
    cex.lab = 1.0,
    cex.axis= 0.60,
    # Zebra stripes (alternate row shading)
    shade    = rows_ad[seq(2, k_ad, by = 2)],
    colshade = "grey95"
  )
  
  addpoly(
    res_func_adapt_study,
    transf = transf.ztor,
    row    = 0,
    mlab   = "Overall",
    col    = "red",
    border = "red",
    cex    = 0.60
  )
}

##########################
# 6.11.4 Maladaptive functioning (USED)
##########################
dat_func_maladapt_plot2 <- dat_func_adapt_plot %>%
  dplyr::filter(func_adaptivity == "maladaptive_functioning")

if (nrow(dat_func_maladapt_plot2) > 0) {
  
  dat_func_maladapt_study <- collapse_by_studyid_raw(dat_func_maladapt_plot2)
  dat_func_maladapt_study <- dat_func_maladapt_study[order(dat_func_maladapt_study$study_key), ]
  
  res_func_maladapt_study <- rma.uni(yi = yi, vi = vi, data = dat_func_maladapt_study, method = "REML")
  
  k_mal    <- nrow(dat_func_maladapt_study)
  rows_mal <- k_mal:1
  ylim_mal <- c(-1, k_mal + 3)
  
  forest(
    x       = dat_func_maladapt_study$yi,
    vi      = dat_func_maladapt_study$vi,
    slab    = dat_func_maladapt_study$slab,
    rows    = rows_mal,
    ylim    = ylim_mal,
    xlab    = "Maladaptive functioning",
    transf  = transf.ztor,
    at      = at_z,
    textpos = c(tp_left, tp_right),
    xlim    = xlim_use,
    refline = 0,
    cex     = 0.60,
    cex.lab = 1.0,
    cex.axis= 0.60,
    # Zebra stripes (alternate row shading)
    shade    = rows_mal[seq(2, k_mal, by = 2)],
    colshade = "grey95"
  )
  
  addpoly(
    res_func_maladapt_study,
    transf = transf.ztor,
    row    = 0,
    mlab   = "Overall",
    col    = "red",
    border = "red",
    cex    = 0.60
  )
}

############################################################
# 7. Meta-regression helper (CR2; prints both pre/post filtering counts)
############################################################
run_meta_reg <- function(dat_in, moderator, min_k_per_level = 2, ref_level = NULL) {
  
  # Keep original level order stable
  x_raw <- dat_in[[moderator]]
  if (is.factor(x_raw)) {
    orig_levels <- levels(x_raw)
  } else {
    orig_levels <- unique(as.character(x_raw[!is.na(x_raw)]))  # first-appearance order
  }
  
  # (A) Non-missing subset (for eligibility counting)
  dat_mod_all <- dat_in[!is.na(dat_in[[moderator]]), ]
  
  if (nrow(dat_mod_all) < min_k_per_level) {
    message("Moderator ", moderator,
            ": fewer than ", min_k_per_level, " total effect sizes (non-missing); model not fitted.")
    return(NULL)
  }
  
  # Counts BEFORE filtering
  k_per_level_all <- table(dat_mod_all[[moderator]])
  valid_levels <- names(k_per_level_all)[k_per_level_all >= min_k_per_level]
  
  if (length(valid_levels) < 2L) {
    message("Moderator ", moderator,
            ": fewer than 2 levels with k >= ", min_k_per_level, "; model not fitted.")
    return(list(
      k_per_level_all  = k_per_level_all,
      used_levels      = valid_levels,
      k_used_per_level = NULL,
      model            = NULL,
      model_CR2        = NULL,
      omnibus_CR2      = NULL
    ))
  }
  
  # (B) Filter to eligible levels and set factor levels deterministically
  used_levels <- intersect(orig_levels, valid_levels)  # preserve original order
  dat_mod <- dat_mod_all[dat_mod_all[[moderator]] %in% used_levels, ]
  
  # After filtering, re-check we still have >= 2 levels
  if (length(unique(dat_mod[[moderator]])) < 2L || nrow(dat_mod) < 2L) {
    message("Moderator ", moderator,
            ": after filtering to k >= ", min_k_per_level,
            ", fewer than 2 levels remain; model not fitted.")
    return(list(
      k_per_level_all  = k_per_level_all,
      used_levels      = used_levels,
      k_used_per_level = table(dat_mod[[moderator]]),
      model            = NULL,
      model_CR2        = NULL,
      omnibus_CR2      = NULL
    ))
  }
  
  # Optional: force a specific reference group if provided and present
  if (!is.null(ref_level) && ref_level %in% used_levels) {
    used_levels <- c(ref_level, setdiff(used_levels, ref_level))
  }
  dat_mod[[moderator]] <- factor(dat_mod[[moderator]], levels = used_levels)
  
  # Counts AFTER filtering (actually used in model)
  k_used_per_level <- table(dat_mod[[moderator]])
  
  # Build model formula
  form_mod <- as.formula(paste("~", moderator))
  
  # Fit multilevel meta-regression
  res <- rma.mv(
    yi_risk, vi_risk,
    mods   = form_mod,
    random = ~ 1 | study_id/effect_id,
    data   = dat_mod,
    method = "REML"
  )
  
  # CR2 coefficient tests
  res_CR2 <- clubSandwich::coef_test(
    res,
    vcov    = "CR2",
    cluster = dat_mod$study_id
  )
  
  # CR2 omnibus test for the moderator terms (exclude intercept robustly)
  b_names <- names(coef(res))
  intercept_idx <- which(b_names %in% c("intrcpt", "(Intercept)", "Intercept"))
  idx_mod <- setdiff(seq_along(b_names), intercept_idx)
  
  omnibus_CR2 <- NULL
  if (length(idx_mod) > 0) {
    L <- diag(length(b_names))[idx_mod, , drop = FALSE]
    omnibus_CR2 <- tryCatch(
      clubSandwich::Wald_test(
        res,
        constraints = L,
        vcov        = "CR2",
        cluster     = dat_mod$study_id
      ),
      error = function(e) {
        message("  ! Omnibus test for moderator ", moderator,
                " failed: ", conditionMessage(e))
        NULL
      }
    )
  }
  
  # Print summary
  cat("\n============================================\n")
  cat("Moderator:", moderator, "\n")
  cat("Total k (non-missing):", nrow(dat_mod_all), "\n")
  cat("k per level (non-missing; BEFORE filtering):\n")
  print(k_per_level_all)
  cat("Levels eligible (k >=", min_k_per_level, "):\n")
  print(valid_levels)
  
  cat("\nTotal k (USED in model):", nrow(dat_mod), "\n")
  cat("k per level (USED; AFTER filtering):\n")
  print(k_used_per_level)
  cat("Reference level (first level):", levels(dat_mod[[moderator]])[1], "\n")
  
  cat("\nMultilevel meta-regression (rma.mv) summary:\n")
  print(summary(res))
  
  cat("\nCluster-robust coefficient tests (CR2):\n")
  print(res_CR2)
  
  cat("\nCluster-robust omnibus test (CR2):\n")
  print(omnibus_CR2)
  cat("============================================\n")
  
  return(list(
    k_per_level_all  = k_per_level_all,
    used_levels      = levels(dat_mod[[moderator]]),
    k_used_per_level = k_used_per_level,
    model            = res,
    model_CR2        = res_CR2,
    omnibus_CR2      = omnibus_CR2
  ))
}

############################################################
# Choose dataset for moderator analyses (FOLLOW dat_domain_use)
# IMPORTANT: dat_domain_use must already exist upstream (FULL vs CLEAN toggle)
############################################################

# Always follow the same dataset decision as the main pipeline:
# - dat_domain_full  (FULL)
# - dat_domain_clean (CLEAN, Cook/DFBETAS excluded)
# - dat_domain_use   (the chosen one via EXCLUDE_INFLUENTIAL)
dat_mod_use <- dat_domain_use

# Split by domain (still "USED")
dat_health_use <- dat_mod_use %>% dplyr::filter(domain_psych == "psychological_health")
dat_functioning_use <- dat_mod_use %>% dplyr::filter(domain_psych == "psychological_functioning")

############################################################
# 7.2 Use gender_proportion + white_proportion as continuous moderators (USED)
#     Version A: keep on 0–1 scale
############################################################

dat_health_use <- dat_health_use %>%
  dplyr::mutate(
    gender_proportion = as.numeric(gender_proportion),
    white_proportion  = as.numeric(white_proportion)   # 0–1 White proportion
  )

dat_functioning_use <- dat_functioning_use %>%
  dplyr::mutate(
    gender_proportion = as.numeric(gender_proportion),
    white_proportion  = as.numeric(white_proportion)
  )

dat_health_use <- dat_health_use %>%
  dplyr::mutate(
    construct_outcome = as.factor(construct_outcome)
  )

dat_functioning_use <- dat_functioning_use %>%
  dplyr::mutate(
    construct_outcome = as.factor(construct_outcome)
  )

############################################################
# Helper: run moderators for one subdomain (USED)
############################################################

run_mods_for_subdomain <- function(dat_sub, mods, label) {
  message("=== Subdomain: ", label, " ===")
  
  mods_exist <- mods[mods %in% names(dat_sub)]
  mods_missing <- setdiff(mods, mods_exist)
  if (length(mods_missing) > 0) {
    message("  (Skipped missing moderators: ", paste(mods_missing, collapse = ", "), ")")
  }
  
  res_list <- lapply(mods_exist, function(m) {
    message("  - Moderator = ", m)
    run_meta_reg(dat_sub, m)
  })
  names(res_list) <- mods_exist
  res_list
}

############################################################
# 8. Moderator analyses: psychological health (USED)
############################################################

dat_health_wb_use  <- dat_health_use %>% dplyr::filter(health_valence == "wellbeing")
dat_health_ill_use <- dat_health_use %>% dplyr::filter(health_valence == "illbeing")

mods_health <- c("measure_IP","educational_stage","region","subject","construct_outcome")

health_wellbeing_mod_results_use <- run_mods_for_subdomain(
  dat_sub = dat_health_wb_use,
  mods    = mods_health,
  label   = "psychological health – well-being"
)

health_illbeing_mod_results_use <- run_mods_for_subdomain(
  dat_sub = dat_health_ill_use,
  mods    = mods_health,
  label   = "psychological health – ill-being"
)

############################################################
# 9. Moderator analyses: psychological functioning (USED)
############################################################

dat_func_adapt_only_use <- dat_functioning_use %>%
  dplyr::filter(func_adaptivity == "adaptive_functioning")

dat_func_maladapt_use <- dat_functioning_use %>%
  dplyr::filter(func_adaptivity == "maladaptive_functioning")

mods_functioning <- c("measure_IP","educational_stage","region","subject","construct_outcome")

functioning_adaptive_mod_results_use <- run_mods_for_subdomain(
  dat_sub = dat_func_adapt_only_use,
  mods    = mods_functioning,
  label   = "psychological functioning – adaptive"
)

functioning_maladaptive_mod_results_use <- run_mods_for_subdomain(
  dat_sub = dat_func_maladapt_use,
  mods    = mods_functioning,
  label   = "psychological functioning – maladaptive"
)

############################################################
# Helper: build combined subdomain dataset for plotting (USED)
############################################################

dat_sub_all_use <- dplyr::bind_rows(
  dat_health_wb_use        %>% dplyr::mutate(subdomain = "Health – well-being"),
  dat_health_ill_use       %>% dplyr::mutate(subdomain = "Health – ill-being"),
  dat_func_adapt_only_use  %>% dplyr::mutate(subdomain = "Functioning – adaptive"),
  dat_func_maladapt_use    %>% dplyr::mutate(subdomain = "Functioning – maladaptive")
) %>%
  dplyr::mutate(
    subdomain = factor(
      subdomain,
      levels = c(
        "Health – well-being",
        "Health – ill-being",
        "Functioning – adaptive",
        "Functioning – maladaptive"
      )
    )
  )

############################################################
# Helper: summarise effects for one moderator across subdomains (USED)
# - Fits no-intercept rma.mv within each subdomain
# - Uses cluster-robust CR2 for SE/CI (Satterthwaite df)
# - Robust to clubSandwich coef_test output column-name differences
############################################################

summarise_moderator_by_subdomain <- function(dat_all,
                                             moderator,
                                             min_k = 2L) {
  if (!moderator %in% names(dat_all)) {
    warning("Moderator ", moderator, " not found in data.")
    return(NULL)
  }
  
  dat_mod <- dat_all[!is.na(dat_all[[moderator]]), ]
  if (nrow(dat_mod) == 0L) {
    warning("No non-missing data for moderator: ", moderator)
    return(NULL)
  }
  
  # Keep subdomain factor levels stable if present
  if (!("subdomain" %in% names(dat_mod))) {
    stop("dat_all must contain a 'subdomain' column.")
  }
  
  dat_mod[[moderator]] <- as.character(dat_mod[[moderator]])
  
  # helper: safely extract term/beta/SE/df from coef_test output
  extract_coef_test <- function(ct) {
    ct_df <- as.data.frame(ct)
    
    # term names
    term_vec <- NULL
    if ("term" %in% names(ct_df)) {
      term_vec <- as.character(ct_df$term)
    } else if ("Coefficient" %in% names(ct_df)) {
      term_vec <- as.character(ct_df$Coefficient)
    } else if (!is.null(rownames(ct_df)) && all(nzchar(rownames(ct_df)))) {
      term_vec <- rownames(ct_df)
    } else {
      term_vec <- rep(NA_character_, nrow(ct_df))
    }
    
    # beta / SE
    beta_col <- c("beta", "Beta", "estimate", "Estimate")
    se_col   <- c("SE", "se", "StdErr", "Std. Error", "std.error")
    
    beta_name <- beta_col[beta_col %in% names(ct_df)][1]
    se_name   <- se_col[se_col %in% names(ct_df)][1]
    
    if (is.na(beta_name) || is.na(se_name)) {
      stop("coef_test output missing beta/SE columns. Available: ",
           paste(names(ct_df), collapse = ", "))
    }
    
    beta_vec <- as.numeric(ct_df[[beta_name]])
    se_vec   <- as.numeric(ct_df[[se_name]])
    
    # df (Satterthwaite naming differs by version)
    df_candidates <- c("df_Satt", "df", "dfs", "df_denom", "df_Satterthwaite", "df_satt")
    df_name <- df_candidates[df_candidates %in% names(ct_df)][1]
    if (is.na(df_name)) {
      stop("coef_test output missing df column. Available: ",
           paste(names(ct_df), collapse = ", "))
    }
    df_vec <- suppressWarnings(as.numeric(ct_df[[df_name]]))
    
    list(term = term_vec, beta = beta_vec, se = se_vec, df = df_vec)
  }
  
  res_list <- list()
  
  for (sd in levels(dat_mod$subdomain)) {
    
    dat_sd <- dat_mod[dat_mod$subdomain == sd, ]
    if (nrow(dat_sd) == 0L) next
    
    # Count ALL non-missing levels within this subdomain
    k_tab_all <- table(dat_sd[[moderator]])
    valid_levels <- names(k_tab_all)[k_tab_all >= min_k]
    if (length(valid_levels) == 0L) next
    
    # Filter to valid levels only
    dat_sd_used <- dat_sd[dat_sd[[moderator]] %in% valid_levels, ]
    if (nrow(dat_sd_used) < 2L) next
    
    dat_sd_used[[moderator]] <- droplevels(factor(dat_sd_used[[moderator]],
                                                  levels = valid_levels))
    
    # Counts (studies/effects) for USED cells
    counts_sd <- dat_sd_used %>%
      dplyr::group_by(.data[[moderator]]) %>%
      dplyr::summarise(
        n_studies = dplyr::n_distinct(study_id),
        n_effects = dplyr::n(),
        .groups   = "drop"
      ) %>%
      dplyr::rename(level = !!moderator)
    
    # No-intercept model: level-specific estimates (z scale)
    form_mod <- stats::as.formula(paste("~", moderator, "- 1"))
    
    res_sd <- try(
      metafor::rma.mv(
        yi_risk, vi_risk,
        mods   = form_mod,
        random = ~ 1 | study_id/effect_id,
        data   = dat_sd_used,
        method = "REML"
      ),
      silent = TRUE
    )
    if (inherits(res_sd, "try-error")) next
    
    # CR2 robust inference
    V_cr2 <- try(
      clubSandwich::vcovCR(
        res_sd,
        cluster = dat_sd_used$study_id,
        type    = "CR2"
      ),
      silent = TRUE
    )
    if (inherits(V_cr2, "try-error")) next
    
    ct <- try(
      clubSandwich::coef_test(
        res_sd,
        vcov = V_cr2,
        test = "Satterthwaite"
      ),
      silent = TRUE
    )
    if (inherits(ct, "try-error")) next
    
    ct_info <- extract_coef_test(ct)
    
    if (length(ct_info$beta) == 0L) next
    
    tcrit <- stats::qt(0.975, df = ct_info$df)
    
    sum_sd <- data.frame(
      subdomain = sd,
      level     = ct_info$term,
      yi        = ct_info$beta,
      ci_lb     = ct_info$beta - tcrit * ct_info$se,
      ci_ub     = ct_info$beta + tcrit * ct_info$se,
      df        = ct_info$df,
      stringsAsFactors = FALSE
    )
    
    # Clean level names (remove prefix like "educational_stage...")
    sum_sd$level <- gsub(paste0("^", moderator), "", sum_sd$level)
    
    # Convert to r for plotting text
    sum_sd <- sum_sd %>%
      dplyr::mutate(
        est_r   = metafor::transf.ztor(yi),
        ci_lb_r = metafor::transf.ztor(ci_lb),
        ci_ub_r = metafor::transf.ztor(ci_ub)
      ) %>%
      dplyr::left_join(counts_sd, by = "level")
    
    res_list[[sd]] <- sum_sd
  }
  
  if (length(res_list) == 0L) {
    warning("No subdomain × level cells met min_k for moderator: ", moderator)
    return(NULL)
  }
  
  dplyr::bind_rows(res_list) %>%
    dplyr::mutate(
      subdomain = factor(
        subdomain,
        levels = levels(dat_mod$subdomain)
      )
    )
}

############################################################
# 10. Publication bias diagnostics (FOLLOW dat_mod_use; collapse to study)
############################################################

run_pub_bias <- function(dat_sub,
                         label = "overall",
                         collapse_to_study = TRUE,
                         min_studies_for_tests = 10L) {
  
  dat_pb <- dat_sub %>%
    dplyr::filter(!is.na(yi_risk), !is.na(vi_risk), vi_risk > 0)
  
  if (collapse_to_study) {
    dat_pb <- collapse_by_studyid(dat_pb)  # yi_risk/vi_risk + slab
  }
  
  k_rows <- nrow(dat_pb)
  if (k_rows < 3L) {
    warning("Too few rows for publication-bias diagnostics: ", label)
    return(NULL)
  }
  
  res_uni <- metafor::rma.uni(
    yi     = yi_risk,
    vi     = vi_risk,
    data   = dat_pb,
    method = "REML"
  )
  
  cat("\n\n====================================\n")
  cat("Publication bias diagnostics for:", label, "\n")
  cat("Data used:", ifelse(collapse_to_study,
                           "collapsed to 1 effect per study_id",
                           "effect-level (not collapsed)"), "\n")
  cat("k (rows) =", k_rows, "\n")
  cat("====================================\n")
  print(res_uni)
  
  metafor::funnel(
    res_uni,
    yaxis   = "sei",                           # Standard Error on y-axis
    refline = stats::coef(res_uni)[1],         # pooled estimate (z scale)
    level   = c(0.90, 0.95, 0.99),             # significance contours
    shade   = c("white", "grey40", "grey60", "grey95"),  # inside -> outside bands
    legend  = FALSE,
    pch     = 19,
    xlab    = "Effect size (Fisher's z)",
    ylab    = "Standard Error"
  )
  
  egger_res <- NULL
  tf_res    <- NULL
  pooled_r_unadj <- metafor::transf.ztor(stats::coef(res_uni)[1])
  pooled_r_adj   <- NA_real_
  
  if (k_rows >= min_studies_for_tests) {
    egger_res <- metafor::regtest(
      res_uni,
      model     = "rma",
      predictor = "sei"
    )
    cat("\nEgger's regression test:\n")
    print(egger_res)
    
    tf_res <- metafor::trimfill(res_uni)
    cat("\nTrim-and-fill model summary:\n")
    print(summary(tf_res))
    
    pooled_z_unadj <- stats::coef(res_uni)[1]
    pooled_z_adj   <- stats::coef(tf_res)[1]
    
    pooled_r_unadj <- metafor::transf.ztor(pooled_z_unadj)
    pooled_r_adj   <- metafor::transf.ztor(pooled_z_adj)
    
    cat("\nPooled effects (unadjusted vs trim-and-fill adjusted):\n")
    cat("  z-unadjusted:", round(pooled_z_unadj, 3),
        " z-adjusted:",   round(pooled_z_adj,   3), "\n")
    cat("  r-unadjusted:", round(pooled_r_unadj, 3),
        " r-adjusted:",   round(pooled_r_adj,   3), "\n")
  } else {
    cat("\nEgger/trimfill skipped: k <", min_studies_for_tests, "\n")
  }
  
  list(
    data_used      = dat_pb,
    res_uni        = res_uni,
    egger          = egger_res,
    trimfill       = tf_res,
    pooled_r_unadj = pooled_r_unadj,
    pooled_r_adj   = pooled_r_adj
  )
}

pb_health_use <- run_pub_bias(
  dat_sub = dat_health_use,
  label   = "Psychological health (USED; per study_id)",
  collapse_to_study = TRUE
)

pb_functioning_use <- run_pub_bias(
  dat_sub = dat_functioning_use,
  label   = "Psychological functioning (USED; per study_id)",
  collapse_to_study = TRUE
)

############################################################
# Helper: summarise a CONTINUOUS moderator across subdomains (CR2 slope)
# - Fits rma.mv with one continuous moderator (with intercept)
# - Uses CR2 (Satterthwaite df)
# - Returns slope beta (z), 95% CI, t, F(1, df), p, and counts
############################################################

summarise_continuous_moderator_by_subdomain <- function(dat_all,
                                                        moderator,
                                                        min_k_study = 2L) {
  if (!moderator %in% names(dat_all)) {
    warning("Moderator ", moderator, " not found in data.")
    return(NULL)
  }
  if (!("subdomain" %in% names(dat_all))) {
    stop("dat_all must contain a 'subdomain' column.")
  }
  
  res_list <- list()
  
  for (sd in levels(dat_all$subdomain)) {
    
    dat_sd <- dat_all %>%
      dplyr::filter(
        subdomain == sd,
        !is.na(.data[[moderator]]),
        !is.na(yi_risk), !is.na(vi_risk),
        vi_risk > 0
      )
    
    if (nrow(dat_sd) < 2) next
    if (dplyr::n_distinct(dat_sd$study_id) < min_k_study) next
    
    form_mod <- stats::as.formula(paste0("~ ", moderator))
    
    fit <- try(
      metafor::rma.mv(
        yi_risk, vi_risk,
        mods   = form_mod,
        random = ~ 1 | study_id/effect_id,
        data   = dat_sd,
        method = "REML"
      ),
      silent = TRUE
    )
    if (inherits(fit, "try-error")) next
    
    V_cr2 <- try(
      clubSandwich::vcovCR(fit, cluster = dat_sd$study_id, type = "CR2"),
      silent = TRUE
    )
    if (inherits(V_cr2, "try-error")) next
    
    ct <- try(
      clubSandwich::coef_test(fit, vcov = V_cr2, test = "Satterthwaite"),
      silent = TRUE
    )
    if (inherits(ct, "try-error")) next
    
    ct_df <- as.data.frame(ct)
    
    # Term names (robust)
    term_vec <- NULL
    if ("term" %in% names(ct_df)) {
      term_vec <- as.character(ct_df$term)
    } else if ("Coefficient" %in% names(ct_df)) {
      term_vec <- as.character(ct_df$Coefficient)
    } else if (!is.null(rownames(ct_df)) && all(nzchar(rownames(ct_df)))) {
      term_vec <- rownames(ct_df)
    } else {
      next
    }
    
    idx <- which(term_vec == moderator)
    if (length(idx) != 1L) next
    
    # Robust column lookup
    beta_candidates <- c("beta", "Beta", "estimate", "Estimate")
    se_candidates   <- c("SE", "se", "StdErr", "Std. Error", "std.error")
    df_candidates   <- c("df_Satt","df","dfs","df_denom","df_Satterthwaite","df_satt")
    t_candidates    <- c("tstat","t","t_stat","t.value","t_value","t-value")
    p_candidates    <- c("p_Satt","p_val","p","pvalue","p.value","p-value")
    
    beta_name <- beta_candidates[beta_candidates %in% names(ct_df)][1]
    se_name   <- se_candidates[se_candidates %in% names(ct_df)][1]
    df_name   <- df_candidates[df_candidates %in% names(ct_df)][1]
    t_name    <- t_candidates[t_candidates %in% names(ct_df)][1]
    p_name    <- p_candidates[p_candidates %in% names(ct_df)][1]
    
    if (is.na(beta_name) || is.na(se_name) || is.na(df_name)) next
    
    beta <- as.numeric(ct_df[[beta_name]][idx])
    se   <- as.numeric(ct_df[[se_name]][idx])
    dfv  <- as.numeric(ct_df[[df_name]][idx])
    
    # t and p may not exist in some versions; compute if needed
    tval <- if (!is.na(t_name)) as.numeric(ct_df[[t_name]][idx]) else beta / se
    Fval <- tval^2
    pval <- if (!is.na(p_name)) as.numeric(ct_df[[p_name]][idx]) else
      stats::pf(Fval, df1 = 1, df2 = dfv, lower.tail = FALSE)
    
    tcrit <- stats::qt(0.975, dfv)
    
    res_list[[sd]] <- data.frame(
      subdomain = sd,
      moderator = moderator,
      beta_z    = beta,
      ci_lb_z   = beta - tcrit * se,
      ci_ub_z   = beta + tcrit * se,
      t_value   = tval,
      F_1_df    = Fval,   # F(1, df_den)
      df_num    = 1,
      df_den    = dfv,
      p_value   = pval,
      n_studies = dplyr::n_distinct(dat_sd$study_id),
      n_effects = nrow(dat_sd),
      stringsAsFactors = FALSE
    )
  }
  
  if (length(res_list) == 0L) {
    warning("No subdomains met min_k_study for continuous moderator: ", moderator)
    return(NULL)
  }
  
  dplyr::bind_rows(res_list) %>%
    dplyr::mutate(subdomain = factor(subdomain, levels = levels(dat_all$subdomain)))
}

############################################################
# Continuous moderator tests (CR2): F(1, df) within each subdomain (USED)
############################################################

gender_F_use <- summarise_continuous_moderator_by_subdomain(
  dat_all      = dat_sub_all_use,
  moderator    = "gender_proportion",
  min_k_study  = 2L
)

white_F_use <- summarise_continuous_moderator_by_subdomain(
  dat_all      = dat_sub_all_use,
  moderator    = "white_proportion",
  min_k_study  = 2L
)

gender_F_use
white_F_use

############################################################
# Plot: continuous moderator slope across subdomains (fixed x-range)
# - Panel x-range fixed to [-0.6, 0.6] (z scale)
# - CI is clipped at panel borders
# - If CI exceeds borders, draw small arrows at the border
# - CI text labels are placed OUTSIDE the panel on the right (x = Inf)
############################################################

make_continuous_moderator_plot <- function(dat_sub_all, moderator,
                                           main_title = NULL,
                                           min_k_study = 2L,
                                           x_panel_limits = c(-0.6, 0.6),   # fixed panel range (z scale)
                                           x_breaks = seq(-0.6, 0.6, 0.2),
                                           show_trunc_arrows = TRUE,
                                           arrow_len = 0.06,               # arrow length in x-units (z scale)
                                           arrow_gap = 0.02,               # gap between border and arrow tail
                                           right_margin_pt = 140) {        # right margin for outside labels
  
  df <- summarise_continuous_moderator_by_subdomain(
    dat_all     = dat_sub_all,
    moderator   = moderator,
    min_k_study = min_k_study
  )
  if (is.null(df) || nrow(df) == 0) return(NULL)
  
  df <- df %>%
    dplyr::mutate(
      ci_label  = sprintf("%.3f [%.3f, %.3f]", beta_z, ci_lb_z, ci_ub_z),
      subdomain = forcats::fct_rev(subdomain)
    )
  
  # Fixed panel limits
  x_min <- x_panel_limits[1]
  x_max <- x_panel_limits[2]
  
  # Clip CI to panel borders and flag truncation
  df <- df %>%
    dplyr::mutate(
      ci_lb_clip = pmax(ci_lb_z, x_min),
      ci_ub_clip = pmin(ci_ub_z, x_max),
      left_trunc  = ci_lb_z < x_min,
      right_trunc = ci_ub_z > x_max
    )
  
  # Arrow data (optional)
  if (show_trunc_arrows) {
    arrow_left_df <- df %>%
      dplyr::filter(left_trunc) %>%
      dplyr::mutate(
        x    = x_min + arrow_gap + arrow_len,
        xend = x_min + arrow_gap,
        y    = subdomain,
        yend = subdomain
      )
    
    arrow_right_df <- df %>%
      dplyr::filter(right_trunc) %>%
      dplyr::mutate(
        x    = x_max - arrow_gap - arrow_len,
        xend = x_max - arrow_gap,
        y    = subdomain,
        yend = subdomain
      )
  } else {
    arrow_left_df  <- NULL
    arrow_right_df <- NULL
  }
  
  p <- ggplot2::ggplot(df, ggplot2::aes(y = subdomain, x = beta_z)) +
    ggplot2::geom_vline(xintercept = 0, colour = "grey30") +
    
    # CI bars clipped to panel
    ggplot2::geom_errorbarh(
      ggplot2::aes(xmin = ci_lb_clip, xmax = ci_ub_clip),
      height = 0.15, linewidth = 0.6
    ) +
    
    # Point estimate (still plotted; will be clipped if outside panel)
    ggplot2::geom_point(size = 3) +
    
    # CI label placed outside panel (right side)
    ggplot2::geom_text(
      ggplot2::aes(x = Inf, label = ci_label),
      hjust = -0.10, size = 3
    ) +
    
    ggplot2::labs(
      title = if (is.null(main_title)) paste0("Continuous moderator: ", moderator) else main_title,
      x = "Slope (Fisher's z per 1.0 increase in moderator)",
      y = NULL
    ) +
    
    ggplot2::scale_x_continuous(
      limits = c(x_min, x_max),
      breaks = x_breaks,
      expand = ggplot2::expansion(mult = c(0, 0)),
      labels = function(x) sprintf("%.1f", x)
    ) +
    
    ggplot2::theme_bw() +
    ggplot2::coord_cartesian(xlim = c(x_min, x_max), clip = "off") +
    ggplot2::theme(
      plot.margin      = ggplot2::margin(5.5, right_margin_pt, 5.5, 5.5),
      panel.border     = ggplot2::element_blank(),
      plot.background  = ggplot2::element_blank()
    )
  
  # Add truncation arrows on top (optional)
  if (show_trunc_arrows) {
    if (!is.null(arrow_left_df) && nrow(arrow_left_df) > 0) {
      p <- p + ggplot2::geom_segment(
        data = arrow_left_df,
        ggplot2::aes(x = x, xend = xend, y = y, yend = yend),
        inherit.aes = FALSE,
        linewidth = 0.6,
        arrow = ggplot2::arrow(type = "closed", length = grid::unit(0.10, "inches"))
      )
    }
    if (!is.null(arrow_right_df) && nrow(arrow_right_df) > 0) {
      p <- p + ggplot2::geom_segment(
        data = arrow_right_df,
        ggplot2::aes(x = x, xend = xend, y = y, yend = yend),
        inherit.aes = FALSE,
        linewidth = 0.6,
        arrow = ggplot2::arrow(type = "closed", length = grid::unit(0.10, "inches"))
      )
    }
  }
  
  p
}

############################################################
# 11. Moderator summary plots across four subdomains (USED)
############################################################
make_moderator_plot <- function(dat_sub_all,
                                moderator,
                                pretty_recode = NULL,
                                main_title = NULL,
                                min_k = 2L,
                                heading_shift = 0.18,
                                level_order = NULL,
                                x_panel_limits = c(-0.6, 0.6),  # fixed panel x-range (data area)
                                x_breaks = seq(-0.6, 0.6, by = 0.2),
                                right_pad = 0.02,               # gap between panel and right columns (x units)
                                right_margin_pt = 200,          # right margin (points) for outside columns
                                left_margin_pt  = 140,          # left margin (points) for outside headers
                                header_hjust    = -0.05,        # negative -> push header further left
                                show_trunc_arrows = TRUE,       # draw arrows if CI exceeds panel limits
                                arrow_len = 0.035,              # arrow length in x-units (r scale)
                                arrow_gap = 0.010,              # gap between border and arrow tail
                                arrow_y_nudge = 0) {            # vertical nudge for arrows (rarely needed)
  
  mod_df <- summarise_moderator_by_subdomain(
    dat_all   = dat_sub_all,
    moderator = moderator,
    min_k     = min_k
  )
  
  if (is.null(mod_df) || nrow(mod_df) == 0L) {
    warning("No usable cells for moderator ", moderator,
            " under min_k = ", min_k, "; plot not created.")
    return(NULL)
  }
  
  # which subdomains you want to flip sign in the plot
  flip_sds <- c("Health – ill-being", "Functioning – maladaptive")
  
  mod_df <- mod_df %>%
    dplyr::mutate(
      level_pretty = as.character(level),
      
      # flip sign for selected subdomains (NOTE: CI bounds must swap)
      est_r_plot   = dplyr::if_else(subdomain %in% flip_sds, -est_r, est_r),
      ci_lb_r_plot = dplyr::if_else(subdomain %in% flip_sds, -ci_ub_r, ci_lb_r),
      ci_ub_r_plot = dplyr::if_else(subdomain %in% flip_sds, -ci_lb_r, ci_ub_r),
      
      ci_label     = sprintf("%.2f [%.2f, %.2f]", est_r_plot, ci_lb_r_plot, ci_ub_r_plot)
    )
  
  
  if (!is.null(pretty_recode)) {
    mod_df$level_pretty <- dplyr::recode(mod_df$level, !!!pretty_recode)
  }
  
  # Build plotting rows (effects)
  effects_df <- mod_df %>%
    dplyr::mutate(
      row_id      = paste0(as.character(subdomain), " | ", level_pretty),
      header_text = as.character(subdomain)
    )
  
  # Enforce within-subdomain order (after effects_df exists)
  if (!is.null(level_order)) {
    effects_df <- effects_df %>%
      dplyr::mutate(level_pretty = factor(level_pretty, levels = level_order)) %>%
      dplyr::arrange(subdomain, level_pretty) %>%
      dplyr::mutate(
        row_id = paste0(as.character(subdomain), " | ", as.character(level_pretty))
      )
  }
  
  # Header rows
  header_df <- effects_df %>%
    dplyr::distinct(subdomain) %>%
    dplyr::mutate(
      level_pretty = NA_character_,
      row_id       = paste0(as.character(subdomain), " | HEADER"),
      est_r        = NA_real_,
      ci_lb_r      = NA_real_,
      ci_ub_r      = NA_real_,
      ci_label     = "",
      n_studies    = NA_integer_,
      n_effects    = NA_integer_,
      header_text  = as.character(subdomain)
    )
  
  # Build row order: header first, then each level under that subdomain
  row_order <- c()
  for (sd in levels(effects_df$subdomain)) {
    row_order <- c(
      row_order,
      paste0(sd, " | HEADER"),
      effects_df$row_id[effects_df$subdomain == sd]
    )
  }
  row_order <- unique(row_order)
  
  combined_df <- dplyr::bind_rows(
    header_df  %>% dplyr::mutate(row_type = "header"),
    effects_df %>% dplyr::mutate(row_type = "effect")
  ) %>%
    dplyr::mutate(
      row_id = factor(row_id, levels = rev(row_order))
    )
  
  effects_plot_df <- combined_df %>% dplyr::filter(row_type == "effect")
  headers_plot_df <- combined_df %>% dplyr::filter(row_type == "header")
  
  # ---------------------------
  # Fixed panel x-range (data area)
  # ---------------------------
  x_min_data <- x_panel_limits[1]
  x_max_data <- x_panel_limits[2]
  
  # ---------------------------
  # Right-side column x positions (IMPORTANT: do NOT use Inf)
  # These x values are outside the panel; they will still be drawn because
  # we use coord_cartesian(xlim=..., clip="off") and large right margin.
  # ---------------------------
  stud_x <- x_max_data + right_pad + 0.02
  eff_x  <- x_max_data + right_pad + 0.08
  ci_x   <- x_max_data + right_pad + 0.14
  
  # Column header x positions (align with the columns)
  stud_head_x <- stud_x
  eff_head_x  <- eff_x
  ci_head_x   <- ci_x
  
  # ---------------------------
  # Arrow data: mark CIs that exceed the panel limits
  # (Clip error bars at the border and add small arrows indicating truncation.)
  # ---------------------------
  if (show_trunc_arrows) {
    effects_plot_df <- effects_plot_df %>%
      dplyr::mutate(
        ci_lb_clip = pmax(ci_lb_r_plot, x_min_data),
        ci_ub_clip = pmin(ci_ub_r_plot, x_max_data),
        left_trunc  = ci_lb_r_plot < x_min_data,
        right_trunc = ci_ub_r_plot > x_max_data
              )
    
    # Left arrows (pointing left)
    arrow_left_df <- effects_plot_df %>%
      dplyr::filter(left_trunc) %>%
      dplyr::mutate(
        x    = x_min_data + arrow_gap + arrow_len,
        xend = x_min_data + arrow_gap,
        y    = row_id,
        yend = row_id
      )
    
    # Right arrows (pointing right)
    arrow_right_df <- effects_plot_df %>%
      dplyr::filter(right_trunc) %>%
      dplyr::mutate(
        x    = x_max_data - arrow_gap - arrow_len,
        xend = x_max_data - arrow_gap,
        y    = row_id,
        yend = row_id
      )
  } else {
    effects_plot_df <- effects_plot_df %>%
      dplyr::mutate(
        ci_lb_clip = ci_lb_r,
        ci_ub_clip = ci_ub_r
      )
    arrow_left_df  <- NULL
    arrow_right_df <- NULL
  }
  
  p <- ggplot2::ggplot() +
    ggplot2::geom_vline(xintercept = 0, colour = "grey30") +
    
    # Error bars (clipped to panel limits)
    ggplot2::geom_errorbarh(
      data  = effects_plot_df,
      ggplot2::aes(y = row_id, xmin = ci_lb_clip, xmax = ci_ub_clip, colour = subdomain),
      height = 0.15, linewidth = 0.6
    ) +
    
    # Points
    ggplot2::geom_point(
      data = effects_plot_df,
      ggplot2::aes(y = row_id, x = est_r_plot, colour = subdomain),
      size = 3
    ) +
    
    # Right-side columns (outside panel): separate by different x positions
    ggplot2::geom_text(
      data = effects_plot_df,
      ggplot2::aes(y = row_id, x = stud_x, label = n_studies),
      hjust = 0, size = 3
    ) +
    ggplot2::geom_text(
      data = effects_plot_df,
      ggplot2::aes(y = row_id, x = eff_x, label = n_effects),
      hjust = 0, size = 3
    ) +
    ggplot2::geom_text(
      data = effects_plot_df,
      ggplot2::aes(y = row_id, x = ci_x, label = ci_label),
      hjust = 0, size = 3
    ) +
    
    # Left-side subdomain headers (outside panel)
    ggplot2::geom_text(
      data = headers_plot_df,
      ggplot2::aes(y = row_id, x = -Inf, label = header_text),
      fontface = "bold",
      size     = 3.2,
      hjust    = 1.00,
      vjust    = 0.5
    ) +
    
    # IMPORTANT: do NOT set limits here, otherwise outside text gets dropped
    ggplot2::scale_x_continuous(
      breaks = x_breaks,
      expand = ggplot2::expansion(mult = c(0, 0)),
      labels = function(x) sprintf("%.1f", x)
    ) +
    
    ggplot2::scale_y_discrete(
      limits = levels(combined_df$row_id),
      labels = function(x) {
        is_header <- grepl("\\|\\s*HEADER$", x)
        lab <- sub(".*\\|", "", x)
        lab <- trimws(lab)
        ifelse(is_header, "", lab)
      }
    ) +
    
    ggplot2::labs(
      title = if (is.null(main_title)) paste0("Moderator: ", moderator) else main_title,
      x     = "Correlation",
      y     = NULL
    ) +
    
    # Column headings (outside panel) aligned with the columns
    ggplot2::annotate("text", x = stud_head_x, y = Inf, label = "Studies",
                      vjust = 1.5, hjust = 0.5, size = 3) +
    ggplot2::annotate("text", x = eff_head_x,  y = Inf, label = "Effects",
                      vjust = 1.5, hjust = 0.5, size = 3) +
    ggplot2::annotate("text", x = ci_head_x,   y = Inf, label = "95% CI",
                      vjust = 1.5, hjust = 0.05, size = 3) +
    
    ggplot2::theme_bw() +
    # This fixes the visible panel to [-0.6, 0.6] while keeping outside text
    ggplot2::coord_cartesian(xlim = c(x_min_data, x_max_data), clip = "off") +
    ggplot2::theme(
      panel.grid.major.y = ggplot2::element_blank(),
      legend.position    = "none",
      plot.margin        = ggplot2::margin(5.5, right_margin_pt, 5.5, left_margin_pt),
      panel.border       = ggplot2::element_blank(),
      axis.ticks.y       = ggplot2::element_blank()
    )
  
  # Add truncation arrows (drawn on top of error bars)
  if (show_trunc_arrows) {
    if (!is.null(arrow_left_df) && nrow(arrow_left_df) > 0) {
      p <- p + ggplot2::geom_segment(
        data = arrow_left_df,
        ggplot2::aes(x = x, xend = xend, y = y, yend = yend),
        inherit.aes = FALSE,
        linewidth = 0.6,
        arrow = ggplot2::arrow(type = "closed", length = grid::unit(0.10, "inches"))
      )
    }
    if (!is.null(arrow_right_df) && nrow(arrow_right_df) > 0) {
      p <- p + ggplot2::geom_segment(
        data = arrow_right_df,
        ggplot2::aes(x = x, xend = xend, y = y, yend = yend),
        inherit.aes = FALSE,
        linewidth = 0.6,
        arrow = ggplot2::arrow(type = "closed", length = grid::unit(0.10, "inches"))
      )
    }
  }
  
  p
}

############################################################
# 11.1 Examples: draw moderator plots (USED)
############################################################

plot_edu_use <- make_moderator_plot(
  dat_sub_all  = dat_sub_all_use,
  moderator    = "educational_stage",
  main_title   = "Moderator: Educational stage",
  level_order  = c("Secondary", "Undergraduate", "Graduate", "Mixed")
)
plot_edu_use

plot_measure_use <- make_moderator_plot(
  dat_sub_all = dat_sub_all_use,
  moderator   = "measure_IP",
  main_title  = "Moderator: IP measure"
)
plot_measure_use

plot_region_use <- make_moderator_plot(
  dat_sub_all = dat_sub_all_use,
  moderator   = "region",
  main_title  = "Moderator: Region"
)
plot_region_use

plot_construct_use <- make_moderator_plot(
  dat_sub_all  = dat_sub_all_use,
  moderator    = "construct_outcome",
  pretty_recode = NULL,
  main_title   = "Moderator: Construct",
  min_k        = 2L
)
plot_construct_use

plot_subject_use <- make_moderator_plot(
  dat_sub_all  = dat_sub_all_use,
  moderator    = "subject",
  main_title   = "Moderator: Subject",
  level_order  = c("Natural/Engineering Sciences", "Social Sciences", "Health Sciences", "Multidisciplinary")
)
plot_subject_use

plot_gender_slope_use <- make_continuous_moderator_plot(
  dat_sub_all = dat_sub_all_use,
  moderator   = "gender_proportion",
  main_title  = "Continuous moderator: Female proportion"
)
plot_gender_slope_use

plot_white_slope_use <- make_continuous_moderator_plot(
  dat_sub_all = dat_sub_all_use,
  moderator   = "white_proportion",
  main_title  = "Continuous moderator: White proportion"
)
plot_white_slope_use

############################################################
# gender proportion
############################################################
df_scatter <- dat_sub_all_use %>%
  dplyr::filter(!is.na(gender_proportion), !is.na(yi_risk), !is.na(vi_risk)) %>%
  dplyr::mutate(
    female_pct = 100 * as.numeric(gender_proportion),
    r_effect   = metafor::transf.ztor(yi_risk)
  )

ggplot(df_scatter, aes(x = female_pct, y = r_effect)) +
  geom_point(size = 1.6, alpha = 0.75) +
  geom_smooth(method = "lm", se = TRUE) +
  facet_wrap(~ subdomain, ncol = 1) +
  labs(
    title = "Effect sizes vs Female proportion (by subdomain)",
    x = "Proportion of Female Participants (%)",
    y = "Effect Size (r)"
  ) +
  theme_bw()

############################################################
#  White proportion
############################################################

df_scatter_white <- dat_sub_all_use %>%
  dplyr::filter(!is.na(white_proportion), !is.na(yi_risk)) %>%
  dplyr::mutate(
    r_risk = metafor::transf.ztor(yi_risk)
    # If you prefer 0–100 on x-axis:
    # white_pct = 100 * white_proportion
  )

ggplot2::ggplot(df_scatter_white,
                ggplot2::aes(x = white_proportion, y = r_risk)) +
  ggplot2::geom_point(size = 1.5, alpha = 0.7) +
  ggplot2::geom_smooth(method = "lm", se = TRUE) +
  ggplot2::facet_wrap(~ subdomain, ncol = 1) +
  ggplot2::labs(
    title = "Effect sizes (r) vs White proportion (by subdomain)",
    x     = "White proportion (0–1)",
    y     = "Effect size (r; risk-direction)"
  ) +
  ggplot2::theme_bw()

# ============================================================
# Helper: level-specific pooled r (CR2) for a CATEGORICAL moderator
# - Fits no-intercept rma.mv within ONE subdomain dataset
# - Uses CR2 + Satterthwaite df for CI
# - Returns level-specific estimates in Fisher's z and r + p-values
# ============================================================

summarise_categorical_levels_CR2_p <- function(dat_sub,
                                               moderator,
                                               min_k_effect = 2L) {
  stopifnot(moderator %in% names(dat_sub))
  
  dat_m <- dat_sub %>%
    dplyr::filter(!is.na(.data[[moderator]]),
                  !is.na(yi_risk), !is.na(vi_risk),
                  vi_risk > 0)
  
  if (nrow(dat_m) == 0) {
    warning("No usable rows for moderator: ", moderator)
    return(NULL)
  }
  
  # Keep levels that meet the effect-size threshold
  k_tab <- table(dat_m[[moderator]])
  keep_levels <- names(k_tab)[k_tab >= min_k_effect]
  
  if (length(keep_levels) == 0) {
    warning("No levels met min_k_effect = ", min_k_effect,
            " for moderator: ", moderator)
    return(NULL)
  }
  
  dat_m <- dat_m %>%
    dplyr::filter(.data[[moderator]] %in% keep_levels) %>%
    dplyr::mutate(.mod = factor(.data[[moderator]], levels = keep_levels))
  
  # Study/effect counts per level
  counts <- dat_m %>%
    dplyr::group_by(.mod) %>%
    dplyr::summarise(
      n_studies = dplyr::n_distinct(study_id),
      n_effects = dplyr::n(),
      .groups = "drop"
    ) %>%
    dplyr::rename(level = .mod)
  
  # No-intercept model for level-specific pooled effects
  fit <- metafor::rma.mv(
    yi_risk, vi_risk,
    mods   = ~ .mod - 1,
    random = ~ 1 | study_id/effect_id,
    data   = dat_m,
    method = "REML"
  )
  
  V_cr2 <- clubSandwich::vcovCR(fit, cluster = dat_m$study_id, type = "CR2")
  ct    <- clubSandwich::coef_test(fit, vcov = V_cr2, test = "Satterthwaite")
  ct_df <- as.data.frame(ct)
  
  # Term names (robust)
  term_vec <- NULL
  if ("term" %in% names(ct_df)) {
    term_vec <- as.character(ct_df$term)
  } else if ("Coefficient" %in% names(ct_df)) {
    term_vec <- as.character(ct_df$Coefficient)
  } else {
    term_vec <- rownames(ct_df)
  }
  
  # Robust column lookup across clubSandwich versions
  beta_candidates <- c("beta","Beta","estimate","Estimate")
  se_candidates   <- c("SE","se","StdErr","Std. Error","std.error")
  df_candidates   <- c("df_Satt","df","dfs","df_denom","df_Satterthwaite","df_satt")
  t_candidates    <- c("tstat","t","t_stat","t.value","t_value","t-value")
  p_candidates    <- c("p_Satt","p_val","p","pvalue","p.value","p-value")
  
  beta_name <- beta_candidates[beta_candidates %in% names(ct_df)][1]
  se_name   <- se_candidates[se_candidates %in% names(ct_df)][1]
  df_name   <- df_candidates[df_candidates %in% names(ct_df)][1]
  t_name    <- t_candidates[t_candidates %in% names(ct_df)][1]
  p_name    <- p_candidates[p_candidates %in% names(ct_df)][1]
  
  if (is.na(beta_name) || is.na(se_name) || is.na(df_name)) {
    stop("coef_test output missing required columns. Available: ",
         paste(names(ct_df), collapse = ", "))
  }
  
  beta <- as.numeric(ct_df[[beta_name]])
  se   <- as.numeric(ct_df[[se_name]])
  dfv  <- as.numeric(ct_df[[df_name]])
  
  # t / p (compute if missing)
  tval <- if (!is.na(t_name)) as.numeric(ct_df[[t_name]]) else beta / se
  pval <- if (!is.na(p_name)) as.numeric(ct_df[[p_name]]) else
    2 * stats::pt(abs(tval), df = dfv, lower.tail = FALSE)
  
  # CI
  tcrit <- stats::qt(0.975, df = dfv)
  
  out <- data.frame(
    level   = term_vec,
    est_z   = beta,
    se_z    = se,
    ci_lb_z = beta - tcrit * se,
    ci_ub_z = beta + tcrit * se,
    t_value = tval,
    df_den  = dfv,
    p_value = pval,
    stringsAsFactors = FALSE
  )
  
  # Clean label
  out$level <- gsub("^\\.mod", "", out$level)
  
  out <- out %>%
    dplyr::mutate(
      est_r   = metafor::transf.ztor(est_z),
      ci_lb_r = metafor::transf.ztor(ci_lb_z),
      ci_ub_r = metafor::transf.ztor(ci_ub_z),
      r_ci    = sprintf("%.3f [%.3f, %.3f]", est_r, ci_lb_r, ci_ub_r)
    ) %>%
    dplyr::left_join(counts, by = "level") %>%
    dplyr::arrange(match(level, keep_levels))
  
  out
}

# ============================================================
# Helper: print full error location (so you can see which line)
# ============================================================

run_with_trace <- function(expr) {
  tryCatch(
    expr,
    error = function(e) {
      message("ERROR: ", e$message)
      traceback()
      stop(e)
    }
  )
}

# ============================================================
# Example 1) Academic subject -> ill-being (level-specific pooled r + p)
# ============================================================

run_with_trace({
  subject_ill_r_CR2_p <- summarise_categorical_levels_CR2_p(
    dat_sub      = dat_health_ill_use,
    moderator    = "subject",
    min_k_effect = 2L
  )
  print(subject_ill_r_CR2_p %>%
          dplyr::select(level, n_studies, n_effects, est_r, ci_lb_r, ci_ub_r, p_value, r_ci))
})

# ============================================================
# Example 2) Educational stage -> well-being (level-specific pooled r + p)
# ============================================================

run_with_trace({
  edu_wb_r_CR2_p <- summarise_categorical_levels_CR2_p(
    dat_sub      = dat_health_wb_use,
    moderator    = "educational_stage",
    min_k_effect = 2L
  )
  print(edu_wb_r_CR2_p %>%
          dplyr::select(level, n_studies, n_effects, est_r, ci_lb_r, ci_ub_r, p_value, r_ci))
})
