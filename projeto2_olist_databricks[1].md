# Projeto 2 — Pipeline de Dados E-commerce com Databricks + Spark
**Dataset:** Olist (Kaggle) | **Stack:** Databricks, PySpark, SQL, Parquet, Delta Lake

---

## Objetivo
Construir um pipeline de dados de ponta a ponta: ingestão de CSVs brutos → camadas Bronze/Silver/Gold → consultas analíticas com Spark SQL — exatamente como funciona em empresas reais usando arquitetura Medallion.

---

## Onde baixar os dados
```
https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
```
Arquivos:
- `olist_orders_dataset.csv`
- `olist_order_items_dataset.csv`
- `olist_customers_dataset.csv`
- `olist_products_dataset.csv`
- `olist_sellers_dataset.csv`
- `olist_order_reviews_dataset.csv`

---

## Arquitetura Medallion (Bronze → Silver → Gold)

```
/FileStore/tables/olist/
├── bronze/          # dados brutos, exatamente como chegaram
│   ├── orders/
│   ├── items/
│   └── customers/
├── silver/          # dados limpos, tipados, sem duplicatas
│   ├── orders_clean/
│   └── customers_clean/
└── gold/            # agregações prontas para análise / BI
    ├── vendas_por_estado/
    ├── ticket_medio_categoria/
    └── cohort_retencao/
```

---

## Databricks — Notebooks

### Notebook 1: Ingestão Bronze

```python
# ============================================================
# NOTEBOOK 1 — Camada Bronze (Raw Ingestion)
# ============================================================

# Verificar arquivos disponíveis no DBFS
display(dbutils.fs.ls('/FileStore/tables/olist/'))

# Parâmetros reutilizáveis
BASE_PATH   = '/FileStore/tables/olist'
BRONZE_PATH = f'{BASE_PATH}/bronze'

# Função genérica de ingestão — boa prática: nunca repetir código
def ingest_csv(nome_arquivo, destino):
    df = (
        spark.read
        .format("csv")
        .option("header", True)
        .option("inferSchema", True)
        .option("sep", ",")
        .option("encoding", "UTF-8")
        .load(f'{BASE_PATH}/raw/{nome_arquivo}')
    )
    print(f"[{nome_arquivo}] linhas: {df.count():,} | colunas: {len(df.columns)}")
    
    # Salvar como Parquet na camada Bronze (comprimido, muito mais rápido)
    df.write \
      .format("parquet") \
      .option("compression", "snappy") \
      .mode("overwrite") \
      .save(f'{BRONZE_PATH}/{destino}')
    
    return df

# Ingerir todos os arquivos
df_orders    = ingest_csv('olist_orders_dataset.csv',       'orders')
df_items     = ingest_csv('olist_order_items_dataset.csv',  'items')
df_customers = ingest_csv('olist_customers_dataset.csv',    'customers')
df_products  = ingest_csv('olist_products_dataset.csv',     'products')
df_sellers   = ingest_csv('olist_sellers_dataset.csv',      'sellers')
df_reviews   = ingest_csv('olist_order_reviews_dataset.csv','reviews')
```

### Notebook 2: Transformação Silver

```python
# ============================================================
# NOTEBOOK 2 — Camada Silver (Clean & Typed)
# ============================================================

from pyspark.sql import functions as F
from pyspark.sql.types import TimestampType, DoubleType

SILVER_PATH = '/FileStore/tables/olist/silver'

# Ler da Bronze
raw_orders = spark.read.parquet('/FileStore/tables/olist/bronze/orders')

# ---------- Limpeza de orders ----------
orders_clean = (
    raw_orders
    # Converter strings de data para Timestamp
    .withColumn('purchase_ts',
        F.to_timestamp('order_purchase_timestamp', 'yyyy-MM-dd HH:mm:ss'))
    .withColumn('approved_ts',
        F.to_timestamp('order_approved_at', 'yyyy-MM-dd HH:mm:ss'))
    .withColumn('delivered_ts',
        F.to_timestamp('order_delivered_customer_date', 'yyyy-MM-dd HH:mm:ss'))
    .withColumn('estimated_ts',
        F.to_timestamp('order_estimated_delivery_date', 'yyyy-MM-dd HH:mm:ss'))
    # Calcular dias de entrega
    .withColumn('dias_entrega',
        F.datediff(F.col('delivered_ts'), F.col('purchase_ts')))
    # Flag de entrega no prazo
    .withColumn('entregue_no_prazo',
        F.when(F.col('delivered_ts') <= F.col('estimated_ts'), 1).otherwise(0))
    # Remover pedidos sem status definido
    .filter(F.col('order_status').isNotNull())
    # Dropar colunas originais de string de data (já processadas)
    .drop('order_purchase_timestamp','order_approved_at',
          'order_delivered_customer_date','order_estimated_delivery_date',
          'order_delivered_carrier_date')
    # Remover duplicatas
    .dropDuplicates(['order_id'])
)

print(f"Orders antes: {raw_orders.count():,} | após limpeza: {orders_clean.count():,}")

orders_clean.write \
    .format("parquet") \
    .option("compression", "snappy") \
    .mode("overwrite") \
    .save(f'{SILVER_PATH}/orders_clean')


# ---------- Limpeza de items ----------
raw_items = spark.read.parquet('/FileStore/tables/olist/bronze/items')

items_clean = (
    raw_items
    .withColumn('price',         F.col('price').cast(DoubleType()))
    .withColumn('freight_value', F.col('freight_value').cast(DoubleType()))
    .withColumn('total_item',    F.col('price') + F.col('freight_value'))
    .dropDuplicates(['order_id','order_item_id'])
)

items_clean.write \
    .format("parquet") \
    .mode("overwrite") \
    .save(f'{SILVER_PATH}/items_clean')

display(items_clean.describe(['price','freight_value','total_item']))
```

### Notebook 3: Camada Gold — Análises

```python
# ============================================================
# NOTEBOOK 3 — Camada Gold + Análises com Spark SQL
# ============================================================

GOLD_PATH = '/FileStore/tables/olist/gold'

# Registrar tabelas temporárias para usar Spark SQL
orders_clean  = spark.read.parquet('/FileStore/tables/olist/silver/orders_clean')
items_clean   = spark.read.parquet('/FileStore/tables/olist/silver/items_clean')
customers_raw = spark.read.parquet('/FileStore/tables/olist/bronze/customers')
products_raw  = spark.read.parquet('/FileStore/tables/olist/bronze/products')

orders_clean.createOrReplaceTempView('orders')
items_clean.createOrReplaceTempView('items')
customers_raw.createOrReplaceTempView('customers')
products_raw.createOrReplaceTempView('products')
```

```sql
-- ============================================================
-- ANÁLISE 1: Receita mensal com variação MoM (Month-over-Month)
-- Window function no Spark SQL — mesmo conceito do SQL Server!
-- ============================================================
%sql

WITH receita_mensal AS (
    SELECT
        DATE_TRUNC('month', o.purchase_ts)          AS mes,
        ROUND(SUM(i.total_item), 2)                 AS receita_total,
        COUNT(DISTINCT o.order_id)                  AS total_pedidos,
        ROUND(AVG(i.total_item), 2)                 AS ticket_medio
    FROM orders o
    INNER JOIN items i ON o.order_id = i.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY DATE_TRUNC('month', o.purchase_ts)
)
SELECT
    mes,
    receita_total,
    total_pedidos,
    ticket_medio,
    LAG(receita_total) OVER (ORDER BY mes)          AS receita_mes_anterior,
    ROUND(
        100.0 * (receita_total - LAG(receita_total) OVER (ORDER BY mes))
              / NULLIF(LAG(receita_total) OVER (ORDER BY mes), 0)
    , 2)                                            AS variacao_pct,
    SUM(receita_total) OVER (ORDER BY mes
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS receita_acumulada
FROM receita_mensal
ORDER BY mes
```

```sql
-- ============================================================
-- ANÁLISE 2: Ranking de categorias por receita e volume
-- ============================================================
%sql

SELECT
    COALESCE(p.product_category_name, 'sem_categoria') AS categoria,
    COUNT(DISTINCT i.order_id)                          AS pedidos,
    ROUND(SUM(i.price), 2)                              AS receita,
    ROUND(AVG(i.price), 2)                              AS preco_medio,
    ROUND(AVG(i.freight_value), 2)                      AS frete_medio,
    ROUND(SUM(i.freight_value) / NULLIF(SUM(i.price),0) * 100, 2) AS pct_frete_receita,
    RANK() OVER (ORDER BY SUM(i.price) DESC)            AS rank_receita
FROM items i
LEFT JOIN products p ON i.product_id = p.product_id
GROUP BY p.product_category_name
HAVING COUNT(DISTINCT i.order_id) > 50
ORDER BY receita DESC
LIMIT 20
```

```sql
-- ============================================================
-- ANÁLISE 3: Performance de entrega por estado
-- ============================================================
%sql

SELECT
    c.customer_state                                    AS estado,
    COUNT(DISTINCT o.order_id)                          AS total_pedidos,
    ROUND(AVG(o.dias_entrega), 1)                       AS media_dias_entrega,
    ROUND(100.0 * SUM(o.entregue_no_prazo)
               / COUNT(*), 1)                           AS pct_no_prazo,
    PERCENTILE(o.dias_entrega, 0.5)                     AS mediana_dias,
    PERCENTILE(o.dias_entrega, 0.95)                    AS p95_dias
FROM orders o
INNER JOIN customers c ON o.customer_id = c.customer_id
WHERE o.order_status = 'delivered'
  AND o.dias_entrega IS NOT NULL
GROUP BY c.customer_state
ORDER BY media_dias_entrega DESC
```

```python
# ============================================================
# ANÁLISE 4: Cohort de retenção (Python puro — nível avançado)
# Identifica se clientes voltam a comprar em meses seguintes
# ============================================================

from pyspark.sql import functions as F
from pyspark.sql.window import Window

# Primeiro pedido de cada cliente
w_first = Window.partitionBy('customer_unique_id')

cohort_df = (
    orders_clean
    .join(customers_raw.select('customer_id','customer_unique_id'), 'customer_id')
    .withColumn('purchase_month', F.date_trunc('month', F.col('purchase_ts')))
    .withColumn('cohort_month',
        F.min('purchase_month').over(w_first))
    .withColumn('period_number',
        F.months_between(F.col('purchase_month'), F.col('cohort_month')).cast('int'))
    .groupBy('cohort_month', 'period_number')
    .agg(F.countDistinct('customer_unique_id').alias('clientes'))
)

# Salvar na Gold particionado por cohort_month
cohort_df.write \
    .format("parquet") \
    .partitionBy('cohort_month') \
    .mode("overwrite") \
    .save(f'{GOLD_PATH}/cohort_retencao')

display(cohort_df.orderBy('cohort_month', 'period_number'))
```

```python
# ============================================================
# SALVAR GOLD PRINCIPAL — pronto para consumo por BI/relatório
# ============================================================

gold_vendas = spark.sql("""
    SELECT
        c.customer_state            AS estado,
        DATE_TRUNC('month', o.purchase_ts) AS mes,
        COUNT(DISTINCT o.order_id)  AS pedidos,
        ROUND(SUM(i.total_item), 2) AS receita
    FROM orders o
    INNER JOIN items i     ON o.order_id   = i.order_id
    INNER JOIN customers c ON o.customer_id = c.customer_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_state, DATE_TRUNC('month', o.purchase_ts)
""")

gold_vendas.write \
    .format("parquet") \
    .option("compression", "snappy") \
    .partitionBy("estado") \
    .mode("overwrite") \
    .save(f'{GOLD_PATH}/vendas_por_estado')

print("Camada Gold gerada!")
display(gold_vendas.orderBy('receita', ascending=False))
```

---

## README.md para o GitHub

```markdown
# Pipeline E-commerce Olist — Arquitetura Medallion no Databricks

> Pipeline de dados de ponta a ponta: CSV bruto → Bronze → Silver → Gold
> usando PySpark, Spark SQL e Parquet com compressão Snappy.

## Arquitetura
```
Raw CSV → Bronze (Parquet) → Silver (limpo + tipado) → Gold (agregado)
```

## Análises entregues
- Receita mensal com variação MoM e acumulado
- Ranking de categorias por receita e % de frete sobre receita
- SLA de entrega por estado (média, mediana, P95)
- Cohort de retenção de clientes mês a mês

## Conceitos demonstrados
| Conceito | Implementação |
|---|---|
| Arquitetura Medallion | Bronze / Silver / Gold no DBFS |
| Window Functions | LAG, SUM OVER, RANK — Spark SQL |
| Particionamento | `.partitionBy()` para leitura eficiente |
| Compressão | Parquet + Snappy (formato padrão de mercado) |
| Cohort Analysis | Cálculo de retenção com `months_between` |

## Dataset
Olist Brazilian E-Commerce — Kaggle  
https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
```
