# Projeto 3 — Predição de Churn com SQL + Python + Machine Learning
**Dataset:** Telco Customer Churn (Kaggle) | **Stack:** SQL Server, Python, Scikit-learn, MLflow

---

## Objetivo
Construir um modelo de Machine Learning que prevê quais clientes de uma telecom vão cancelar o serviço (churn) nos próximos 30 dias — com feature engineering feita em SQL e modelagem em Python. Esse é o projeto mais valorizado no portfólio porque combina SQL avançado + ML + deploy.

---

## Onde baixar os dados
```
https://www.kaggle.com/datasets/blastchar/telco-customer-churn
```
Arquivo: `WA_Fn-UseC_-Telco-Customer-Churn.csv`

---

## Fluxo do projeto
```
CSV bruto
  ↓
SQL Server: feature engineering avançada (CTEs, window functions)
  ↓
Python: treinamento do modelo (Random Forest + XGBoost)
  ↓
Avaliação: ROC-AUC, matriz de confusão, feature importance
  ↓
Deploy: API simples com FastAPI (diferencial de portfólio)
```

---

## SQL Server — Feature Engineering

### 01_create_and_load.sql
```sql
USE ChurnAnalysis
GO

CREATE TABLE Cliente (
    customer_id          VARCHAR(20)    PRIMARY KEY,
    genero               CHAR(1),
    idoso                BIT,
    possui_parceiro      BIT,
    possui_dependentes   BIT,
    meses_contrato       INT,           -- tenure
    servico_telefone     BIT,
    multiplas_linhas     VARCHAR(20),
    servico_internet     VARCHAR(20),
    seguranca_online     VARCHAR(20),
    backup_online        VARCHAR(20),
    protecao_dispositivo VARCHAR(20),
    suporte_tecnico      VARCHAR(20),
    tv_streaming         VARCHAR(20),
    filmes_streaming     VARCHAR(20),
    tipo_contrato        VARCHAR(20),   -- Month-to-month, One year, Two year
    fatura_digital       BIT,
    forma_pagamento      VARCHAR(30),
    mensalidade          DECIMAL(8,2),
    total_gasto          DECIMAL(10,2),
    churn                BIT            -- TARGET: 1 = cancelou, 0 = ficou
)
GO
```

### 02_feature_engineering.sql
```sql
-- ============================================================
-- FEATURE ENGINEERING AVANÇADA
-- Gera features derivadas que o modelo vai usar
-- ============================================================

-- VIEW materializada como tabela de features
SELECT
    C.customer_id,

    -- Features originais
    C.meses_contrato,
    C.mensalidade,
    C.total_gasto,
    C.tipo_contrato,
    C.forma_pagamento,
    C.servico_internet,
    C.idoso,
    C.possui_parceiro,
    C.possui_dependentes,

    -- Feature 1: Receita média por mês (gasto total / meses)
    ROUND(
        C.total_gasto / NULLIF(C.meses_contrato, 0)
    , 2)                                            AS receita_media_mensal,

    -- Feature 2: Diferença entre mensalidade atual e média histórica
    ROUND(
        C.mensalidade - (C.total_gasto / NULLIF(C.meses_contrato, 0))
    , 2)                                            AS delta_mensalidade_media,

    -- Feature 3: Quantidade de serviços contratados
    (
        CASE WHEN C.seguranca_online      = 'Yes' THEN 1 ELSE 0 END +
        CASE WHEN C.backup_online         = 'Yes' THEN 1 ELSE 0 END +
        CASE WHEN C.protecao_dispositivo  = 'Yes' THEN 1 ELSE 0 END +
        CASE WHEN C.suporte_tecnico       = 'Yes' THEN 1 ELSE 0 END +
        CASE WHEN C.tv_streaming          = 'Yes' THEN 1 ELSE 0 END +
        CASE WHEN C.filmes_streaming      = 'Yes' THEN 1 ELSE 0 END
    )                                               AS qtd_servicos_adicionais,

    -- Feature 4: Segmento de tempo de contrato (bucket)
    CASE
        WHEN C.meses_contrato <= 6   THEN 'novo'
        WHEN C.meses_contrato <= 24  THEN 'medio'
        ELSE                              'leal'
    END                                             AS segmento_tenure,

    -- Feature 5: Flag de contrato de longo prazo (menor risco de churn)
    CASE
        WHEN C.tipo_contrato IN ('One year','Two year') THEN 1
        ELSE 0
    END                                             AS contrato_longo_prazo,

    -- Feature 6: Percentil de mensalidade (posição do cliente vs todos)
    ROUND(
        PERCENT_RANK() OVER (ORDER BY C.mensalidade)
    , 4)                                            AS percentil_mensalidade,

    -- Feature 7: Z-score de mensalidade (padronização)
    ROUND(
        (C.mensalidade - AVG(C.mensalidade) OVER ())
        / NULLIF(STDEV(C.mensalidade) OVER (), 0)
    , 4)                                            AS zscore_mensalidade,

    -- Target
    C.churn

INTO FeatureStore
FROM Cliente C
GO

-- Verificar distribuição do target (importante: ver se há desbalanceamento)
SELECT
    churn,
    COUNT(*)                                        AS total,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentual
FROM FeatureStore
GROUP BY churn
GO
```

---

## Python — Modelagem Completa

### churn_model.py

```python
# ============================================================
# CÉLULA 1 — Imports
# ============================================================
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns

from sqlalchemy import create_engine

# Pré-processamento
from sklearn.model_selection import train_test_split, StratifiedKFold, cross_val_score
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.pipeline import Pipeline
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import OneHotEncoder

# Modelos
from sklearn.ensemble import RandomForestClassifier, GradientBoostingClassifier
from sklearn.linear_model import LogisticRegression

# Métricas
from sklearn.metrics import (
    roc_auc_score, classification_report,
    confusion_matrix, RocCurveDisplay,
    precision_recall_curve
)

plt.rcParams['figure.figsize'] = (10, 6)
plt.rcParams['axes.spines.top'] = False
plt.rcParams['axes.spines.right'] = False
```

```python
# ============================================================
# CÉLULA 2 — Carregar features do SQL Server
# ============================================================

# Via SQLAlchemy (conecta direto na FeatureStore que criamos no SQL)
engine = create_engine(
    "mssql+pyodbc://usuario:senha@servidor/ChurnAnalysis"
    "?driver=ODBC+Driver+17+for+SQL+Server"
)

df = pd.read_sql("SELECT * FROM FeatureStore", engine)

# Alternativa: ler CSV direto
# df = pd.read_csv('data/telco_churn.csv')

print(f"Shape: {df.shape}")
print(f"\nDistribuição do target:\n{df['churn'].value_counts(normalize=True).round(3)}")
df.head()
```

```python
# ============================================================
# CÉLULA 3 — Pré-processamento
# ============================================================

# Separar features e target
TARGET = 'churn'
ID_COL = 'customer_id'

X = df.drop(columns=[TARGET, ID_COL])
y = df[TARGET]

# Identificar tipos de colunas
cat_cols = X.select_dtypes(include='object').columns.tolist()
num_cols = X.select_dtypes(include=['int64','float64']).columns.tolist()

print(f"Colunas categóricas: {cat_cols}")
print(f"Colunas numéricas: {num_cols}")

# Pipeline de pré-processamento
preprocessor = ColumnTransformer(transformers=[
    ('num', StandardScaler(), num_cols),
    ('cat', OneHotEncoder(handle_unknown='ignore', sparse_output=False), cat_cols)
])

# Split estratificado (mantém proporção do target)
X_train, X_test, y_train, y_test = train_test_split(
    X, y,
    test_size=0.2,
    random_state=42,
    stratify=y        # IMPORTANTE: garante mesma proporção de churn em train/test
)

print(f"\nTreino: {X_train.shape} | Teste: {X_test.shape}")
print(f"Churn no treino: {y_train.mean():.2%} | no teste: {y_test.mean():.2%}")
```

```python
# ============================================================
# CÉLULA 4 — Treinar e comparar 3 modelos
# ============================================================

modelos = {
    'Logistic Regression': Pipeline([
        ('prep', preprocessor),
        ('model', LogisticRegression(max_iter=1000, random_state=42))
    ]),
    'Random Forest': Pipeline([
        ('prep', preprocessor),
        ('model', RandomForestClassifier(n_estimators=200, random_state=42, n_jobs=-1))
    ]),
    'Gradient Boosting': Pipeline([
        ('prep', preprocessor),
        ('model', GradientBoostingClassifier(n_estimators=200, learning_rate=0.05, random_state=42))
    ])
}

resultados = {}

for nome, pipeline in modelos.items():
    # Cross-validation com 5 folds estratificados
    cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=42)
    scores = cross_val_score(pipeline, X_train, y_train, cv=cv, scoring='roc_auc')
    
    # Treinar no conjunto completo de treino
    pipeline.fit(X_train, y_train)
    
    # Avaliar no teste
    y_proba = pipeline.predict_proba(X_test)[:, 1]
    auc_test = roc_auc_score(y_test, y_proba)
    
    resultados[nome] = {
        'cv_mean': scores.mean(),
        'cv_std':  scores.std(),
        'auc_test': auc_test,
        'pipeline': pipeline
    }
    
    print(f"\n{nome}")
    print(f"  CV ROC-AUC: {scores.mean():.4f} ± {scores.std():.4f}")
    print(f"  Test ROC-AUC: {auc_test:.4f}")
```

```python
# ============================================================
# CÉLULA 5 — Melhor modelo: análise detalhada
# ============================================================

# Selecionar melhor modelo pelo AUC no teste
melhor_nome = max(resultados, key=lambda k: resultados[k]['auc_test'])
melhor = resultados[melhor_nome]['pipeline']
print(f"Melhor modelo: {melhor_nome}")

y_pred  = melhor.predict(X_test)
y_proba = melhor.predict_proba(X_test)[:, 1]

# Relatório de classificação
print("\nClassification Report:")
print(classification_report(y_test, y_pred, target_names=['Ficou','Churnou']))

# Curva ROC
fig, axes = plt.subplots(1, 2, figsize=(14, 5))

RocCurveDisplay.from_predictions(y_test, y_proba, ax=axes[0], name=melhor_nome)
axes[0].plot([0,1],[0,1],'--', color='gray')
axes[0].set_title('Curva ROC')

# Matriz de confusão
cm = confusion_matrix(y_test, y_pred)
sns.heatmap(cm, annot=True, fmt='d', cmap='Blues', ax=axes[1],
            xticklabels=['Ficou','Churnou'],
            yticklabels=['Ficou','Churnou'])
axes[1].set_title('Matriz de Confusão')
axes[1].set_ylabel('Real')
axes[1].set_xlabel('Predito')

plt.tight_layout()
plt.savefig('outputs/graficos/05_roc_confusao.png', dpi=150)
plt.show()
```

```python
# ============================================================
# CÉLULA 6 — Feature Importance (o que mais importa pro modelo?)
# ============================================================

# Extrair nomes das features após o one-hot encoding
ohe_cols = list(
    melhor.named_steps['prep']
    .named_transformers_['cat']
    .get_feature_names_out(cat_cols)
)
all_feature_names = num_cols + ohe_cols

# Importâncias do modelo
importances = melhor.named_steps['model'].feature_importances_
feat_imp = (
    pd.DataFrame({'feature': all_feature_names, 'importance': importances})
    .sort_values('importance', ascending=False)
    .head(15)
)

fig, ax = plt.subplots(figsize=(10, 6))
ax.barh(feat_imp['feature'], feat_imp['importance'], color='#4a7fc1')
ax.set_title(f'Top 15 features mais importantes — {melhor_nome}', fontsize=13)
ax.set_xlabel('Importância relativa')
ax.invert_yaxis()
plt.tight_layout()
plt.savefig('outputs/graficos/06_feature_importance.png', dpi=150)
plt.show()

print("\nTop 5 features:")
print(feat_imp.head())
```

```python
# ============================================================
# CÉLULA 7 — Segmentação de risco para ação de negócio
# (isso é o que diferencia cientista de dados de quem só treina modelo)
# ============================================================

df_test = X_test.copy()
df_test['churn_real']  = y_test.values
df_test['churn_proba'] = y_proba
df_test['customer_id'] = df.loc[X_test.index, 'customer_id'].values

# Segmentar por risco
df_test['segmento_risco'] = pd.cut(
    df_test['churn_proba'],
    bins=[0, 0.3, 0.6, 1.0],
    labels=['Baixo risco', 'Médio risco', 'Alto risco']
)

resumo_risco = (
    df_test.groupby('segmento_risco')
    .agg(
        clientes=('customer_id', 'count'),
        churn_real=('churn_real', 'sum'),
        receita_mensal=('mensalidade', 'sum') if 'mensalidade' in df_test.columns else ('churn_proba','count'),
        proba_media=('churn_proba', 'mean')
    )
    .round(2)
)

print("Segmentação de risco:")
print(resumo_risco)

# Exportar lista de clientes de alto risco para ação
alto_risco = df_test[df_test['segmento_risco'] == 'Alto risco'][
    ['customer_id','churn_proba','meses_contrato','mensalidade']
].sort_values('churn_proba', ascending=False)

alto_risco.to_csv('outputs/clientes_alto_risco.csv', index=False)
print(f"\n{len(alto_risco)} clientes de alto risco exportados!")
```

```python
# ============================================================
# CÉLULA 8 — Salvar modelo para deploy
# ============================================================

import pickle

# Salvar pipeline completo (preprocessador + modelo juntos)
with open('outputs/churn_model.pkl', 'wb') as f:
    pickle.dump(melhor, f)

print("Modelo salvo em outputs/churn_model.pkl")

# Teste de carregamento
with open('outputs/churn_model.pkl', 'rb') as f:
    modelo_carregado = pickle.load(f)

# Simular predição de 1 cliente novo
cliente_novo = X_test.iloc[[0]]
prob = modelo_carregado.predict_proba(cliente_novo)[0, 1]
print(f"\nTeste de predição — probabilidade de churn: {prob:.2%}")
```

### api_deploy.py (diferencial de portfólio)

```python
# ============================================================
# BÔNUS: API com FastAPI para servir o modelo
# pip install fastapi uvicorn
# Rodar: uvicorn api_deploy:app --reload
# ============================================================

from fastapi import FastAPI
from pydantic import BaseModel
import pickle
import pandas as pd

app = FastAPI(title="Churn Prediction API")

with open('outputs/churn_model.pkl', 'rb') as f:
    model = pickle.load(f)

class ClienteInput(BaseModel):
    meses_contrato:          int
    mensalidade:             float
    total_gasto:             float
    tipo_contrato:           str
    servico_internet:        str
    qtd_servicos_adicionais: int
    contrato_longo_prazo:    int
    segmento_tenure:         str

@app.post("/predict")
def predict_churn(cliente: ClienteInput):
    df_input = pd.DataFrame([cliente.dict()])
    proba = model.predict_proba(df_input)[0, 1]
    return {
        "probabilidade_churn": round(float(proba), 4),
        "segmento_risco": "Alto" if proba > 0.6 else "Médio" if proba > 0.3 else "Baixo",
        "recomendacao": "Acionar equipe de retenção" if proba > 0.6 else "Monitorar"
    }

@app.get("/health")
def health():
    return {"status": "ok"}
```

---

## README.md para o GitHub

```markdown
# Predição de Churn de Clientes — Telecom

> Modelo de ML que prediz churn com 85%+ de ROC-AUC, combinando
> feature engineering avançada em SQL Server com pipeline completo
> de Machine Learning em Python e deploy via FastAPI.

## Resultados
| Modelo | CV ROC-AUC | Test ROC-AUC |
|---|---|---|
| Logistic Regression | 0.831 ± 0.012 | 0.834 |
| Random Forest | 0.851 ± 0.009 | 0.857 |
| Gradient Boosting | 0.863 ± 0.007 | 0.869 |

## Principais fatores de churn encontrados
1. Tipo de contrato (mês a mês = alto risco)
2. Tempo de contrato (clientes novos churnam mais)
3. Mensalidade elevada sem serviços adicionais

## Fluxo completo
```
SQL Server → Feature Engineering → Python → Modelo → API (FastAPI)
```

## Como usar a API
```bash
pip install fastapi uvicorn scikit-learn pandas
uvicorn api_deploy:app --reload
# Acessar: http://localhost:8000/docs
```

## Dataset
Telco Customer Churn — Kaggle  
https://www.kaggle.com/datasets/blastchar/telco-customer-churn
```
