Date: 2026-04-23

## Framing of the AR test

The goal is to test whether politically driven reallocation of BNDES credit across sectors affects municipal GDP. The identifying shock combines political turnover (mayoral elections) with baseline political affiliation of firms — sectors whose firms were connected to the incoming party gain access, those connected to the outgoing party lose it. This is arguably exogenous to local economic conditions because the variation comes from the interaction of national party identity with pre-existing firm-owner partisanship, not from local demand shocks.

We are exploring multiple ways to operationalize the test. The exercises below are complementary approaches, not a single pipeline.

## Main task

Start the Anderson-Rubin (AR) test. Reduced-form OLS regressions of log GDP on sector-level instruments using the four coarse BNDES sectors (Agropecuária, Indústria, Infraestrutura, Comércio e Serviços). Controls: municipality FE + year FE.

## Construction ideas
    
- Use the step-0 first-stage results (BNDES loans regressed on instruments) to construct predicted sectoral loans. These predicted loans become the right-hand-side variables in the GDP regression, making the 2SLS mechanism transparent: instruments -> predicted loans -> GDP.
- On the right-hand side, explore variations: (a) shares of sector loans, (b) importance/employment measures such as share of aligned employment or share of aligned firms within a sector.
- Try employment in logs and in shares as functional forms.
- Run log GDP on log employment as a direct relationship check.
- Run log GDP on shares of BNDES money going to different sectors.
- Control for total disbursements as a share of initial GDP. Note: there is a log issue with this ratio that needs careful thought (log of a ratio bounded in [0,1], potential zeros).
- Consider aggregating using the share of employment that is aligned — i.e., the share of municipal employment in firms that receive a loan or are politically connected. This differs from the current emp_share_weighted (which weights by employment share regardless of alignment) because it conditions on treatment status, measuring political exposure through the labor market rather than through the loan channel.

## Open question (explore later)

The first stage shows instruments predict employment (F up to 265) but not loan amounts (F ~ 6). Why does employment respond but loans do not? This may suggest the mechanism runs through hiring/labor allocation rather than credit allocation. Worth investigating once the baseline AR test is in place.
