Date: 2026-04-17

## Regression Tasks

- Run the full battery of firm-level and aggregated regressions using the new employment weights (share of employment within a municipality), splitting the sample by quartiles of municipality employment.
- Run aggregated regressions with employment outcomes on the left-hand side and the different instruments as explanatory variables — full sample and by quartiles of municipality employment.
- Run the full battery from `paper/meetings/first_stage.tex` and `paper/meetings/agg_first_stage.tex` using the new sector classification of terciles within the four aggregated BNDES sectors.

## Anderson-Rubin Test

Start exploring the regression of log real GDP on the instruments, using municipality FEs and year FEs as controls. Try with and without total municipality employment. Open question: can this be run municipality by municipality, and in what share of municipalities do we reject the null?

## Data Tasks

- Verify whether the current real GDP variable was constructed using spatial deflators.
- Explore employment data from sources other than RAIS, by municipality and year. More broadly, investigate data on production factor supply by municipality: employment by age and sector, education, total capital, productive land.
- Explore local price deflators: yearly frequency, municipality-level granularity, frequency of updates, and geographic unit size.

## Methodological Note

When using many sectors on the right-hand side in the AR test, the number of regressors grows rapidly with the number of instruments. Explore penalized regression methods (LASSO, ridge) and evaluate their suitability for this setting.
