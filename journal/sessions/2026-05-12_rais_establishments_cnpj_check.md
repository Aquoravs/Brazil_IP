# 2026-05-12 RAIS Establishments CNPJ Check

## 2026-05-12 15:52 - BD RAIS Establishment Sample

**Operations:**
- Queried BigQuery metadata for `basedosdados.br_me_rais.microdados_estabelecimentos`.
- Downloaded a 40-row sample from 2002 and 2017 to `tmp/rais_estabelecimentos_bd_sample_2002_2017.csv`.
- Copied the sample to `explorations/firm_universe/rais_coverage_audit/output/rais_estabelecimentos_bd_sample_2002_2017.csv`.
- Checked companion `basedosdados.br_me_rais.microdados_vinculos` metadata for CNPJ-like fields.

**Decisions:**
- Treated `microdados_estabelecimentos` as the table from the Base dos Dados link and used 2002 plus 2017 as the two in-window years.

**Results:**
- The establishment table has 26 columns and no `cnpj`, `cpf`, `cnpj_basico`, `raiz`, `id_estabelecimento`, or equivalent firm/establishment identifier.
- The only establishment-named fields are descriptors: `natureza_estabelecimento`, `tamanho_estabelecimento`, and `tipo_estabelecimento`.
- Current project matching keys remain available locally as 8-digit `firm_id` roots and 14-digit BNDES loan-level `cnpj`, but the BD RAIS establishments table cannot match to either key.

**Commits:**
- None.

**Status:**
- Done: sample downloaded and CNPJ availability checked.
- Pending: if a CNPJ-level RAIS source is required, identify a restricted/local RAIS file or another source that preserves establishment identifiers.
