-- ============================================================================
-- Quality Analytics & Defect Prediction
-- Quality Analytics & Defect Prediction for Vietnam - ML.FORECAST and Dynamic Tables power real-time quality analytics intelligence for electronics manufacturing in Ho Chi Minh City & Bac Ninh.
-- ============================================================================
USE ROLE ACCOUNTADMIN;
CREATE DATABASE IF NOT EXISTS ELECTRONICS_QUALITY;
CREATE WAREHOUSE IF NOT EXISTS ELECTRONICS_WH WAREHOUSE_SIZE = 'MEDIUM' AUTO_SUSPEND = 120 AUTO_RESUME = TRUE;
USE DATABASE ELECTRONICS_QUALITY;
CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS CURATED;
CREATE SCHEMA IF NOT EXISTS ML;
CREATE SCHEMA IF NOT EXISTS AI;
CREATE SCHEMA IF NOT EXISTS SEARCH;
CREATE SCHEMA IF NOT EXISTS APP;

USE WAREHOUSE ELECTRONICS_WH;
