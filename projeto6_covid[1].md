# Projeto 6 — Análise de Casos de COVID-19 no Brasil
**Dataset:** Ministério da Saúde / Brasil.io | **Stack:** SQL Server + Python iniciante

---

## Objetivo
Analisar a evolução dos casos e óbitos de COVID-19 no Brasil por estado e período. Projeto com dados amplamente conhecidos, fácil de contextualizar para qualquer recrutador, e ótimo para demonstrar análise de séries temporais de forma simples.

---

## Onde baixar os dados
```
https://brasil.io/dataset/covid19/caso_full/
```
Ou direto:
```
https://data.brasil.io/dataset/covid19/caso_full.csv.gz
```
O arquivo tem dados diários por município/estado desde o início da pandemia.

Colunas que vamos usar:
- `date` — data do registro
- `state` — estado (UF)
- `city` — município (NULL = dado do estado inteiro)
- `new_confirmed` — novos casos confirmados no dia
- `new_deaths` — novos óbitos no dia
- `estimated_population` — população estimada

---

## Estrutura do projeto
```
analise-covid-brasil/
├── data/
│   └── README.md
├── sql/
│   └── queries_covid.sql
├── notebooks/
│   └── analise_covid.ipynb
├── outputs/
│   └── graficos/
└── README.md
```

---

## SQL Server — Queries

### queries_covid.sql
```sql
-- ============================================================
-- PROJETO: Análise COVID-19 Brasil
-- FONTE: brasil.io / Ministério da Saúde
-- ============================================================

CREATE DATABASE AnaliseCovid
GO
USE AnaliseCovid
GO

CREATE TABLE CasosCovid (
    id                   INT           PRIMARY KEY IDENTITY,
    data_registro        DATE          NOT NULL,
    estado               CHAR(2)       NOT NULL,
    cidade               VARCHAR(100),
    novos_casos          INT           DEFAULT 0,
    novos_obitos         INT           DEFAULT 0,
    populacao_estimada   BIGINT
)
GO

-- Importar via BULK INSERT
BULK INSERT CasosCovid
FROM 'C:\dados\caso_full.csv'
WITH (
    FIRSTROW        = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR   = '\n',
    DATAFILETYPE    = 'char',
    CODEPAGE        = '65001'
)
GO


-- ============================================================
-- QUERY 1: Total de casos e óbitos por estado
-- ============================================================
SELECT
    estado,
    SUM(novos_casos)                    AS total_casos,
    SUM(novos_obitos)                   AS total_obitos,
    ROUND(
        100.0 * SUM(novos_obitos)
              / NULLIF(SUM(novos_casos), 0)
    , 2)                                AS taxa_letalidade_pct,
    MAX(populacao_estimada)             AS populacao
FROM CasosCovid
WHERE cidade IS NULL                    -- apenas dados estaduais (não municipais)
  AND novos_casos >= 0
GROUP BY estado
ORDER BY total_casos DESC
GO


-- ============================================================
-- QUERY 2: Evolução mensal de casos e óbitos no Brasil
-- ============================================================
SELECT
    YEAR(data_registro)                 AS ano,
    MONTH(data_registro)                AS mes,
    DATENAME(MONTH, data_registro)      AS nome_mes,
    SUM(novos_casos)                    AS casos_mes,
    SUM(novos_obitos)                   AS obitos_mes,
    ROUND(
        AVG(CAST(novos_casos AS FLOAT))
    , 0)                                AS media_diaria_casos
FROM CasosCovid
WHERE cidade IS NULL
  AND novos_casos >= 0
GROUP BY
    YEAR(data_registro),
    MONTH(data_registro),
    DATENAME(MONTH, data_registro)
ORDER BY ano, mes
GO


-- ============================================================
-- QUERY 3: Top 5 piores semanas por número de óbitos
-- ============================================================
SELECT TOP 5
    DATEPART(YEAR,  data_registro)      AS ano,
    DATEPART(WEEK,  data_registro)      AS semana,
    MIN(data_registro)                  AS inicio_semana,
    MAX(data_registro)                  AS fim_semana,
    SUM(novos_obitos)                   AS total_obitos_semana,
    SUM(novos_casos)                    AS total_casos_semana
FROM CasosCovid
WHERE cidade IS NULL
  AND novos_obitos >= 0
GROUP BY
    DATEPART(YEAR, data_registro),
    DATEPART(WEEK, data_registro)
ORDER BY total_obitos_semana DESC
GO


-- ============================================================
-- QUERY 4: Taxa de letalidade por estado com classificação
-- ============================================================
SELECT
    estado,
    SUM(novos_casos)                    AS total_casos,
    SUM(novos_obitos)                   AS total_obitos,
    ROUND(
        100.0 * SUM(novos_obitos)
              / NULLIF(SUM(novos_casos), 0)
    , 2)                                AS taxa_letalidade,
    CASE
        WHEN 100.0 * SUM(novos_obitos)
                   / NULLIF(SUM(novos_casos),0) > 3  THEN 'Alta'
        WHEN 100.0 * SUM(novos_obitos)
                   / NULLIF(SUM(novos_casos),0) > 1.5 THEN 'Média'
        ELSE 'Baixa'
    END                                 AS classificacao_letalidade
FROM CasosCovid
WHERE cidade IS NULL
  AND novos_casos > 100
GROUP BY estado
ORDER BY taxa_letalidade DESC
GO
```

---

## Python — Notebook (nível iniciante com muitos comentários)

### analise_covid.ipynb

```python
# ============================================================
# CÉLULA 1 — Importar bibliotecas
# ============================================================
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import seaborn as sns

plt.rcParams['figure.figsize'] = (12, 5)
plt.rcParams['axes.spines.top']   = False
plt.rcParams['axes.spines.right'] = False

print("Pronto!")
```

```python
# ============================================================
# CÉLULA 2 — Carregar os dados
# O arquivo é grande — usamos dtype para economizar memória
# ============================================================

dtype_map = {
    'state':             'str',
    'city':              'str',
    'new_confirmed':     'Int64',   # Int64 aceita valores nulos (diferente de int64)
    'new_deaths':        'Int64',
    'estimated_population': 'Int64'
}

df_raw = pd.read_csv(
    'data/caso_full.csv',
    usecols=['date','state','city','new_confirmed','new_deaths','estimated_population'],
    dtype=dtype_map,
    parse_dates=['date']
)

print(f"Shape: {df_raw.shape}")
print(df_raw.head())
```

```python
# ============================================================
# CÉLULA 3 — Limpeza dos dados
# ============================================================

# Filtrar apenas registros estaduais (city == NaN = dado do estado todo)
# Equivalente ao WHERE cidade IS NULL do SQL
df_estados = df_raw[df_raw['city'].isna()].copy()

# Remover valores negativos (erros de registro)
df_estados = df_estados[
    (df_estados['new_confirmed'] >= 0) &
    (df_estados['new_deaths']    >= 0)
]

# Criar colunas de ano e mês
df_estados['ano'] = df_estados['date'].dt.year
df_estados['mes'] = df_estados['date'].dt.month

print(f"Registros estaduais: {len(df_estados):,}")
print(f"Período: {df_estados['date'].min().date()} até {df_estados['date'].max().date()}")
print(f"Estados: {sorted(df_estados['state'].unique())}")
```

```python
# ============================================================
# CÉLULA 4 — Análise 1: Evolução diária nacional (média móvel)
# ============================================================

# Somar todos os estados por dia = dado nacional
nacional_diario = (
    df_estados
    .groupby('date')
    .agg(casos=('new_confirmed','sum'), obitos=('new_deaths','sum'))
    .reset_index()
    .sort_values('date')
)

# Média móvel de 7 dias — suaviza os picos de subnotificação do fim de semana
# .rolling(7).mean() calcula a média das últimas 7 linhas
nacional_diario['casos_mm7']  = nacional_diario['casos'].rolling(7).mean().round(0)
nacional_diario['obitos_mm7'] = nacional_diario['obitos'].rolling(7).mean().round(1)

fig, ax1 = plt.subplots()

ax1.fill_between(nacional_diario['date'], nacional_diario['casos'],
                 alpha=0.25, color='#4a7fc1', label='Casos diários')
ax1.plot(nacional_diario['date'], nacional_diario['casos_mm7'],
         color='#4a7fc1', linewidth=2, label='Média móvel 7 dias (casos)')
ax1.set_ylabel('Novos casos', color='#4a7fc1')
ax1.set_xlabel('Data')

ax2 = ax1.twinx()
ax2.plot(nacional_diario['date'], nacional_diario['obitos_mm7'],
         color='#c94040', linewidth=2, label='Média móvel 7 dias (óbitos)')
ax2.set_ylabel('Óbitos', color='#c94040')

ax1.xaxis.set_major_formatter(mdates.DateFormatter('%b/%Y'))
ax1.xaxis.set_major_locator(mdates.MonthLocator(interval=3))
plt.setp(ax1.xaxis.get_majorticklabels(), rotation=45, ha='right')

lines1, labels1 = ax1.get_legend_handles_labels()
lines2, labels2 = ax2.get_legend_handles_labels()
ax1.legend(lines1 + lines2, labels1 + labels2, loc='upper left', fontsize=9)

plt.title('Evolução de casos e óbitos COVID-19 — Brasil', fontsize=13)
plt.tight_layout()
plt.savefig('outputs/graficos/01_evolucao_nacional.png', dpi=150)
plt.show()
```

```python
# ============================================================
# CÉLULA 5 — Análise 2: Total por estado
# ============================================================

por_estado = (
    df_estados
    .groupby('state')
    .agg(
        total_casos=('new_confirmed', 'sum'),
        total_obitos=('new_deaths', 'sum'),
        populacao=('estimated_population', 'max')
    )
    .reset_index()
)

# Calcular taxa de letalidade e casos por 100 mil habitantes
por_estado['taxa_letalidade'] = (
    por_estado['total_obitos'] / por_estado['total_casos'].replace(0, pd.NA) * 100
).round(2)

por_estado['casos_por_100k'] = (
    por_estado['total_casos'] / por_estado['populacao'].replace(0, pd.NA) * 100_000
).round(1)

por_estado = por_estado.sort_values('total_casos', ascending=False)
print(por_estado.head(10).to_string(index=False))

# Gráfico
fig, ax = plt.subplots()
ax.barh(por_estado['state'], por_estado['total_casos'], color='#4a7fc1')
ax.set_title('Total de casos COVID-19 por estado', fontsize=13)
ax.set_xlabel('Total de casos')
ax.invert_yaxis()
ax.xaxis.set_major_formatter(
    plt.FuncFormatter(lambda x, _: f'{x/1e6:.1f}M')
)
plt.tight_layout()
plt.savefig('outputs/graficos/02_casos_por_estado.png', dpi=150)
plt.show()
```

```python
# ============================================================
# CÉLULA 6 — Análise 3: Comparar evolução de 5 estados
# ============================================================

top5_estados = por_estado.head(5)['state'].tolist()
df_top5 = df_estados[df_estados['state'].isin(top5_estados)].copy()

mensal_estado = (
    df_top5
    .groupby(['state', 'ano', 'mes'])
    .agg(casos=('new_confirmed','sum'))
    .reset_index()
)

# Criar coluna de data para o eixo X
mensal_estado['data'] = pd.to_datetime(
    mensal_estado['ano'].astype(str) + '-' +
    mensal_estado['mes'].astype(str) + '-01'
)

fig, ax = plt.subplots()
cores = ['#4a7fc1','#c94040','#5b9e6f','#c96a3a','#7f77dd']

for i, estado in enumerate(top5_estados):
    dados_estado = mensal_estado[mensal_estado['state'] == estado]
    ax.plot(dados_estado['data'], dados_estado['casos'],
            label=estado, color=cores[i], linewidth=2, marker='o', markersize=3)

ax.set_title('Evolução mensal de casos — Top 5 estados', fontsize=13)
ax.set_ylabel('Novos casos no mês')
ax.xaxis.set_major_formatter(mdates.DateFormatter('%b/%Y'))
ax.xaxis.set_major_locator(mdates.MonthLocator(interval=4))
plt.setp(ax.xaxis.get_majorticklabels(), rotation=45, ha='right')
ax.legend()
plt.tight_layout()
plt.savefig('outputs/graficos/03_comparativo_estados.png', dpi=150)
plt.show()
```

```python
# ============================================================
# CÉLULA 7 — Análise 4: Taxa de letalidade por estado (mapa de calor simples)
# ============================================================

letalidade_estado = por_estado[['state','taxa_letalidade']].set_index('state')

fig, ax = plt.subplots(figsize=(4, 9))
sns.heatmap(
    letalidade_estado.sort_values('taxa_letalidade', ascending=False),
    annot=True, fmt='.2f',
    cmap='Reds',
    linewidths=0.5,
    ax=ax,
    cbar_kws={'label':'Taxa de letalidade (%)'}
)
ax.set_title('Taxa de letalidade por estado (%)', fontsize=12)
ax.set_xlabel('')
plt.tight_layout()
plt.savefig('outputs/graficos/04_letalidade_estados.png', dpi=150)
plt.show()
```

```python
# ============================================================
# CÉLULA 8 — Resumo e exportação
# ============================================================

total_casos  = df_estados['new_confirmed'].sum()
total_obitos = df_estados['new_deaths'].sum()
letalidade   = total_obitos / total_casos * 100

print("===== RESUMO COVID-19 BRASIL =====")
print(f"Total de casos confirmados: {total_casos:,.0f}")
print(f"Total de óbitos:            {total_obitos:,.0f}")
print(f"Taxa de letalidade geral:   {letalidade:.2f}%")
print(f"Estado mais afetado (casos): {por_estado.iloc[0]['state']}")
print(f"Estado maior letalidade:     {por_estado.sort_values('taxa_letalidade', ascending=False).iloc[0]['state']}")

por_estado.to_csv('outputs/resumo_covid_por_estado.csv', index=False, encoding='utf-8-sig')
nacional_diario.to_csv('outputs/evolucao_diaria_nacional.csv', index=False, encoding='utf-8-sig')
print("\nArquivos exportados!")
```

---

## README.md para o GitHub

```markdown
# Análise de COVID-19 no Brasil

> Análise exploratória da evolução de casos e óbitos de COVID-19
> no Brasil com dados oficiais do Ministério da Saúde.

## Perguntas respondidas
- Como evoluíram os casos e óbitos ao longo do tempo?
- Quais estados tiveram mais casos?
- Qual a taxa de letalidade por estado?
- Como se compara a evolução entre os 5 estados mais afetados?

## Conceitos demonstrados
- Média móvel de 7 dias (suavização de série temporal)
- Gráfico de eixo duplo (casos + óbitos)
- Normalização por população (casos por 100 mil hab.)
- Heatmap de taxa de letalidade

## Stack
| Ferramenta | Uso |
|---|---|
| SQL Server | Modelagem, BULK INSERT, GROUP BY, CASE WHEN, NULLIF |
| Python / Pandas | Limpeza, filtros, média móvel com rolling() |
| Matplotlib | Gráfico de área, linha, barras horizontais |
| Seaborn | Heatmap de letalidade |

## Dataset
Brasil.io — Casos COVID-19  
https://brasil.io/dataset/covid19/caso_full/
```
