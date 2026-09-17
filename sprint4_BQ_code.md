


# Exercici 1: Consulta sobre Taula no Optimitzada (Diagnòstic)
```text
El Country Manager d'Alemanya necessita revisar urgentment les transaccions del dia 12 de març de 2022.
🧩 Tasca:

    » 1. Escriu la consulta que uneix (JOIN) transaccions i companyies.
    » 2. Filtra els resultats per la data indicada i el país "Germany".
    » 3. Sense executar la consulta, realitza un "Dry Run" (auditoria de costos).

    👀 Observació: Fixa't que BigQuery llegeix gairebé tota la taula tot i demanar només un dia (Full Table Scan).

```

```sql
SELECT * 
FROM `sprint3_silver.transactions_clean` as t
JOIN  `sprint3_silver.companies_clean` as c
ON t.company_id = c.company_id
WHERE t.timestamp = '2022-03-12'
  AND country = 'Germany';
--        Observació: Fixa't que BigQuery llegeix gairebé tota la taula tot i demanar només un dia (Full Table Scan).
```




# Exercici 2: Re-arquitectura i Optimització de l'Emmagatzematge (Partition & Cluster)
```text
Pas 1: Generació de Dades Recents (Mocking Data) 
Crea una taula intermèdia anomenada sprint3_silver.transactions_recent a partir de la taula sprint3_silver.transactions_clean. El teu objectiu és mantenir totes les columnes, però substituir el timestamp original per un de nou, generat aleatòriament perquè caigui dins dels últims 50 dies. 
```

```sql
CREATE OR REPLACE TABLE `sprint3_silver.transactions_recent`
AS  SELECT * EXCEPT(timestamp),
TIMESTAMP_SUB(
    CURRENT_TIMESTAMP(),
    INTERVAL CAST(RAND() * 50 AS INT64) DAY
    -- INTERVAL randomINT(0-50) DAY
) as timestamp
FROM `sprint3_silver.transactions_clean`
```




# Pas 2: Creació de la Taula Optimitzada (Partitioning & Clustering) 
CREATE OR REPLACE TABLE dataset.tabla
PARTITION BY DATE(nombre_columna_fecha)
AS
SELECT ...
`
```text
Ara, crea la teva taula definitiva sprint3_gold.fact_transactions_optimized a partir de les dades recents que acabes de generar a transactions_recent. Has de construir la sentència DDL per configurar la taula amb les següents estratègies físiques d'emmagatzematge: 
    • » Particionament (Partitioning): Divideix la taula per la data del camp DATE(timestamp). Això permetrà que les consultes que filtrin per dia (WHERE date = ...) només llegeixin la partició necessària. 
    • » Clustering: Ordena les dades dins de cada partició per business_id. Això accelerarà dràsticament els filtres per companyia i els encreuaments (JOINs) amb la dimensió d'empreses. 

```

```sql
CREATE OR REPLACE TABLE `sprint3_gold.fact_transactions_optimized`
PARTITION BY DATE(timestamp)
CLUSTER BY company_id
AS
SELECT * FROM `sprint3_silver.transactions_recent`
```


# Exercici 3: La Prova del Cotó (Benchmark)
```text
L'objectiu és clar i directe: aplicar exactament la mateixa consulta a dues taules diferents i comparar-ne el cost computacional.
Construeix una consulta SQL que
seleccioni totes les columnes (SELECT *) i filtri les dades dels últims 30 dies.
```

```sql
-- no optimizada
SELECT * FROM `sprint3_silver.transactions_recent`
WHERE timestamp BETWEEN 
  TIMESTAMP_SUB(CURRENT_TIMESTAMP(),INTERVAL 30 DAY) 
    AND 
      CURRENT_TIMESTAMP()
;

-- OPTIMIZADA
SELECT * FROM `sprint3_gold.fact_transactions_optimized`
WHERE timestamp BETWEEN 
  TIMESTAMP_SUB(CURRENT_TIMESTAMP(),INTERVAL 30 DAY) 
    AND 
      CURRENT_TIMESTAMP()
;
-- es el 60% de sin optimizar, te ahorras un 40%
```


# 
```text
Exercici 4: Smart Caching (Vistes Materialitzades)
Escenari:
El Director General té un quadre de comandament que mostra les "Vendes Totals per Dia". Ell (i 50 managers més) refresquen aquest gràfic constantment.
🧩 Tasca:
    • » Crea una Vista Materialitzada anomenada sprint3_gold.mv_daily_sales que mostri les Vendes Totals per Dia. 
```

```sql
CREATE MATERIALIZED VIEW IF NOT EXISTS `sprint3_gold.mv_daily_sales`
AS
SELECT DATE(timestamp) as day, SUM(amount) as total_sales
FROM `sprint3_gold.fact_transactions_optimized`
WHERE declined = 0
GROUP BY day;
```


# Nivell 2: SQL Analític Avançat
```text 
Exercici 1: Perfilat de Clients VIP (Mètriques Agregades amb CTEs)
Escenari:
Definim "VIP" com aquells amb una despesa acumulada superior a 500€. Necessiten un informe que, per a cada VIP, mostri el seu nom, contacte i el seu patró de compra: quantes vegades ha comprat, quant gasta de mitjana i quina va ser la seva compra rècord.

```

```sql
WITH VIP_Stats AS (
SELECT user_id,
SUM(amount) as total_gastat, 
COUNT(*) as num_compres,
ROUND(AVG(amount), 2) as tiquet_mig,
MAX(amount) as max_compra
FROM
`sprint3_silver.transactions_clean` 
WHERE declined = 0
GROUP BY user_id
HAVING total_gastat > 500
)

SELECT user_id, uc.name as nom, uc.surname as cognom, uc.email, num_compres, tiquet_mig, max_compra, total_gastat
FROM VIP_Stats
JOIN `sprint3_silver.users_combined` AS uc
ON VIP_Stats.user_id = uc.user_id
ORDER BY total_gastat DESC
;

```


# Exercici 2: Anàlisi de Tendències (Window Functions sobre Vistes)
```text
Escenari:
La Direcció Financera vol monitoritzar la "velocitat de vendes" diària. Necessiten un informe que compari el rendiment de cada dia contra el dia anterior per detectar caigudes brusques o pics de creixement (Day-over-Day Growth).
```

```sql
WITH tendencia_ventas AS (
  SELECT
    day,
    total_sales,
    LAG(total_sales) OVER (ORDER BY day) AS sales_yesterday -- la CTE es para no repetir tres veces LAG...
  FROM `sprint3_gold.mv_daily_sales`
)

SELECT
  day AS Data,
  total_sales AS Vendes_Avui,
  sales_yesterday AS Vendes_Ahir,
  ROUND(
    ((total_sales - sales_yesterday) / sales_yesterday) * 100,
    2
  ) AS Diff_Percentual
FROM tendencia_ventas
ORDER BY day;
```


# Exercici 4: Fidelització i Valor del Client (Filtratge Avançat)
```text
    • » 1.Dades d'usuari (user_id, nom_complet, email). 
    • » 2.La data i l'import exacte de la 3a compra. 
    • » 3.Mitjana de les 3 primeres: La mitjana de despesa de les seves transaccions 1, 2 i 3. 
```

```sql
-- CTE 1 -> numerar compras
WITH TC1 AS (
  SELECT ROW_NUMBER() OVER (PARTITION BY tc.user_id ORDER BY tc.timestamp) AS rn,
  tc.user_id,  uc.name, uc.surname , uc.email, tc.amount, tc.timestamp
  FROM `sprint3_silver.transactions_clean` AS tc
  JOIN `sprint3_silver.users_combined` AS uc
  ON uc.user_id = tc.user_id
  WHERE declined = 0
  QUALIFY rn <= 3
)

-- CTE 2 -> media de las primeras 3
, TC2 AS (
SELECT user_id, round(AVG(amount), 2) AS avg
FROM TC1
GROUP BY user_id
)

-- SELECT final -> juntar todo
SELECT TC1.user_id, name, surname ,email, amount AS importe_3a_compra, 
DATE(timestamp) AS fecha_3a_compra, 
TC2.avg AS avg_first_3
FROM TC1
JOIN TC2 ON TC1.user_id = TC2.user_id
WHERE rn = 3
;
```


# Nivell 3: Analytics Engineering (Arrays & Automatització)
## Exercici 1: Desanidament i Aplanament de Dades (Unnesting)
```text
Crea la taula dim_transactions_flat desnormalitzant la informació. Has d'"explotar" l'array de productes i creuar-lo amb el catàleg mestre per obtenir els noms i preus individuals.
```

```sql
CREATE OR REPLACE TABLE `sprint3_gold.dim_transactions_flat`
AS
SELECT transaction_id, DATE(timestamp) AS timestamp, amount AS total_ticket_GLOBAL, product_id, pr.name AS product_name, pr.price AS product_price
FROM `sprint3_silver.transactions_clean` AS tr
CROSS JOIN UNNEST(tr.product_ids) AS product_id
JOIN `sprint3_silver.products_clean` AS pr
ON product_id = pr.product_id
WHERE tr.declined = 0
ORDER BY transaction_id;
```


## Exercici 2: El Rànquing de Vendes (Agregació Simple)
```text
Genera el Top 5 de productes més venuts en la història de la companyia.
» 1. User Defined Functions (UDF): Crea una funció SQL persistent anomenada calculate_tax(amount) que rebi un valor numèric i retorni el resultat aplicant el 21% d'impost.
```

```sql
CREATE OR REPLACE FUNCTION sprint3_gold.calculate_tax(product_price FLOAT64)
RETURNS FLOAT64
AS(
    (product_price * 0.21) + product_price
);
```

# 
```text
    • » 2. Integració i Orquestració: 
        ◦ Modifica el codi de creació de la taula (de l'Exercici 1) perquè utilitzi la teva nova funció calculate_tax i generi una columna nova: product_price_tax_inc. 
```

```sql
CREATE OR REPLACE TABLE `sprint3_gold.dim_transactions_flat`
AS
SELECT transaction_id, DATE(timestamp) AS timestamp, amount AS total_ticket_GLOBAL, product_id, pr.name AS product_name, pr.price AS product_price,
sprint3_gold.calculate_tax(pr.price) AS product_price_tax_inc
FROM `sprint3_silver.transactions_clean` AS tr
CROSS JOIN UNNEST(tr.product_ids) AS product_id
JOIN `sprint3_silver.products_clean` AS pr
ON product_id = pr.product_id
WHERE tr.declined = 0
ORDER BY transaction_id;
```


# 
```text

```

```sql

```


# 
```text

```

```sql

```


# 
```text

```

```sql

```


# 
```text

```

```sql

```


# 
```text

```

```sql

```


# 
```text

```

```sql

```


# 
```text

```

```sql

```


# 
```text

```

```sql

```


# 
```text

```

```sql

```


# 
```text

```

```sql

```


# 
```text

```

```sql

```


# 
```text

```

```sql

```


# 
```text

```

```sql

```





