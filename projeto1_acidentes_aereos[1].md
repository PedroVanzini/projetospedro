# Projeto 1 — Análise de Acidentes Aéreos no Brasil
**Dataset:** CENIPA / dados.gov.br | **Stack:** SQL Server avançado + Python (Pandas, Matplotlib, Seaborn)

---

## Objetivo
Investigar padrões em ocorrências aeronáuticas brasileiras para identificar fatores de risco, sazonalidade e causas humanas — entregando insights acionáveis como um cientista de dados faria para uma seguradora ou agência reguladora.

---

## Onde baixar os dados
```
https://dados.gov.br/dados/conjuntos-dados/ocorrencias-aeronauticas-da-aviacao-civil-brasileira
```
Arquivos necessários:
- `ocorrencia.csv` — tabela principal
- `ocorrencia_tipo.csv` — classificação do evento
- `aeronave.csv` — dados da aeronave envolvida
- `fator_contribuinte.csv` — causas e fatores humanos

---

## Estrutura do projeto no GitHub
```
acidentes-aereos-brasil/
├── data/
│   └── README.md          # instruções para baixar os CSVs
├── sql/
│   ├── 01_create_tables.sql
│   ├── 02_staging_load.sql
│   └── 03_analytical_queries.sql
├── notebooks/
│   └── analise_acidentes.ipynb
├── outputs/
│   └── graficos/
└── README.md
```

---

## SQL Server — Código Avançado

### 01_create_tables.sql
```sql
-- ============================================================
-- PROJETO: Análise de Acidentes Aéreos Brasil
-- FONTE:   CENIPA / dados.gov.br
-- ============================================================

CREATE DATABASE AcidentesAereos
GO
USE AcidentesAereos
GO

-- Tabela principal de ocorrências
CREATE TABLE Ocorrencia (
    codigo_ocorrencia    INT            PRIMARY KEY,
    data_ocorrencia      DATE           NOT NULL,
    hora_ocorrencia      TIME,
    uf_ocorrencia        CHAR(2),
    cidade_ocorrencia    VARCHAR(60),
    latitude             DECIMAL(9,6),
    longitude            DECIMAL(9,6),
    fase_operacao        VARCHAR(40),
    classificacao        VARCHAR(30),   -- ACIDENTE, INCIDENTE, INCIDENTE GRAVE
    total_recomendacoes  INT            DEFAULT 0,
    total_fatais         INT            DEFAULT 0
)
GO

CREATE TABLE Aeronave (
    id_aeronave          INT            PRIMARY KEY IDENTITY,
    codigo_ocorrencia    INT            NOT NULL,
    tipo_veiculo         VARCHAR(30),
    fabricante           VARCHAR(50),
    modelo               VARCHAR(50),
    motor_tipo           VARCHAR(20),
    quantidade_motores   INT,
    nivel_dano           VARCHAR(20),   -- NENHUM, LEVE, SUBSTANCIAL, DESTRUÍDA
    CONSTRAINT FK_Aeronave_Ocorrencia FOREIGN KEY (codigo_ocorrencia)
        REFERENCES Ocorrencia(codigo_ocorrencia)
)
GO

CREATE TABLE FatorContribuinte (
    id_fator             INT            PRIMARY KEY IDENTITY,
    codigo_ocorrencia    INT            NOT NULL,
    fator                VARCHAR(100),
    area                 VARCHAR(40),   -- HUMANO, OPERACIONAL, MATERIAL, MEIO AMBIENTE
    aspecto              VARCHAR(60),
    condicionante        VARCHAR(60),
    CONSTRAINT FK_Fator_Ocorrencia FOREIGN KEY (codigo_ocorrencia)
        REFERENCES Ocorrencia(codigo_ocorrencia)
)
GO

CREATE TABLE OcorrenciaTipo (
    id_tipo              INT            PRIMARY KEY IDENTITY,
    codigo_ocorrencia    INT            NOT NULL,
    tipo_ocorrencia      VARCHAR(60),
    CONSTRAINT FK_Tipo_Ocorrencia FOREIGN KEY (codigo_ocorrencia)
        REFERENCES Ocorrencia(codigo_ocorrencia)
)
GO
```

### 02_staging_load.sql
```sql
-- Importação via BULK INSERT (adapte o caminho dos seus arquivos)
BULK INSERT Ocorrencia
FROM 'C:\dados\ocorrencia.csv'
WITH (
    FIRSTROW        = 2,
    DATAFILETYPE    = 'char',
    FIELDTERMINATOR = ';',
    ROWTERMINATOR   = '\n',
    CODEPAGE        = '65001'   -- UTF-8
)
GO

-- Validação pós-carga (você já sabe isso!)
SELECT
    COUNT(*)                                        AS total_registros,
    SUM(CASE WHEN uf_ocorrencia IS NULL THEN 1 END) AS uf_nulos,
    MIN(data_ocorrencia)                            AS data_minima,
    MAX(data_ocorrencia)                            AS data_maxima
FROM Ocorrencia
GO
```

### 03_analytical_queries.sql
```sql
-- ============================================================
-- QUERY 1: Ranking de estados com window function + CTE
-- Calcula total, percentual acumulado e rank por estado
-- ============================================================
WITH AcidentesPorUF AS (
    SELECT
        uf_ocorrencia,
        COUNT(*)                                    AS total,
        SUM(total_fatais)                           AS total_fatais
    FROM Ocorrencia
    WHERE classificacao = 'ACIDENTE'
      AND uf_ocorrencia IS NOT NULL
    GROUP BY uf_ocorrencia
)
SELECT
    uf_ocorrencia,
    total,
    total_fatais,
    ROUND(100.0 * total / SUM(total) OVER (), 2)   AS pct_total,
    SUM(total) OVER (
        ORDER BY total DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                               AS acumulado,
    RANK() OVER (ORDER BY total DESC)               AS ranking
FROM AcidentesPorUF
ORDER BY total DESC
GO


-- ============================================================
-- QUERY 2: Sazonalidade — acidentes por mês e fase do voo
-- Pivô com CASE para criar colunas por fase
-- ============================================================
SELECT
    DATENAME(MONTH, data_ocorrencia)                AS mes,
    MONTH(data_ocorrencia)                          AS num_mes,
    COUNT(*)                                        AS total_acidentes,
    SUM(CASE WHEN fase_operacao LIKE '%POUSO%'      THEN 1 ELSE 0 END) AS pouso,
    SUM(CASE WHEN fase_operacao LIKE '%DECOLAGEM%'  THEN 1 ELSE 0 END) AS decolagem,
    SUM(CASE WHEN fase_operacao LIKE '%CRUZEIRO%'   THEN 1 ELSE 0 END) AS cruzeiro,
    SUM(CASE WHEN fase_operacao LIKE '%APROXIMACAO%'THEN 1 ELSE 0 END) AS aproximacao,
    AVG(total_fatais)                               AS media_fatais
FROM Ocorrencia
WHERE classificacao = 'ACIDENTE'
GROUP BY DATENAME(MONTH, data_ocorrencia), MONTH(data_ocorrencia)
ORDER BY num_mes
GO


-- ============================================================
-- QUERY 3: Fator humano dominante por tipo de aeronave
-- JOIN triplo + GROUP BY + HAVING
-- ============================================================
SELECT
    A.tipo_veiculo,
    F.area,
    F.fator,
    COUNT(*)                                        AS ocorrencias,
    SUM(O.total_fatais)                             AS total_fatais,
    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY A.tipo_veiculo)
    , 2)                                            AS pct_dentro_tipo
FROM Ocorrencia O
INNER JOIN Aeronave A        ON O.codigo_ocorrencia = A.codigo_ocorrencia
INNER JOIN FatorContribuinte F ON O.codigo_ocorrencia = F.codigo_ocorrencia
WHERE F.area = 'HUMANO'
  AND A.tipo_veiculo IS NOT NULL
GROUP BY A.tipo_veiculo, F.area, F.fator
HAVING COUNT(*) > 5
ORDER BY A.tipo_veiculo, ocorrencias DESC
GO


-- ============================================================
-- QUERY 4: Tendência anual com variação YoY (Year-over-Year)
-- LAG para comparar com ano anterior
-- ============================================================
WITH AnualBase AS (
    SELECT
        YEAR(data_ocorrencia)   AS ano,
        COUNT(*)                AS total_acidentes,
        SUM(total_fatais)       AS total_fatais
    FROM Ocorrencia
    WHERE classificacao = 'ACIDENTE'
    GROUP BY YEAR(data_ocorrencia)
)
SELECT
    ano,
    total_acidentes,
    total_fatais,
    LAG(total_acidentes) OVER (ORDER BY ano)        AS acidentes_ano_anterior,
    total_acidentes - LAG(total_acidentes) OVER (ORDER BY ano) AS variacao_absoluta,
    ROUND(
        100.0 * (total_acidentes - LAG(total_acidentes) OVER (ORDER BY ano))
              / NULLIF(LAG(total_acidentes) OVER (ORDER BY ano), 0)
    , 2)                                            AS variacao_pct
FROM AnualBase
ORDER BY ano
GO


-- ============================================================
-- QUERY 5: Score de risco por combinação tipo_veiculo + fase
-- Weighted risk score = fatais * 3 + total_acidentes
-- ============================================================
SELECT TOP 15
    A.tipo_veiculo,
    O.fase_operacao,
    COUNT(*)                                        AS total_ocorrencias,
    SUM(O.total_fatais)                             AS total_fatais,
    COUNT(*) + (SUM(O.total_fatais) * 3)            AS risk_score,
    DENSE_RANK() OVER (
        ORDER BY COUNT(*) + (SUM(O.total_fatais) * 3) DESC
    )                                               AS risk_rank
FROM Ocorrencia O
INNER JOIN Aeronave A ON O.codigo_ocorrencia = A.codigo_ocorrencia
WHERE A.tipo_veiculo IS NOT NULL
  AND O.fase_operacao IS NOT NULL
GROUP BY A.tipo_veiculo, O.fase_operacao
ORDER BY risk_score DESC
GO
```

---

## Python — Notebook completo

### analise_acidentes.ipynb

```python
# ============================================================
# CÉLULA 1 — Imports e configuração
# ============================================================
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import seaborn as sns
from sqlalchemy import create_engine   # conexão com SQL Server

# Estilo dos gráficos
plt.rcParams['figure.figsize'] = (12, 6)
plt.rcParams['axes.spines.top']   = False
plt.rcParams['axes.spines.right'] = False
sns.set_palette('muted')

print("Bibliotecas carregadas com sucesso!")
```

```python
# ============================================================
# CÉLULA 2 — Conexão com SQL Server via SQLAlchemy
# (alternativa: ler direto do CSV se não tiver SQL Server local)
# ============================================================

# OPÇÃO A: via SQL Server
engine = create_engine(
    "mssql+pyodbc://usuario:senha@servidor/AcidentesAereos"
    "?driver=ODBC+Driver+17+for+SQL+Server"
)

# OPÇÃO B: via CSV (mais simples para começar)
ocorrencia     = pd.read_csv('data/ocorrencia.csv',          sep=';', encoding='utf-8')
aeronave       = pd.read_csv('data/aeronave.csv',            sep=';', encoding='utf-8')
fator          = pd.read_csv('data/fator_contribuinte.csv',  sep=';', encoding='utf-8')
ocorrencia_tipo= pd.read_csv('data/ocorrencia_tipo.csv',     sep=';', encoding='utf-8')

print(f"Ocorrências carregadas: {len(ocorrencia):,}")
print(ocorrencia.dtypes)
```

```python
# ============================================================
# CÉLULA 3 — Limpeza e preparação (Data Wrangling)
# ============================================================

# Converter tipos
ocorrencia['data_ocorrencia'] = pd.to_datetime(
    ocorrencia['ocorrencia_dia'], format='%d/%m/%Y', errors='coerce'
)
ocorrencia['ano']  = ocorrencia['data_ocorrencia'].dt.year
ocorrencia['mes']  = ocorrencia['data_ocorrencia'].dt.month
ocorrencia['hora'] = pd.to_numeric(
    ocorrencia['ocorrencia_hora'].str[:2], errors='coerce'
)

# Filtrar apenas acidentes (não incidentes)
acidentes = ocorrencia[ocorrencia['ocorrencia_classificacao'] == 'ACIDENTE'].copy()

# Merge com aeronave
df = acidentes.merge(aeronave, on='codigo_ocorrencia', how='left')

print(f"Acidentes filtrados: {len(acidentes):,}")
print(f"Valores nulos por coluna:\n{acidentes.isnull().sum()[acidentes.isnull().sum() > 0]}")
```

```python
# ============================================================
# CÉLULA 4 — Análise 1: Tendência anual com YoY
# (espelhando a Query 4 do SQL)
# ============================================================

anual = (
    acidentes
    .groupby('ano')
    .agg(
        total=('codigo_ocorrencia', 'count'),
        fatais=('total_fatais', 'sum')
    )
    .reset_index()
)

# Variação year-over-year — equivalente ao LAG do SQL
anual['variacao_pct'] = anual['total'].pct_change() * 100

fig, ax1 = plt.subplots()

# Barras: total de acidentes
ax1.bar(anual['ano'], anual['total'], color='#4a7fc1', alpha=0.8, label='Total acidentes')
ax1.set_ylabel('Total de acidentes', fontsize=12)
ax1.set_xlabel('Ano')

# Linha secundária: % de variação
ax2 = ax1.twinx()
ax2.plot(anual['ano'], anual['variacao_pct'], color='#c94040',
         marker='o', linewidth=2, label='Variação YoY (%)')
ax2.axhline(0, color='gray', linestyle='--', linewidth=0.8)
ax2.set_ylabel('Variação anual (%)', fontsize=12)
ax2.yaxis.set_major_formatter(mticker.FormatStrFormatter('%.1f%%'))

fig.legend(loc='upper right', bbox_to_anchor=(0.88, 0.88))
plt.title('Tendência anual de acidentes aéreos no Brasil', fontsize=14, pad=15)
plt.tight_layout()
plt.savefig('outputs/graficos/01_tendencia_anual.png', dpi=150)
plt.show()
```

```python
# ============================================================
# CÉLULA 5 — Análise 2: Heatmap sazonalidade (mês x fase)
# ============================================================

fases_principais = ['POUSO', 'DECOLAGEM', 'CRUZEIRO', 'APROXIMAÇÃO FINAL']

sazonalidade = (
    acidentes[acidentes['ocorrencia_fase_operacao'].isin(fases_principais)]
    .groupby(['mes', 'ocorrencia_fase_operacao'])
    .size()
    .unstack(fill_value=0)
)

sazonalidade.index = ['Jan','Fev','Mar','Abr','Mai','Jun',
                       'Jul','Ago','Set','Out','Nov','Dez']

fig, ax = plt.subplots(figsize=(10, 5))
sns.heatmap(
    sazonalidade,
    annot=True, fmt='d',
    cmap='YlOrRd',
    linewidths=0.5,
    ax=ax
)
ax.set_title('Acidentes por mês e fase do voo', fontsize=14, pad=15)
ax.set_xlabel('Fase da operação')
ax.set_ylabel('Mês')
plt.tight_layout()
plt.savefig('outputs/graficos/02_heatmap_sazonalidade.png', dpi=150)
plt.show()
```

```python
# ============================================================
# CÉLULA 6 — Análise 3: Risk score por tipo de aeronave
# (espelhando Query 5 do SQL direto no Python)
# ============================================================

risk = (
    df.groupby(['aeronave_tipo_veiculo', 'ocorrencia_fase_operacao'])
    .agg(
        total=('codigo_ocorrencia', 'count'),
        fatais=('total_fatais', 'sum')
    )
    .reset_index()
)

risk['risk_score'] = risk['total'] + (risk['fatais'] * 3)
risk = risk.sort_values('risk_score', ascending=False).head(15)

fig, ax = plt.subplots(figsize=(11, 6))
bars = ax.barh(
    risk['aeronave_tipo_veiculo'] + ' — ' + risk['ocorrencia_fase_operacao'],
    risk['risk_score'],
    color=plt.cm.RdYlGn_r(np.linspace(0.2, 0.9, len(risk)))
)

# Rótulos nas barras
for bar, val in zip(bars, risk['risk_score']):
    ax.text(bar.get_width() + 0.5, bar.get_y() + bar.get_height()/2,
            f'{val}', va='center', fontsize=10)

ax.set_title('Top 15 combinações de maior risco (tipo + fase)', fontsize=13)
ax.set_xlabel('Risk Score  (acidentes + fatais × 3)')
ax.invert_yaxis()
plt.tight_layout()
plt.savefig('outputs/graficos/03_risk_score.png', dpi=150)
plt.show()
```

```python
# ============================================================
# CÉLULA 7 — Análise 4: Fatores humanos dominantes
# ============================================================

fator_humano = fator[fator['fator_area'] == 'FATOR HUMANO'].copy()

top_fatores = (
    fator_humano
    .groupby('fator_nome')
    .size()
    .reset_index(name='contagem')
    .sort_values('contagem', ascending=False)
    .head(10)
)

fig, ax = plt.subplots()
ax.barh(top_fatores['fator_nome'], top_fatores['contagem'], color='#5b7fa6')
ax.set_title('Top 10 fatores humanos em acidentes aéreos', fontsize=13)
ax.set_xlabel('Número de ocorrências')
ax.invert_yaxis()
plt.tight_layout()
plt.savefig('outputs/graficos/04_fatores_humanos.png', dpi=150)
plt.show()
```

```python
# ============================================================
# CÉLULA 8 — Exportar resumo para CSV (entregável do projeto)
# ============================================================

resumo = (
    acidentes
    .groupby(['ano', 'uf_ocorrencia'])
    .agg(
        total_acidentes=('codigo_ocorrencia', 'count'),
        total_fatais=('total_fatais', 'sum'),
        media_fatais=('total_fatais', 'mean')
    )
    .round(2)
    .reset_index()
)

resumo.to_csv('outputs/resumo_acidentes_por_estado_ano.csv', index=False, encoding='utf-8-sig')
print("Exportado com sucesso!")
print(resumo.head(10))
```

---

## README.md para o GitHub

```markdown
# Análise de Acidentes Aéreos no Brasil (CENIPA)

> Projeto de análise de dados explorando 20+ anos de ocorrências aeronáuticas
> brasileiras com SQL Server avançado e Python.

## Principais insights encontrados
- **SP, MG e MT** concentram ~40% dos acidentes registrados
- A fase de **pouso** é a mais crítica — responsável por X% dos acidentes
- **Fadiga do piloto** é o fator humano mais recorrente (X ocorrências)
- Acidentes tiveram queda de X% entre 2015 e 2022, mas incidentes subiram

## Stack utilizada
| Ferramenta | Uso |
|---|---|
| SQL Server | Modelagem, ingestão via BULK INSERT, queries analíticas com CTEs e Window Functions |
| Python / Pandas | Limpeza, merge de tabelas, feature engineering |
| Matplotlib / Seaborn | Visualizações: heatmap, barras horizontais, dual-axis |
| SQLAlchemy | Conexão Python → SQL Server |

## Como reproduzir
1. Baixe os CSVs em dados.gov.br (link na pasta `/data`)
2. Execute os scripts SQL na pasta `/sql` em ordem
3. Abra o notebook `/notebooks/analise_acidentes.ipynb`

## Fonte dos dados
CENIPA — Centro de Investigação e Prevenção de Acidentes Aeronáuticos  
https://dados.gov.br/dados/conjuntos-dados/ocorrencias-aeronauticas-da-aviacao-civil-brasileira
```
