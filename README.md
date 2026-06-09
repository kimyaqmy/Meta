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
```

**Supporting reference file:**

```text
.agents/skills/meta-analysis-r-reporting/references/rmarkdown_reporting.md
```

**Use this skill when you need Codex to:**

- inspect extracted meta-analysis workbooks;
- identify study IDs, effect IDs, sample sizes, moderators, domains, and outcome variables;
- decide whether the analysis should use Pearson r/Fisher z or SMD/Hedges g;
- convert effect sizes from reported statistics;
- generate or adapt reusable R scripts;
- run multilevel `metafor` models;
- apply `clubSandwich` CR2 robust tests;
- conduct moderator, subgroup, influence, outlier, and publication-bias analyses;
- produce forest plots, funnel plots, scatter plots, and moderator figures;
- generate manuscript-ready Word, HTML, or PDF R Markdown reports.

## Installation

### Recommended: install with Codex

In Codex, ask:

```text
Use $skill-installer.

Install the skill from:
https://github.com/kimyaqmy/Meta/tree/main/.agents/skills/meta-analysis-r-reporting
```

After installation, restart Codex so the new skill is available.

To verify that Codex can see the skill, start a new task with:

```text
Use $meta-analysis-r-reporting.
```

### Manual fallback

If you prefer to install the skill manually, copy this folder:

```text
.agents/skills/meta-analysis-r-reporting
```

into your local Codex skills directory as:

```text
~/.codex/skills/meta-analysis-r-reporting
```

Then restart Codex and start a new task with:

```text
Use $meta-analysis-r-reporting.
```

## How to Use This Skill in Codex

After installing the skill, or after opening this repository directly in Codex, start your task with:

```text
Use $meta-analysis-r-reporting.
```

For example:

```text
Use $meta-analysis-r-reporting.

Please inspect this extracted meta-analysis Excel dataset, identify the effect-size type, generate the appropriate R analysis script, run the analysis if possible, and create manuscript-ready Word/HTML results summaries with tables and figures.
```

If Codex does not automatically load the skill, explicitly ask it to read:

```text
Please read `.agents/skills/meta-analysis-r-reporting/SKILL.md` first and follow its instructions.
```

For R Markdown or Word report tasks, also ask it to read:

```text
Please also read `.agents/skills/meta-analysis-r-reporting/references/rmarkdown_reporting.md` before generating the report.
```

## Repository Structure

```text
Meta/
├── README.md
└── .agents/
    └── skills/
        └── meta-analysis-r-reporting/
            ├── SKILL.md
            └── references/
                └── rmarkdown_reporting.md
```

## Typical Use Cases

- Generate a complete R meta-analysis script from an extracted Excel file.
- Adapt an existing meta-analysis pipeline to a new dataset.
- Convert reported statistics into Pearson r, Fisher z, Cohen's d, or Hedges g.
- Run multilevel meta-analysis models with nested effect sizes.
- Apply CR2 robust variance estimation.
- Test categorical and continuous moderators.
- Create publication-bias diagnostics.
- Build manuscript-style Results sections with tables and figures.
- Generate Word, HTML, or PDF reports from R Markdown.
- Audit whether model outputs, sample counts, and reporting tables are consistent.

## Notes

This repository is not a general-purpose meta-analysis textbook. It is a practical Codex skill repository for reusable R-based meta-analysis workflows.

The skill assumes that study information or effect-size data have already been extracted into structured Excel or CSV files. It does not replace careful screening, coding, or risk-of-bias assessment, but it can help standardize the analysis and reporting workflow after extraction.

## For AI Assistants and Coding Agents

When using this repository, treat the following file as the main source of workflow instructions:

```text
.agents/skills/meta-analysis-r-reporting/SKILL.md
```

When generating R Markdown reports, manuscript-style Word summaries, HTML reports, PDF reports, tables, and figures, also consult:

```text
.agents/skills/meta-analysis-r-reporting/references/rmarkdown_reporting.md
```

Do not rely on old project-specific labels, domains, moderators, or variable names unless they appear in the live dataset or are explicitly defined by the user. Always inspect the uploaded workbook before generating or adapting analysis code.
