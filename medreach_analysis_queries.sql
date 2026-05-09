-- TABLE CREATION: MR CALL ACTIVITY
-- Store MR-level activity and prescription generation data

CREATE TABLE mr_call_activity (
    mr_id               VARCHAR(10),
    mr_name             VARCHAR(100),
    zone                VARCHAR(20),
    role                VARCHAR(30),
    hire_type           VARCHAR(10),
    join_date           DATE,
    product_assigned    VARCHAR(30),
    month               VARCHAR(10),
    calls_made          INTEGER,
    doctors_visited     INTEGER,
    avg_call_duration   NUMERIC(5,1),
    rxns_generated      INTEGER
);


SELECT column_name, data_type 
FROM information_schema.columns
WHERE table_name = 'mr_call_activity';

COPY mr_call_activity
FROM 'C:/Users/Zeel Bhadra/Desktop/DA Project/mr_call_activity.csv'
DELIMITER ','
CSV HEADER;

SELECT * 
FROM mr_call_activity 
LIMIT 10;

SELECT COUNT(*) AS total_rows
FROM mr_call_activity;

-- How many missing values exist in avg_call_duration?
-- Used for data quality auditing.

SELECT COUNT(*) AS null_count
FROM mr_call_activity
WHERE avg_call_duration is NULL;

-- Q1: Are new hire MRs making fewer calls than existing MRs?

SELECT 
    hire_type,
    ROUND(AVG(calls_made), 2) AS avg_calls_made
FROM mr_call_activity
GROUP BY hire_type
ORDER BY avg_calls_made DESC;

-- Q2: What is the conversion rate gap between new and existing MRs?

SELECT 
	hire_type,
	ROUND(AVG(calls_made), 2) AS avg_calls_made,
	ROUND(AVG(rxns_generated), 2) AS avg_rxns_generated,
	ROUND(AVG(rxns_generated) / NULLIF(AVG(calls_made), 0), 3) AS conversion_ratio
FROM mr_call_activity
GROUP BY hire_type
ORDER BY conversion_ratio DESC;

-- Q3: Which MRs are high activity but low conversion performers?

SELECT 
    mr_name,
    zone,
	COUNT(zone),
    SUM(calls_made) AS total_calls,
    SUM(rxns_generated) AS total_rxns,
    ROUND(SUM(rxns_generated) / NULLIF(SUM(calls_made), 0), 3) AS conversion_rate
FROM mr_call_activity
GROUP BY mr_name, zone
HAVING SUM(calls_made)> 100 AND ROUND(SUM(rxns_generated) / NULLIF(SUM(calls_made), 0), 3)< 0.10
ORDER BY conversion_rate ASC;

-- Are underperformers concentrated more among new hires or existing employees?

SELECT 
    hire_type,
    COUNT(*) AS underperformer_count
FROM (
    SELECT 
        mr_name,
        zone,
        hire_type,
        SUM(calls_made) AS total_calls,
        ROUND(SUM(rxns_generated) / NULLIF(SUM(calls_made), 0), 3) AS conversion_rate
    FROM mr_call_activity
    GROUP BY mr_name, zone, hire_type
    HAVING SUM(calls_made) > 100 
    AND ROUND(SUM(rxns_generated) / NULLIF(SUM(calls_made), 0), 3) < 0.10
) AS underperformers
GROUP BY hire_type
ORDER BY underperformer_count DESC;

-- Which MR roles and hire categories contribute most to underperformance?

SELECT 
    role,
    hire_type,
    COUNT(*) AS underperformer_count
FROM (
    SELECT 
        mr_name,
        zone,
        role,
        hire_type,
        SUM(calls_made) AS total_calls,
        ROUND(SUM(rxns_generated) / NULLIF(SUM(calls_made), 0), 3) AS conversion_rate
    FROM mr_call_activity
    GROUP BY mr_name, zone, role, hire_type
    HAVING SUM(calls_made) > 100 
    AND ROUND(SUM(rxns_generated) / NULLIF(SUM(calls_made), 0), 3) < 0.10
) AS underperformers
GROUP BY role, hire_type
ORDER BY role, hire_type;

-- underperformers vs on-track

SELECT
    mr_name,
    zone,
    role,
    hire_type,
    SUM(calls_made) AS total_calls,
    SUM(doctors_visited) AS total_doctors,
    ROUND(SUM(rxns_generated) / NULLIF(SUM(calls_made),0), 3) AS conversion_rate,
    CASE
        WHEN role = 'Territory Manager' THEN 'Excluded - Different KPI'
        WHEN role = 'Senior MR' 
            AND ROUND(SUM(rxns_generated) / NULLIF(SUM(calls_made),0), 3) < 0.25
            THEN 'Underperformer'
        WHEN role = 'Junior MR'
            AND SUM(calls_made) > 50
            AND ROUND(SUM(rxns_generated) / NULLIF(SUM(calls_made),0), 3) < 0.10
            THEN 'Underperformer'
        ELSE 'On Track'
    END AS performance_flag
FROM mr_call_activity
GROUP BY mr_name, zone, role, hire_type
ORDER BY role, conversion_rate ASC;


SELECT
    role,
    performance_flag,
    hire_type,
    COUNT(*) AS mr_count
FROM (
    SELECT
    mr_name,
    zone,
    role,
    hire_type,
    SUM(calls_made) AS total_calls,
    SUM(doctors_visited) AS total_doctors,
    ROUND(SUM(rxns_generated) / NULLIF(SUM(calls_made),0), 3) AS conversion_rate,
    CASE
        WHEN role = 'Territory Manager' THEN 'Excluded - Different KPI'
        WHEN role = 'Senior MR' 
            AND ROUND(SUM(rxns_generated) / NULLIF(SUM(calls_made),0), 3) < 0.25
            THEN 'Underperformer'
        WHEN role = 'Junior MR'
            AND SUM(calls_made) > 50
            AND ROUND(SUM(rxns_generated) / NULLIF(SUM(calls_made),0), 3) < 0.10
            THEN 'Underperformer'
        ELSE 'On Track'
    END AS performance_flag
FROM mr_call_activity
GROUP BY mr_name, zone, role, hire_type
ORDER BY role, conversion_rate ASC
) AS performance_analysis
WHERE role != 'Territory Manager'
GROUP BY role, performance_flag, hire_type
ORDER BY role, performance_flag, hire_type;

--TABLE CREATION: DOCTOR UNIVERSE
-- Store doctor segmentation and prescription potential data

CREATE TABLE doctor_universe(
	doctor_id VARCHAR(10) PRIMARY KEY,
	doctor_name VARCHAR(100),
	specialization VARCHAR(30),
	segment VARCHAR(5),
	zone VARCHAR(20),
	avg_monthly_rxns NUMERIC(6,1),
	is_key_account BOOLEAN,
	monthly_patients INTEGER,
	mr_id_assigned VARCHAR(10)
);

COPY doctor_universe
FROM 'C:/Users/Zeel Bhadra/Desktop/DA Project/doctor_universe.csv'
DELIMITER ','
CSV HEADER;

SELECT * FROM doctor_universe
LIMIT 10;

-- Which doctors are being targeted by which MR types,
-- and are high-potential doctors receiving attention?
-- LEFT JOIN
SELECT DISTINCT 
du.doctor_name,
du.segment, 
du.avg_monthly_rxns,
mca.hire_type,
mca.zone
FROM doctor_universe du
LEFT JOIN mr_call_activity mca
	ON du.mr_id_assigned = mca.mr_id
ORDER BY du.segment, du.avg_monthly_rxns DESC
LIMIT 20;


-- Doctor distribution along with the prescription potential segment wise 

SELECT 
segment, 
COUNT(*) AS dr_count,
AVG(avg_monthly_rxns),
ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct_of_total
FROM doctor_universe
GROUP BY segment
ORDER BY dr_count DESC;

-- NULL Hypothesis testing : MRs spending more time on low prescribing doctors

SELECT 
    du.segment,
    COUNT(DISTINCT du.doctor_id) AS doctors_in_segment,
    ROUND(AVG(mca.calls_made), 1) AS avg_calls_by_mr,
    ROUND(AVG(du.avg_monthly_rxns), 1) AS avg_rxn_potential,
    ROUND(COUNT(DISTINCT du.doctor_id) * 100.0 / 
          SUM(COUNT(DISTINCT du.doctor_id)) OVER (), 1) AS pct_doctors_covered
FROM doctor_universe du
LEFT JOIN mr_call_activity mca
    ON du.mr_id_assigned = mca.mr_id
GROUP BY du.segment
ORDER BY du.segment;