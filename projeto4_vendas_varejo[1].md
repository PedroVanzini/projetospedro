# Projeto 4 — Análise de Vendas do Varejo Brasileiro
**Dataset:** Brazilian E-Commerce Olist (Kaggle) | **Stack:** SQL Server básico/intermediário + Python iniciante (Pandas + Matplotlib)

---

## Objetivo
Analisar o desempenho de vendas de um e-commerce para responder perguntas simples de negócio: quais produtos vendem mais, qual estado compra mais, como as vendas variaram por mês. Projeto ideal para quem está aprendendo Python.

---

## Onde baixar os dados
```
https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
```
Arquivo principal: `olist_orders_dataset.csv` + `olist_order_items_dataset.csv`

---

## Estrutura do projeto
```
analise-vendas-varejo/
├── data/
│   └── README.md
├── sql/
│   └── queries_vendas.sql
├── notebooks/
│   └── analise_vendas.ipynb
├── outputs/
│   └── graficos/
└── README.md
```

---

## SQL Server — Queries

### queries_vendas.sql
```sql
-- ============================================================
-- PROJETO: Análise de Vendas Varejo Brasileiro
-- FONTE: Olist / Kaggle
-- ============================================================

CREATE DATABASE VendasVarejo
GO
USE VendasVarejo
GO

-- Criar tabela de pedidos
CREATE TABLE Pedidos (
    order_id             VARCHAR(40) PRIMARY KEY,
    customer_id          VARCHAR(40) NOT NULL,
    status_pedido        VARCHAR(20),
    data_compra          DATETIME,
    data_aprovacao       DATETIME,
    data_entrega         DATETIME,
    data_estimada        DATETIME
)
GO

-- Criar tabela de itens do pedido
CREATE TABLE ItensPedido (
    order_id             VARCHAR(40),
    item_id              INT,
    product_id           VARCHAR(40),
    seller_id            VARCHAR(40),
    preco                DECIMAL(10,2),
    frete                DECIMAL(10,2),
    CONSTRAINT PK_Itens PRIMARY KEY (order_id, item_id),
    CONSTRAINT FK_Itens_Pedido FOREIGN KEY (order_id)
        REFERENCES Pedidos(order_id)
)
GO

-- Criar tabela de clientes
CREATE TABLE Clientes (
    customer_id          VARCHAR(40) PRIMARY KEY,
    customer_unique_id   VARCHAR(40),
    cidade               VARCHAR(60),
    estado               CHAR(2)
)
GO

-- ============================================================
-- QUERY 1: Total de vendas e receita por mês
-- ============================================================
SELECT
    YEAR(P.data_compra)                 AS ano,
    MONTH(P.data_compra)                AS mes,
    DATENAME(MONTH, P.data_compra)      AS nome_mes,
    COUNT(DISTINCT P.order_id)          AS total_pedidos,
    ROUND(SUM(I.preco), 2)              AS receita_total,
    ROUND(AVG(I.preco), 2)              AS ticket_medio
FROM Pedidos P
INNER JOIN ItensPedido I ON P.order_id = I.order_id
WHERE P.status_pedido = 'delivered'
GROUP BY
    YEAR(P.data_compra),
    MONTH(P.data_compra),
    DATENAME(MONTH, P.data_compra)
ORDER BY ano, mes
GO


-- ============================================================
-- QUERY 2: Top 10 estados que mais compram
-- ============================================================
SELECT TOP 10
    C.estado,
    COUNT(DISTINCT P.order_id)          AS total_pedidos,
    ROUND(SUM(I.preco), 2)              AS receita_total,
    ROUND(AVG(I.preco), 2)              AS ticket_medio,
    COUNT(DISTINCT P.customer_id)       AS clientes_unicos
FROM Pedidos P
INNER JOIN ItensPedido I ON P.order_id = I.order_id
INNER JOIN Clientes C    ON P.customer_id = C.customer_id
WHERE P.status_pedido = 'delivered'
GROUP BY C.estado
ORDER BY receita_total DESC
GO


-- ============================================================
-- QUERY 3: Dias médios de entrega por estado
-- ============================================================
SELECT
    C.estado,
    COUNT(DISTINCT P.order_id)              AS pedidos_entregues,
    AVG(DATEDIFF(DAY, P.data_compra, P.data_entrega))   AS media_dias_entrega,
    MIN(DATEDIFF(DAY, P.data_compra, P.data_entrega))   AS minimo_dias,
    MAX(DATEDIFF(DAY, P.data_compra, P.data_entrega))   AS maximo_dias
FROM Pedidos P
INNER JOIN Clientes C ON P.customer_id = C.customer_id
WHERE P.status_pedido = 'delivered'
  AND P.data_entrega IS NOT NULL
GROUP BY C.estado
ORDER BY media_dias_entrega DESC
GO


-- ============================================================
-- QUERY 4: Pedidos por dia da semana (padrão de compra)
-- ============================================================
SELECT
    DATENAME(WEEKDAY, data_compra)      AS dia_semana,
    DATEPART(WEEKDAY, data_compra)      AS num_dia,
    COUNT(DISTINCT order_id)            AS total_pedidos,
    ROUND(AVG(
        (SELECT SUM(preco) FROM ItensPedido I WHERE I.order_id = P.order_id)
    ), 2)                               AS ticket_medio
FROM Pedidos P
WHERE status_pedido = 'delivered'
GROUP BY
    DATENAME(WEEKDAY, data_compra),
    DATEPART(WEEKDAY, data_compra)
ORDER BY num_dia
GO


-- ============================================================
-- QUERY 5: Status dos pedidos — quantos foram entregues, cancelados etc
-- ============================================================
SELECT
    status_pedido,
    COUNT(*)                            AS quantidade,
    ROUND(
        100.0 * COUNT(*) / (SELECT COUNT(*) FROM Pedidos)
    , 2)                                AS percentual
FROM Pedidos
GROUP BY status_pedido
ORDER BY quantidade DESC
GO
```

---

## Python — Notebook completo (nível iniciante)

### analise_vendas.ipynb

```python
# ============================================================
# CÉLULA 1 — Instalar e importar bibliotecas
# (rode isso no terminal antes: pip install pandas matplotlib seaborn)
# ============================================================

import pandas as pd           # manipulação de dados (substitui o Excel)
import matplotlib.pyplot as plt  # gráficos
import seaborn as sns         # gráficos mais bonitos

# Configurações visuais
plt.rcParams['figure.figsize'] = (10, 5)
plt.rcParams['axes.spines.top'] = False
plt.rcParams['axes.spines.right'] = False

print("Tudo importado com sucesso!")
```

```python
# ============================================================
# CÉLULA 2 — Carregar os dados (CSVs do Kaggle)
# ============================================================

# pd.read_csv lê um arquivo CSV e transforma em tabela (DataFrame)
pedidos = pd.read_csv('data/olist_orders_dataset.csv')
itens   = pd.read_csv('data/olist_order_items_dataset.csv')
clientes= pd.read_csv('data/olist_customers_dataset.csv')

# Ver as primeiras linhas — equivalente ao SELECT TOP 5
print("=== PEDIDOS ===")
print(pedidos.head())

print("\n=== ITENS ===")
print(itens.head())

# Ver quantas linhas e colunas tem cada tabela
print(f"\nPedidos: {pedidos.shape[0]:,} linhas, {pedidos.shape[1]} colunas")
print(f"Itens:   {itens.shape[0]:,} linhas, {itens.shape[1]} colunas")
```

```python
# ============================================================
# CÉLULA 3 — Limpeza básica dos dados
# ============================================================

# Converter coluna de data de texto para data de verdade
# Equivalente ao CAST ou CONVERT do SQL
pedidos['data_compra'] = pd.to_datetime(pedidos['order_purchase_timestamp'])

# Extrair ano e mês (igual ao YEAR() e MONTH() do SQL)
pedidos['ano'] = pedidos['data_compra'].dt.year
pedidos['mes'] = pedidos['data_compra'].dt.month
pedidos['mes_nome'] = pedidos['data_compra'].dt.strftime('%b/%Y')  # ex: Jan/2018

# Filtrar só pedidos entregues (equivalente ao WHERE do SQL)
pedidos_entregues = pedidos[pedidos['order_status'] == 'delivered'].copy()

print(f"Total de pedidos: {len(pedidos):,}")
print(f"Pedidos entregues: {len(pedidos_entregues):,}")
print(f"\nColunas com datas nulas:\n{pedidos[['order_purchase_timestamp']].isnull().sum()}")
```

```python
# ============================================================
# CÉLULA 4 — Juntar tabelas (equivalente ao JOIN do SQL)
# ============================================================

# merge = JOIN do Python
# 'on' = coluna em comum entre as tabelas
# 'how' = tipo do join (left, inner, right)

df = pedidos_entregues.merge(itens,    on='order_id',    how='inner')
df = df.merge(clientes, on='customer_id', how='left')

print(f"Tabela combinada: {df.shape[0]:,} linhas, {df.shape[1]} colunas")
print(df[['order_id','customer_state','price','freight_value']].head())
```

```python
# ============================================================
# CÉLULA 5 — Análise 1: Receita mensal (equivalente à Query 1 do SQL)
# ============================================================

# groupby = GROUP BY do SQL
# agg = funções de agregação (SUM, COUNT, AVG)
mensal = (
    df.groupby(['ano', 'mes', 'mes_nome'])
    .agg(
        total_pedidos=('order_id', 'nunique'),   # COUNT DISTINCT
        receita=('price', 'sum'),                 # SUM
        ticket_medio=('price', 'mean')            # AVG
    )
    .round(2)
    .reset_index()
    .sort_values(['ano', 'mes'])
)

print(mensal)

# Gráfico de barras da receita mensal
fig, ax = plt.subplots()
ax.bar(range(len(mensal)), mensal['receita'], color='#4a7fc1')
ax.set_xticks(range(len(mensal)))
ax.set_xticklabels(mensal['mes_nome'], rotation=45, ha='right', fontsize=9)
ax.set_title('Receita mensal — E-commerce Olist', fontsize=13)
ax.set_ylabel('Receita (R$)')
ax.yaxis.set_major_formatter(
    plt.FuncFormatter(lambda x, _: f'R$ {x/1000:.0f}k')
)
plt.tight_layout()
plt.savefig('outputs/graficos/01_receita_mensal.png', dpi=150)
plt.show()
```

```python
# ============================================================
# CÉLULA 6 — Análise 2: Top 10 estados (equivalente à Query 2 do SQL)
# ============================================================

por_estado = (
    df.groupby('customer_state')
    .agg(
        pedidos=('order_id', 'nunique'),
        receita=('price', 'sum'),
        ticket_medio=('price', 'mean')
    )
    .round(2)
    .reset_index()
    .sort_values('receita', ascending=False)
    .head(10)
)

print(por_estado)

# Gráfico horizontal de barras
fig, ax = plt.subplots()
ax.barh(por_estado['customer_state'], por_estado['receita'], color='#5b9e6f')
ax.set_title('Top 10 estados por receita', fontsize=13)
ax.set_xlabel('Receita total (R$)')
ax.invert_yaxis()
ax.xaxis.set_major_formatter(
    plt.FuncFormatter(lambda x, _: f'R$ {x/1e6:.1f}M')
)
plt.tight_layout()
plt.savefig('outputs/graficos/02_receita_por_estado.png', dpi=150)
plt.show()
```

```python
# ============================================================
# CÉLULA 7 — Análise 3: Distribuição do ticket médio
# ============================================================

# Remover outliers extremos para visualização limpa
preco_filtrado = df[df['price'] < df['price'].quantile(0.99)]['price']

fig, ax = plt.subplots()
ax.hist(preco_filtrado, bins=40, color='#c96a3a', edgecolor='white')
ax.axvline(preco_filtrado.mean(),   color='navy',  linestyle='--', label=f'Média: R$ {preco_filtrado.mean():.2f}')
ax.axvline(preco_filtrado.median(), color='green', linestyle='--', label=f'Mediana: R$ {preco_filtrado.median():.2f}')
ax.set_title('Distribuição de preços dos produtos', fontsize=13)
ax.set_xlabel('Preço (R$)')
ax.set_ylabel('Frequência')
ax.legend()
plt.tight_layout()
plt.savefig('outputs/graficos/03_distribuicao_preco.png', dpi=150)
plt.show()
```

```python
# ============================================================
# CÉLULA 8 — Análise 4: Dias da semana com mais compras
# ============================================================

pedidos['dia_semana'] = pedidos['data_compra'].dt.day_name()
pedidos['num_dia']    = pedidos['data_compra'].dt.dayofweek

por_dia = (
    pedidos.groupby(['num_dia','dia_semana'])
    .size()
    .reset_index(name='total_pedidos')
    .sort_values('num_dia')
)

dias_pt = {
    'Monday':'Segunda','Tuesday':'Terça','Wednesday':'Quarta',
    'Thursday':'Quinta','Friday':'Sexta','Saturday':'Sábado','Sunday':'Domingo'
}
por_dia['dia_semana'] = por_dia['dia_semana'].map(dias_pt)

fig, ax = plt.subplots()
ax.bar(por_dia['dia_semana'], por_dia['total_pedidos'], color='#7f77dd')
ax.set_title('Pedidos por dia da semana', fontsize=13)
ax.set_ylabel('Total de pedidos')
plt.tight_layout()
plt.savefig('outputs/graficos/04_pedidos_dia_semana.png', dpi=150)
plt.show()
```

```python
# ============================================================
# CÉLULA 9 — Resumo final e exportação
# ============================================================

print("===== RESUMO DO PROJETO =====")
print(f"Período analisado: {pedidos['data_compra'].min().date()} até {pedidos['data_compra'].max().date()}")
print(f"Total de pedidos entregues: {len(pedidos_entregues):,}")
print(f"Receita total: R$ {df['price'].sum():,.2f}")
print(f"Ticket médio geral: R$ {df['price'].mean():.2f}")
print(f"Estado com mais compras: {por_estado.iloc[0]['customer_state']}")
print(f"Receita do top estado: R$ {por_estado.iloc[0]['receita']:,.2f}")

# Exportar tabela resumo
mensal.to_csv('outputs/receita_mensal.csv', index=False, encoding='utf-8-sig')
por_estado.to_csv('outputs/receita_por_estado.csv', index=False, encoding='utf-8-sig')
print("\nArquivos exportados!")
```

---

## README.md para o GitHub

```markdown
# Análise de Vendas — E-commerce Olist Brasil

> Análise exploratória de dados de um e-commerce brasileiro com SQL Server e Python,
> respondendo perguntas de negócio sobre receita, estados e padrão de compra.

## Perguntas respondidas
- Qual mês teve maior receita?
- Quais estados concentram as compras?
- Qual o ticket médio dos produtos?
- Em quais dias da semana as pessoas mais compram?

## Stack
| Ferramenta | Uso |
|---|---|
| SQL Server | Modelagem relacional, JOINs, GROUP BY, funções de data |
| Python / Pandas | Leitura de CSVs, merge de tabelas, agregações |
| Matplotlib | Gráficos de barras, histograma |

## Dataset
Olist Brazilian E-Commerce — Kaggle  
https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
```
