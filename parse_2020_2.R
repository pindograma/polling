# parse_2020_2.R
# (c) 2020 CincoNoveSeis Jornalismo Ltda.

# MUST VERIFY:
# - dup_polls
# - multiple scenarios
# - total and relation to vv

library(tidyverse)
library(stringi)
library(lubridate)
library(mgsub)
library(fastdigest)

library(sqldf)
options('sqldf.dll' = paste0(getwd(), '/', 'spellfix.so'))

Rcpp::sourceCpp('src/wordmatch.cpp')
source('polling_utils.R')
source('poll_to_candidate_matcher.R')

cands = read_csv2('data/tse/consulta_cand_2020_BRASIL.csv', locale = locale(encoding = 'ISO-8859-1')) %>%
  rename(NOME_CANDIDATO = NM_CANDIDATO, NOME_URNA_CANDIDATO = NM_URNA_CANDIDATO,
         CODIGO_CARGO = CD_CARGO, SIGLA_UE = SG_UE, NUMERO_CANDIDATO = NR_CANDIDATO,
         NUM_TURNO = NR_TURNO) %>%
  select(NOME_CANDIDATO, NOME_URNA_CANDIDATO, CODIGO_CARGO, SIGLA_UE, NUMERO_CANDIDATO, NUM_TURNO, ANO_ELEICAO) %>%
  mutate(NOME_CANDIDATO = normalize_cand(NOME_CANDIDATO)) %>%
  mutate(NOME_URNA_CANDIDATO = normalize_cand(NOME_URNA_CANDIDATO)) %>%
  mutate(CODIGO_CARGO = ifelse(CODIGO_CARGO == 8, 7, CODIGO_CARGO)) %>%
  mutate(SIGLA_UF = NA)

estatisticos_ids = read_csv('data/manual-data/estatisticos_ids.csv')

df = load_poll_registry_data(estatisticos_ids = estatisticos_ids, old = F)
df_for_merge = get_poll_registry_for_merge(df)

leva1 = read_csv('data/manual-data/manual-2020/pedro-fixed-pedro_leva1_2020_orig.csv', col_types = rtypes)
leva2 = read_csv('data/manual-data/manual-2020/pedro-fixed-pedro_leva2_2020_orig.csv', col_types = rtypes)
leva3 = read_csv('data/manual-data/manual-2020/pedro_leva3_2020.csv', col_types = rtypes)
leva3_ex = read_csv('data/manual-data/manual-2020/pedro_leva_3_extra_.csv', col_types = rtypes)
leva4 = read_csv('data/manual-data/manual-2020/pedro_leva4_2020.csv', col_types = rtypes)
leva5 = read_csv('data/manual-data/manual-2020/pedro_leva5_2020.csv', col_types = rtypes)
leva6 = read_csv('data/manual-data/manual-2020/pedro_leva6_2020.csv', col_types = rtypes)
leva7 = read_csv('data/manual-data/manual-2020/pedro_leva7_2020.csv', col_types = rtypes)
leva8 = read_csv('data/manual-data/manual-2020/pedro_leva8_2020.csv', col_types = rtypes)
leva9 = read_csv('data/manual-data/manual-2020/pedro_leva9_2020.csv', col_types = rtypes)
leva10 = read_csv('data/manual-data/manual-2020/pedro_leva10_2020.csv', col_types = rtypes)
leva11 = read_csv('data/manual-data/manual-2020/leva11_2020.csv', col_types = rtypes)
leva11_ex = read_csv('data/manual-data/manual-2020/pedro_review_zeros.csv', col_types = rtypes)
leva12_ex = read_csv('data/manual-data/manual-2020/pedro_leva12_extra.csv', col_types = rtypes)
leva12_ex2 = read_csv('data/manual-data/manual-2020/pedro_leva12_extra2.csv', col_types = rtypes)

X2020 = bind_rows(leva1, leva2, leva3, leva3_ex, leva4, leva5, leva6, leva7, leva8, leva9, leva10, leva11, leva11_ex, leva12_ex)

X2020_2 = X2020 %>%
  select(-contains('unnamed')) %>%
  mutate_at(vars(matches('resul')), str_to_dbl) %>%
  filter(util == 1 & !is.na(cand1)) %>%
  mutate(position = tolower(position)) %>%
  rowwise() %>%
  mutate(total = sum(c_across(matches('resul')), na.rm = T)) %>%
  ungroup() %>%
  mutate_at(vars(matches('cand')), normalize_cand) %>%
  mutate_at(vars(matches('resul')), function(x, t) {
    case_when(
      x < 1 ~ ifelse(t <= 1, x * 100, x),
      T ~ x
    )
  }, .$total) %>%
  mutate(year = 2020)

cur = X2020_2 %>%
  mutate(scenario_id = row_number()) %>%
  rowwise() %>%
  mutate(total = sum(c_across(contains('resul')), na.rm = T)) %>%
  mutate(for_patch = (total > 98 & is.na(vv)) | (total < 98 & !is.na(vv)) | total > 102) %>%
  ungroup()

patch_1 = read_csv('data/manual-data/manual-2020/patch_1_2020.csv')

cur = bind_rows(
  cur %>% filter(!for_patch),
  patch_1
) %>%
  mutate(scenario_id = row_number())

lhs = cur %>%
  pivot_longer(cols = starts_with('cand'),
               names_to = 'index',
               names_prefix = 'cand',
               values_to = 'candidate',
               values_drop_na = T) %>%
  select(-matches('resul'), -matches('part'))

rhs = cur %>%
  pivot_longer(cols = starts_with('resul'),
               names_to = 'index',
               names_prefix = 'resul',
               values_to = 'result',
               values_drop_na = T) %>%
  select(-matches('cand'), -matches('part'))

manual = inner_join(lhs, rhs, by = c(
  'index' = 'index',
  'scenario_id' = 'scenario_id'
)) %>%
  select(-matches('\\.y')) %>%
  rename_at(vars(matches('\\.x')), function(x) { str_sub(x, end = -3) }) %>%
  mutate(tse_id = ifelse(is.na(tse_id), id_pesq, tse_id)) %>%
  mutate(NM_UE = ifelse(is.na(NM_UE), info_muni, NM_UE))

manual_tse = manual %>%
  left_join(df_for_merge, by = c('tse_id' = 'f_id', 'NM_UE' = 'NM_UE')) %>%
  mutate(main_source = 'Pindograma-Manual') %>%
  rename(source = url) %>%
  mutate(CD_CARGO = recode(position,
    `p` = 11,
    `v` = 13,
  )) %>%
  mutate(company_id = case_when(
    NR_CNPJ_EMPRESA %in% c('24776969000117', '07742623000189', '67662494000140', '14931054000185', '26195312000191') ~ 'REALIDADE',
    NR_CNPJ_EMPRESA %in% c('23254436000102', '00852438000106', '00852501000104') ~ 'VOX POPULI',
    NR_CNPJ_EMPRESA %in% c('05939922000263', '32208779000121') ~ 'GERP',
    NR_CNPJ_EMPRESA %in% c('10828442000184', '22198794000182', '33539440000170') ~ 'MULTIPLA',
    NR_CNPJ_EMPRESA %in% c('17070395000100', '06154093000195') ~ 'MULTIDADOS',
    NR_CNPJ_EMPRESA %in% c('09656847000101', '09283689000183') ~ 'PROMIDIA',
    NR_CNPJ_EMPRESA %in% c('03622028000159', '39795414000190') ~ 'FUTURA',
    NR_CNPJ_EMPRESA %in% c('26968293000199', '11785871000184') ~ 'RANKING',
    NR_CNPJ_EMPRESA %in% c('57541377000175', '16623147000178') ~ 'DGABC',
    NR_CNPJ_EMPRESA %in% c('01077145000153', '10575983000148') ~ 'DATAMETRICA',
    NR_CNPJ_EMPRESA %in% c('13776203000116', '12784563000105') ~ 'ARBEIT',
    NR_CNPJ_EMPRESA %in% c('14263830000116', '16684996000131') ~ 'AGORASEI',
    NR_CNPJ_EMPRESA %in% c('11509901000120', '20450146000146') ~ 'LONDON',
    NR_CNPJ_EMPRESA %in% c('17110229000181', '29880121000157') ~ 'AMPLACE',
    NR_CNPJ_EMPRESA %in% c('03397255000128', '33030852000180') ~ 'TDL',
    NR_CNPJ_EMPRESA %in% c('04996040000196', '09439784000123') ~ 'ANGULO',
    NR_CNPJ_EMPRESA %in% c('03490620000144', '32980640000100') ~ 'TENDENCIAMS',
    NR_CNPJ_EMPRESA %in% c('36607622000120', '11535761000164') ~ 'SUDOESTE',
    NR_CNPJ_EMPRESA %in% c('02291216000189', '01338700000153') ~ 'GAUSS',
    T ~ NR_CNPJ_EMPRESA
  )) %>%
  mutate(turno = 1) %>%
  mutate(candidate_without_title = normalize_cand_rm_titles(candidate))

manual_matches = match_polls_with_candidates(manual_tse)

company_names = read_csv('data/manual-data/nomes_empresas.csv')

all_polls = manual_matches %>%
  distinct(year, NR_IDENTIFICACAO_PESQUISA, NR_CNPJ_EMPRESA, SG_UE, CD_CARGO, company_id, suspensa,
           estimulada, NUMERO_CANDIDATO, NOME_URNA_CANDIDATO, result, DT_FIM_PESQUISA, vv, turno,
           is_fluxo, is_phone, self_hired, QT_ENTREVISTADOS, main_source, source, scenario_id, is_complete,
           DT_INICIO_PESQUISA, hirer, confidence_interval_final, error_final, candidate) %>%
  left_join(company_names, 'company_id') %>%
  mutate(polled_UE = SG_UE) %>%
  group_by(NR_IDENTIFICACAO_PESQUISA, NR_CNPJ_EMPRESA, SG_UE, CD_CARGO, estimulada, scenario_id) %>%
  mutate(undecided = 100 - sum(result)) %>%
  ungroup()

all_polls_2 = all_polls %>%
  group_by(NR_IDENTIFICACAO_PESQUISA, estimulada, CD_CARGO, scenario_id) %>%
  filter(n_distinct(candidate) == n()) %>%
  mutate(scenario_count = n()) %>%
  ungroup() %>%
  group_by(NR_IDENTIFICACAO_PESQUISA, estimulada, CD_CARGO, NR_CNPJ_EMPRESA) %>%
  mutate(multiple_scenarios = n_distinct(scenario_id) > 1) %>%
  filter(scenario_count == max(scenario_count)) %>%
  ungroup() %>%
  select(-scenario_count)

all_polls_3 = all_polls_2 %>%
  group_by(NR_IDENTIFICACAO_PESQUISA, NR_CNPJ_EMPRESA, SG_UE, polled_UE, estimulada, CD_CARGO, vv, scenario_id) %>%
  mutate(group_digest = fastdigest(cur_data() %>% arrange(NUMERO_CANDIDATO) %>% select(NUMERO_CANDIDATO, result))) %>%
  ungroup() %>%
  group_by(NR_IDENTIFICACAO_PESQUISA, NR_CNPJ_EMPRESA, SG_UE, polled_UE, estimulada, CD_CARGO, vv, group_digest) %>%
  filter(scenario_id == first(scenario_id)) %>%
  ungroup()

no_vv_polls = all_polls_3 %>%
  filter(is.na(vv)) %>%
  filter(!(SG_UE == '02550' & NUMERO_CANDIDATO == 27 & NOME_URNA_CANDIDATO != 'CHICO PRETO')) %>%
  group_by(NR_IDENTIFICACAO_PESQUISA, scenario_id, NUMERO_CANDIDATO) %>%
  filter(all(n() == 1)) %>%
  ungroup() %>%
  select(-NOME_URNA_CANDIDATO)

early_polls_2 = no_vv_polls %>%
  left_join(election_dates, 'year') %>%
  filter(DT_FIM_PESQUISA <= candidate_registry_date) %>%
  filter(estimulada == 0)

recent_polls = no_vv_polls %>%
  left_join(election_dates, 'year') %>%
  group_by(NR_IDENTIFICACAO_PESQUISA, NR_CNPJ_EMPRESA, SG_UE, polled_UE, CD_CARGO, vv) %>%
  filter(n_distinct(estimulada) == 1 | estimulada == 1) %>%
  ungroup() %>%
  anti_join(early_polls_2, by = c('NR_IDENTIFICACAO_PESQUISA', 'scenario_id'))

early_polls_2 %>% write.csv('output/early_polls_2020_2.csv', row.names = F)
recent_polls %>% write.csv('output/recent_polls_2020.csv', row.names = F)

cands %>%
  semi_join(all_polls_3, by = c('SIGLA_UE' = 'SG_UE', 'CODIGO_CARGO' = 'CD_CARGO', 'ANO_ELEICAO' = 'year')) %>%
  filter(CODIGO_CARGO %in% c(1, 3, 11)) %>%
  distinct(SIGLA_UE, NUM_TURNO, CODIGO_CARGO, ANO_ELEICAO, NUMERO_CANDIDATO, NOME_URNA_CANDIDATO) %>%
  write.csv('output/pindograma_candlist_2020.csv', row.names = F)