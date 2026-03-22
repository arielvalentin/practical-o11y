-- Create databases for each service
CREATE DATABASE store_development;
CREATE DATABASE shipping_service_development;
CREATE DATABASE recommendation_service_development;
CREATE DATABASE notification_service_development;

-- Production databases
CREATE DATABASE store_production;
CREATE DATABASE store_production_cache;
CREATE DATABASE store_production_queue;
CREATE DATABASE store_production_cable;
CREATE DATABASE shipping_service_production;
CREATE DATABASE recommendation_service_production;
CREATE DATABASE notification_service_production;
