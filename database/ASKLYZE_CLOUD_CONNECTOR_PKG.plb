create or replace PACKAGE ASKLYZE_CLOUD_CONNECTOR_PKG AS        
        
    -- Version        
    FUNCTION GET_VERSION RETURN VARCHAR2;        
           
    -- Config Helper (Exposed for Debugging)       
    FUNCTION GET_CONFIG_VALUE(p_key IN VARCHAR2) RETURN VARCHAR2;        
    -- Enforced plan limits (always validated against Cloud)  
    FUNCTION GET_ENFORCED_LIMIT(p_key IN VARCHAR2) RETURN NUMBER;  
    -- Get cached plan code (e.g., 'STANDARD', 'PROFESSIONAL')  
    FUNCTION GET_PLAN_CODE RETURN VARCHAR2;        
        
    -- Configuration Management        
    PROCEDURE SET_API_KEY(p_api_key IN VARCHAR2, p_result OUT CLOB);        
    PROCEDURE SET_ACTIVATION_TOKEN(p_token IN VARCHAR2, p_result OUT CLOB);        
    FUNCTION GET_API_KEY RETURN VARCHAR2;        
    PROCEDURE GET_CONFIG(p_result OUT CLOB);        
        
    -- Subscription Validation        
    FUNCTION VALIDATE_SUBSCRIPTION RETURN CLOB;        
    FUNCTION VALIDATE_SUBSCRIPTION_SCHEMA(p_schema_owner IN VARCHAR2) RETURN CLOB; 
    FUNCTION IS_SUBSCRIPTION_VALID RETURN BOOLEAN;        
    FUNCTION GET_SUBSCRIPTION_STATUS RETURN VARCHAR2;        
    FUNCTION GET_RENEWAL_URL RETURN VARCHAR2;        
        
    -- Cloud API Calls        
    FUNCTION CALL_CLOUD_API(        
        p_endpoint      IN VARCHAR2,        
        p_method        IN VARCHAR2 DEFAULT 'POST',        
        p_body          IN CLOB DEFAULT NULL        
    ) RETURN CLOB;        
        
    -- AI Generation (routes to cloud)        
    PROCEDURE GENERATE_INSIGHTS(        
        p_question      IN CLOB,        
        p_schema_name   IN VARCHAR2,        
        p_category      IN VARCHAR2,        
        p_context       IN CLOB DEFAULT NULL,        
        p_result        OUT CLOB        
    );        
        
    -- AI Suggestions (routes to cloud)        
    PROCEDURE GET_SUGGESTIONS(        
        p_schema_name   IN VARCHAR2,        
        p_mode          IN VARCHAR2,        
        p_context       IN CLOB DEFAULT NULL,        
        p_last_question IN VARCHAR2 DEFAULT NULL,        
        p_result        OUT CLOB        
    );        
        
    -- Catalog AI Description (routes to cloud)        
    PROCEDURE AI_DESCRIBE_TABLES(        
        p_tables_json   IN CLOB,        
        p_schema_name   IN VARCHAR2 DEFAULT NULL,     
        p_tables_count  IN NUMBER DEFAULT NULL,     
        p_result        OUT CLOB        
    );        
        
    -- Catalog Search (routes to cloud for semantic search)      
    FUNCTION CATALOG_SEARCH(      
        p_query         IN VARCHAR2,      
        p_context       IN CLOB DEFAULT NULL      
    ) RETURN CLOB;      
      
    -- =========================================================================      
    -- NEW AI OPERATIONS (Route to Cloud API)      
    -- =========================================================================      
      
    -- Generate trend SQL via cloud      
        FUNCTION GENERATE_TREND_SQL(      
        p_value_sql IN CLOB,      
        p_schema_name IN VARCHAR2 DEFAULT NULL      
    ) RETURN CLOB;      
      
    -- Validate/compile SQL via cloud      
    PROCEDURE COMPILE_SQL(p_sql IN CLOB, p_context IN CLOB DEFAULT NULL, p_result OUT CLOB);      
      
    -- Add new chart to dashboard via cloud AI      
    PROCEDURE ADD_DASHBOARD_CHART(p_query_id IN NUMBER, p_question IN VARCHAR2, p_chart_type IN VARCHAR2 DEFAULT NULL, p_context IN CLOB DEFAULT NULL, p_result OUT CLOB);      
      
    -- Detect pivot configuration via cloud      
    FUNCTION DETECT_PIVOT_CONFIG(p_question IN VARCHAR2, p_data_profile IN CLOB, p_sample_data IN CLOB DEFAULT NULL) RETURN CLOB;      
      
    -- Analyze pivot suitability via cloud  
    FUNCTION ANALYZE_PIVOT_SUITABILITY(p_data_profile IN CLOB, p_row_count IN NUMBER, p_question IN VARCHAR2 DEFAULT NULL) RETURN CLOB;  
  
    -- Audio transcription via cloud (Whisper)  
    FUNCTION TRANSCRIBE_AUDIO(p_audio_base64 IN CLOB, p_mime_type IN VARCHAR2 DEFAULT 'audio/webm') RETURN CLOB;  
  
    -- =========================================================================  
    -- LOCAL DATA OPERATIONS (Moved from ASKLYZE_LOCAL_PKG)      
    -- =========================================================================      
      
    -- SQL Execution      
    FUNCTION EXECUTE_SQL_TO_JSON(p_sql IN CLOB, p_max_rows IN NUMBER DEFAULT 1000) RETURN CLOB;      
    PROCEDURE EXECUTE_AND_RENDER(p_query_id IN NUMBER, p_result OUT CLOB);      
      
    -- Query Store Management      
    PROCEDURE UPDATE_QUERY(p_query_id IN NUMBER, p_new_sql IN CLOB, p_result OUT CLOB);      
    PROCEDURE UPDATE_REPORT_KPI(      
        p_query_id    IN NUMBER,      
        p_kpi_index   IN NUMBER,      
        p_new_sql     IN CLOB,      
        p_kpi_title   IN VARCHAR2 DEFAULT NULL,      
        p_result_json OUT CLOB      
    );      
    PROCEDURE UPDATE_DASHBOARD_KPI(      
        p_query_id    IN NUMBER,      
        p_kpi_index   IN NUMBER,      
        p_value_sql   IN CLOB,      
        p_kpi_title   IN VARCHAR2 DEFAULT NULL,      
        p_trend_sql   IN CLOB DEFAULT NULL,      
        p_result_json OUT CLOB      
    );     
        PROCEDURE UPDATE_DASHBOARD_CHART(      
        p_query_id    IN NUMBER,      
        p_chart_index IN NUMBER,      
        p_new_sql     IN CLOB DEFAULT NULL,      
        p_chart_type  IN VARCHAR2 DEFAULT NULL,      
        p_chart_title IN VARCHAR2 DEFAULT NULL,      
        p_result_json OUT CLOB      
    );       
        PROCEDURE DELETE_DASHBOARD_CHART(      
        p_query_id    IN NUMBER,      
        p_chart_index IN NUMBER,      
        p_result_json OUT CLOB      
    );      
      
    -- Chat History      
    PROCEDURE GET_CHAT_HISTORY(p_user IN VARCHAR2 DEFAULT NULL, p_limit IN NUMBER DEFAULT 50, p_offset IN NUMBER DEFAULT 0, p_search IN VARCHAR2 DEFAULT NULL, p_result_json OUT CLOB);      
    PROCEDURE DELETE_CHAT(p_query_id IN NUMBER, p_result OUT CLOB);      
    PROCEDURE TOGGLE_FAVORITE(p_query_id IN NUMBER, p_result OUT CLOB);      
    PROCEDURE RENAME_CHAT(p_query_id IN NUMBER, p_new_name IN VARCHAR2, p_result OUT CLOB);      
    PROCEDURE CLEAR_HISTORY(p_user IN VARCHAR2, p_result OUT CLOB);      
      
    -- Dashboard Layout      
    PROCEDURE SAVE_DASHBOARD_LAYOUT(p_query_id IN NUMBER, p_layout_json IN CLOB, p_result OUT CLOB);      
    PROCEDURE RESET_DASHBOARD_LAYOUT(p_query_id IN NUMBER, p_result OUT CLOB);      
      
    -- Catalog Local Operations      
    PROCEDURE CATALOG_REFRESH_SCHEMA(p_org_id IN NUMBER, p_schema_owner IN VARCHAR2, p_mode IN VARCHAR2, p_result OUT CLOB);      
    PROCEDURE CATALOG_SET_WHITELIST(p_org_id IN NUMBER, p_schema_owner IN VARCHAR2, p_table_name IN VARCHAR2, p_object_type IN VARCHAR2, p_is_whitelisted IN VARCHAR2, p_is_enabled IN VARCHAR2, p_domain IN VARCHAR2, p_result OUT CLOB);      
    FUNCTION CATALOG_GET_STATS(p_org_id IN NUMBER, p_schema_owner IN VARCHAR2) RETURN CLOB;      
    FUNCTION CATALOG_GET_FULL_CONTEXT(      
        p_org_id        IN NUMBER,      
        p_schema_owner  IN VARCHAR2,      
        p_question      IN VARCHAR2 DEFAULT NULL      
    ) RETURN CLOB;      
    FUNCTION CATALOG_GET_TABLE_DETAILS_JSON(p_table_id IN NUMBER, p_max_cols IN NUMBER DEFAULT 200) RETURN CLOB;      
    FUNCTION CATALOG_SEARCH_TABLES(p_org_id IN NUMBER DEFAULT 1, p_schema_owner IN VARCHAR2 DEFAULT NULL, p_keywords IN VARCHAR2, p_domain IN VARCHAR2 DEFAULT NULL, p_max_results IN NUMBER DEFAULT 10) RETURN CLOB;      
    FUNCTION CATALOG_GET_SEMANTIC_CONTEXT(p_org_id IN NUMBER DEFAULT 1, p_schema_owner IN VARCHAR2 DEFAULT NULL, p_domain IN VARCHAR2 DEFAULT NULL, p_max_tables IN NUMBER DEFAULT 30) RETURN CLOB;      
    PROCEDURE CATALOG_AI_PENDING_COUNT(p_org_id IN NUMBER, p_schema_owner IN VARCHAR2, p_result_json OUT CLOB);      
    PROCEDURE CATALOG_AI_DESCRIBE_BATCH(p_org_id IN NUMBER, p_schema_owner IN VARCHAR2, p_batch_size IN NUMBER DEFAULT 10, p_force IN CHAR DEFAULT 'N', p_result_json OUT CLOB);      
      
    -- Schema Management      
    PROCEDURE GET_CONFIGURED_SCHEMAS(p_org_id IN NUMBER, p_result OUT CLOB);      
    PROCEDURE ADD_SCHEMA(p_org_id IN NUMBER, p_schema_name IN VARCHAR2, p_result OUT CLOB);      
    PROCEDURE SET_DEFAULT_SCHEMA(p_org_id IN NUMBER, p_schema_name IN VARCHAR2, p_result OUT CLOB);      
    PROCEDURE REMOVE_SCHEMA(p_org_id IN NUMBER, p_schema_name IN VARCHAR2, p_result OUT CLOB);      
      
    -- Chart Types      
    PROCEDURE GET_CHART_TYPES(p_result_json OUT CLOB);      
      
    -- Store AI Response (for saving cloud-generated results locally)      
    PROCEDURE STORE_AI_RESPONSE(      
        p_question      IN VARCHAR2,      
        p_mode          IN VARCHAR2,      
        p_schema_name   IN VARCHAR2,      
        p_ai_response   IN CLOB,      
        p_query_id      OUT NUMBER      
    );      
      
    -- =========================================================================      
    -- NEW: Validation Helpers (from Enterprise - local utility functions)      
    -- =========================================================================      
    FUNCTION VALIDATE_ORACLE_IDENTIFIER(p_val IN VARCHAR2) RETURN BOOLEAN;      
    FUNCTION VALIDATE_DB_LINK_NAME(p_val IN VARCHAR2) RETURN BOOLEAN;      
    FUNCTION VALIDATE_HOST_NAME(p_val IN VARCHAR2) RETURN BOOLEAN;      
    FUNCTION VALIDATE_SERVICE_NAME(p_val IN VARCHAR2) RETURN BOOLEAN;      
    FUNCTION VALIDATE_CONNECTION_STRING(p_val IN VARCHAR2) RETURN BOOLEAN;      
    FUNCTION ESCAPE_DB_PASSWORD(p_val IN VARCHAR2) RETURN VARCHAR2;      
      
    -- =========================================================================      
    -- NEW: Response Builders (from Enterprise - standardized JSON responses)      
    -- =========================================================================      
    FUNCTION BUILD_ERROR_RESPONSE(      
        p_message       IN VARCHAR2,      
        p_error_code    IN VARCHAR2 DEFAULT NULL,      
        p_details       IN VARCHAR2 DEFAULT NULL,      
        p_needs_config  IN BOOLEAN DEFAULT FALSE,      
        p_needs_refresh IN BOOLEAN DEFAULT FALSE      
    ) RETURN CLOB;      
    FUNCTION BUILD_SUCCESS_RESPONSE(      
        p_message       IN VARCHAR2 DEFAULT 'Operation completed successfully',      
        p_data          IN CLOB DEFAULT NULL      
    ) RETURN CLOB;      
      
    -- =========================================================================      
    -- NEW: Catalog Context Functions (from Enterprise - local catalog access)      
    -- =========================================================================      
    FUNCTION HAS_WHITELISTED_TABLES(      
        p_org_id       IN NUMBER DEFAULT 1,      
        p_schema_owner IN VARCHAR2 DEFAULT NULL      
    ) RETURN BOOLEAN;      
      
    FUNCTION GET_WHITELISTED_CONTEXT(      
        p_org_id       IN NUMBER DEFAULT 1,      
        p_schema_owner IN VARCHAR2 DEFAULT NULL,      
        p_app_user     IN VARCHAR2 DEFAULT NULL,      
        p_include_relations IN CHAR DEFAULT 'Y',      
        p_question     IN VARCHAR2 DEFAULT NULL      
    ) RETURN CLOB;      
      
    FUNCTION GET_WHITELISTED_TABLE_LIST(      
        p_org_id       IN NUMBER DEFAULT 1,      
        p_schema_owner IN VARCHAR2 DEFAULT NULL,      
        p_max_tables   IN NUMBER DEFAULT 10      
    ) RETURN VARCHAR2;      
      
    FUNCTION VALIDATE_SQL_WHITELIST(      
        p_sql          IN CLOB,      
        p_org_id       IN NUMBER DEFAULT 1,      
        p_schema_owner IN VARCHAR2 DEFAULT NULL      
    ) RETURN VARCHAR2;      
      
    PROCEDURE CHECK_SCHEMA_ACCESS(      
        p_schema_name  IN VARCHAR2,      
        p_has_access   OUT BOOLEAN,      
        p_message      OUT VARCHAR2      
    );      
      
    FUNCTION GET_CONTEXT_SCHEMA(p_owner VARCHAR2 DEFAULT NULL) RETURN CLOB;      
      
    FUNCTION GET_SMART_CONTEXT(      
        p_org_id       IN NUMBER DEFAULT 1,      
        p_schema_owner IN VARCHAR2 DEFAULT NULL,      
        p_question     IN VARCHAR2,      
        p_include_relations IN CHAR DEFAULT 'Y'      
    ) RETURN CLOB;      
      
    FUNCTION SMART_SELECT_TABLES_FALLBACK(      
        p_schema_id    IN NUMBER,      
        p_question     IN VARCHAR2,      
        p_max_tables   IN NUMBER DEFAULT 25      
    ) RETURN CLOB;      
      
    -- =========================================================================      
    -- NEW: Local Processing Functions (from Enterprise)      
    -- =========================================================================      
    FUNCTION VALIDATE_QUESTION(p_question IN VARCHAR2) RETURN VARCHAR2;      
    FUNCTION DETECT_QUERY_INTENT(p_question IN VARCHAR2) RETURN VARCHAR2;      
    FUNCTION PROCESS_KPIS(p_kpi_json IN CLOB) RETURN CLOB;      
    FUNCTION ANALYZE_DATA_PROFILE(p_sql IN CLOB, p_sample_size IN NUMBER DEFAULT 100) RETURN CLOB;      
    FUNCTION BUILD_CHART_CONFIG(p_data_profile IN CLOB, p_ai_suggestion IN CLOB, p_user_preference IN VARCHAR2 DEFAULT NULL) RETURN CLOB;      
    FUNCTION CLEAN_AI_SQL(p_sql IN CLOB) RETURN CLOB;      
      
    -- =========================================================================      
    -- NEW: Catalog Helper Functions (from Enterprise)      
    -- =========================================================================      
    FUNCTION ASKLYZE_CAT_JSON_ESC(p_val IN VARCHAR2) RETURN VARCHAR2;      
    FUNCTION ASKLYZE_CAT_YN(p_val IN CHAR, p_default IN CHAR DEFAULT 'Y') RETURN CHAR;      
    FUNCTION ASKLYZE_CAT_HASH64(p_text IN CLOB) RETURN VARCHAR2;      
    FUNCTION ASKLYZE_CAT_ROLE(p_col_name IN VARCHAR2, p_data_type IN VARCHAR2) RETURN VARCHAR2;      
    PROCEDURE ASKLYZE_CAT_GET_OR_CREATE_SCHEMA(      
        p_org_id        IN NUMBER,      
        p_schema_owner  IN VARCHAR2,      
        p_include_views IN CHAR,      
        p_schema_id     OUT NUMBER,      
        p_eff_inc_views OUT CHAR      
    );      
    FUNCTION CATALOG_GET_CONTEXT_TABLES_JSON(      
        p_org_id        IN NUMBER,      
        p_schema_owner  IN VARCHAR2,      
        p_app_user      IN VARCHAR2 DEFAULT NULL,      
        p_max_tables    IN NUMBER DEFAULT 1000,      
        p_max_cols      IN NUMBER DEFAULT 1000      
    ) RETURN CLOB;      
      
    -- =========================================================================      
    -- NEW: External Connection Management (from Enterprise)      
    -- =========================================================================      
    PROCEDURE GET_EXTERNAL_CONNECTIONS(p_org_id IN NUMBER DEFAULT 1, p_result_json OUT CLOB);      
    PROCEDURE ADD_EXTERNAL_CONNECTION(      
        p_org_id            IN NUMBER DEFAULT 1,      
        p_connection_name   IN VARCHAR2,      
        p_connection_type   IN VARCHAR2,      
        p_db_host           IN VARCHAR2 DEFAULT NULL,      
        p_db_port           IN NUMBER DEFAULT 1521,      
        p_service_name      IN VARCHAR2 DEFAULT NULL,      
        p_connection_string IN VARCHAR2 DEFAULT NULL,      
        p_db_user           IN VARCHAR2,      
        p_db_password       IN VARCHAR2,      
        p_result_json       OUT CLOB      
    );      
    PROCEDURE UPDATE_EXTERNAL_CONNECTION(      
        p_connection_id     IN NUMBER,      
        p_connection_name   IN VARCHAR2 DEFAULT NULL,      
        p_connection_type   IN VARCHAR2 DEFAULT NULL,      
        p_db_host           IN VARCHAR2 DEFAULT NULL,      
        p_db_port           IN NUMBER DEFAULT NULL,      
        p_service_name      IN VARCHAR2 DEFAULT NULL,      
        p_connection_string IN VARCHAR2 DEFAULT NULL,      
        p_db_user           IN VARCHAR2 DEFAULT NULL,      
        p_db_password       IN VARCHAR2 DEFAULT NULL,      
        p_result_json       OUT CLOB      
    );      
    PROCEDURE DELETE_EXTERNAL_CONNECTION(p_connection_id IN NUMBER, p_result_json OUT CLOB);      
    PROCEDURE TEST_EXTERNAL_CONNECTION(p_connection_id IN NUMBER, p_result_json OUT CLOB);      
    PROCEDURE CREATE_DB_LINK(p_connection_id IN NUMBER, p_result_json OUT CLOB);      
      
    -- Database instance fingerprint for COUNT_DB_INSTANCES enforcement  
    FUNCTION GET_DB_FINGERPRINT RETURN VARCHAR2;  
  
    -- Returns DB_INSTANCE_LIMIT error message if last validation was blocked, NULL otherwise  
    FUNCTION GET_DB_INSTANCE_ERROR RETURN VARCHAR2;  
  
END ASKLYZE_CLOUD_CONNECTOR_PKG;
/



create or replace PACKAGE BODY ASKLYZE_CLOUD_CONNECTOR_PKG wrapped 
a000000
369
abcd
abcd
abcd
abcd
abcd
abcd
abcd
abcd
abcd
abcd
abcd
abcd
abcd
abcd
abcd
b
41971 bf05
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

/
