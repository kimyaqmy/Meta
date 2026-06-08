# Meta-analysis R Skills

A focused repository of reusable Codex skills for meta-analysis workflows, especially R-based data analysis, effect-size conversion, robust meta-analytic modeling, diagnostic checking, and manuscript-ready reporting.

This repository is designed for researchers working with already-extracted study-level or effect-size datasets in Excel or CSV format. It helps Codex generate, adapt, audit, run, and report reproducible R/R Markdown meta-analysis pipelines.

## What are Codex Skills?

Codex Skills are portable instruction packages for AI coding agents. A skill is usually a folder containing a `SKILL.md` file, plus optional reference files, scripts, templates, examples, or reporting rules.

In this repository, the skill tells Codex how to handle meta-analysis projects consistently: inspect the extracted data, identify the correct effect-size family, adapt reusable R pipelines, run `metafor` models, apply CR2 robust tests, check diagnostics, and create manuscript-ready reports.

## Available Skill

### meta-analysis-r-reporting

**Best for:** education, psychology, health, and social-science meta-analysis projects using extracted Excel/CSV datasets.

**Skill path:**

```text
.agents/skills/meta-analysis-r-reporting/SKILL.md

Supporting reference file:

.agents/skills/meta-analysis-r-reporting/references/rmarkdown_reporting.md

Use this skill when you need Codex to:

inspect extracted meta-analysis workbooks;
identify study IDs, effect IDs, sample sizes, moderators, domains, and outcome variables;
decide whether the analysis should use Pearson r/Fisher z or SMD/Hedges g;
convert effect sizes from reported statistics;
generate or adapt reusable R scripts;
run multilevel metafor models;
apply clubSandwich CR2 robust tests;
conduct moderator, subgroup, influence, outlier, and publication-bias analyses;
produce forest plots, funnel plots, scatter plots, and moderator figures;
generate manuscript-ready Word, HTML, or PDF R Markdown reports.
How to Use This Skill in Codex

Open this repository in Codex, then start your task with:
