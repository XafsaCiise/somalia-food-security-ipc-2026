# Somalia Food Security Crisis — IPC 2026 Analysis

**Tools:** PostgreSQL · Power BI · DAX · Excel  
**Data Source:** WFP / FSNAU IPC Somalia 2026  
**Author:** Hafsa Isa  

---
## Somali Summary 

Mashruucani wuxuu baarayaa xaaladda amniga cuntada ee Soomaaliya sanadka 2026,
xogta waxaan ka keenay WFP iyo IPC. Xogta asalka ah waxaa ku jiray khaladaad
keenaya in isku darka  tira koobku dhawr jeer labo jibbaarmo . Waxaan nadiifiyay xogta anigoo adeegsanaya
"PostgreSQL", ka dibna ku dhisay dashboard Power BI ah oo muujinaya xaaladda 107(zone) aag ee
degmo walba. Aag kasta wuxuu leeyahay ilaa 7 ROW oo ku saabsan heerarka IPC — Phase 1
ilaa Phase 5 — sidaas darteed 749 saf(ROW) ayaa xogta ku jira oo idil.

**Natiijooyink muhiimka ah ee aan heelay :**
- 1 ka mid ah 3-dii Soomaali ah  ayaa ku jira xaalad amni cunto oo khatar ah ama ka sii dareysa.
- 6 milyan oo qof ayaa ku jira Phase 3 iyo wixii ka sareeya.
- 1.9 milyan ayaa ku jira xaalad degdega oo in cunto lala gaaro ay tahay (Emergency/Famine)
- Degmada ugu daran, xaga tirooyinka: Banadir Urban IDPs, Muqdisho — 166,391 kun oo qof
- Degmada ugu daran , xaga boqolleyda : Sanaag iyo Sool — 65% dadkooda ayaa xaalad
  khatar ah ku jira





## Project Overview

This project analyses the WFP Somalia IPC 2026 food security dataset to identify where food insecurity is most severe across Somalia's 107 livelihood zones. The raw data contained structural issues causing double counting in aggregations. I cleaned the dataset using PostgreSQL, validated findings against SQL analytical queries, and rebuilt an interactive Power BI dashboard from the clean data.

**The central question:** Where are Somalis most at risk, and how severe is the crisis?

---

## Key Findings

| Finding | Value |
|---------|-------|
| Total population assessed | 19 million |
| People in Crisis or worse (Phase 3+) | 6 million (31%) |
| People in Emergency or Famine (Phase 4+5) | 1.9 million (10%) |
| Worst affected area by absolute numbers | Banadir Urban IDPs, Mogadishu — 166,391 |
| Worst affected area by proportion | NW Northern Inland Pastoral (Sanaag & Sool) — 65% in crisis |
| Areas with 65% population in crisis | 3 areas simultaneously |

### So What?

Nearly 1 in 3 Somalis faces Crisis or worse food insecurity. Mogadishu's IDP population and the Sanaag and Sool pastoral zones are effectively tied as Somalia's most crisis-affected areas with over 165,000 people each in Emergency or Famine conditions — but they represent completely different crisis drivers. Urban displacement versus pastoral livelihood collapse require fundamentally different humanitarian responses.

Three areas have 65% of their entire population in Crisis or worse. These small pastoral communities face proportionally identical devastation to large urban IDP camps but receive less attention because their absolute numbers are smaller. This finding is invisible without the concentration index analysis.

---

## Data Issues Identified and Fixed

| Issue | Impact | Fix Applied |
|-------|--------|-------------|
| Each area repeated across 7 phase rows | SUM of population returns 7x actual value | Filtered measures to Phase = ALL for totals |
| Phase "3+" is a combined figure | Adding 3+ and 3,4,5 together double counts | Used 3+ row directly for crisis totals |
| Population stored as text with commas | Cannot aggregate numerically | Cast to INTEGER using REGEXP_REPLACE |
| Phase values needed standardisation | Inconsistent case causes DAX mismatches | Applied UPPER(TRIM()) in clean view |
| No phase sort order | Alphabetical sort shows Phase 3 before Phase 1 | Added phase_sort column in Power Query |

---

## Data Structure

The dataset uses a long format where each row represents one livelihood zone × one IPC phase × one time period.

```
Area               | Phase | Population Affected | Validity Period
-------------------|-------|--------------------|-----------------
Banadir Urban IDPs | 1     | 12,450             | Current
Banadir Urban IDPs | 2     | 38,920             | Current
Banadir Urban IDPs | 3     | 55,210             | Current
Banadir Urban IDPs | 3+    | 166,391            | Current  ← combined Phase 3,4,5
Banadir Urban IDPs | 4     | 89,340             | Current
Banadir Urban IDPs | 5     | 11,230             | Current
Banadir Urban IDPs | all   | 207,151            | Current  ← true total
```

**107 areas × 7 phase rows = 749 total rows**

---

## SQL Cleaning Process

### Step 1 — Data Profiling
```sql
-- Confirmed 749 rows, 107 unique areas, zero nulls in critical columns
SELECT COUNT(*) AS total_rows FROM ipc_som_raw;
-- Result: 749

SELECT COUNT(DISTINCT area) AS unique_areas FROM ipc_som_raw;
-- Result: 107

-- Confirmed all areas have an 'all' row for correct totals
SELECT COUNT(*) AS areas_with_all_row
FROM ipc_som_raw
WHERE LOWER(TRIM(phase)) = 'all';
-- Result: 107 ✓
```

### Step 2 — Clean View with Derived Columns
```sql
CREATE VIEW ipc_som_clean AS
SELECT
    TRIM(area)                    AS area,
    UPPER(TRIM(phase))            AS phase,
    CASE UPPER(TRIM(phase))
        WHEN '1'   THEN 'Phase 1 - Minimal'
        WHEN '2'   THEN 'Phase 2 - Stressed'
        WHEN '3'   THEN 'Phase 3 - Crisis'
        WHEN '3+'  THEN 'Phase 3+ - Crisis or Worse'
        WHEN '4'   THEN 'Phase 4 - Emergency'
        WHEN '5'   THEN 'Phase 5 - Famine'
        WHEN 'ALL' THEN 'All Phases - Total'
    END                           AS phase_label,
    CASE UPPER(TRIM(phase))
        WHEN '4'  THEN 'Emergency or Famine'
        WHEN '5'  THEN 'Emergency or Famine'
        WHEN '3+' THEN 'Crisis or Worse'
        WHEN '3'  THEN 'Crisis'
        WHEN '2'  THEN 'Stressed'
        WHEN '1'  THEN 'Minimal'
        ELSE 'Total'
    END                           AS severity_category,
    NULLIF(REGEXP_REPLACE(
        TRIM(population_affected), '[^0-9]', '', 'g'
    ), '')::INTEGER               AS population_affected
FROM ipc_som_raw
WHERE area IS NOT NULL;
```

### Step 3 — Analytical Queries

**National severity distribution:**
```sql
SELECT severity_category,
       SUM(population_affected) AS total_population,
       ROUND(SUM(population_affected) * 100.0 /
             SUM(SUM(population_affected)) OVER (), 1) AS pct_of_total
FROM ipc_som_clean
WHERE UPPER(phase) NOT IN ('ALL', '3+')
GROUP BY severity_category
ORDER BY total_population DESC;
```

Results:
```
Stressed          | 7,725,794 | 39.7%
Minimal           | 5,686,108 | 29.2%
Crisis            | 4,154,332 | 21.4%
Emergency/Famine  | 1,875,950 |  9.6%
```

**Crisis concentration index — hidden crises in smaller areas:**
```sql
SELECT area,
       MAX(CASE WHEN UPPER(phase) = 'ALL' THEN population_affected END) AS total_pop,
       MAX(CASE WHEN UPPER(phase) = '3+'  THEN population_affected END) AS crisis_or_worse,
       ROUND(
           MAX(CASE WHEN UPPER(phase) = '3+' THEN population_affected END) * 100.0 /
           NULLIF(MAX(CASE WHEN UPPER(phase) = 'ALL' THEN population_affected END), 0), 1
       ) AS pct_in_crisis
FROM ipc_som_clean
GROUP BY area
ORDER BY pct_in_crisis DESC
LIMIT 10;
```

Top result: NW Northern Inland Pastoral (Sanaag and Sool) — **65% of population in Crisis or worse**

---

## Power BI Dashboard

### DAX Measures
```
Total Population =
CALCULATE(
    SUM('somalia_ipc_clean_2026'[population_affected]),
    REMOVEFILTERS('somalia_ipc_clean_2026'[phase]),
    REMOVEFILTERS('somalia_ipc_clean_2026'[phase_label]),
    REMOVEFILTERS('somalia_ipc_clean_2026'[severity_category]),
    'somalia_ipc_clean_2026'[phase] = "ALL"
)

People in Crisis =
CALCULATE(
    SUM('somalia_ipc_clean_2026'[population_affected]),
    REMOVEFILTERS('somalia_ipc_clean_2026'[phase]),
    REMOVEFILTERS('somalia_ipc_clean_2026'[phase_label]),
    REMOVEFILTERS('somalia_ipc_clean_2026'[severity_category]),
    'somalia_ipc_clean_2026'[phase] = "3+"
)

Emergency Famine =
CALCULATE(
    SUM('somalia_ipc_clean_2026'[population_affected]),
    REMOVEFILTERS('somalia_ipc_clean_2026'[phase]),
    REMOVEFILTERS('somalia_ipc_clean_2026'[phase_label]),
    REMOVEFILTERS('somalia_ipc_clean_2026'[severity_category]),
    'somalia_ipc_clean_2026'[phase] IN {"4", "5"}
)
```

### Dashboard Features
- 3 KPI cards showing national totals — Total Population, People in Crisis, Emergency or Famine
- Bar chart — Top affected areas by Emergency or Famine population (Phase 4+5)
- Donut chart — Severity distribution using official IPC color scheme
- Filled map — Somalia geographic context
- Area slicer — drill into specific livelihood zones
- Detail table — phase breakdown per area with phase labels and severity categories

### IPC Color Scheme Applied
| Phase | Color |
|-------|-------|
| Phase 1 Minimal | #CDFACD |
| Phase 2 Stressed | #FAE61E |
| Phase 3 Crisis | #E67800 |
| Phase 4 Emergency | #C80000 |
| Phase 5 Famine | #640000 |

---

## Data Limitations

- Dataset contains Current period only — projection data not available in this extract
- Livelihood zone names are too specific for standard geocoding — map uses country level only
- Phase 3+ rows are combined figures and cannot be disaggregated further
- Total country population column in raw data contained district level figures not national figures — excluded from analysis

---

## Repository Structure

```
somalia-food-security-ipc-2026/
│
├── README.md                          ← this file
├── somalia_ipc_cleaning.sql           ← full PostgreSQL cleaning script
├── somalia_ipc_clean_2026.csv         ← cleaned dataset exported from SQL
├── screenshots/
│   ├── dashboard_overview.png         ← main dashboard view
│   ├── dashboard_area_drill.png       ← area slicer in action
│   ├── sql_profiling_results.png      ← data quality check results
│   └── sql_analytical_queries.png     ← key findings from SQL
```

---

## How to Reproduce

1. Download raw dataset from WFP/FSNAU IPC Somalia 2026
2. Install PostgreSQL and pgAdmin
3. Create database `somalia_food_security`
4. Run `somalia_ipc_cleaning.sql` step by step
5. Export clean view to CSV
6. Open Power BI Desktop
7. Load `somalia_ipc_clean_2026.csv`
8. Create DAX measures as documented above
9. Build visuals following dashboard structure





 ## Sida u samayn kartid project-gaan

1. Soo degso xogta asalka ah ee WFP/FSNAU IPC Somalia 2026 
2. kusoo daji PostgreSQL iyo pgAdmin kombiyuutarkaaga
3. Samee database cusub oo magaceedu yahay `somalia_food_security`
4. Fur `somalia_ipc_cleaning.sql` oo raac tallaabooyinkaan
5. Xogta aad ku nadiifisay postgreSQL ku dagso qaab CSV file ahaan
6. Fur Power BI Desktop [soo dagso hadii uusan kugu jirin]
7. kadib tag Power BI oo  fur file-ka ad so nadiifisay`somalia_ipc_clean_2026.csv` adigoo tagaya "HOME"-"GET DATA"
8. raac oo samee DAX sida kor lagu sharaxay ↑ ### Dashboard Features ↑
   
---

## About

Built by Hafsa Isa as part of a data analyst portfolio project.  
Combining SQL data cleaning with Power BI visualisation on real humanitarian data.

**Connect:** [LinkedIn](https://www.linkedin.com/in/hafsa-isse)

---

*Data source: WFP Somalia IPC 2026 — downloaded from humanitarian open data portal*  
*This project is for portfolio and educational purposes*
