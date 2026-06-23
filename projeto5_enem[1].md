# Projeto 5 — Análise das Notas do ENEM por Estado
**Dataset:** Microdados ENEM (dados.gov.br) | **Stack:** SQL Server + Python iniciante

---

## Objetivo
Explorar os microdados do ENEM para entender diferenças de desempenho por estado, tipo de escola (pública x privada) e área do conhecimento. Projeto com dados 100% brasileiros e muito reconhecido por recrutadores.

---

## Onde baixar os dados
```
https://www.gov.br/inep/pt-br/acesso-a-informacao/dados-abertos/microdados/enem
```
Baixe o arquivo do ano mais recente disponível. Usar apenas uma amostra (ex: 100 mil linhas) é suficiente para o portfólio.

Colunas principais que vamos usar:
- `NU_NOTA_MT` — nota de Matemática
- `NU_NOTA_LC` — nota de Linguagens
- `NU_NOTA_CN` — nota de Ciências da Natureza
- `NU_NOTA_CH` — nota de Ciências Humanas
- `NU_NOTA_REDACAO` — nota da Redação
- `TP_ESCOLA` — tipo de escola (1=pública, 2=privada)
- `SG_UF_PROVA` — estado onde fez a prova
- `TP_SEXO` — sexo do candidato

---

## Estrutura do projeto
```
analise-enem/
├── data/
│   └── README.md
├── sql/
│   └── queries_enem.sql
├── notebooks/
│   └── analise_enem.ipynb
├── outputs/
│   └── graficos/
└── README.md
```

---

## SQL Server — Queries

### queries_enem.sql
```sql
-- ============================================================
-- PROJETO: Análise ENEM
-- FONTE: INEP / dados.gov.br
-- ============================================================

CREATE DATABASE AnaliseENEM
GO
USE AnaliseENEM
GO

CREATE TABLE Candidatos (
    nu_inscricao         BIGINT         PRIMARY KEY,
    nu_ano               INT            NOT NULL,
    sg_uf_prova          CHAR(2),
    tp_sexo              CHAR(1),
    tp_escola            INT,           -- 1=pública, 2=privada
    nu_nota_cn           DECIMAL(6,1),  -- Ciências da Natureza
    nu_nota_ch           DECIMAL(6,1),  -- Ciências Humanas
    nu_nota_lc           DECIMAL(6,1),  -- Linguagens
    nu_nota_mt           DECIMAL(6,1),  -- Matemática
    nu_nota_redacao      DECIMAL(6,1),
    tp_status_redacao    INT            -- 1=válida, outros=anulada/etc
)
GO

-- Importar amostra via BULK INSERT
BULK INSERT Candidatos
FROM 'C:\dados\enem_amostra.csv'
WITH (
    FIRSTROW        = 2,
    FIELDTERMINATOR = ';',
    ROWTERMINATOR   = '\n',
    DATAFILETYPE    = 'char',
    CODEPAGE        = '65001'
)
GO


-- ============================================================
-- QUERY 1: Média das notas por estado
-- ============================================================
SELECT
    sg_uf_prova                         AS estado,
    COUNT(*)                            AS candidatos,
    ROUND(AVG(nu_nota_mt),  1)          AS media_matematica,
    ROUND(AVG(nu_nota_lc),  1)          AS media_linguagens,
    ROUND(AVG(nu_nota_cn),  1)          AS media_ciencias_nat,
    ROUND(AVG(nu_nota_ch),  1)          AS media_ciencias_hum,
    ROUND(AVG(nu_nota_redacao), 1)      AS media_redacao,
    ROUND(
        (AVG(nu_nota_mt) + AVG(nu_nota_lc) +
         AVG(nu_nota_cn) + AVG(nu_nota_ch) + AVG(nu_nota_redacao)) / 5
    , 1)                                AS media_geral
FROM Candidatos
WHERE nu_nota_mt      IS NOT NULL
  AND nu_nota_redacao IS NOT NULL
  AND tp_status_redacao = 1
GROUP BY sg_uf_prova
ORDER BY media_geral DESC
GO


-- ============================================================
-- QUERY 2: Escola pública x privada — diferença de nota
-- ============================================================
SELECT
    CASE tp_escola
        WHEN 1 THEN 'Pública'
        WHEN 2 THEN 'Privada'
        ELSE        'Não informado'
    END                                 AS tipo_escola,
    COUNT(*)                            AS candidatos,
    ROUND(AVG(nu_nota_mt),      1)      AS media_matematica,
    ROUND(AVG(nu_nota_redacao), 1)      AS media_redacao,
    ROUND(
        (AVG(nu_nota_mt) + AVG(nu_nota_lc) +
         AVG(nu_nota_cn) + AVG(nu_nota_ch) + AVG(nu_nota_redacao)) / 5
    , 1)                                AS media_geral
FROM Candidatos
WHERE nu_nota_mt IS NOT NULL
  AND tp_escola IN (1, 2)
GROUP BY tp_escola
GO


-- ============================================================
-- QUERY 3: Distribuição das notas de redação por faixa
-- ============================================================
SELECT
    CASE
        WHEN nu_nota_redacao < 400  THEN '0–399'
        WHEN nu_nota_redacao < 600  THEN '400–599'
        WHEN nu_nota_redacao < 800  THEN '600–799'
        WHEN nu_nota_redacao < 900  THEN '800–899'
        ELSE                             '900–1000'
    END                                 AS faixa_nota,
    COUNT(*)                            AS quantidade,
    ROUND(100.0 * COUNT(*) / (
        SELECT COUNT(*) FROM Candidatos
        WHERE nu_nota_redacao IS NOT NULL
          AND tp_status_redacao = 1
    ), 2)                               AS percentual
FROM Candidatos
WHERE nu_nota_redacao IS NOT NULL
  AND tp_status_redacao = 1
GROUP BY
    CASE
        WHEN nu_nota_redacao < 400  THEN '0–399'
        WHEN nu_nota_redacao < 600  THEN '400–599'
        WHEN nu_nota_redacao < 800  THEN '600–799'
        WHEN nu_nota_redacao < 900  THEN '800–899'
        ELSE                             '900–1000'
    END
ORDER BY faixa_nota
GO


-- ============================================================
-- QUERY 4: Nota média por sexo e área
-- ============================================================
SELECT
    CASE tp_sexo WHEN 'M' THEN 'Masculino' ELSE 'Feminino' END AS sexo,
    ROUND(AVG(nu_nota_mt),      1)      AS media_matematica,
    ROUND(AVG(nu_nota_lc),      1)      AS media_linguagens,
    ROUND(AVG(nu_nota_redacao), 1)      AS media_redacao,
    COUNT(*)                            AS candidatos
FROM Candidatos
WHERE nu_nota_mt IS NOT NULL
GROUP BY tp_sexo
GO
```

---

## Python — Notebook (nível iniciante com comentários explicativos)

### analise_enem.ipynb

```python
# ============================================================
# CÉLULA 1 — Importar bibliotecas
# ============================================================
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import seaborn as sns

plt.rcParams['figure.figsize'] = (11, 5)
plt.rcParams['axes.spines.top']   = False
plt.rcParams['axes.spines.right'] = False
sns.set_style('whitegrid')

print("Bibliotecas prontas!")
```

```python
# ============================================================
# CÉLULA 2 — Carregar os dados
# O ENEM tem milhões de linhas — usamos nrows para amostrar
# ============================================================

df = pd.read_csv(
    'data/MICRODADOS_ENEM_2023.csv',
    sep=';',
    encoding='latin-1',   # encoding padrão dos arquivos do INEP
    nrows=100_000          # 100 mil linhas são suficientes para análise
)

print(f"Shape: {df.shape}")
print(df[['NU_NOTA_MT','NU_NOTA_REDACAO','SG_UF_PROVA','TP_ESCOLA']].head())
```

```python
# ============================================================
# CÉLULA 3 — Limpeza dos dados
# ============================================================

# Selecionar apenas colunas que vamos usar
colunas = [
    'SG_UF_PROVA','TP_SEXO','TP_ESCOLA',
    'NU_NOTA_CN','NU_NOTA_CH','NU_NOTA_LC',
    'NU_NOTA_MT','NU_NOTA_REDACAO','TP_ST_CONCLUSAO'
]
df = df[colunas].copy()

# Renomear para ficar mais legível
df.columns = [
    'estado','sexo','tipo_escola',
    'nota_cn','nota_ch','nota_lc',
    'nota_mt','nota_redacao','status'
]

# Filtrar candidatos com notas válidas
df = df[
    df['nota_mt'].notna() &
    df['nota_redacao'].notna() &
    df['nota_redacao'] > 0
]

# Criar coluna de média geral
df['media_geral'] = (
    df[['nota_cn','nota_ch','nota_lc','nota_mt','nota_redacao']].mean(axis=1)
).round(1)

# Traduzir tipo de escola
df['tipo_escola'] = df['tipo_escola'].map({1:'Pública', 2:'Privada'})

print(f"Candidatos com notas válidas: {len(df):,}")
print(df.describe().round(1))
```

```python
# ============================================================
# CÉLULA 4 — Análise 1: Média por estado
# ============================================================

por_estado = (
    df.groupby('estado')
    .agg(
        candidatos=('nota_mt', 'count'),
        media_mat=('nota_mt', 'mean'),
        media_redacao=('nota_redacao', 'mean'),
        media_geral=('media_geral', 'mean')
    )
    .round(1)
    .reset_index()
    .sort_values('media_geral', ascending=False)
)

print(por_estado.to_string(index=False))

# Gráfico
fig, ax = plt.subplots(figsize=(12, 6))
cores = ['#4a7fc1' if e != por_estado.iloc[0]['estado'] else '#c94040'
         for e in por_estado['estado']]
ax.bar(por_estado['estado'], por_estado['media_geral'], color=cores)
ax.set_title('Média geral do ENEM por estado', fontsize=13)
ax.set_ylabel('Média geral')
ax.set_xlabel('Estado')
ax.set_ylim(400, por_estado['media_geral'].max() + 30)
plt.tight_layout()
plt.savefig('outputs/graficos/01_media_por_estado.png', dpi=150)
plt.show()
```

```python
# ============================================================
# CÉLULA 5 — Análise 2: Pública x Privada
# ============================================================

escola = (
    df[df['tipo_escola'].notna()]
    .groupby('tipo_escola')
    [['nota_mt','nota_lc','nota_cn','nota_ch','nota_redacao']]
    .mean()
    .round(1)
)

print(escola)
print(f"\nDiferença na média de Matemática: {escola.loc['Privada','nota_mt'] - escola.loc['Pública','nota_mt']:.1f} pontos")

# Gráfico de barras agrupadas
materias = ['nota_mt','nota_lc','nota_cn','nota_ch','nota_redacao']
labels   = ['Matemática','Linguagens','Ciências Nat.','Ciências Hum.','Redação']

x = range(len(materias))
w = 0.35

fig, ax = plt.subplots()
ax.bar([i - w/2 for i in x], escola.loc['Pública',  materias], w, label='Pública',  color='#4a7fc1')
ax.bar([i + w/2 for i in x], escola.loc['Privada', materias], w, label='Privada', color='#c94040')

ax.set_xticks(x)
ax.set_xticklabels(labels)
ax.set_title('Desempenho: escola pública x privada', fontsize=13)
ax.set_ylabel('Nota média')
ax.legend()
ax.set_ylim(400, 750)
plt.tight_layout()
plt.savefig('outputs/graficos/02_publica_privada.png', dpi=150)
plt.show()
```

```python
# ============================================================
# CÉLULA 6 — Análise 3: Distribuição das notas de redação
# ============================================================

fig, ax = plt.subplots()
ax.hist(df['nota_redacao'], bins=30, color='#5b9e6f', edgecolor='white')
ax.axvline(df['nota_redacao'].mean(),   color='navy', linestyle='--',
           label=f"Média: {df['nota_redacao'].mean():.0f}")
ax.axvline(df['nota_redacao'].median(), color='red',  linestyle='--',
           label=f"Mediana: {df['nota_redacao'].median():.0f}")
ax.set_title('Distribuição das notas de Redação — ENEM', fontsize=13)
ax.set_xlabel('Nota')
ax.set_ylabel('Quantidade de candidatos')
ax.legend()
plt.tight_layout()
plt.savefig('outputs/graficos/03_distribuicao_redacao.png', dpi=150)
plt.show()
```

```python
# ============================================================
# CÉLULA 7 — Análise 4: Heatmap de notas por área e estado
# ============================================================

heatmap_data = (
    df.groupby('estado')
    [['nota_mt','nota_lc','nota_cn','nota_ch','nota_redacao']]
    .mean()
    .round(1)
)
heatmap_data.columns = ['Matemática','Linguagens','Ciências Nat.','Ciências Hum.','Redação']

fig, ax = plt.subplots(figsize=(10, 10))
sns.heatmap(
    heatmap_data,
    annot=True, fmt='.0f',
    cmap='YlOrRd',
    linewidths=0.5,
    ax=ax
)
ax.set_title('Nota média por estado e área do conhecimento', fontsize=13)
plt.tight_layout()
plt.savefig('outputs/graficos/04_heatmap_estados.png', dpi=150)
plt.show()
```

```python
# ============================================================
# CÉLULA 8 — Resumo e exportação
# ============================================================

print("===== RESUMO DA ANÁLISE =====")
print(f"Total de candidatos analisados: {len(df):,}")
print(f"Média geral nacional: {df['media_geral'].mean():.1f}")
print(f"Melhor estado (média geral): {por_estado.iloc[0]['estado']} — {por_estado.iloc[0]['media_geral']}")
print(f"Pior estado (média geral):   {por_estado.iloc[-1]['estado']} — {por_estado.iloc[-1]['media_geral']}")

media_esc = df[df['tipo_escola'].notna()].groupby('tipo_escola')['media_geral'].mean().round(1)
print(f"\nMédia pública:  {media_esc.get('Pública', 'N/A')}")
print(f"Média privada: {media_esc.get('Privada', 'N/A')}")

por_estado.to_csv('outputs/media_enem_por_estado.csv', index=False, encoding='utf-8-sig')
print("\nExportado!")
```

---

## README.md para o GitHub

```markdown
# Análise das Notas do ENEM por Estado

> Exploração dos microdados do ENEM com foco em desigualdade educacional:
> diferenças por estado, tipo de escola e área do conhecimento.

## Perguntas respondidas
- Quais estados têm melhor desempenho no ENEM?
- Qual a diferença de nota entre escola pública e privada?
- Qual a distribuição das notas de Redação?
- Existe diferença por área do conhecimento entre os estados?

## Stack
| Ferramenta | Uso |
|---|---|
| SQL Server | Criação de tabelas, BULK INSERT, GROUP BY, CASE WHEN |
| Python / Pandas | Limpeza, filtros, agrupamentos |
| Seaborn | Heatmap de notas por estado e área |
| Matplotlib | Barras, histograma, barras agrupadas |

## Dataset
Microdados ENEM — INEP / dados.gov.br  
https://www.gov.br/inep/pt-br/acesso-a-informacao/dados-abertos/microdados/enem
```
