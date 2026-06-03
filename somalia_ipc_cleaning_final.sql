-- ============================================================
-- WFP Somalia IPC 2026 — PostgreSQL Cleaning & Analysis Script
-- Author: Hafsa Isa
-- Dataset: WFP / FSNAU IPC Somalia 2026
-- Database: somalia_food_security
-- Purpose: Clean raw IPC data, remove double counting,
--          add derived columns, extract analytical insights
-- ============================================================


-- ============================================================
-- STEP 1: CREATE RAW TABLE
-- Import all columns as TEXT first to avoid import errors.
-- Data types are cast correctly in the clean view (Step 3).
-- Column order matches the source CSV exactly.
-- ============================================================

DROP TABLE IF EXISTS ipc_som_raw;

CREATE TABLE ipc_som_raw (
    date_of_analysis        TEXT,
    country                 TEXT,
    total_country_pop       TEXT,
    level_1                 TEXT,
    area                    TEXT,
    validity_period         TEXT,
    date_from               TEXT,
    date_to                 TEXT,
    phase                   TEXT,
    population_affected     TEXT,
    pct_total_pop           TEXT
);

-- Import CSV via pgAdmin:
-- Right click ipc_som_raw > Import/Export Data
-- Format: CSV | Header: ON | Delimiter: , | Encoding: UTF8


-- ============================================================
-- STEP 2: DATA PROFILING
-- Always inspect data before cleaning.
-- These queries confirm structure and identify issues.
-- ============================================================

-- Total row count
-- Expected: 749 (107 areas x 7 phases)
SELECT COUNT(*) AS total_rows
FROM ipc_som_raw;

-- Unique phase values
-- Expected: 1, 2, 3, 3+, 4, 5, all
SELECT DISTINCT phase, COUNT(*) AS row_count
FROM ipc_som_raw
GROUP BY phase
ORDER BY phase;

-- Unique validity periods
-- Expected: current only in this extract
SELECT DISTINCT validity_period, COUNT(*) AS row_count
FROM ipc_som_raw
GROUP BY validity_period;

-- Count of unique areas
-- Expected: 107 livelihood zones
SELECT COUNT(DISTINCT area) AS unique_areas
FROM ipc_som_raw;

-- Confirm every area has an 'all' row for accurate totals
-- Result must match unique_areas count above
SELECT COUNT(*) AS areas_with_all_row
FROM ipc_som_raw
WHERE LOWER(TRIM(phase)) = 'all';


-- ============================================================
-- STEP 3: DATA QUALITY CHECKS
-- Identify nulls, whitespace, and missing phase rows
-- before any cleaning is applied.
-- ============================================================

-- Check for nulls in critical columns
-- All results should be 0
SELECT
    COUNT(*) FILTER (WHERE area IS NULL)                AS null_area,
    COUNT(*) FILTER (WHERE phase IS NULL)               AS null_phase,
    COUNT(*) FILTER (WHERE population_affected IS NULL) AS null_population,
    COUNT(*) FILTER (WHERE validity_period IS NULL)     AS null_validity
FROM ipc_som_raw;

-- Check for whitespace or inconsistencies in phase values
-- All rows should show no_leading_trailing_spaces = true
SELECT DISTINCT
    phase,
    LENGTH(phase)              AS char_length,
    phase = TRIM(phase)        AS no_leading_trailing_spaces
FROM ipc_som_raw
ORDER BY phase;

-- Identify areas missing Phase 4 or 5 rows
-- Empty result means all areas have emergency/famine data
SELECT DISTINCT area
FROM ipc_som_raw
WHERE area NOT IN (
    SELECT DISTINCT area
    FROM ipc_som_raw
    WHERE phase IN ('4', '5')
)
ORDER BY area;


-- ============================================================
-- STEP 4: CREATE CLEAN VIEW
-- A VIEW reads fresh from raw table on every query.
-- Source data is never altered — best practice.
-- Derived columns added: phase_label, severity_category.
-- Data types corrected: population to INTEGER, pct to NUMERIC.
-- ============================================================

DROP VIEW IF EXISTS ipc_som_clean;

CREATE VIEW ipc_som_clean AS
SELECT
    -- Core identifiers cleaned
    TRIM(area)                          AS area,
    TRIM(country)                       AS country,

    -- Phase standardised to uppercase
    UPPER(TRIM(phase))                  AS phase,

    -- Human readable phase label
    CASE UPPER(TRIM(phase))
        WHEN '1'   THEN 'Phase 1 - Minimal'
        WHEN '2'   THEN 'Phase 2 - Stressed'
        WHEN '3'   THEN 'Phase 3 - Crisis'
        WHEN '3+'  THEN 'Phase 3+ - Crisis or Worse'
        WHEN '4'   THEN 'Phase 4 - Emergency'
        WHEN '5'   THEN 'Phase 5 - Famine'
        WHEN 'ALL' THEN 'All Phases - Total'
        ELSE 'Unknown'
    END                                 AS phase_label,

    -- Severity category for dashboard filtering
    CASE UPPER(TRIM(phase))
        WHEN '4'  THEN 'Emergency or Famine'
        WHEN '5'  THEN 'Emergency or Famine'
        WHEN '3+' THEN 'Crisis or Worse'
        WHEN '3'  THEN 'Crisis'
        WHEN '2'  THEN 'Stressed'
        WHEN '1'  THEN 'Minimal'
        ELSE 'Total'
    END                                 AS severity_category,

    -- Validity period standardised
    INITCAP(TRIM(validity_period))      AS validity_period,

    -- Population cast from text to integer
    NULLIF(REGEXP_REPLACE(
        TRIM(population_affected), '[^0-9]', '', 'g'
    ), '')::INTEGER                     AS population_affected,

    -- Percentage cast from text to decimal
    NULLIF(TRIM(pct_total_pop), '')::NUMERIC(8,4)
                                        AS pct_total_population

FROM ipc_som_raw
WHERE
    area IS NOT NULL
    AND TRIM(area) != '';


-- ============================================================
-- STEP 5: ANALYTICAL QUERIES
-- Each query answers a specific humanitarian question.
-- Results validated against Power BI dashboard figures.
-- ============================================================

-- QUERY 1: National severity distribution
-- Question: How is Somalia's population distributed
--           across food security phases?
-- Note: Excludes ALL and 3+ rows to avoid double counting
SELECT
    severity_category,
    SUM(population_affected)       AS total_population,
    ROUND(
        SUM(population_affected) * 100.0 /
        SUM(SUM(population_affected)) OVER (), 1
    )                              AS pct_of_total
FROM ipc_som_clean
WHERE UPPER(phase) NOT IN ('ALL', '3+')
GROUP BY severity_category
ORDER BY total_population DESC;

-- Results:
-- Stressed          | 7,725,794 | 39.7%
-- Minimal           | 5,686,108 | 29.2%
-- Crisis            | 4,154,332 | 21.4%
-- Emergency/Famine  | 1,875,950 |  9.6%


-- QUERY 2: Top 10 worst affected areas by Emergency/Famine population
-- Question: Which areas have the most people in Phase 4 or 5?
-- Finding: Mogadishu IDPs and Sanaag/Sool are effectively tied
SELECT
    area,
    SUM(population_affected)       AS emergency_famine_pop
FROM ipc_som_clean
WHERE UPPER(phase) IN ('4', '5')
GROUP BY area
ORDER BY emergency_famine_pop DESC
LIMIT 10;

-- Results:
-- Banadir Urban IDPs (Mogadishu)              | 166,391
-- NW Northern Inland Pastoral (Sanaag & Sool) | 165,601
-- Bay Urban IDPs (Baydhaba)                   | 154,587


-- QUERY 3: Crisis concentration index
-- Question: Which areas have the highest PROPORTION
--           of population in Crisis or worse?
-- Finding: 3 areas have 65% of population in crisis
--          Small pastoral zones hidden by absolute number rankings
SELECT
    area,
    MAX(CASE WHEN UPPER(phase) = 'ALL'
        THEN population_affected END)  AS total_pop,
    MAX(CASE WHEN UPPER(phase) = '3+'
        THEN population_affected END)  AS crisis_or_worse,
    ROUND(
        MAX(CASE WHEN UPPER(phase) = '3+'
            THEN population_affected END) * 100.0 /
        NULLIF(MAX(CASE WHEN UPPER(phase) = 'ALL'
            THEN population_affected END), 0), 1
    )                                  AS pct_in_crisis
FROM ipc_som_clean
GROUP BY area
ORDER BY pct_in_crisis DESC
LIMIT 10;

-- Results:
-- NW Northern Inland Pastoral (Sanaag & Sool) | 552,004 | 358,803 | 65%
-- Bay Urban IDPs (Baydhaba)                   | 515,291 | 334,939 | 65%
-- NE Coastal Deeh Pastoral (Bari, Mudug)      |  84,690 |  55,049 | 65%


-- ============================================================
-- STEP 6: EXPORT CLEAN DATA FOR POWER BI
-- Export clean view as CSV for dashboard rebuild.
-- Update file path to match your local directory.
-- ============================================================

SELECT
    area,
    country,
    phase,
    phase_label,
    severity_category,
    validity_period,
    population_affected,
    pct_total_population
FROM ipc_som_clean
ORDER BY area, phase;

-- Export via pgAdmin:
-- Run query above > Data Output toolbar > Save results to file
-- Save as somalia_ipc_clean_2026.csv
-- Load this clean CSV into Power BI instead of raw file


-- ============================================================
-- END OF SCRIPT
-- 
-- Data Quality Summary:
-- Total rows imported:     749
-- Unique areas:            107
-- Null values found:       0
-- Whitespace issues:       0
-- Missing phase rows:      0
-- Dataset status:          Clean and validated
--
-- Key Findings:
-- 1. 1.9M Somalis in Emergency or Famine (Phase 4+5)
-- 2. 6M in Crisis or worse (Phase 3+) = 31% of population
-- 3. Mogadishu IDPs and Sanaag/Sool tied as worst affected
-- 4. 3 areas have 65% of population in crisis
-- ============================================================