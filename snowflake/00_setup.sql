-- Generated from generator/demo_specs/aws-vietnam-electronics-quality.json
-- Regenerate with: python3 generator/gen_repo_docs.py aws-vietnam-electronics-quality
-- This is the schema that is actually deployed for VIETNAM_ELECTRONICS_QUALITY.

-- VIETNAM_ELECTRONICS_QUALITY  (Quality Analytics & Defect Prediction)
-- generated from generator/demo_specs/aws-vietnam-electronics-quality.json - do not hand-edit
CREATE DATABASE IF NOT EXISTS VIETNAM_ELECTRONICS_QUALITY;
CREATE SCHEMA IF NOT EXISTS VIETNAM_ELECTRONICS_QUALITY.RAW;
CREATE SCHEMA IF NOT EXISTS VIETNAM_ELECTRONICS_QUALITY.CURATED;
CREATE SCHEMA IF NOT EXISTS VIETNAM_ELECTRONICS_QUALITY.APP;
USE DATABASE VIETNAM_ELECTRONICS_QUALITY;

-- 5 real regions; entity names carry their region so the two always agree
