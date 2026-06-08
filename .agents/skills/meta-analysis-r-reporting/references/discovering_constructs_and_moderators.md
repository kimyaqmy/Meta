# Discovering Constructs and Moderators From a New Workbook

Use this before adapting any reference script's domain, subdomain, construct, moderator, or plot-label blocks.

## Core rule

Do not inherit old project labels. Labels in reference scripts are examples of code structure, not reusable substantive categories.

Examples of labels that must not be copied unless they appear in the new workbook or are explicitly defined by the user:

- `psychological health`
- `psychological functioning`
- `well-being`
- `ill-being`
- `adaptive functioning`
- `maladaptive functioning`
- `Needs`
- `Motivation`
- `Technology_Category`
- `Grade_Level`
- `Learning_Subject`
- `literacy_type`
- `antecedent`

## Discovery workflow

1. Inspect all sheets in the workbook.
2. List column names and identify plausible analytic grouping columns.
3. Standardize synonymous column names, but do not standardize values into old project categories.
4. Print unique values and missing counts for candidate columns.
5. Choose model/subgroup/moderator variables from the observed columns and user instructions.
6. Generate labels and output filenames from the selected variables and levels.

## Useful R inspection block

Insert a block like this near the start of adapted scripts:

```r
candidate_group_cols <- intersect(
  c(
    "construct_outcome", "construct_category", "construct_subcategory",
    "outcome_domain", "outcome_subdomain",
    "domain", "subdomain", "category", "subcategory",
    "moderator", "construct", "measure", "scale"
  ),
  names(dat_raw)
)

for (cc in candidate_group_cols) {
  cat("\n================", cc, "================\n")
  print(table(dat_raw[[cc]], useNA = "ifany"))
}
```

For one/two stream scripts, run the same inspection separately on each imported workbook before combining.

## Value recoding

Only recode values when:

- The new workbook contains obvious spelling/capitalization variants of the same value.
- The user gives a coding scheme.
- A local codebook or extraction instruction file defines the mapping.

Do not collapse values because the old script did so. For example, do not map a new construct into `Needs` or `Motivation` unless the new meta-analysis actually uses those categories.

## Model generation

When adapting a reference model block:

- Replace hard-coded subgroup filters with variables selected from the new workbook.
- Build lists of levels dynamically from non-missing observed values.
- Keep minimum-k checks before fitting subgroup/moderator models.
- If a selected grouping column has one level, skip the moderator model and report why.

## Plot labels

Generate plot labels from the new variable names and values. Old labels belong to the old manuscript and should be replaced.

If the new workbook has no domain/subdomain/moderator columns, write the main model only and state that subgroup/moderator analyses require additional coded columns.
