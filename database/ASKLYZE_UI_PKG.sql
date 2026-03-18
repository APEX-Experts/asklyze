create or replace PACKAGE ASKLYZE_UI_PKG AS        
    PROCEDURE render_dashboard(        
        p_region IN apex_plugin.t_region,        
        p_plugin IN apex_plugin.t_plugin,        
        p_param  IN apex_plugin.t_region_render_param,        
        p_result IN OUT NOCOPY apex_plugin.t_region_render_result        
    );        
    PROCEDURE ajax_handler(        
        p_region IN apex_plugin.t_region,        
        p_plugin IN apex_plugin.t_plugin,        
        p_param  IN apex_plugin.t_region_ajax_param,        
        p_result IN OUT NOCOPY apex_plugin.t_region_ajax_result        
    );        
END ASKLYZE_UI_PKG;
/

create or replace PACKAGE BODY ASKLYZE_UI_PKG AS        
        
    -- Helper to output JavaScript || operator safely        
    FUNCTION JS_OR RETURN VARCHAR2 IS        
    BEGIN        
        RETURN CHR(124) || CHR(124);        
    END JS_OR;        
        
-- Helper to print CLOBs larger than 32k        
    PROCEDURE PRINT_CLOB(p_clob IN CLOB) IS        
        l_offset NUMBER := 1;        
        l_length NUMBER;        
        l_amount NUMBER := 8000; -- Chunk size (safe for varchar2)        
    BEGIN        
        IF p_clob IS NULL THEN        
            RETURN;        
        END IF;        
                
        l_length := DBMS_LOB.GETLENGTH(p_clob);        
                
        WHILE l_offset <= l_length LOOP        
            htp.prn(DBMS_LOB.SUBSTR(p_clob, l_amount, l_offset));        
            l_offset := l_offset + l_amount;        
        END LOOP;        
    EXCEPTION WHEN OTHERS THEN        
        htp.p('{"status":"error","message":"Error printing CLOB"}');        
    END PRINT_CLOB;        
        
    PROCEDURE render_dashboard( 
        p_region IN apex_plugin.t_region, 
        p_plugin IN apex_plugin.t_plugin, 
        p_param  IN apex_plugin.t_region_render_param, 
        p_result IN OUT NOCOPY apex_plugin.t_region_render_result 
    ) IS 
        l_id        VARCHAR2(255); 
        l_ajax      VARCHAR2(4000); 
        l_js        CLOB; 
        l_or        VARCHAR2(5) := CHR(124) || CHR(124); -- JavaScript || operator 
        l_api_key   VARCHAR2(4000); 
        l_current_key VARCHAR2(4000); 
        l_config_result CLOB; 
        l_render_schema_limit NUMBER; 
        l_render_enabled_cnt  NUMBER; 
        l_render_show_block   VARCHAR2(1) := 'N'; 
        l_render_cnt          NUMBER := 0; 
        l_render_found        VARCHAR2(1) := 'N'; 
        l_render_current      VARCHAR2(128);      
    BEGIN        
        IF p_param.is_printer_friendly THEN RETURN; END IF;        
        l_id := p_region.static_id;        
        l_ajax := apex_plugin.get_ajax_identifier;      
              
        -- ===================================================================      
        -- PLUG AND PLAY: Auto-configure API Key from Plugin Attribute      
        -- ===================================================================      
        -- Strategy 1: Component Attribute      
        l_api_key := p_region.attribute_01;      
        htp.p('<!-- ASKLYZE DEBUG: Strategy 1 (Region): ' || NVL(LENGTH(l_api_key), 0) || ' chars -->');      
      
        -- Strategy 2: Application Attribute (Standard Mapping)      
        IF l_api_key IS NULL THEN      
            l_api_key := p_plugin.attribute_01;      
            htp.p('<!-- ASKLYZE DEBUG: Strategy 2 (Plugin): ' || NVL(LENGTH(l_api_key), 0) || ' chars -->');      
        END IF;      
      
        -- Strategy 3: Direct Query of Plugin Settings (The "Nuclear Option")      
        IF (l_api_key IS NULL OR LENGTH(l_api_key) < 5) THEN      
            BEGIN      
                htp.p('<!-- ASKLYZE DEBUG: Strategy 3 (Direct Query) executing... -->');      
                      
                -- Dynamic SQL to avoid compilation errors if view doesn't exist      
                -- We query by PLUGIN_CODE which user confirmed is 'PLUGIN_ASKLYZE_AI_PLUGIN'      
                EXECUTE IMMEDIATE '      
                    SELECT JSON_VALUE(s.attributes, ''$.api_key'')       
                      FROM apex_appl_plugin_settings s       
                     WHERE s.application_id = :1       
                       AND s.plugin_code = ''PLUGIN_ASKLYZE_AI_PLUGIN'''       
                  INTO l_api_key       
                 USING v('APP_ID');      
                       
                 htp.p('<!-- ASKLYZE DEBUG: Strategy 3 Result: ' || NVL(LENGTH(l_api_key), 0) || ' chars -->');      
            EXCEPTION      
                WHEN OTHERS THEN      
                    htp.p('<!-- ASKLYZE DEBUG: Strategy 3 Failed: ' || SQLERRM || ' -->');      
            END;      
        END IF;      
      
        if l_api_key is not null then      
             htp.p('<!-- ASKLYZE DEBUG: Final Key Prefix: ' || SUBSTR(l_api_key, 1, 5) || '... -->');      
        end if;      
              
        IF l_api_key IS NOT NULL AND LENGTH(TRIM(l_api_key)) > 5 THEN      
             -- Check if API key is already configured      
            BEGIN      
                l_current_key := ASKLYZE_CLOUD_CONNECTOR_PKG.GET_API_KEY;      
            EXCEPTION      
                WHEN OTHERS THEN l_current_key := NULL;      
            END;      
                  
            htp.p('<!-- ASKLYZE DEBUG: current_key exists = ' || CASE WHEN l_current_key IS NOT NULL THEN 'YES' ELSE 'NO' END || ' -->');      
                  
            -- If not configured or different key, auto-save      
            IF l_current_key IS NULL OR l_current_key != l_api_key THEN      
                BEGIN      
                    htp.p('<!-- ASKLYZE DEBUG: Attempting to save API Key... -->');      
                          
                    ASKLYZE_CLOUD_CONNECTOR_PKG.SET_API_KEY(      
                        p_api_key => l_api_key,      
                        p_result  => l_config_result      
                    );      
                          
                    htp.p('<!-- ASKLYZE DEBUG: SET_API_KEY result = ' || SUBSTR(l_config_result, 1, 200) || ' -->');      
                EXCEPTION      
                    WHEN OTHERS THEN       
                        htp.p('<!-- ASKLYZE DEBUG: SET_API_KEY error = ' || SQLERRM || ' -->');      
                END;      
            ELSE      
                htp.p('<!-- ASKLYZE DEBUG: API key matches current config, skipping save -->');      
            END IF;      
        ELSE      
             htp.p('<!-- ASKLYZE DEBUG: API Key could not be found in any attribute source -->');      
        END IF;      
        -- ===================================================================        
        
        -- Libraries        
        htp.p('<script src="https://cdn.jsdelivr.net/npm/echarts@5.4.3/dist/echarts.min.js"></script>');        
        htp.p('<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.css">');        
        htp.p('<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/theme/dracula.min.css">');        
        htp.p('<script src="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/codemirror.min.js"></script>');        
        htp.p('<script src="https://cdnjs.cloudflare.com/ajax/libs/codemirror/5.65.16/mode/sql/sql.min.js"></script>');        
        htp.p('<script src="https://unpkg.com/sql-formatter@4.0.2/dist/sql-formatter.min.js"></script>');        
        htp.p('<script src="https://cdnjs.cloudflare.com/ajax/libs/xlsx/0.18.5/xlsx.full.min.js"></script>');        
        htp.p('<script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>');        
        htp.p('<script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf-autotable/3.5.31/jspdf.plugin.autotable.min.js"></script>');        
        htp.p('<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>');        
        htp.p('<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/gridstack@9.4.0/dist/gridstack.min.css">');        
        htp.p('<script src="https://cdn.jsdelivr.net/npm/gridstack@9.4.0/dist/gridstack-all.js"></script>');        
        htp.p('<link href="https://cdn.webdatarocks.com/latest/webdatarocks.min.css" rel="stylesheet">');        
        htp.p('<script src="https://cdn.webdatarocks.com/latest/webdatarocks.toolbar.min.js"></script>');        
        htp.p('<script src="https://cdn.webdatarocks.com/latest/webdatarocks.js"></script>');        
        htp.p('<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">');        
        htp.p('<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/ag-grid-community@31.0.3/styles/ag-grid.css">');        
        htp.p('<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/ag-grid-community@31.0.3/styles/ag-theme-alpine.css">');        
        htp.p('<script src="https://cdn.jsdelivr.net/npm/ag-grid-community@31.0.3/dist/ag-grid-community.min.js"></script>');        
        -- htp.p('<link rel="stylesheet" href="#PLUGIN_FILES#asklyze-ui.css">');     
        -- htp.p('<script src="#PLUGIN_FILES#asklyze-ui.js"></script>');        
     
         -- HTML STRUCTURE        
        htp.p('<div id="' || l_id || '" class="apex-ai-container">'); 
 
        -- Server-side schema limit check (renders overlay directly, no JS dependency) 
        -- Uses ID "schema_block_" instead of "subscription_alert_" so JS hideSubscriptionAlert cannot remove it 
        BEGIN 
            l_render_schema_limit := ASKLYZE_CLOUD_CONNECTOR_PKG.GET_ENFORCED_LIMIT('COUNT_SCHEMA'); 
            l_render_current := NVL(apex_application.g_flow_owner, USER); 
 
            IF l_render_schema_limit IS NOT NULL AND l_render_schema_limit > 0 THEN 
                SELECT COUNT(*) INTO l_render_enabled_cnt 
                FROM asklyze_catalog_schemas 
                WHERE org_id = 1 AND is_enabled = 'Y'; 
 
                -- Check A: More schemas configured than plan allows 
                IF l_render_enabled_cnt > l_render_schema_limit THEN 
                    l_render_show_block := 'Y'; 
                ELSE 
                    -- Check B: Current schema not among the allowed schemas 
                    l_render_cnt := 0; 
                    l_render_found := 'N'; 
                    FOR sr IN ( 
                        SELECT schema_owner 
                        FROM asklyze_catalog_schemas 
                        WHERE org_id = 1 AND is_enabled = 'Y' 
                        ORDER BY CASE WHEN is_default = 'Y' THEN 0 ELSE 1 END, 
                                 NVL(display_order, 999), schema_owner 
                    ) LOOP 
                        EXIT WHEN l_render_cnt >= l_render_schema_limit; 
                        l_render_cnt := l_render_cnt + 1; 
                        IF UPPER(sr.schema_owner) = UPPER(l_render_current) THEN 
                            l_render_found := 'Y'; 
                        END IF; 
                    END LOOP; 
                    -- Block if current schema is not in allowed set AND there are enabled schemas 
                    IF l_render_found = 'N' AND l_render_enabled_cnt > 0 THEN 
                        l_render_show_block := 'Y'; 
                    END IF; 
                END IF; 
            END IF; 
 
            htp.p('<!-- ASKLYZE_SCHEMA_CHECK: limit=' || NVL(TO_CHAR(l_render_schema_limit),'NULL') || ' enabled=' || NVL(TO_CHAR(l_render_enabled_cnt),'NULL') || ' current=' || l_render_current || ' block=' || l_render_show_block || ' -->'); 
 
            IF l_render_show_block = 'Y' THEN 
                htp.p('<div id="schema_block_' || l_id || '" class="ai-subscription-alert-overlay" style="z-index:10001;">'); 
                htp.p('<div class="ai-subscription-alert-content">'); 
                htp.p('<div class="ai-subscription-alert-icon"><i class="fas fa-database"></i></div>'); 
                htp.p('<h2 class="ai-subscription-alert-title">Schema Limit Reached</h2>'); 
                htp.p('<p class="ai-subscription-alert-message">Your plan allows ' || l_render_schema_limit || ' schema. Please visit the ASKLYZE Portal to upgrade your plan for additional schemas.</p>'); 
                htp.p('</div></div>'); 
            END IF; 
        EXCEPTION WHEN OTHERS THEN 
            htp.p('<!-- ASKLYZE_SCHEMA_CHECK_ERROR: ' || REPLACE(SQLERRM, '--', '- -') || ' -->'); 
        END; 
 
        -- Toast Notification Container 
        htp.p('<div id="toast_container_' || l_id || '" class="ai-toast-container"></div>');        
        
        -- Confirmation Modal (Delete/Clear) - SEPARATE        
        htp.p('<div id="modal_' || l_id || '" class="ai-modal-overlay">');        
        htp.p('<div class="ai-modal">');        
        htp.p('<h3 id="modal_title_' || l_id || '">Confirm</h3>');        
        htp.p('<p id="modal_msg_' || l_id || '">Are you sure?</p>');        
        htp.p('<div class="ai-modal-btns">');        
        htp.p('<button type="button" class="ai-btn ai-btn-cancel" onclick="window.AID_' || l_id || '.closeModal()">Cancel</button>');        
        htp.p('<button type="button" class="ai-btn ai-btn-confirm" onclick="window.AID_' || l_id || '.confirmAction()">Delete</button>');        
        htp.p('</div></div></div>');        
        
        -- =====================================================        
        -- PROFESSIONAL WIZARD MODAL (Data Settings)        
        -- =====================================================        
        htp.p('<div id="wizard_' || l_id || '" class="ai-wizard-overlay">');        
        htp.p('<div class="ai-wizard">');        
                
        -- Wizard Header - New Design        
        htp.p('<div class="ai-wizard-header">');        
        htp.p('<div class="ai-wizard-header-content">');        
        htp.p('<div class="ai-wizard-title-area">');        
        htp.p('<div class="ai-wizard-icon"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 2L15.09 8.26L22 9.27L17 14.14L18.18 21.02L12 17.77L5.82 21.02L7 14.14L2 9.27L8.91 8.26L12 2Z"/></svg></div>');        
        htp.p('<div>');        
        htp.p('<h2 class="ai-wizard-title">AI Data Configuration</h2>');        
        htp.p('<div class="ai-wizard-subtitle">Configure which tables AI can access and analyze</div>');        
        htp.p('</div></div>');        
        htp.p('<button type="button" class="ai-wizard-close" onclick="window.AID_' || l_id || '.closeWizard()"><i class="fas fa-times"></i></button>');        
        htp.p('</div></div>');        
                
        -- Stepper with connecting lines        
        htp.p('<div class="ai-wizard-stepper">');        
        htp.p('<div id="wiz_step1_' || l_id || '" class="ai-wizard-step active">');        
        htp.p('<div class="ai-wizard-step-num">1</div>');        
        htp.p('<div class="ai-wizard-step-info">');        
        htp.p('<div class="ai-wizard-step-title">Select Tables</div>');        
        htp.p('<div class="ai-wizard-step-desc">Choose data sources</div>');        
        htp.p('</div></div>');        
        htp.p('<div id="wiz_line1_' || l_id || '" class="ai-wizard-step-line"></div>');        
        htp.p('<div id="wiz_step2_' || l_id || '" class="ai-wizard-step">');        
        htp.p('<div class="ai-wizard-step-num">2</div>');        
        htp.p('<div class="ai-wizard-step-info">');        
        htp.p('<div class="ai-wizard-step-title">Build Metadata</div>');        
        htp.p('<div class="ai-wizard-step-desc">AI analyzes structure</div>');        
        htp.p('</div></div>');        
        htp.p('<div id="wiz_line2_' || l_id || '" class="ai-wizard-step-line"></div>');        
        htp.p('<div id="wiz_step3_' || l_id || '" class="ai-wizard-step">');        
        htp.p('<div class="ai-wizard-step-num">3</div>');        
        htp.p('<div class="ai-wizard-step-info">');        
        htp.p('<div class="ai-wizard-step-title">Complete</div>');        
        htp.p('<div class="ai-wizard-step-desc">Ready to use</div>');        
        htp.p('</div></div>');        
        htp.p('</div>');        
                
        -- Wizard Body        
        htp.p('<div class="ai-wizard-body">');        
                
        -- Step 1 Content: Table Selection - New Design        
        htp.p('<div id="wiz_content1_' || l_id || '" class="ai-wizard-content active">');        
        
        -- Schema Selector - New Design with Dropdown and Management        
        htp.p('<div class="ai-schema-section">');        
        htp.p('<div class="ai-schema-header">');        
        htp.p('<div class="ai-schema-select-wrap">');        
        htp.p('<label class="ai-schema-label">        
                <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="vertical-align: middle; margin-right: 5px;">        
                    <line x1="18" y1="20" x2="18" y2="10"></line>        
                    <line x1="12" y1="20" x2="12" y2="4"></line>        
                    <line x1="6" y1="20" x2="6" y2="14"></line>        
                </svg>        
                Schema:        
            </label>');        
        htp.p('<select id="wiz_schema_select_' || l_id || '" class="ai-schema-dropdown" onchange="window.AID_' || l_id || '.selectWizardSchema(this.value)"></select>');        
        htp.p('<button type="button" class="ai-schema-manage-btn" id="schema_manage_btn_' || l_id || '" onclick="window.AID_' || l_id || '.toggleSchemaManager()" title="Manage Schemas">');        
        htp.p('<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9c.26.604.852.997 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg>');        
        htp.p('</button>');        
        htp.p('</div>');        
        htp.p('</div>');        
        
        -- Schema Manager Panel (collapsible)        
        htp.p('<div class="ai-schema-manager" id="schema_manager_' || l_id || '">');        
        htp.p('<div class="ai-schema-manager-header">');        
        htp.p('<span>Manage Schemas</span>');        
        htp.p('<button type="button" class="ai-schema-close-btn" onclick="window.AID_' || l_id || '.toggleSchemaManager()"><i class="fas fa-times"></i></button>');        
        htp.p('</div>');        
        htp.p('<div class="ai-schema-list" id="schema_list_' || l_id || '"></div>');        
        htp.p('<div class="ai-schema-add-row" id="schema_add_row_' || l_id || '">');        
        htp.p('<input type="text" class="ai-schema-add-input" id="new_schema_input_' || l_id || '" placeholder="Enter schema name..." onkeyup="if(event.key===''Enter'') window.AID_' || l_id || '.addNewSchema()">');        
        htp.p('<button type="button" class="ai-schema-add-btn" onclick="window.AID_' || l_id || '.addNewSchema()">+ Add</button>');        
        htp.p('</div>');        
        htp.p('<button type="button" class="ai-ext-conn-add-btn" id="ext_conn_btn_' || l_id || '" onclick="window.AID_' || l_id || '.openExtConnModal()">');        
        htp.p('<span style="display: inline-flex; align-items: center; gap: 8px;">        
            <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">        
                <path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"></path>        
                <path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"></path>        
            </svg>        
            Manage External Connections        
        </span>');        
        htp.p('</button>');        
        htp.p('</div>');        
        htp.p('</div>');        
        
        htp.p('<div class="ai-table-toolbar">');        
        htp.p('<div class="ai-search-box">');        
        htp.p('<input type="text" id="wiz_search_' || l_id || '" class="ai-wiz-search" placeholder="Search tables..." autocomplete="off" autocapitalize="off" autocorrect="off" spellcheck="false" onkeyup="window.AID_' || l_id || '.filterWizardTables(this.value)">');        
        htp.p('</div>');        
        htp.p('<div class="ai-filter-chips">');        
        htp.p('<button type="button" class="ai-filter-chip recommended" data-filter="recommended" onclick="window.AID_' || l_id || '.setWizardFilter(''recommended'', this)">Recommended</button>');        
        htp.p('<button type="button" class="ai-filter-chip" data-filter="selected" onclick="window.AID_' || l_id || '.setWizardFilter(''selected'', this)">Selected (<span id="wiz_count_' || l_id || '">0</span>)</button>');        
        htp.p('<button type="button" class="ai-filter-chip active" data-filter="all" onclick="window.AID_' || l_id || '.setWizardFilter(''all'', this)">All Tables</button>');        
        htp.p('</div>');        
        htp.p('<select id="wiz_domain_' || l_id || '" class="ai-domain-select" onchange="window.AID_' || l_id || '.renderWizardTables()">');        
        htp.p('<option value="all">All Domains</option>');        
        htp.p('<option value="Sales"><i class="fas fa-coins"></i> Sales</option>');        
        htp.p('<option value="HR"><i class="fas fa-users"></i> HR</option>');        
        htp.p('<option value="Finance"><i class="fas fa-dollar-sign"></i> Finance</option>');        
        htp.p('<option value="Inventory"><i class="fas fa-box"></i> Inventory</option>');        
        htp.p('<option value="Supply Chain"><i class="fas fa-truck"></i> Supply Chain</option>');        
        htp.p('<option value="Customer"><i class="fas fa-user-tie"></i> Customer</option>');        
        htp.p('<option value="Marketing"><i class="fas fa-bullhorn"></i> Marketing</option>');        
        htp.p('<option value="Operations"><i class="fas fa-cogs"></i> Operations</option>');        
        htp.p('<option value="IT"><i class="fas fa-laptop-code"></i> IT</option>');        
        htp.p('<option value="Analytics"><i class="fas fa-chart-bar"></i> Analytics</option>');        
        htp.p('<option value="Master Data"><i class="fas fa-folder-open"></i> Master Data</option>');        
        htp.p('<option value="Audit"><i class="fas fa-clipboard-check"></i> Audit</option>');        
        htp.p('<option value="Security"><i class="fas fa-lock"></i> Security</option>');        
        htp.p('<option value="Other"><i class="fas fa-folder"></i> Other</option>');        
        htp.p('</select>');        
        htp.p('<div class="ai-select-actions">');        
        htp.p('<button type="button" class="ai-select-btn" onclick="window.AID_' || l_id || '.selectAllTables()">Select All</button>');        
        htp.p('<button type="button" class="ai-select-btn" onclick="window.AID_' || l_id || '.selectNoneTables()">Clear</button>');        
        htp.p('</div></div>');        
        htp.p('<div id="wiz_table_list_' || l_id || '" class="ai-table-list-container">');        
        htp.p('<div class="ai-table-grid" id="wiz_grid_' || l_id || '"></div>');        
        htp.p('</div></div>');        
                
        -- Step 2 Content: Building Metadata        
        htp.p('<div id="wiz_content2_' || l_id || '" class="ai-wizard-content">');        
        htp.p('<div class="ai-build-container">');        
        htp.p('<div class="ai-build-animation">');        
        htp.p('<div class="ai-build-circle"></div>');        
        htp.p('<div class="ai-build-circle spinning"></div>');        
        htp.p('<div class="ai-build-icon">        
            <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">        
                <path d="M12 8V4H8"></path>        
                <rect width="16" height="12" x="4" y="8" rx="2"></rect>        
                <path d="M2 14h2"></path>        
                <path d="M20 14h2"></path>        
                <path d="M15 13v2"></path>        
                <path d="M9 13v2"></path>        
            </svg>        
        </div>');        
        htp.p('</div>');        
        htp.p('<h3 class="ai-build-title">Building AI Knowledge Base</h3>');        
        htp.p('<p class="ai-build-subtitle">AI is analyzing your table structures, relationships, and data patterns to provide intelligent insights.</p>');        
        htp.p('<div class="ai-progress-container">');        
        htp.p('<div class="ai-progress-bar"><div id="wiz_progress_' || l_id || '" class="ai-progress-fill" style="width: 0%"></div></div>');        
        htp.p('<div class="ai-progress-text">');        
        htp.p('<span id="wiz_progress_status_' || l_id || '">Initializing...</span>');        
        htp.p('<span id="wiz_progress_pct_' || l_id || '" class="ai-progress-percent">0%</span>');        
        htp.p('</div></div>');        
        htp.p('<div id="wiz_log_' || l_id || '" class="ai-build-log"></div>');        
        htp.p('</div></div>');        
                
        -- Step 3 Content: Complete        
        htp.p('<div id="wiz_content3_' || l_id || '" class="ai-wizard-content">');        
        htp.p('<div class="ai-complete-container">');        
        htp.p('<div class="ai-complete-icon"><i class="fas fa-check"></i></div>');        
        htp.p('<h3 class="ai-complete-title">Configuration Complete!</h3>');        
        htp.p('<p class="ai-complete-subtitle">Your AI assistant is now ready to analyze your data and provide intelligent insights.</p>');        
        htp.p('<div class="ai-complete-stats">');        
        htp.p('<div class="ai-complete-stat"><div id="wiz_stat_tables_' || l_id || '" class="ai-complete-stat-value">0</div><div class="ai-complete-stat-label">Tables Configured</div></div>');        
        htp.p('<div class="ai-complete-stat"><div id="wiz_stat_cols_' || l_id || '" class="ai-complete-stat-value">0</div><div class="ai-complete-stat-label">Columns Analyzed</div></div>');        
        htp.p('<div class="ai-complete-stat"><div id="wiz_stat_ai_' || l_id || '" class="ai-complete-stat-value">0</div><div class="ai-complete-stat-label">AI Descriptions</div></div>');        
        htp.p('</div></div></div>');        
                
        htp.p('</div>'); -- End wizard body        
                
        -- Wizard Footer - New Design        
        htp.p('<div class="ai-wizard-footer">');        
        htp.p('<div id="wiz_ready_' || l_id || '" class="ai-ready-indicator"><span id="wiz_ready_count_' || l_id || '">0</span> tables ready for AI</div>');        
        htp.p('<div style="display:flex;gap:12px;">');        
        htp.p('<button type="button" id="wiz_back_' || l_id || '" class="ai-wizard-btn ai-wizard-btn-secondary" onclick="window.AID_' || l_id || '.wizardBack()" style="display:none;"><i class="fas fa-arrow-left"></i> Back</button>');        
        htp.p('<button type="button" id="wiz_next_' || l_id || '" class="ai-wizard-btn ai-wizard-btn-primary" onclick="window.AID_' || l_id || '.wizardNext()">Continue to Build Metadata</button>');        
        htp.p('</div></div>');        
                
        htp.p('</div></div>'); -- End wizard        
        -- =====================================================        
        -- END WIZARD MODAL        
        -- =====================================================        
        
        -- =====================================================        
        -- AI SETTINGS MODAL        
        -- =====================================================        
        htp.p('<div id="ai_settings_' || l_id || '" class="ai-settings-overlay" onclick="if(event.target===this) window.AID_' || l_id || '.closeAISettings()">');        
        htp.p('<div class="ai-settings-modal">');        
        -- Header        
        htp.p('<div class="ai-settings-header">');        
        htp.p('<div class="ai-settings-title">');        
        htp.p('<div class="ai-settings-title-icon"><i class="fas fa-robot"></i></div>');        
        htp.p('<div><div style="font-size:20px;">AI Configuration</div><div style="font-size:12px;opacity:0.7;font-weight:400;margin-top:2px;">Manage API settings</div></div>');        
        htp.p('</div>');        
        htp.p('<button type="button" class="ai-settings-close" onclick="window.AID_' || l_id || '.closeAISettings()"><i class="fas fa-times"></i></button>');        
        htp.p('</div>');        
        -- Body        
        htp.p('<div class="ai-settings-body">');        
        -- API Key Status        
        htp.p('<div id="ai_settings_status_' || l_id || '" class="ai-settings-status not-configured">');        
        htp.p('<span><i class="fas fa-exclamation-triangle"></i></span> API Key not configured');        
        htp.p('</div>');        
        -- API Key Field        
        htp.p('<div class="ai-settings-group">');        
        htp.p('<label class="ai-settings-label"><span class="ai-settings-label-icon"><i class="fas fa-key"></i></span> API Key</label>');        
        htp.p('<div class="ai-settings-key-wrapper">');        
        htp.p('<input type="password" id="ai_settings_key_' || l_id || '" class="ai-settings-input ai-settings-key-input" placeholder="Enter your API key..." autocomplete="off" oncopy="return false;" oncut="return false;">');        
        htp.p('<button type="button" class="ai-settings-key-toggle" onclick="window.AID_' || l_id || '.toggleKeyVisibility()" title="Show/Hide"><i class="fas fa-eye"></i></button>');        
        htp.p('</div>');        
        htp.p('<div class="ai-settings-input-hint">Your API key is encrypted and stored securely. Leave empty to keep existing key.</div>');        
        htp.p('</div>');        
        -- Model Field        
        htp.p('<div class="ai-settings-group">');        
        htp.p('<label class="ai-settings-label"><span class="ai-settings-label-icon"><i class="fas fa-brain"></i></span> AI Model</label>');        
        htp.p('<input type="text" id="ai_settings_model_' || l_id || '" class="ai-settings-input" placeholder="e.g., openai/gpt-oss-20b">');        
        htp.p('<div class="ai-settings-input-hint">The model identifier used for AI requests</div>');        
        htp.p('</div>');        
        -- API URL Field        
        htp.p('<div class="ai-settings-group">');        
        htp.p('<label class="ai-settings-label"><span class="ai-settings-label-icon"><i class="fas fa-globe"></i></span> API URL</label>');        
        htp.p('<input type="text" id="ai_settings_url_' || l_id || '" class="ai-settings-input" placeholder="https://api.example.com/v1/chat/completions">');        
        htp.p('<div class="ai-settings-input-hint">The endpoint URL for AI API calls</div>');        
        htp.p('</div>');        
        htp.p('</div>');        
        -- Footer        
        htp.p('<div class="ai-settings-footer">');        
        htp.p('<button type="button" class="ai-settings-btn ai-settings-btn-cancel" onclick="window.AID_' || l_id || '.closeAISettings()">Cancel</button>');        
        htp.p('<button type="button" id="ai_settings_save_' || l_id || '" class="ai-settings-btn ai-settings-btn-save" onclick="window.AID_' || l_id || '.saveAISettings()">Save Settings</button>');        
        htp.p('</div>');        
        htp.p('</div></div>');        
        -- =====================================================        
        -- END AI SETTINGS MODAL        
        -- =====================================================        
        
        -- =====================================================        
        -- EXTERNAL CONNECTION MANAGER MODAL        
        -- =====================================================        
        htp.p('<div id="ext_conn_modal_' || l_id || '" class="ai-ext-conn-modal" onclick="if(event.target===this) window.AID_' || l_id || '.closeExtConnModal()">');        
        htp.p('<div class="ai-ext-conn-container">');        
        htp.p('<div class="ai-ext-conn-header">');        
        htp.p('<div class="ai-ext-conn-title"><i class="fas fa-link"></i> External Database Connections</div>');        
        htp.p('<button type="button" class="ai-ext-conn-close" onclick="window.AID_' || l_id || '.closeExtConnModal()"><i class="fas fa-times"></i></button>');        
        htp.p('</div>');        
        htp.p('<div class="ai-ext-conn-body">');        
        
        -- Coming Soon Section        
        htp.p('<div class="ai-ext-conn-coming-soon">');        
        htp.p('<div class="ai-ext-conn-coming-soon-icon">');        
        htp.p('<i class="fas fa-database"></i>');        
        htp.p('<span class="ai-ext-conn-coming-soon-badge">Coming Soon</span>');        
        htp.p('</div>');        
        htp.p('<div class="ai-ext-conn-coming-soon-title">External Connections</div>');        
        htp.p('<div class="ai-ext-conn-coming-soon-subtitle">We''re working on something powerful! Soon you''ll be able to connect to external databases and query them directly through Asklyze.</div>');        
        htp.p('<div class="ai-ext-conn-coming-soon-features">');        
        htp.p('<div class="ai-ext-conn-coming-soon-feature"><i class="fas fa-plug"></i><span>Connect to Oracle, PostgreSQL, MySQL & more</span></div>');        
        htp.p('<div class="ai-ext-conn-coming-soon-feature"><i class="fas fa-shield-alt"></i><span>Secure encrypted connections</span></div>');        
        htp.p('<div class="ai-ext-conn-coming-soon-feature"><i class="fas fa-brain"></i><span>AI-powered cross-database analytics</span></div>');        
        htp.p('<div class="ai-ext-conn-coming-soon-feature"><i class="fas fa-sync-alt"></i><span>Real-time data synchronization</span></div>');        
        htp.p('</div>');        
        htp.p('</div>'); -- End coming soon section        
        
        htp.p('</div>'); -- End body        
        htp.p('</div></div>');        
        -- =====================================================        
        -- END EXTERNAL CONNECTION MODAL        
        -- =====================================================        
        
        -- SIDEBAR        
        htp.p('<div id="sidebar_' || l_id || '" class="aid-sidebar">');        
        -- Header with logo and toggle button        
        htp.p('<div class="aid-sidebar-header">');        
        htp.p('<div class="aid-sidebar-logo"><img src="https://i.ibb.co/Lzpmw0YZ/Asklyze-IN-Line-Purple.png" alt="Asklyze" /></div>');        
        htp.p('<button type="button" class="aid-sidebar-toggle-btn" onclick="window.AID_' || l_id || '.toggleSidebar()" title="Toggle sidebar">');        
        htp.p('<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"/></svg>');        
        htp.p('</button>');        
        htp.p('</div>');        
        htp.p('<button type="button" class="aid-new-chat-btn" onclick="window.AID_' || l_id || '.newChat()"><span class="btn-icon">+</span><span class="btn-text">New</span></button>');        
        htp.p('<div class="aid-search-box">');        
        htp.p('<input type="text" id="search_history_' || l_id || '" class="aid-search-input" placeholder="Search conversations..." onkeyup="window.AID_' || l_id || '.searchHistory(this.value)">');        
        htp.p('</div>');        
        htp.p('<div class="aid-tabs-container">');        
        htp.p('<button type="button" id="tab_all_' || l_id || '" class="aid-hist-tab active" onclick="window.AID_' || l_id || '.setHistoryFilter(''all'')"><span class="tab-icon"><i class="fas fa-comments"></i></span><span class="tab-text">All</span></button>');        
        htp.p('<button type="button" id="tab_reports_' || l_id || '" class="aid-hist-tab" onclick="window.AID_' || l_id || '.setHistoryFilter(''reports'')"><span class="tab-icon"><i class="fas fa-clipboard-list"></i></span><span class="tab-text">Reports</span></button>');        
        htp.p('<button type="button" id="tab_dashboards_' || l_id || '" class="aid-hist-tab" onclick="window.AID_' || l_id || '.setHistoryFilter(''dashboards'')"><span class="tab-icon"><i class="fas fa-chart-line"></i></span><span class="tab-text">Dashboards</span></button>');        
        htp.p('<button type="button" id="tab_fav_' || l_id || '" class="aid-hist-tab" onclick="window.AID_' || l_id || '.setHistoryFilter(''fav'')"><span class="tab-icon"><i class="fas fa-star"></i></span><span class="tab-text">Favorites</span></button>');        
        htp.p('</div>');        
        htp.p('<div id="chat_list_' || l_id || '" class="aid-chat-list"><div class="aid-loading-history">Loading...</div></div>');        
        htp.p('<div class="aid-sidebar-footer">');        
        htp.p('<div class="aid-settings-wrapper">');        
        htp.p('<button type="button" class="aid-settings-btn" onclick="window.AID_' || l_id || '.toggleSettingsDropdown(event)"><span class="btn-icon"><i class="fas fa-cog"></i></span><span class="btn-text">Settings</span></button>');        
        htp.p('<div id="settings_dropdown_' || l_id || '" class="aid-settings-dropdown">');        
        htp.p('<div class="aid-settings-dropdown-item" style="cursor:default;"><i class="fas fa-user"></i> ' || apex_escape.html(NVL(v('APP_USER'), apex_application.g_user)) || '</div>');        
        htp.p('<div class="aid-settings-divider" role="separator"></div>');        
        htp.p('<button type="button" class="aid-settings-dropdown-item" onclick="window.AID_' || l_id || '.openWizard(); window.AID_' || l_id || '.closeSettingsDropdown();"><i class="fas fa-database"></i> Data Settings</button>');        
        -- htp.p('<button type="button" class="aid-settings-dropdown-item" onclick="window.AID_' || l_id || '.openAISettings(); window.AID_' || l_id || '.closeSettingsDropdown();"><i class="fas fa-robot"></i> AI Settings</button>');        
        htp.p('<button type="button" class="aid-settings-dropdown-item danger" onclick="window.AID_' || l_id || '.clearHistory(); window.AID_' || l_id || '.closeSettingsDropdown();"><i class="fas fa-trash"></i> Clear All History</button>');        
        htp.p('<div class="aid-settings-divider" role="separator"></div>');        
        htp.p('<a class="aid-settings-dropdown-item" href="' || apex_escape.html_attribute(v('LOGOUT_URL')) || '"><i class="fas fa-right-from-bracket"></i> Logout</a>');        
        htp.p('</div>');        
        htp.p('</div>');        
        htp.p('<button type="button" id="theme_toggle_' || l_id || '" class="aid-theme-icon-btn" onclick="window.AID_' || l_id || '.toggleTheme()" title="Toggle theme"><i id="theme_icon_' || l_id || '" class="fas fa-moon"></i></button>');        
        htp.p('</div></div>');        
        
        -- MAIN CONTENT        
        htp.p('<div class="aid-main-content">');        
        
        -- Error div        
        htp.p('<div id="err_' || l_id || '" class="aid-err"></div>');        
        
        -- AI Settings Warning Banner        
        htp.p('<div id="ai_settings_warning_' || l_id || '" class="ai-settings-warning">');        
        htp.p('<div class="ai-settings-warning-icon"><i class="fas fa-exclamation-triangle"></i></div>');        
        htp.p('<div class="ai-settings-warning-content">');        
        htp.p('<div class="ai-settings-warning-title">AI Configuration Required</div>');        
        htp.p('<div class="ai-settings-warning-text">Please configure your API key to enable AI features. Click the button to open settings.</div>');        
        htp.p('</div>');        
        htp.p('<button type="button" class="ai-settings-warning-btn" onclick="window.AID_' || l_id || '.openAISettings()">Configure AI Settings</button>');        
        htp.p('</div>');        
        
        -- Data Sources Warning Banner        
        htp.p('<div id="data_sources_warning_' || l_id || '" class="data-sources-warning">');        
        htp.p('<div class="data-sources-warning-icon"><i class="fas fa-database"></i></div>');        
        htp.p('<div class="data-sources-warning-content">');        
        htp.p('<div class="data-sources-warning-title">Data Sources Configuration Required</div>');        
        htp.p('<div class="data-sources-warning-text">Please configure your data sources and add tables to enable AI suggestions. Click the button to open settings.</div>');        
        htp.p('</div>');        
        htp.p('<button type="button" class="data-sources-warning-btn" onclick="window.AID_' || l_id || '.openWizard()">Configure Data Settings</button>');        
        htp.p('</div>');        
        
        -- Report Skeleton Container        
        htp.p('<div id="skeleton_report_' || l_id || '" class="aid-skeleton-container">');        
        htp.p('<div class="skel-report-title skeleton"></div>');        
        htp.p('<div class="skel-kpis-row">');        
        FOR i IN 1..4 LOOP        
            htp.p('<div class="skel-kpi-card"><div class="skel-kpi-header skeleton"></div><div class="skel-kpi-body"><div class="skel-kpi-value skeleton"></div><div class="skel-kpi-icon skeleton"></div></div></div>');        
        END LOOP;        
        htp.p('</div>');        
        htp.p('<div class="skel-tabs"><div class="skel-tab skeleton"></div><div class="skel-tab skeleton"></div><div class="skel-tab skeleton"></div></div>');        
        htp.p('<div class="skel-table-container"><div class="skel-table-toolbar"><div class="skel-search skeleton"></div><div class="skel-export-btn skeleton"></div></div><div class="skel-table-header skeleton"></div>');        
        FOR i IN 1..6 LOOP        
            htp.p('<div class="skel-table-row"><div class="skel-table-cell skeleton"></div><div class="skel-table-cell skeleton"></div><div class="skel-table-cell skeleton"></div><div class="skel-table-cell skeleton"></div></div>');        
        END LOOP;        
        htp.p('</div></div>');        
                
        -- Dashboard Skeleton Container        
        htp.p('<div id="skeleton_dashboard_' || l_id || '" class="aid-skeleton-container">');        
        htp.p('<div class="skel-dash-title skeleton"></div>');        
        htp.p('<div class="skel-dash-kpis">');        
        FOR i IN 1..4 LOOP        
            htp.p('<div class="skel-dash-kpi"><div class="skel-dash-kpi-header skeleton"></div><div class="skel-dash-kpi-body"><div class="skel-dash-kpi-main"><div class="skel-dash-kpi-value skeleton"></div><div class="skel-dash-kpi-trend skeleton"></div></div><div class="skel-dash-kpi-icon skeleton"></div></div></div>');        
        END LOOP;        
        htp.p('</div>');        
        htp.p('<div class="skel-dash-charts">');        
        htp.p('<div class="skel-dash-chart colspan-2"><div class="skel-dash-chart-header"><div class="skel-dash-chart-title skeleton"></div></div><div class="skel-dash-chart-body">');        
        FOR i IN 1..6 LOOP htp.p('<div class="skel-bar skeleton"></div>'); END LOOP;        
        htp.p('</div></div>');        
        htp.p('<div class="skel-dash-chart"><div class="skel-dash-chart-header"><div class="skel-dash-chart-title skeleton"></div></div><div class="skel-pie-container"><div class="skel-pie skeleton"></div></div></div>');        
        htp.p('<div class="skel-dash-chart"><div class="skel-dash-chart-header"><div class="skel-dash-chart-title skeleton"></div></div><div class="skel-line-container">');        
        FOR i IN 1..4 LOOP htp.p('<div class="skel-line skeleton"></div>'); END LOOP;        
        htp.p('</div></div>');        
        htp.p('<div class="skel-dash-chart"><div class="skel-dash-chart-header"><div class="skel-dash-chart-title skeleton"></div></div><div class="skel-dash-chart-body">');        
        FOR i IN 1..5 LOOP htp.p('<div class="skel-bar skeleton"></div>'); END LOOP;        
        htp.p('</div></div>');        
        htp.p('<div class="skel-dash-chart"><div class="skel-dash-chart-header"><div class="skel-dash-chart-title skeleton"></div></div><div class="skel-pie-container"><div class="skel-pie skeleton"></div></div></div>');        
        htp.p('</div></div>');        
        
        -- Dashboard View Container        
        htp.p('<div id="dashboard_view_' || l_id || '" class="aid-dashboard-view">');        
        htp.p('<div id="dash_title_' || l_id || '" class="aid-dash-title">');        
        htp.p('<span class="aid-dash-title-text"></span>');        
        htp.p('<button type="button" id="dash_export_btn_' || l_id || '" class="aid-dash-export-btn" onclick="window.AID_' || l_id || '.exportDashboardPDF()">');        
        htp.p('<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" /></svg>');        
        htp.p('Export PDF</button>');        
        htp.p('</div>');        
        htp.p('<div id="dash_kpis_' || l_id || '" class="aid-dash-kpis"></div>');        
        htp.p('<div id="dash_charts_' || l_id || '" class="aid-dash-charts grid-stack"></div>');        
        htp.p('</div>');        
                
        -- Report View Container        
        htp.p('<div id="report_view_' || l_id || '" class="aid-report-view">');        
        htp.p('<div id="res_area_' || l_id || '" class="aid-results-area">');        
        htp.p('<div id="content_wrapper_' || l_id || '" class="ai-flex-col" style="display:none;">');        
        htp.p('<div id="report_title_' || l_id || '" class="ai-report-title-bar" style="display:none"></div>');        
        htp.p('<div id="kpis_' || l_id || '" class="aid-kpis"></div>');        
        htp.p('<div class="ai-tabs" id="tabs_' || l_id || '">');        
        htp.p('<button type="button" class="ai-tab-btn active" onclick="window.AID_' || l_id || '.switchTab(''report'')"><i class="fas fa-clipboard-list"></i> Report</button>');        
        htp.p('<button type="button" class="ai-tab-btn" onclick="window.AID_' || l_id || '.switchTab(''pivot'')"><i class="fas fa-sync-alt"></i> Pivot</button>');        
        htp.p('<button type="button" class="ai-tab-btn" onclick="window.AID_' || l_id || '.switchTab(''chart'')"><i class="fas fa-chart-line"></i> Chart</button>');        
        htp.p('<button type="button" class="ai-tab-btn" onclick="window.AID_' || l_id || '.switchTab(''sql'')"><i class="fas fa-code"></i> SQL</button>');        
        htp.p('</div>');        
        htp.p('<div id="view_report_' || l_id || '" class="ai-view-content active"><div id="dyn_content_' || l_id || '" class="ai-flex-col"></div></div>');        
        htp.p('<div id="view_pivot_' || l_id || '" class="ai-view-content">');        
        htp.p('<div id="pivot_recommendation_' || l_id || '" class="ai-pivot-recommendation" style="display:none;">');        
        htp.p('<div class="ai-pivot-recommendation-icon"><i class="fas fa-lightbulb"></i></div>');        
        htp.p('<div class="ai-pivot-recommendation-text">');        
        htp.p('<div class="ai-pivot-recommendation-title">AI Recommendation</div>');        
        htp.p('<div id="pivot_reason_' || l_id || '" class="ai-pivot-recommendation-desc"></div>');        
        htp.p('</div>');        
        htp.p('<button type="button" class="ai-pivot-recommendation-btn" onclick="window.AID_' || l_id || '.applyPivotConfig()">Apply Suggested Config</button>');        
        htp.p('</div>');        
        htp.p('<div class="ai-pivot-container">');        
        htp.p('<div class="ai-pivot-toolbar">');        
        htp.p('<div class="ai-pivot-title"><i class="fas fa-sync-alt"></i> Pivot Analysis</div>');        
        htp.p('</div>');        
        htp.p('<div id="pivot_container_' || l_id || '" class="ai-pivot-content"></div>');        
        htp.p('</div></div>');        
        htp.p('<div id="view_chart_' || l_id || '" class="ai-view-content ai-chart-view-wrapper">');        
        htp.p('<div class="ai-chart-main-area"><div id="chart_container_' || l_id || '" class="ai-chart-container"></div></div>');        
        htp.p('<div class="ai-chart-type-panel">');        
        htp.p('<div class="ai-chart-type-panel-header"><h3>Chart Types</h3><span>Select a visualization</span></div>');        
        htp.p('<div id="report_chart_types_' || l_id || '" class="ai-report-chart-types"></div>');        
        htp.p('</div></div>');        
        htp.p('<div id="view_sql_' || l_id || '" class="ai-view-content">');        
        htp.p('<div class="ai-sql-container">');        
        htp.p('<div class="ai-sql-toolbar">');        
        htp.p('<button type="button" id="sql_copy_btn_' || l_id || '" class="ai-sql-copy-btn" onclick="window.AID_' || l_id || '.copySql(); return false;"><i class="fas fa-copy"></i> Copy</button>');        
        htp.p('<button type="button" class="ai-sql-run-btn" onclick="window.AID_' || l_id || '.runSql()"><i class="fas fa-play"></i> Run & Save Query</button>');        
        htp.p('</div>');        
        htp.p('<div id="sql_error_' || l_id || '" class="ai-sql-compile-result"></div>');        
        htp.p('<textarea id="sql_editor_' || l_id || '"></textarea>');        
        htp.p('</div></div></div></div></div>');        
        
        -- KPI Edit Modal        
        htp.p('<div id="kpi_edit_overlay_' || l_id || '" class="ai-kpi-edit-overlay">');        
        htp.p('<div class="ai-kpi-edit-modal">');        
        htp.p('<div class="ai-kpi-edit-header"><h3>Edit KPI</h3><button type="button" class="ai-kpi-edit-close" onclick="window.AID_' || l_id || '.closeKpiEdit()"><i class="fas fa-times"></i></button></div>');        
        htp.p('<div class="ai-kpi-edit-body">');        
        htp.p('<div class="ai-kpi-edit-field"><label>KPI Title</label><input type="text" id="kpi_edit_title_' || l_id || '" class="ai-kpi-edit-title" placeholder="Enter KPI title"></div>');        
        htp.p('<div class="ai-kpi-edit-field"><label>SQL Query (must return a single numeric value)</label><textarea id="kpi_edit_sql_' || l_id || '" class="ai-kpi-edit-sql" placeholder="SELECT COUNT(*) FROM table_name"></textarea></div>');        
        htp.p('<div id="kpi_edit_error_' || l_id || '" class="ai-sql-compile-result"></div>');        
        htp.p('</div>');        
        htp.p('<div class="ai-kpi-edit-footer">');        
        htp.p('<button type="button" class="ai-kpi-edit-btn-cancel" onclick="window.AID_' || l_id || '.closeKpiEdit()">Cancel</button>');        
        htp.p('<button type="button" id="kpi_edit_save_' || l_id || '" class="ai-kpi-edit-btn-save" onclick="window.AID_' || l_id || '.saveKpiEdit()"><i class="fas fa-save"></i> Save Changes</button>');        
        htp.p('</div></div></div>');        
        
        -- Dashboard KPI Edit Modal - Modern Design        
        htp.p('<div id="dash_kpi_edit_overlay_' || l_id || '" class="ai-dash-kpi-edit-overlay">');        
        htp.p('<div class="ai-dash-kpi-edit-modal">');        
        -- Header with gradient        
        htp.p('<div class="ai-dash-kpi-edit-header">');        
        htp.p('<div class="ai-dash-kpi-edit-header-title">');        
        htp.p('<div class="ai-dash-kpi-edit-header-icon"><i class="fas fa-chart-bar"></i></div>');        
        htp.p('<div><h3>Edit KPI</h3><div class="ai-dash-kpi-edit-header-subtitle" id="dash_kpi_edit_subtitle_' || l_id || '">Configure your KPI metrics</div></div>');        
        htp.p('</div>');        
        htp.p('<button type="button" class="ai-dash-kpi-edit-close" onclick="window.AID_' || l_id || '.closeDashKpiEdit()"><i class="fas fa-times"></i></button>');        
        htp.p('</div>');        
        -- Body        
        htp.p('<div class="ai-dash-kpi-edit-body">');        
        -- Title Input        
        htp.p('<div class="ai-dash-kpi-edit-field">');        
        htp.p('<label><span class="field-icon"><i class="fas fa-tag"></i></span> KPI Title <small>Display name for this metric</small></label>');        
        htp.p('<input type="text" id="dash_kpi_edit_title_' || l_id || '" placeholder="e.g., Total Revenue, Active Users, Order Count...">');        
        htp.p('</div>');        
        -- Value SQL Section        
        htp.p('<div class="ai-dash-kpi-sql-section">');        
        htp.p('<div class="ai-dash-kpi-sql-header">');        
        htp.p('<h4><span class="sql-icon"><i class="fas fa-chart-bar"></i></span> Value SQL<small>Query must return a single numeric value</small></h4>');        
        htp.p('<div class="ai-dash-kpi-sql-header-actions">');        
        htp.p('<button type="button" id="dash_kpi_test_value_btn_' || l_id || '" class="ai-dash-kpi-test-btn" onclick="window.AID_' || l_id || '.testDashKpiValueSql()"><i class="fas fa-play"></i> Test</button>');        
        htp.p('</div></div>');        
        htp.p('<div class="ai-dash-kpi-sql-body">');        
        htp.p('<div class="ai-dash-kpi-sql-editor-wrap"><textarea id="dash_kpi_edit_value_sql_' || l_id || '"></textarea></div>');        
        htp.p('<div id="dash_kpi_value_sql_result_' || l_id || '" class="ai-dash-kpi-sql-result"></div>');        
        htp.p('<div id="dash_kpi_value_preview_' || l_id || '" class="ai-dash-kpi-test-preview"></div>');        
        htp.p('</div></div>');        
        -- Trend SQL Section        
        htp.p('<div class="ai-dash-kpi-sql-section">');        
        htp.p('<div class="ai-dash-kpi-sql-header">');        
        htp.p('<h4><span class="sql-icon"><i class="fas fa-chart-line"></i></span> Trend SQL<small>Optional - calculates % change vs previous period</small></h4>');        
        htp.p('<div class="ai-dash-kpi-sql-header-actions">');        
        htp.p('<button type="button" id="dash_kpi_test_trend_btn_' || l_id || '" class="ai-dash-kpi-test-btn" onclick="window.AID_' || l_id || '.testDashKpiTrendSql()"><i class="fas fa-play"></i> Test</button>');        
        htp.p('</div></div>');        
        htp.p('<div class="ai-dash-kpi-sql-body">');        
        htp.p('<div class="ai-dash-kpi-sql-editor-wrap"><textarea id="dash_kpi_edit_trend_sql_' || l_id || '"></textarea></div>');        
        htp.p('<div id="dash_kpi_trend_sql_result_' || l_id || '" class="ai-dash-kpi-sql-result"></div>');        
        htp.p('<div id="dash_kpi_trend_preview_' || l_id || '" class="ai-dash-kpi-test-preview"></div>');        
        htp.p('</div></div>');        
        htp.p('</div>');        
        -- Footer        
        htp.p('<div class="ai-dash-kpi-edit-footer">');        
        htp.p('<div class="ai-dash-kpi-edit-footer-hint"><i class="fas fa-lightbulb"></i> Test your SQL before saving</div>');        
        htp.p('<div class="ai-dash-kpi-edit-footer-actions">');        
        htp.p('<button type="button" class="ai-dash-kpi-edit-btn-cancel" onclick="window.AID_' || l_id || '.closeDashKpiEdit()">Cancel</button>');        
        htp.p('<button type="button" id="dash_kpi_edit_save_' || l_id || '" class="ai-dash-kpi-edit-btn-save" onclick="window.AID_' || l_id || '.saveDashKpiEdit()"><i class="fas fa-check"></i> Save & Compile</button>');        
        htp.p('</div></div></div></div>');        
        
        -- Interaction Container        
        htp.p('<div id="interaction_' || l_id || '" class="ai-interaction-container centered">');        
        htp.p('<div id="welcome_' || l_id || '" class="ai-welcome-text">');        
        htp.p('<h2>Hi <span>' || apex_escape.html(apex_application.g_user) || '</span>, how can I help you?</h2>');        
        htp.p('</div>');        
        htp.p('<div id="suggestions_' || l_id || '" class="ai-suggestions-container"></div>');        
        
        -- Schema Selector for Chat        
        htp.p('<div class="ai-chat-schema-wrap" id="chat_schema_wrap_' || l_id || '">');        
        htp.p('<span class="ai-chat-schema-label"><i class="fas fa-database"></i> Schema:</span>');        
        htp.p('<select id="chat_schema_' || l_id || '" class="ai-chat-schema-select" onchange="window.AID_' || l_id || '.onSchemaChange()">');        
        htp.p('</select>');        
        htp.p('</div>');        
        
        htp.p('<div class="ai-mode-toggle-bar">');        
        htp.p('<button type="button" id="mode_report_' || l_id || '" class="ai-mode-btn report-mode active" onclick="window.AID_' || l_id || '.setMode(''report'')">');        
        htp.p('<span><i class="fas fa-chart-bar"></i></span> Report</button>');        
        htp.p('<button type="button" id="mode_dashboard_' || l_id || '" class="ai-mode-btn dashboard-mode" onclick="window.AID_' || l_id || '.setMode(''dashboard'')">');        
        htp.p('<span><i class="fas fa-chart-line"></i></span> Dashboard</button>');        
        htp.p('</div>');        
                
        htp.p('<div class="ai-search-wrapper">');        
        htp.p('<div id="active_cat_' || l_id || '" class="ai-active-cat-chip">');        
        htp.p('<span id="cat_text_' || l_id || '">General</span>');        
        htp.p('<span class="ai-cat-remove" onclick="window.AID_' || l_id || '.clearCat()"><i class="fas fa-times"></i></span>');        
        htp.p('</div>');        
        htp.p('<textarea id="inp_' || l_id || '" class="ai-input" rows="1" placeholder="Ask anything about your data..."></textarea>');        
        htp.p('<button type="button" class="ai-send-btn" onclick="window.AID_' || l_id || '.go()">');        
        htp.p('<svg viewBox="0 0 24 24" style="width:20px;height:20px;fill:white;"><path d="M2.01 21L23 12 2.01 3 2 10l15 2-15 2z"/></svg>');        
        htp.p('</button>');        
        -- Voice Input Button        
        htp.p('<div class="ai-voice-wrapper">');        
        htp.p('<button type="button" id="voice_btn_' || l_id || '" class="ai-voice-btn" onclick="window.AID_' || l_id || '.toggleVoice()" title="Voice input - click to speak">');        
        htp.p('<svg viewBox="0 0 24 24"><path d="M12 14c1.66 0 3-1.34 3-3V5c0-1.66-1.34-3-3-3S9 3.34 9 5v6c0 1.66 1.34 3 3 3zm-1-9c0-.55.45-1 1-1s1 .45 1 1v6c0 .55-.45 1-1 1s-1-.45-1-1V5zm6 6c0 2.76-2.24 5-5 5s-5-2.24-5-5H5c0 3.53 2.61 6.43 6 6.92V21h2v-3.08c3.39-.49 6-3.39 6-6.92h-2z"/></svg>');        
        htp.p('</button>');        
        htp.p('<div id="voice_status_' || l_id || '" class="ai-voice-status">Click to speak</div>');        
        htp.p('</div>');        
        htp.p('</div>');        
                
        htp.p('<div class="ai-auto-detect-hint"><i class="fas fa-lightbulb"></i> AI auto-detects intent. Keywords: dashboard, executive, overview, KPI - Dashboard mode</div>');        
        htp.p('</div>');        
                
        htp.p('</div></div>');        
        
        
                -- Chart Edit Modal        
        htp.p('<div id="chart_edit_' || l_id || '" class="ai-chart-edit-overlay">');        
        htp.p('<div class="ai-chart-edit-modal">');        
        
        -- Header        
        htp.p('<div class="ai-chart-edit-header">');        
        htp.p('<div class="ai-chart-edit-title"><div class="ai-chart-edit-title-icon"><i class="fas fa-chart-bar"></i></div> Edit Chart</div>');        
        htp.p('<button type="button" class="ai-chart-edit-close" onclick="window.AID_' || l_id || '.closeChartEdit()"><i class="fas fa-times"></i></button>');        
        htp.p('</div>');        
        
        -- Body with two columns        
        htp.p('<div class="ai-chart-edit-body">');        
        
        -- Left Panel: Title + Chart Types        
        htp.p('<div class="ai-edit-left-panel">');        
        htp.p('<div class="ai-edit-form-group">');        
        htp.p('<label class="ai-edit-label">Chart Title</label>');        
        htp.p('<input type="text" id="chart_edit_title_' || l_id || '" class="ai-edit-input" placeholder="Enter chart title...">');        
        htp.p('</div>');        
        htp.p('<div class="ai-edit-form-group" style="flex:1;">');        
        htp.p('<label class="ai-edit-label">Chart Type</label>');        
        htp.p('<div id="chart_type_grid_' || l_id || '" class="ai-chart-type-grid"></div>');        
        htp.p('</div>');        
        htp.p('</div>');        
        
        -- Right Panel: Tabs (Chart Preview / SQL Query)        
        htp.p('<div class="ai-edit-right-panel">');        
        htp.p('<div class="ai-edit-tabs">');        
        htp.p('<button type="button" class="ai-edit-tab active" onclick="window.AID_' || l_id || '.switchEditTab(''preview'')">Chart Preview</button>');        
        htp.p('<button type="button" class="ai-edit-tab" onclick="window.AID_' || l_id || '.switchEditTab(''sql'')">SQL Query</button>');        
        htp.p('</div>');        
        
        -- Chart Preview Tab Content        
        htp.p('<div id="edit_tab_preview_' || l_id || '" class="ai-edit-tab-content active">');        
        htp.p('<div class="ai-chart-preview-container">');        
        htp.p('<div id="chart_preview_' || l_id || '" class="ai-chart-preview-body">');        
        htp.p('<div class="ai-preview-loading">Select a chart type to preview</div>');        
        htp.p('</div>');        
        htp.p('</div>');        
        htp.p('</div>');        
        
        -- SQL Query Tab Content        
        htp.p('<div id="edit_tab_sql_' || l_id || '" class="ai-edit-tab-content">');        
        htp.p('<div class="ai-sql-edit-container">');        
        htp.p('<div class="ai-sql-edit-area"><textarea id="chart_sql_editor_' || l_id || '"></textarea></div>');        
        htp.p('<div id="chart_sql_error_' || l_id || '" class="ai-sql-compile-result"></div>');        
        htp.p('<div id="chart_sql_preview_' || l_id || '" class="ai-sql-data-preview"></div>');        
        htp.p('</div>');        
        htp.p('</div>');        
        
        htp.p('</div>'); -- End right panel        
        htp.p('</div>'); -- End body        
        
        -- Footer        
        htp.p('<div class="ai-chart-edit-footer">');        
        htp.p('<div class="ai-edit-footer-left">');        
        htp.p('<button type="button" class="ai-edit-btn ai-edit-btn-cancel" onclick="window.AID_' || l_id || '.closeChartEdit()">Cancel</button>');        
        htp.p('</div>');        
        htp.p('<div class="ai-edit-footer-right">');        
        htp.p('<button type="button" id="chart_test_sql_btn_' || l_id || '" class="ai-edit-btn ai-edit-btn-test" onclick="window.AID_' || l_id || '.testChartSql()">Test SQL</button>');        
        htp.p('<button type="button" id="chart_delete_btn_' || l_id || '" class="ai-edit-btn ai-edit-btn-danger" onclick="window.AID_' || l_id || '.deleteChart()">Delete Chart</button>');        
        htp.p('<button type="button" id="chart_save_btn_' || l_id || '" class="ai-edit-btn ai-edit-btn-save" onclick="window.AID_' || l_id || '.saveChartEdit()">Save &amp; Compile</button>');        
        htp.p('</div>');        
        htp.p('</div>');        
        
        -- Close Chart Edit Modal        
        htp.p('</div></div>');        
        
        -- Add Chart Modal        
        htp.p('<div id="add_chart_' || l_id || '" class="ai-add-chart-overlay">');        
        htp.p('<div class="ai-add-chart-modal">');        
        htp.p('<div class="ai-add-chart-header">');        
        htp.p('<div class="ai-add-chart-title"><div class="ai-add-chart-title-icon"><i class="fas fa-plus"></i></div> Add New Chart</div>');        
        htp.p('<button type="button" class="ai-add-chart-close" onclick="window.AID_' || l_id || '.closeAddChart()"><i class="fas fa-times"></i></button>');        
        htp.p('</div>');        
        htp.p('<div class="ai-add-chart-body">');        
        htp.p('<div class="ai-edit-form-group">');        
        htp.p('<label class="ai-edit-label">What would you like to visualize?</label>');        
        htp.p('<textarea id="add_chart_question_' || l_id || '" class="ai-add-chart-question" placeholder="e.g., Show monthly sales by region, Display top 10 customers by revenue..."></textarea>');        
        htp.p('</div>');        
        htp.p('<div class="ai-edit-form-group">');        
        htp.p('<label class="ai-edit-label">Chart Type</label>');        
        htp.p('<div id="add_chart_types_' || l_id || '" class="ai-add-chart-types"></div>');        
        htp.p('</div>');        
        htp.p('</div>');        
        htp.p('<div class="ai-add-chart-footer">');        
        htp.p('<button type="button" class="ai-add-chart-btn ai-add-chart-btn-cancel" onclick="window.AID_' || l_id || '.closeAddChart()">Cancel</button>');        
        htp.p('<button type="button" id="add_chart_btn_' || l_id || '" class="ai-add-chart-btn ai-add-chart-btn-generate" onclick="window.AID_' || l_id || '.generateNewChart()">Generate Chart</button>');        
        htp.p('</div>');        
        htp.p('</div></div>');        
     
                -- JS Init (external file)     
        htp.p('<script type="text/javascript">');     
        htp.p('window.ASKLYZE_UI_CONFIG = window.ASKLYZE_UI_CONFIG || [];');     
        htp.p('window.ASKLYZE_UI_CONFIG.push({id: "' || l_id || '", ajax: "' || l_ajax || '"});');     
        htp.p('if (window.ASKLYZE_UI_INIT) { window.ASKLYZE_UI_INIT(); }');     
        htp.p('</script>');      
             
    END render_dashboard;        
        
-- =====================================================================================       
-- AJAX HANDLER - CLOUD VERSION       
-- =====================================================================================       
       
PROCEDURE ajax_handler(       
    p_region IN apex_plugin.t_region,       
    p_plugin IN apex_plugin.t_plugin,       
    p_param IN apex_plugin.t_region_ajax_param,       
    p_result IN OUT NOCOPY apex_plugin.t_region_ajax_result       
) IS       
    l_act VARCHAR2(50) := apex_application.g_x01;       
    l_p1 VARCHAR2(4000) := apex_application.g_x02;       
    l_p2 VARCHAR2(32767) := apex_application.g_x03;       
    l_p3 VARCHAR2(32767) := apex_application.g_x04;       
    l_p4 VARCHAR2(4000) := apex_application.g_x05;       
    l_p5 VARCHAR2(32767) := apex_application.g_x06;       
    l_current_schema VARCHAR2(128);       
    l_out CLOB;       
    l_validation CLOB;       
    l_query_id NUMBER;       
    l_context CLOB;       
    l_conn_mode VARCHAR2(20);      
    l_schema_limit NUMBER; 
    l_allowed_schema VARCHAR2(128); 
    l_req_schema VARCHAR2(128); 
    l_enabled_cnt NUMBER;      
BEGIN       
    -- Set JSON header       
    owa_util.mime_header('application/json', FALSE);       
    owa_util.http_header_close;       
       
    l_current_schema := NVL(apex_application.g_flow_owner, USER);       
          
    -- Get connection mode      
    BEGIN      
        SELECT config_value INTO l_conn_mode FROM ASKLYZE_CLOUD_CONFIG WHERE config_key = 'CONNECTION_MODE';      
    EXCEPTION WHEN OTHERS THEN l_conn_mode := 'REMOTE'; END;      
       
    -- Enforce schema limit (cloud plan) 
    BEGIN 
        l_schema_limit := ASKLYZE_CLOUD_CONNECTOR_PKG.GET_ENFORCED_LIMIT('COUNT_SCHEMA'); 
    EXCEPTION WHEN OTHERS THEN l_schema_limit := NULL; END; 

    -- Determine how many schemas are configured/enabled locally 
    BEGIN 
        SELECT COUNT(*) INTO l_enabled_cnt 
        FROM asklyze_catalog_schemas 
        WHERE org_id = 1 AND is_enabled = 'Y'; 
    EXCEPTION WHEN OTHERS THEN 
        l_enabled_cnt := 0; 
    END; 



-- Determine requested schema for schema-dependent actions (used for global tenant enforcement)
l_req_schema := NULL;
IF l_act = 'ADD_SCHEMA' THEN
    l_req_schema := NULLIF(TRIM(SUBSTR(l_p1, 1, 128)), '');
ELSIF l_act IN ('CAT_LIST','CAT_APPLY','CAT_AI_BATCH','CAT_UPDATE_DESC','TABLE_MENTION','DEL_SCHEMA','SET_DEFAULT_SCHEMA','REFRESH_SCHEMA') THEN
    l_req_schema := NVL(NULLIF(TRIM(SUBSTR(l_p1, 1, 128)), ''), l_current_schema);
ELSIF l_act = 'GENERATE' THEN
    l_req_schema := NVL(NULLIF(TRIM(SUBSTR(l_p2, 1, 128)), ''), l_current_schema);
END IF;

-- Global schema limit enforcement happens in cloud (per tenant), not locally.
-- This call registers the schema usage and lets the cloud reject new schemas when COUNT_SCHEMA is exceeded.
IF l_req_schema IS NOT NULL
   AND l_act IN ('ADD_SCHEMA','GENERATE','CAT_LIST','CAT_APPLY','CAT_AI_BATCH','CAT_UPDATE_DESC','TABLE_MENTION','DEL_SCHEMA','SET_DEFAULT_SCHEMA','REFRESH_SCHEMA') THEN
    DECLARE
        l_v    VARCHAR2(10);
        l_st   VARCHAR2(50);
        l_code VARCHAR2(50);
        l_msg  VARCHAR2(2000);
    BEGIN
        l_validation := ASKLYZE_CLOUD_CONNECTOR_PKG.VALIDATE_SUBSCRIPTION_SCHEMA(l_req_schema);
        l_v  := JSON_VALUE(l_validation, '$.valid');
        l_st := JSON_VALUE(l_validation, '$.status');

        IF l_v != 'true' OR l_st NOT IN ('ACTIVE','TRIAL') THEN
            l_code := NVL(JSON_VALUE(l_validation, '$.code'), NVL(JSON_VALUE(l_validation, '$.error'), 'SUBSCRIPTION_INVALID'));
            l_msg  := NVL(JSON_VALUE(l_validation, '$.message'), 'Subscription validation failed.');

            htp.p('{"status":"error","code":"' || REPLACE(l_code, '"', '\"') || '","message":"' || REPLACE(l_msg, '"', '\"') || '"}');
            RETURN;
        END IF;
    EXCEPTION WHEN OTHERS THEN
        htp.p('{"status":"error","message":"Subscription validation error: ' || REPLACE(SQLERRM, '"', '''') || '"}');
        RETURN;
    END;
END IF;
    IF l_schema_limit IS NOT NULL AND l_schema_limit > 0 THEN 
        -- If no schemas are configured yet, do NOT raise SCHEMA_LIMIT (it locks the UI). 
        -- Instead: allow generic suggestions, and prompt configuration for data-dependent actions. 
        IF l_enabled_cnt = 0 THEN
          -- IMPORTANT: CAT_LIST must still run so the wizard can show tables
          IF l_act IN ('GENERATE','CAT_APPLY','CAT_AI_BATCH','CAT_UPDATE_DESC','TABLE_MENTION') THEN
            htp.p('{"status":"error","needs_config":true,"message":"No schemas configured yet. Please add a schema in AI Data Configuration, then refresh and select tables."}');
            RETURN;
          END IF;
        END IF;



        -- Determine the requested schema for this action 
        IF l_act = 'SUGGEST' THEN 
            -- Do not fall back to the APEX parsing schema when the caller did not specify a schema 
            l_req_schema := NULLIF(TRIM(SUBSTR(l_p2, 1, 128)), ''); 
        ELSIF l_act = 'GENERATE' THEN 
            l_req_schema := NVL(NULLIF(TRIM(SUBSTR(l_p2, 1, 128)), ''), l_current_schema); 
        ELSIF l_act IN ('CAT_LIST','CAT_APPLY','CAT_AI_BATCH','CAT_UPDATE_DESC','TABLE_MENTION') THEN 
            l_req_schema := NVL(NULLIF(TRIM(l_p1), ''), l_current_schema); 
        ELSE 
            l_req_schema := NULL; 
        END IF; 

        IF l_req_schema IS NOT NULL AND l_enabled_cnt > 0 THEN 
            -- Check if the requested schema is within the allowed set 
            DECLARE 
                l_found BOOLEAN := FALSE; 
                l_cnt   NUMBER := 0; 
            BEGIN 
                FOR sr IN ( 
                    SELECT schema_owner 
                    FROM asklyze_catalog_schemas 
                    WHERE org_id = 1 AND is_enabled = 'Y' 
                    ORDER BY CASE WHEN is_default = 'Y' THEN 0 ELSE 1 END, 
                             NVL(display_order, 999), schema_owner 
                ) LOOP 
                    EXIT WHEN l_cnt >= l_schema_limit; 
                    l_cnt := l_cnt + 1; 
                    IF UPPER(sr.schema_owner) = UPPER(l_req_schema) THEN 
                        l_found := TRUE; 
                    END IF; 
                END LOOP; 

                IF NOT l_found THEN 
                    htp.p('{"status":"error","code":"SCHEMA_LIMIT","message":"Maximum schemas allowed is ' || l_schema_limit || '. Please upgrade your plan for additional schemas."}'); 
                    RETURN; 
                END IF; 
            END; 
        END IF; 
    ELSIF l_schema_limit = 0 THEN 
        -- Check if blocked due to DB instance limit (not subscription) 
        IF ASKLYZE_CLOUD_CONNECTOR_PKG.GET_DB_INSTANCE_ERROR IS NOT NULL THEN 
            htp.p('{"status":"error","code":"DB_INSTANCE_LIMIT","message":"' || REPLACE(ASKLYZE_CLOUD_CONNECTOR_PKG.GET_DB_INSTANCE_ERROR, '"', '\"') || '"}'); 
        ELSE 
            -- Subscription invalid - block completely 
            htp.p('{"status":"error","code":"SUBSCRIPTION_REQUIRED","message":"Valid subscription required. Please check your subscription status."}'); 
        END IF; 
        RETURN; 
    END IF;
       
    BEGIN       
        -- =========================================================================     
        -- AI GENERATION (All routes through Cloud API)     
        -- =========================================================================      
      
        IF l_act = 'TEST_AI' THEN      
             DECLARE       
                 l_prompt CLOB := NVL(l_p1, 'Hello');       
                 l_response CLOB;       
             BEGIN       
                 l_response := ASKLYZE_CLOUD_CONNECTOR_PKG.CALL_CLOUD_API(       
                     p_endpoint => 'test/ai',       
                     p_method => 'POST',       
                     p_body => '{"prompt":"' || REPLACE(REPLACE(l_prompt, '\', '\\'), '"', '\"') || '"}'       
                 );       
                 PRINT_CLOB(l_response);       
             EXCEPTION WHEN OTHERS THEN       
                 htp.p('{"status":"error","message":"TEST_AI ERROR: ' || REPLACE(SQLERRM, '"', '''') || '"}');       
             END;      
      
        ELSIF l_act = 'SUGGEST' THEN     
            -- Get suggestions (Cloud API) - Context-aware based on last question      
      
            DECLARE       
                l_schema VARCHAR2(128) := NVL(NULLIF(TRIM(SUBSTR(l_p2, 1, 128)), ''), l_current_schema);       
                l_last_question VARCHAR2(4000) := l_p3;  -- Last question for context-aware suggestions 
                l_debug CLOB := '';       
                l_ctx_length NUMBER := 0;      
            BEGIN       
                -- DEBUG: Log start      
                l_debug := l_debug || '[SUGGEST] Starting. Schema=' || l_schema || '. ';      
                IF l_last_question IS NOT NULL THEN 
                    l_debug := l_debug || 'LastQ=' || SUBSTR(l_last_question, 1, 50) || '... '; 
                END IF; 
                      
                -- Build FULL context from local catalog for cloud AI (tables, columns, relations)       
                BEGIN      
                    l_context := ASKLYZE_CLOUD_CONNECTOR_PKG.CATALOG_GET_FULL_CONTEXT(1, l_schema);       
                    l_ctx_length := NVL(DBMS_LOB.GETLENGTH(l_context), 0);      
                    l_debug := l_debug || 'Context length=' || l_ctx_length || ' chars. ';      
                          
                    IF l_ctx_length < 50 THEN      
                        l_debug := l_debug || 'WARNING: Context too short! ';      
                    END IF;      
                EXCEPTION WHEN OTHERS THEN      
                    l_debug := l_debug || 'CATALOG_GET_FULL_CONTEXT ERROR: ' || SQLERRM || '. ';      
                    l_context := NULL;      
                END;      
       
                -- Call cloud for suggestions with last question       
                BEGIN      
                    l_debug := l_debug || 'Calling CLOUD_CONNECTOR.GET_SUGGESTIONS... ';      
                    ASKLYZE_CLOUD_CONNECTOR_PKG.GET_SUGGESTIONS(l_schema, NVL(l_p1, 'REPORT'), l_context, l_last_question, l_out);       
                    l_debug := l_debug || 'Response length=' || NVL(DBMS_LOB.GETLENGTH(l_out), 0) || ' chars. ';      
                    l_debug := l_debug || 'Response prefix=' || SUBSTR(l_out, 1, 200) || '... ';      
                EXCEPTION WHEN OTHERS THEN      
                    l_debug := l_debug || 'GET_SUGGESTIONS ERROR: ' || SQLERRM || '. ';      
                    l_out := '[]';      
                END;      
                      
                htp.p('{');      
                htp.p('"_debug":"' || REPLACE(REPLACE(l_debug, '"', ''''), CHR(10), ' ') || '",');      
                htp.p('"_context_length":' || l_ctx_length || ',');      
                htp.p('"_context_preview":"' || REPLACE(REPLACE(SUBSTR(l_context, 1, 500), '"', ''''), CHR(10), ' ') || '",');      
                htp.p('"suggestions":');       
                PRINT_CLOB(NVL(l_out,'[]'));       
                htp.p('}');       
            END;       
       
        ELSIF l_act = 'GENERATE' THEN       
            -- AI Generation - Route to Cloud       
            DECLARE       
                l_schema VARCHAR2(128) := NVL(NULLIF(TRIM(SUBSTR(l_p2, 1, 128)), ''), l_current_schema);       
                l_question CLOB := TO_CLOB(l_p1);       
                l_category VARCHAR2(100) := NVL(l_p3, 'General');       
                l_response CLOB;       
                l_status VARCHAR2(50);       
                l_code VARCHAR2(50);       
                l_debug CLOB := '';      
                l_ctx_length NUMBER := 0;      
                l_api_key_check VARCHAR2(100);      
            BEGIN       
                -- DEBUG: Start      
                l_debug := l_debug || '[GENERATE] Started. ';      
                l_debug := l_debug || 'Schema=' || l_schema || '. ';      
                l_debug := l_debug || 'Question=' || SUBSTR(l_question, 1, 100) || '... ';      
                l_debug := l_debug || 'Category=' || l_category || '. ';      
                      
                -- DEBUG: Check API Key      
                BEGIN      
                    l_api_key_check := SUBSTR(ASKLYZE_CLOUD_CONNECTOR_PKG.GET_API_KEY, 1, 20);      
                    IF l_api_key_check IS NULL THEN      
                        l_debug := l_debug || 'API_KEY=NULL! ';      
                    ELSE      
                        l_debug := l_debug || 'API_KEY=' || SUBSTR(l_api_key_check, 1, 12) || '***. ';      
                    END IF;      
                EXCEPTION WHEN OTHERS THEN      
                    l_debug := l_debug || 'GET_API_KEY ERROR: ' || SQLERRM || '. ';      
                END;      
                      
                -- Build FULL context from local catalog for cloud AI (tables, columns, relations)       
                BEGIN      
                    l_debug := l_debug || 'Building context... ';      
                    l_context := ASKLYZE_CLOUD_CONNECTOR_PKG.CATALOG_GET_FULL_CONTEXT(     
                        1,      
                        l_schema,      
                        DBMS_LOB.SUBSTR(l_question, 4000, 1)     
                    );       
                    l_ctx_length := NVL(DBMS_LOB.GETLENGTH(l_context), 0);      
                    l_debug := l_debug || 'Context length=' || l_ctx_length || ' chars. ';      
                          
                    IF l_ctx_length < 50 THEN      
                        l_debug := l_debug || 'WARNING: Context too short or empty! ';      
                        l_debug := l_debug || 'Context=' || NVL(SUBSTR(l_context, 1, 200), 'NULL') || '. ';      
                    ELSE       
                        l_debug := l_debug || 'Context preview=' || SUBSTR(l_context, 1, 100) || '... ';      
                    END IF;      
                EXCEPTION WHEN OTHERS THEN      
                    l_debug := l_debug || 'CATALOG_GET_FULL_CONTEXT ERROR: ' || SQLERRM || '. ';      
                    l_context := NULL;      
                END;      
       
                -- Call cloud AI       
                BEGIN      
                    l_debug := l_debug || 'Calling CLOUD_CONNECTOR.GENERATE_INSIGHTS... ';      
                    ASKLYZE_CLOUD_CONNECTOR_PKG.GENERATE_INSIGHTS(       
                        p_question => l_question,       
                        p_schema_name => l_schema,       
                        p_category => l_category,       
                        p_context => l_context,       
                        p_result => l_response       
                    );       
                    l_debug := l_debug || 'Response length=' || NVL(DBMS_LOB.GETLENGTH(l_response), 0) || ' chars. ';      
                    l_debug := l_debug || 'Response preview=' || SUBSTR(l_response, 1, 300) || '... ';      
                EXCEPTION WHEN OTHERS THEN      
                    l_debug := l_debug || 'GENERATE_INSIGHTS ERROR: ' || SQLERRM || '. ';      
                    l_response := '{"status":"error","message":"' || REPLACE(SQLERRM, '"', '''') || '"}';      
                END;      
       
                -- Check for subscription errors       
                BEGIN      
                    l_status := JSON_VALUE(l_response, '$.status');       
                    l_code := JSON_VALUE(l_response, '$.code');       
                    l_debug := l_debug || 'Status=' || l_status || '. Code=' || l_code || '. ';      
                EXCEPTION WHEN OTHERS THEN      
                    l_debug := l_debug || 'JSON parse error: ' || SQLERRM || '. ';      
                END;      
       
                IF l_code = 'DB_INSTANCE_LIMIT' THEN 
                    -- API key used from a different database instance than registered 
                    htp.p('{'); 
                    htp.p('"_debug":"' || REPLACE(REPLACE(l_debug, '"', ''''), CHR(10), ' ') || '",'); 
                    htp.p('"status":"error",'); 
                    htp.p('"code":"DB_INSTANCE_LIMIT",'); 
                    htp.p('"message":"' || REPLACE(NVL(JSON_VALUE(l_response, '$.message'), 'This API key is registered to another database instance. Please upgrade your plan for additional instances.'), '"', '\"') || '"'); 
                    htp.p('}'); 
                    RETURN; 
                ELSIF l_code IN ('SUBSCRIPTION_INVALID', 'SUBSCRIPTION_EXPIRED', 'UNAUTHORIZED', 'FORBIDDEN') THEN 
                    -- Return subscription error with renewal prompt 
                    htp.p('{'); 
                    htp.p('"_debug":"' || REPLACE(REPLACE(l_debug, '"', ''''), CHR(10), ' ') || '",'); 
                    htp.p('"status":"error",'); 
                    htp.p('"code":"' || l_code || '",'); 
                    htp.p('"subscription_error":true,'); 
                    htp.p('"message":"' || JSON_VALUE(l_response, '$.message') || '",'); 
                    htp.p('"renew_url":"' || ASKLYZE_CLOUD_CONNECTOR_PKG.GET_RENEWAL_URL || '"'); 
                    htp.p('}'); 
                    RETURN; 
                ELSIF l_code = 'NO_API_KEY' THEN       
                    -- API key not configured       
                    htp.p('{');       
                    htp.p('"_debug":"' || REPLACE(REPLACE(l_debug, '"', ''''), CHR(10), ' ') || '",');      
                    htp.p('"status":"error",');       
                    htp.p('"code":"NO_API_KEY",');       
                    htp.p('"message":"ASKLYZE Cloud API key not configured. Please enter your API key in Settings.",');       
                    htp.p('"show_settings":true');       
                    htp.p('}');       
                    RETURN;       
                ELSIF l_status = 'error' THEN       
                    -- Other error - inject debug      
                    l_response := REGEXP_REPLACE(l_response, '^\{', '{"_debug":"' || REPLACE(REPLACE(l_debug, '"', ''''), CHR(10), ' ') || '",');      
                    PRINT_CLOB(l_response);       
                    RETURN;       
                END IF;       
       
                -- Success - store response locally and return       
                BEGIN      
                    ASKLYZE_CLOUD_CONNECTOR_PKG.STORE_AI_RESPONSE(       
                        p_question => TO_CHAR(SUBSTR(l_question, 1, 4000)),       
                        p_mode => l_category,       
                        p_schema_name => l_schema,       
                        p_ai_response => l_response,       
                        p_query_id => l_query_id       
                    );       
                    l_debug := l_debug || 'Stored query_id=' || l_query_id || '. ';      
                EXCEPTION WHEN OTHERS THEN      
                    l_debug := l_debug || 'STORE_AI_RESPONSE ERROR: ' || SQLERRM || '. ';      
                END;      
       
                -- Add query_id and debug to response       
                -- Escape: quotes, newlines (LF), carriage returns (CR), tabs, backslashes for valid JSON     
                DECLARE     
                    l_safe_debug VARCHAR2(32000);     
                BEGIN     
                    l_safe_debug := l_debug;     
                    l_safe_debug := REPLACE(l_safe_debug, '\', '\\');  -- Escape backslash first     
                    l_safe_debug := REPLACE(l_safe_debug, '"', '''');  -- Replace quotes with apostrophes     
                    l_safe_debug := REPLACE(l_safe_debug, CHR(13), ' '); -- Carriage return     
                    l_safe_debug := REPLACE(l_safe_debug, CHR(10), ' '); -- Line feed     
                    l_safe_debug := REPLACE(l_safe_debug, CHR(9), ' ');  -- Tab     
                         
                    IF l_query_id IS NOT NULL THEN       
                        l_response := REGEXP_REPLACE(l_response, '^\{', '{"_debug":"' || l_safe_debug || '","query_id":' || l_query_id || ',');       
                    ELSE      
                        -- STORE_AI_RESPONSE failed - return error instead of incomplete response    
                        htp.p('{"status":"error","message":"Failed to save query. Please try again.","_debug":"' || l_safe_debug || '"}');    
                        RETURN;    
                    END IF;     
                END;       
       
                PRINT_CLOB(NVL(l_response,'{"status":"error","message":"Empty response from cloud","_debug":"' || REPLACE(REPLACE(l_debug, '"', ''''), CHR(10), ' ') || '"}'));       
            END;       
       
        -- =========================================================================       
        -- LOCAL DATA OPERATIONS - Data stays on customer DB       
        -- =========================================================================       
        ELSIF l_act = 'DATA' THEN       
            DECLARE    
                l_query_id NUMBER;   
                l_validation CLOB;   
                l_valid VARCHAR2(10);   
                l_status VARCHAR2(50);   
            BEGIN    
                -- Validate subscription first   
                l_validation := ASKLYZE_CLOUD_CONNECTOR_PKG.VALIDATE_SUBSCRIPTION;   
                l_valid := JSON_VALUE(l_validation, '$.valid');   
                l_status := JSON_VALUE(l_validation, '$.status');   
                   
                IF l_valid != 'true' THEN 
                    IF JSON_VALUE(l_validation, '$.code') = 'DB_INSTANCE_LIMIT' THEN 
                        htp.p('{"status":"error","code":"DB_INSTANCE_LIMIT","message":"' || REPLACE(NVL(JSON_VALUE(l_validation, '$.message'), 'This API key is registered to another database instance.'), '"', '\"') || '"}'); 
                    ELSE 
                        htp.p('{"status":"error","code":"SUBSCRIPTION_INVALID","message":"Your subscription is not active.","renew_url":"' || ASKLYZE_CLOUD_CONNECTOR_PKG.GET_RENEWAL_URL || '"}'); 
                    END IF; 
                    RETURN; 
                END IF;   
                   
                IF l_status NOT IN ('ACTIVE', 'TRIAL') THEN   
                    htp.p('{"status":"error","code":"SUBSCRIPTION_EXPIRED","message":"Your subscription has expired.","renew_url":"' || ASKLYZE_CLOUD_CONNECTOR_PKG.GET_RENEWAL_URL || '"}');   
                    RETURN;   
                END IF;   
                   
                -- Validate l_p1 is a valid number before conversion    
                IF l_p1 IS NULL OR LENGTH(TRIM(l_p1)) = 0 THEN    
                    htp.p('{"status":"error","message":"Query ID is required"}');    
                    RETURN;    
                END IF;    
                    
                -- Safe conversion with error handling    
                BEGIN    
                    l_query_id := TO_NUMBER(l_p1);    
                EXCEPTION    
                    WHEN VALUE_ERROR THEN    
                        htp.p('{"status":"error","message":"Invalid query ID format: ' || REPLACE(SUBSTR(l_p1, 1, 50), '"', '''') || '"}');    
                        RETURN;    
                    WHEN OTHERS THEN    
                        htp.p('{"status":"error","message":"Query ID conversion error: ' || REPLACE(SQLERRM, '"', '''') || '"}');    
                        RETURN;    
                END;    
                    
                ASKLYZE_CLOUD_CONNECTOR_PKG.EXECUTE_AND_RENDER(l_query_id, l_out);       
                PRINT_CLOB(NVL(l_out,'{"status":"error","message":"No data returned"}'));    
            END;       
       
        ELSIF l_act = 'UPDATE_SQL' THEN       
            ASKLYZE_CLOUD_CONNECTOR_PKG.UPDATE_QUERY(TO_NUMBER(l_p1), l_p2, l_out);       
            PRINT_CLOB(NVL(l_out,'{"status":"error","message":"Update failed"}'));       
       
        ELSIF l_act = 'SAVE_CHART_TYPE' THEN       
            DECLARE       
                l_query_id NUMBER := TO_NUMBER(l_p1);       
                l_chart_type VARCHAR2(100) := SUBSTR(l_p2, 1, 100);       
            BEGIN       
                UPDATE ASKLYZE_AI_QUERY_STORE       
                SET SAVED_CHART_TYPE = l_chart_type       
                WHERE ID = l_query_id;       
                COMMIT;       
                htp.p('{"status":"success"}');       
            EXCEPTION WHEN OTHERS THEN 
                htp.p('{"status":"error","message":"' || REPLACE(SQLERRM, '"', '''') || '"}'); 
            END; 
 
        ELSIF l_act = 'SAVE_PIVOT_CONFIG' THEN 
            DECLARE 
                l_query_id NUMBER := TO_NUMBER(l_p1); 
                l_pivot_config CLOB := TO_CLOB(l_p2); 
            BEGIN 
                UPDATE ASKLYZE_AI_QUERY_STORE 
                SET SAVED_PIVOT_CONFIG = l_pivot_config 
                WHERE ID = l_query_id; 
                COMMIT; 
                htp.p('{"status":"success"}'); 
            EXCEPTION WHEN OTHERS THEN 
                htp.p('{"status":"error","message":"' || REPLACE(SQLERRM, '"', '''') || '"}'); 
            END; 
 
        ELSIF l_act = 'UPDATE_KPI' THEN       
            DECLARE       
                l_query_id NUMBER := TO_NUMBER(l_p1);       
                l_kpi_idx NUMBER := TO_NUMBER(TO_CHAR(l_p2));       
                l_kpi_sql CLOB := TO_CLOB(l_p3);       
                l_kpi_title VARCHAR2(200) := l_p4;       
            BEGIN       
                ASKLYZE_CLOUD_CONNECTOR_PKG.UPDATE_REPORT_KPI(l_query_id, l_kpi_idx, l_kpi_sql, l_kpi_title, l_out);       
                PRINT_CLOB(NVL(l_out,'{"status":"error","message":"Update failed"}'));       
            EXCEPTION WHEN OTHERS THEN       
                htp.p('{"status":"error","message":"' || REPLACE(SQLERRM, '"', '''') || '"}');       
            END;       
       
        ELSIF l_act = 'UPDATE_DASH_KPI' THEN       
            DECLARE       
                l_query_id NUMBER := TO_NUMBER(l_p1);       
                l_kpi_idx NUMBER := TO_NUMBER(l_p2);       
                l_value_sql VARCHAR2(32767) := l_p3;       
                l_kpi_title VARCHAR2(200) := SUBSTR(l_p4, 1, 200);       
                l_trend_sql VARCHAR2(32767) := l_p5;       
            BEGIN       
                IF l_query_id IS NULL THEN       
                    htp.p('{"status":"error","message":"Query ID is required"}');       
                    RETURN;       
                END IF;       
                IF l_kpi_idx IS NULL THEN       
                    htp.p('{"status":"error","message":"KPI index is required"}');       
                    RETURN;       
                END IF;       
                IF l_value_sql IS NULL OR LENGTH(TRIM(l_value_sql)) = 0 THEN       
                    htp.p('{"status":"error","message":"Value SQL is required"}');       
                    RETURN;       
                END IF;       
       
                ASKLYZE_CLOUD_CONNECTOR_PKG.UPDATE_DASHBOARD_KPI(l_query_id, l_kpi_idx, TO_CLOB(l_value_sql), l_kpi_title, TO_CLOB(l_trend_sql), l_out);       
                PRINT_CLOB(NVL(l_out,'{"status":"error","message":"Update failed"}'));       
            EXCEPTION WHEN OTHERS THEN       
                htp.p('{"status":"error","message":"' || SUBSTR(REPLACE(SQLERRM, '"', ''''), 1, 500) || '"}');       
            END;       
       
        -- =========================================================================       
        -- CHAT HISTORY - Local operations       
        -- =========================================================================       
        ELSIF l_act = 'HISTORY' THEN       
            ASKLYZE_CLOUD_CONNECTOR_PKG.GET_CHAT_HISTORY(       
                p_user => NULL,       
                p_limit => NVL(TO_NUMBER(NULLIF(l_p2, '')), 50),       
                p_offset => NVL(TO_NUMBER(NULLIF(l_p3, '')), 0),       
                p_search => l_p1,       
                p_result_json => l_out       
            );       
            PRINT_CLOB(NVL(l_out,'{"status":"error","message":"History empty"}'));       
       
        ELSIF l_act = 'DELETE_CHAT' THEN       
            ASKLYZE_CLOUD_CONNECTOR_PKG.DELETE_CHAT(TO_NUMBER(l_p1), l_out);       
            PRINT_CLOB(NVL(l_out,'{"status":"error"}'));       
       
        ELSIF l_act = 'TOGGLE_FAV' THEN       
            ASKLYZE_CLOUD_CONNECTOR_PKG.TOGGLE_FAVORITE(TO_NUMBER(l_p1), l_out);       
            PRINT_CLOB(NVL(l_out,'{"status":"error"}'));       
       
        ELSIF l_act = 'RENAME_CHAT' THEN       
            ASKLYZE_CLOUD_CONNECTOR_PKG.RENAME_CHAT(TO_NUMBER(l_p1), l_p3, l_out);       
            PRINT_CLOB(NVL(l_out,'{"status":"error"}'));       
       
        ELSIF l_act = 'CLEAR_HISTORY' THEN       
            ASKLYZE_CLOUD_CONNECTOR_PKG.CLEAR_HISTORY(NULL, l_out);       
            PRINT_CLOB(NVL(l_out,'{"status":"error"}'));       
       
        -- =========================================================================       
        -- DASHBOARD LAYOUT - Local operations       
        -- =========================================================================       
        ELSIF l_act = 'SAVE_LAYOUT' THEN       
            ASKLYZE_CLOUD_CONNECTOR_PKG.SAVE_DASHBOARD_LAYOUT(TO_NUMBER(l_p1), l_p2, l_out);       
            PRINT_CLOB(l_out);       
       
        ELSIF l_act = 'RESET_LAYOUT' THEN       
            ASKLYZE_CLOUD_CONNECTOR_PKG.RESET_DASHBOARD_LAYOUT(TO_NUMBER(l_p1), l_out);       
            PRINT_CLOB(l_out);       
       
        -- =========================================================================       
        -- CATALOG MANAGEMENT - Local with Cloud AI for descriptions       
        -- =========================================================================       
        ELSIF l_act = 'CAT_LIST' THEN       
            DECLARE       
                l_org_id NUMBER := 1;       
                l_owner VARCHAR2(128) := NVL(NULLIF(TRIM(l_p1), ''), l_current_schema);       
                l_has_schema NUMBER := 0;     
                l_table_count NUMBER := 0;     
                l_table_limit NUMBER := NULL;     
                l_refresh CLOB;     
            BEGIN       
                -- Always refresh catalog to capture new/changed tables before listing     
                ASKLYZE_CLOUD_CONNECTOR_PKG.CATALOG_REFRESH_SCHEMA(l_org_id, l_owner, 'INCR', l_refresh);     
                -- Check if refresh returned an error     
                IF l_refresh IS NOT NULL AND INSTR(l_refresh, '"status":"error"') > 0 THEN     
                    PRINT_CLOB(l_refresh);     
                    RETURN;     
                END IF;     
     
                SELECT COUNT(*) INTO l_has_schema       
                FROM asklyze_catalog_schemas       
                WHERE org_id = l_org_id AND UPPER(schema_owner) = UPPER(l_owner);       
      
                BEGIN     
                    l_table_limit := ASKLYZE_CLOUD_CONNECTOR_PKG.GET_ENFORCED_LIMIT('COUNT_TABLES');     
                EXCEPTION WHEN OTHERS THEN     
                    l_table_limit := NULL;     
                END;     
       
                apex_json.initialize_clob_output;       
                apex_json.open_object;       
                apex_json.write('status', 'success');       
                apex_json.open_array('tables');       
                FOR r IN (       
                    SELECT t.id, t.object_name, t.object_type,       
                           NVL(t.is_whitelisted,'N') w,       
                           NVL(t.is_enabled,'Y') e,       
                           t.summary_en,       
                           t.table_comment,       
                           t.business_domain,       
                           t.relevance_score,       
                           t.num_rows       
                    FROM asklyze_catalog_tables t       
                    JOIN asklyze_catalog_schemas s ON s.id = t.schema_id       
                    WHERE s.org_id = l_org_id AND UPPER(s.schema_owner) = UPPER(l_owner)       
                      AND t.object_name NOT LIKE 'ASKLYZE%'       
                    ORDER BY t.is_whitelisted DESC, t.relevance_score DESC NULLS LAST, t.object_type, t.object_name     
                ) LOOP     
                    l_table_count := l_table_count + 1;     
                    apex_json.open_object;     
                    apex_json.write('id', r.id);       
                    apex_json.write('object_name', r.object_name);       
                    apex_json.write('object_type', r.object_type);       
                    apex_json.write('is_whitelisted', r.w);       
                    apex_json.write('is_enabled', r.e);       
                    apex_json.write('summary_en', r.summary_en);       
                    apex_json.write('table_comment', r.table_comment);       
                    apex_json.write('business_domain', r.business_domain);       
                    apex_json.write('relevance_score', r.relevance_score);       
                    apex_json.write('num_rows', r.num_rows);       
                    apex_json.close_object;       
                END LOOP;     
                apex_json.close_array;     
                -- Add diagnostic info     
                apex_json.write('schema_requested', l_owner);     
                apex_json.write('schema_found', CASE WHEN l_has_schema > 0 THEN 'Y' ELSE 'N' END);     
                apex_json.write('table_count', l_table_count); 
                apex_json.write('table_limit', l_table_limit); 
                apex_json.write('table_limit_scope', 'PER_SCHEMA'); 
                apex_json.write('plan_code', ASKLYZE_CLOUD_CONNECTOR_PKG.GET_PLAN_CODE); 
                apex_json.close_object;     
     
                l_out := apex_json.get_clob_output;     
                apex_json.free_output;     
                PRINT_CLOB(l_out);     
            END;     
       
        ELSIF l_act = 'CAT_UPDATE_DESC' THEN     
            DECLARE     
                l_org_id NUMBER := 1;     
                l_owner VARCHAR2(128) := NVL(NULLIF(TRIM(l_p1), ''), l_current_schema);     
                l_table_id NUMBER;     
                l_table_name VARCHAR2(128);     
                l_desc VARCHAR2(4000);     
                l_rows NUMBER := 0;     
            BEGIN     
                IF l_p2 IS NOT NULL THEN     
                    apex_json.parse(l_p2);     
                    l_table_id := apex_json.get_number('table_id');     
                    l_table_name := apex_json.get_varchar2('table_name');     
                    l_desc := apex_json.get_varchar2('description');     
                END IF;     
     
                l_table_name := TRIM(l_table_name);     
                IF l_desc IS NOT NULL THEN     
                    l_desc := TRIM(l_desc);     
                END IF;     
                IF l_desc IS NULL OR LENGTH(l_desc) = 0 THEN     
                    l_desc := NULL;     
                END IF;     
     
                IF l_table_id IS NULL AND l_table_name IS NULL THEN     
                    htp.p('{"status":"error","message":"Missing table identifier"}');     
                    RETURN;     
                END IF;     
     
                IF l_table_id IS NOT NULL THEN     
                    UPDATE asklyze_catalog_tables t     
                    SET summary_en = CASE WHEN l_desc IS NULL THEN NULL ELSE SUBSTR(l_desc, 1, 4000) END,     
                        updated_at = SYSTIMESTAMP     
                    WHERE t.id = l_table_id     
                      AND t.schema_id IN (     
                          SELECT id FROM asklyze_catalog_schemas     
                           WHERE org_id = l_org_id AND UPPER(schema_owner) = UPPER(l_owner)     
                      );     
                ELSE     
                    UPDATE asklyze_catalog_tables t     
                    SET summary_en = CASE WHEN l_desc IS NULL THEN NULL ELSE SUBSTR(l_desc, 1, 4000) END,     
                        updated_at = SYSTIMESTAMP     
                    WHERE t.schema_id IN (     
                          SELECT id FROM asklyze_catalog_schemas     
                           WHERE org_id = l_org_id AND UPPER(schema_owner) = UPPER(l_owner)     
                      )     
                      AND UPPER(t.object_name) = UPPER(l_table_name);     
                END IF;     
     
                l_rows := SQL%ROWCOUNT;     
                IF l_rows = 0 THEN     
                    htp.p('{"status":"error","message":"Table not found"}');     
                    RETURN;     
                END IF;     
     
                COMMIT;     
                apex_json.initialize_clob_output;     
                apex_json.open_object;     
                apex_json.write('status', 'success');     
                apex_json.write('table_id', l_table_id);     
                apex_json.write('table_name', l_table_name);     
                IF l_desc IS NOT NULL THEN     
                    apex_json.write('description', SUBSTR(l_desc, 1, 4000));     
                END IF;     
                apex_json.close_object;     
                l_out := apex_json.get_clob_output;     
                apex_json.free_output;     
                PRINT_CLOB(l_out);     
            EXCEPTION WHEN OTHERS THEN     
                htp.p('{"status":"error","message":"' || REPLACE(SQLERRM,'"','`') || '"}');     
            END;     
       
        ELSIF l_act = 'CAT_STATS' THEN       
            BEGIN       
                l_out := ASKLYZE_CLOUD_CONNECTOR_PKG.CATALOG_GET_STATS(1, l_current_schema);       
                PRINT_CLOB(NVL(l_out, '{"error":"No stats"}'));       
            EXCEPTION WHEN OTHERS THEN       
                htp.p('{"status":"error","message":"' || REPLACE(SQLERRM,'"','`') || '"}');       
            END;       
     
        ELSIF l_act = 'CAT_SEARCH' THEN     
            DECLARE     
                l_keywords VARCHAR2(4000) := l_p1;     
                l_domain VARCHAR2(100) := l_p2;     
            BEGIN     
                l_out := ASKLYZE_CLOUD_CONNECTOR_PKG.CATALOG_SEARCH_TABLES(     
                    p_org_id       => 1,     
                    p_schema_owner => l_current_schema,     
                    p_keywords     => l_keywords,     
                    p_domain       => l_domain,     
                    p_max_results  => 20     
                );     
                PRINT_CLOB(NVL(l_out, '{"results":[]}'));     
            EXCEPTION WHEN OTHERS THEN     
                htp.p('{"status":"error","message":"' || REPLACE(SQLERRM,'"','`') || '"}');     
            END;     
     
        ELSIF l_act = 'CAT_CONTEXT' THEN     
            DECLARE     
                l_domain VARCHAR2(100) := l_p1;     
                l_max NUMBER := NVL(TO_NUMBER(l_p2), 30);     
            BEGIN     
                l_out := ASKLYZE_CLOUD_CONNECTOR_PKG.CATALOG_GET_SEMANTIC_CONTEXT(     
                    p_org_id       => 1,     
                    p_schema_owner => l_current_schema,     
                    p_domain       => l_domain,     
                    p_max_tables   => l_max     
                );     
                PRINT_CLOB(NVL(l_out, '{"tables":[]}'));     
            EXCEPTION WHEN OTHERS THEN     
                htp.p('{"status":"error","message":"' || REPLACE(SQLERRM,'"','`') || '"}');     
            END;     
     
        ELSIF l_act = 'CAT_APPLY' THEN     
            -- Apply whitelist and refresh catalog locally       
            DECLARE       
                l_org_id NUMBER := 1;       
                l_owner VARCHAR2(128) := NVL(NULLIF(TRIM(l_p1), ''), l_current_schema);       
                l_dummy CLOB; l_refresh CLOB;       
                l_stats_result CLOB;     
                l_pending_cnt NUMBER := 0;       
                l_total_cnt NUMBER := 0;      
                l_cnt NUMBER; l_name VARCHAR2(4000);       
                l_table_limit NUMBER;       
                TYPE t_set IS TABLE OF VARCHAR2(1) INDEX BY VARCHAR2(4000); l_sel t_set;       
            BEGIN       
                IF l_p2 IS NOT NULL THEN       
                     apex_json.parse(l_p2);       
                     l_cnt := apex_json.get_count('selected');       
                     FOR i IN 1..l_cnt LOOP       
                         l_name := apex_json.get_varchar2('selected[%d]', i);       
                         IF l_name IS NOT NULL THEN l_sel(UPPER(TRIM(l_name))) := 'Y'; END IF;       
                     END LOOP;       
                END IF;       
       
                -- Enforce table whitelist limit (if configured)       
                BEGIN       
                    l_table_limit := ASKLYZE_CLOUD_CONNECTOR_PKG.GET_ENFORCED_LIMIT('COUNT_TABLES');       
                EXCEPTION WHEN OTHERS THEN       
                    l_table_limit := NULL;       
                END;       
       
                IF l_table_limit IS NOT NULL THEN 
                    -- If limit is 0, subscription is invalid - block completely 
                    IF l_table_limit = 0 THEN 
                        htp.p('{"status":"error","code":"SUBSCRIPTION_REQUIRED","message":"Valid subscription required to add tables. Please check your subscription status."}'); 
                        RETURN; 
                    END IF; 
                    -- -1 means unlimited, skip the check 
                    IF l_table_limit > 0 THEN 
                        IF l_cnt IS NULL THEN l_cnt := 0; END IF; 
                        IF l_cnt > l_table_limit THEN 
                            htp.p('{"status":"error","code":"TABLE_LIMIT","message":"Maximum whitelisted tables allowed is ' || l_table_limit || '"}'); 
                            RETURN; 
                        END IF; 
                    END IF; 
                END IF;       
        
                FOR r IN (SELECT t.object_name, t.object_type FROM asklyze_catalog_tables t JOIN asklyze_catalog_schemas s ON s.id=t.schema_id WHERE s.org_id=l_org_id AND UPPER(s.schema_owner)=UPPER(l_owner) AND t.object_name NOT LIKE 'ASKLYZE%') LOOP       
                    ASKLYZE_CLOUD_CONNECTOR_PKG.CATALOG_SET_WHITELIST(l_org_id, l_owner, r.object_name, r.object_type, CASE WHEN l_sel.EXISTS(UPPER(r.object_name)) THEN 'Y' ELSE 'N' END, 'Y', NULL, l_dummy);       
                END LOOP;       
        
                ASKLYZE_CLOUD_CONNECTOR_PKG.CATALOG_REFRESH_SCHEMA(l_org_id, l_owner, 'INCR', l_refresh);       
        
                -- Manual count of pending AI descriptions       
                SELECT COUNT(*) INTO l_pending_cnt       
                  FROM asklyze_catalog_tables t       
                  JOIN asklyze_catalog_schemas s ON s.id = t.schema_id       
                 WHERE s.org_id = l_org_id        
                   AND UPPER(s.schema_owner) = UPPER(l_owner)       
                   AND t.is_whitelisted = 'Y'       
                   AND (t.summary_en IS NULL OR LENGTH(t.summary_en) < 5);       
                          
                SELECT COUNT(*) INTO l_total_cnt       
                  FROM asklyze_catalog_tables t       
                  JOIN asklyze_catalog_schemas s ON s.id = t.schema_id       
                 WHERE s.org_id = l_org_id        
                   AND UPPER(s.schema_owner) = UPPER(l_owner)       
                   AND t.is_whitelisted = 'Y';       
     
                -- Push stats to cloud (schema + tables_count) even if no pending AI work     
                BEGIN     
                    ASKLYZE_CLOUD_CONNECTOR_PKG.AI_DESCRIBE_TABLES('[]', UPPER(l_owner), l_total_cnt, l_stats_result);     
                EXCEPTION WHEN OTHERS THEN     
                    NULL;     
                END;     
       
                apex_json.initialize_clob_output;       
                apex_json.open_object;       
                apex_json.write('status', 'success');       
                apex_json.write_raw('refresh', NVL(l_refresh,'{}'));       
                apex_json.open_object('pending');       
                apex_json.write('pending', l_pending_cnt);       
                apex_json.write('total', l_total_cnt);       
                apex_json.close_object;       
                apex_json.write('_debug', 'Recalculated pending: ' || l_pending_cnt);       
                apex_json.close_object;       
                l_out := apex_json.get_clob_output;       
                apex_json.free_output;       
                PRINT_CLOB(l_out);       
            EXCEPTION WHEN OTHERS THEN       
                htp.p('{"status":"error","message":"' || REPLACE(SQLERRM,'"','`') || '"}');       
            END;       
        
        ELSIF l_act = 'CAT_AI_BATCH' THEN     
            -- AI catalog descriptions (Cloud API)     
            ASKLYZE_CLOUD_CONNECTOR_PKG.CATALOG_AI_DESCRIBE_BATCH(     
                p_org_id       => 1,     
                p_schema_owner => NVL(NULLIF(TRIM(l_p1), ''), l_current_schema),     
                p_batch_size   => NVL(TO_NUMBER(l_p2), 10),     
                p_force        => 'N',     
                p_result_json  => l_out     
            );     
            PRINT_CLOB(l_out);     
            RETURN;     
     
            -- Legacy cloud batch code (kept for reference, not executed)      
      
            -- Cloud batch descriptions logic (keep existing)      
            DECLARE       
                l_org_id NUMBER := 1;       
                l_owner VARCHAR2(128) := NVL(NULLIF(TRIM(l_p1), ''), l_current_schema);       
                l_batch_size NUMBER := NVL(TO_NUMBER(l_p2), 10);       
                l_tables_json CLOB;       
                l_result CLOB;       
                l_processed NUMBER := 0;       
                l_remaining NUMBER := 0;       
                l_whitelist_count NUMBER := 0;     
            BEGIN       
                BEGIN     
                    SELECT COUNT(*) INTO l_whitelist_count     
                    FROM asklyze_catalog_tables t     
                    JOIN asklyze_catalog_schemas s ON s.id = t.schema_id     
                    WHERE s.org_id = l_org_id     
                      AND UPPER(s.schema_owner) = UPPER(l_owner)     
                      AND t.is_whitelisted = 'Y';     
                EXCEPTION     
                    WHEN OTHERS THEN     
                        l_whitelist_count := 0;     
                END;     
                -- Get pending tables for AI description       
                apex_json.initialize_clob_output;       
                apex_json.open_array;       
                FOR r IN (       
                    SELECT t.id, t.object_name, t.object_type, t.table_comment       
                    FROM asklyze_catalog_tables t       
                    JOIN asklyze_catalog_schemas s ON s.id = t.schema_id       
                    WHERE s.org_id = l_org_id       
                    AND UPPER(s.schema_owner) = UPPER(l_owner)       
                    AND t.is_whitelisted = 'Y'       
                    AND (t.summary_en IS NULL OR LENGTH(t.summary_en) < 5)       
                    FETCH FIRST l_batch_size ROWS ONLY       
                ) LOOP       
                    apex_json.open_object;       
                    apex_json.write('id', r.id);       
                    apex_json.write('name', r.object_name);       
                    apex_json.write('type', r.object_type);       
                    apex_json.write('comment', r.table_comment);       
                    -- Send columns preview to help AI       
                    apex_json.open_array('columns');       
                        FOR c IN (SELECT column_name, data_type, column_comment FROM asklyze_catalog_columns WHERE table_id = r.id ORDER BY column_id) LOOP       
                            apex_json.open_object;       
                            apex_json.write('name', c.column_name);       
                            apex_json.write('type', c.data_type);       
                            apex_json.write('comment', c.column_comment);       
                            apex_json.close_object;       
                        END LOOP;       
                    apex_json.close_array;       
                    apex_json.close_object;       
                END LOOP;       
                apex_json.close_array;       
                l_tables_json := apex_json.get_clob_output;       
                apex_json.free_output;       
        
                IF l_tables_json = '[]' THEN       
                    htp.p('{"status":"success","processed":0,"done":true,"message":"No tables pending AI description"}');       
                    RETURN;       
                END IF;       
        
                -- Call cloud for AI descriptions       
                ASKLYZE_CLOUD_CONNECTOR_PKG.AI_DESCRIBE_TABLES(l_tables_json, l_owner, l_whitelist_count, l_result);       
        
                -- Parse result to check status      
                apex_json.parse(l_result);       
                      
                -- CRITICAL: If cloud returned error, return it immediately to stop client loop      
                IF apex_json.get_varchar2('status') != 'success' THEN      
                    PRINT_CLOB(l_result);      
                    RETURN;      
                END IF;      
      
                -- Process descriptions and update local tables       
                DECLARE       
                    l_desc_cnt NUMBER;      
                    l_tbl_name CLOB;       
                    l_sum_en CLOB;       
                    l_sum_ar CLOB;       
                    l_domain CLOB;       
                    l_debug_step VARCHAR2(100) := 'Init';      
                BEGIN       
                    -- Validate descriptions existence      
                    l_debug_step := 'Check Path';      
                    IF NOT apex_json.does_exist('descriptions') THEN      
                         RAISE_APPLICATION_ERROR(-20001, 'JSON path "descriptions" not found.');      
                    END IF;      
      
                    l_debug_step := 'Get Count';      
                    l_desc_cnt := apex_json.get_count('descriptions');       
                          
                    FOR i IN 1..l_desc_cnt LOOP       
                        l_debug_step := 'Get items ' || i;      
                        l_tbl_name := apex_json.get_clob('descriptions[%d].table_name', i);       
                        l_sum_en := apex_json.get_clob('descriptions[%d].summary_en', i);       
                        l_sum_ar := apex_json.get_clob('descriptions[%d].summary_ar', i);       
                        l_domain := apex_json.get_clob('descriptions[%d].business_domain', i);       
                               
                        l_debug_step := 'Update ' || i;      
                        UPDATE asklyze_catalog_tables t       
                        SET summary_en = DBMS_LOB.SUBSTR(l_sum_en, 3500, 1),       
                            summary_ar = DBMS_LOB.SUBSTR(l_sum_ar, 2000, 1),       
                            business_domain = DBMS_LOB.SUBSTR(l_domain, 100, 1),       
                            updated_at = SYSTIMESTAMP       
                        WHERE object_name = DBMS_LOB.SUBSTR(l_tbl_name, 128, 1)       
                          AND EXISTS (SELECT 1 FROM asklyze_catalog_schemas s WHERE s.id = t.schema_id AND s.org_id = l_org_id AND UPPER(s.schema_owner) = UPPER(l_owner));       
                               
                        l_processed := l_processed + SQL%ROWCOUNT;       
                    END LOOP;       
                    COMMIT;       
                EXCEPTION WHEN OTHERS THEN      
                   ROLLBACK;      
                   -- Include snippet of l_result to debug      
                   htp.p('{"status":"error","message":"Error at ' || l_debug_step || ': ' || REPLACE(SQLERRM, '"', '''') || '","debug_response":"' || REPLACE(REPLACE(DBMS_LOB.SUBSTR(l_result, 500, 1), '"', ''''), CHR(10), ' ') || '"}');      
                   RETURN;      
                END;       
        
                -- Calculate remaining       
                SELECT COUNT(*) INTO l_remaining       
                  FROM asklyze_catalog_tables t       
                  JOIN asklyze_catalog_schemas s ON s.id = t.schema_id       
                 WHERE s.org_id = l_org_id        
                   AND UPPER(s.schema_owner) = UPPER(l_owner)       
                   AND t.is_whitelisted = 'Y'       
                   AND (t.summary_en IS NULL OR LENGTH(t.summary_en) < 5);       
        
                apex_json.initialize_clob_output;       
                apex_json.open_object;       
                apex_json.write('status', 'success');       
                apex_json.write('processed', l_processed);       
                apex_json.write('ok', l_processed);       
                apex_json.write('remaining', l_remaining);       
                apex_json.write('done', CASE WHEN l_remaining = 0 THEN TRUE ELSE FALSE END);       
                apex_json.close_object;       
                l_out := apex_json.get_clob_output;       
                apex_json.free_output;       
        
                PRINT_CLOB(l_out);       
            EXCEPTION WHEN OTHERS THEN       
                ROLLBACK;       
                htp.p('{"status":"error","message":"' || REPLACE(SQLERRM,'"','`') || '"}');       
            END;       
       
        -- =========================================================================       
        -- CHART MANAGEMENT - Local operations       
        -- =========================================================================       
        ELSIF l_act = 'CHART_TYPES' THEN       
            ASKLYZE_CLOUD_CONNECTOR_PKG.GET_CHART_TYPES(l_out);       
            PRINT_CLOB(NVL(l_out,'{"status":"error"}'));       
       
        ELSIF l_act = 'UPDATE_CHART' THEN       
            DECLARE       
                 l_query_id NUMBER := TO_NUMBER(l_p1);       
                 l_idx NUMBER; l_nsql CLOB; l_type VARCHAR2(100); l_title VARCHAR2(500);       
            BEGIN       
                 apex_json.parse(l_p2);       
                 l_idx := apex_json.get_number('chart_index');       
                 l_nsql := apex_json.get_clob('sql');       
                 l_type := apex_json.get_varchar2('chart_type');       
                 l_title := apex_json.get_varchar2('title');       
                 ASKLYZE_CLOUD_CONNECTOR_PKG.UPDATE_DASHBOARD_CHART(l_query_id, l_idx, l_nsql, l_type, l_title, l_out);       
                 PRINT_CLOB(l_out);       
            END;       
       
        ELSIF l_act = 'DELETE_CHART' THEN       
            ASKLYZE_CLOUD_CONNECTOR_PKG.DELETE_DASHBOARD_CHART(      
                    p_query_id    => TO_NUMBER(l_p1),      
                    p_chart_index => TO_NUMBER(l_p2),      
                    p_result_json => l_out      
                );      
            PRINT_CLOB(NVL(l_out,'{"status":"error"}'));       
       
        ELSIF l_act = 'ADD_CHART' THEN       
            -- Add chart requires AI - route to cloud       
            DECLARE       
                l_query_id NUMBER := TO_NUMBER(l_p1);       
                l_question VARCHAR2(4000);       
                l_chart_type VARCHAR2(100);       
                l_grid_idx NUMBER;     
                l_schema VARCHAR2(128);     
                l_chart_context CLOB;     
            BEGIN       
                apex_json.parse(l_p2);       
                l_question := apex_json.get_varchar2('question');       
                l_chart_type := apex_json.get_varchar2('chart_type');       
                l_grid_idx := apex_json.get_number('grid_index');       
     
                -- Get schema from query store     
                BEGIN     
                    SELECT schema_owner INTO l_schema      
                    FROM ASKLYZE_AI_QUERY_STORE WHERE ID = l_query_id;     
                EXCEPTION WHEN OTHERS THEN     
                    l_schema := l_current_schema;     
                END;     
     
                -- Build context from local catalog     
                l_chart_context := ASKLYZE_CLOUD_CONNECTOR_PKG.CATALOG_GET_FULL_CONTEXT(     
                    1,     
                    l_schema,     
                    l_question     
                );     
     
                -- Call Cloud API for chart generation     
                ASKLYZE_CLOUD_CONNECTOR_PKG.ADD_DASHBOARD_CHART(     
                    p_query_id   => l_query_id,     
                    p_question   => l_question,     
                    p_chart_type => l_chart_type,     
                    p_context    => l_chart_context,     
                    p_result     => l_out     
                );     
                PRINT_CLOB(NVL(l_out,'{"status":"error","message":"Failed to add chart"}'));     
            EXCEPTION WHEN OTHERS THEN     
                htp.p('{"status":"error","message":"' || REPLACE(SQLERRM, '"', '''') || '"}');     
            END;     
       
        -- =========================================================================       
        -- SQL TESTING - Local operations       
        -- =========================================================================       
        ELSIF l_act = 'TEST_SQL' THEN       
            DECLARE       
                l_sql_clean VARCHAR2(32767);       
                l_cursor_id INTEGER;       
                l_scalar_val NUMBER;       
                l_is_scalar BOOLEAN := FALSE;       
            BEGIN       
                IF l_p2 IS NULL OR LENGTH(TRIM(l_p2)) = 0 THEN       
                    htp.p('{"status":"error","message":"SQL query is empty"}');       
                    RETURN;       
                END IF;       
       
                l_sql_clean := TRIM(REPLACE(REPLACE(l_p2, '```sql', ''), '```', ''));       
                IF SUBSTR(l_sql_clean, -1) = ';' THEN       
                    l_sql_clean := SUBSTR(l_sql_clean, 1, LENGTH(l_sql_clean) - 1);       
                END IF;       
       
                -- Compile check       
                BEGIN       
                    l_cursor_id := DBMS_SQL.OPEN_CURSOR;       
                    DBMS_SQL.PARSE(l_cursor_id, l_sql_clean, DBMS_SQL.NATIVE);       
                    DBMS_SQL.CLOSE_CURSOR(l_cursor_id);       
                EXCEPTION WHEN OTHERS THEN       
                    IF l_cursor_id IS NOT NULL AND DBMS_SQL.IS_OPEN(l_cursor_id) THEN       
                        DBMS_SQL.CLOSE_CURSOR(l_cursor_id);       
                    END IF;       
                    htp.p('{"status":"error","message":"' || SUBSTR(REPLACE(REPLACE(SQLERRM,'"','`'),CHR(10),' '), 1, 500) || '"}');       
                    RETURN;       
                END;       
       
                -- Try scalar       
                BEGIN       
                    EXECUTE IMMEDIATE l_sql_clean INTO l_scalar_val;       
                    l_is_scalar := TRUE;       
                EXCEPTION WHEN OTHERS THEN       
                    l_is_scalar := FALSE;       
                END;       
       
                IF l_is_scalar THEN       
                    IF l_scalar_val IS NOT NULL THEN       
                        PRINT_CLOB('{"status":"success","data":[{"RESULT":' || TO_CHAR(l_scalar_val) || '}],"scalar":true}');       
                    ELSE       
                        PRINT_CLOB('{"status":"success","data":[{"RESULT":null}],"scalar":true,"message":"Query returned NULL"}');       
                    END IF;       
                ELSE       
                    BEGIN       
                        l_out := ASKLYZE_CLOUD_CONNECTOR_PKG.EXECUTE_SQL_TO_JSON(l_sql_clean);       
                        IF l_out IS NULL OR l_out = '[]' THEN       
                            PRINT_CLOB('{"status":"success","data":[],"message":"Query returned no rows"}');       
                        ELSE       
                            PRINT_CLOB('{"status":"success","data":' || l_out || '}');       
                        END IF;       
                    EXCEPTION WHEN OTHERS THEN       
                        htp.p('{"status":"error","message":"Execution error: ' || SUBSTR(REPLACE(REPLACE(SQLERRM,'"','`'),CHR(10),' '), 1, 400) || '"}');       
                    END;       
                END IF;       
            EXCEPTION WHEN OTHERS THEN       
                 htp.p('{"status":"error","message":"' || REPLACE(REPLACE(SQLERRM,'"','`'),CHR(10),' ') || '"}');       
            END;       
       
        ELSIF l_act = 'COMPILE_SQL' THEN       
            DECLARE       
                l_sql_clean VARCHAR2(32767);       
                l_cursor_id INTEGER;       
            BEGIN       
                IF l_p2 IS NULL OR LENGTH(TRIM(l_p2)) = 0 THEN       
                    htp.p('{"status":"error","message":"SQL query is empty"}');       
                    RETURN;       
                END IF;       
       
                l_sql_clean := TRIM(REPLACE(REPLACE(l_p2, '```sql', ''), '```', ''));       
                IF SUBSTR(l_sql_clean, -1) = ';' THEN       
                    l_sql_clean := SUBSTR(l_sql_clean, 1, LENGTH(l_sql_clean) - 1);       
                END IF;       
       
                l_cursor_id := DBMS_SQL.OPEN_CURSOR;       
                DBMS_SQL.PARSE(l_cursor_id, l_sql_clean, DBMS_SQL.NATIVE);       
                DBMS_SQL.CLOSE_CURSOR(l_cursor_id);       
                htp.p('{"status":"success","message":"SQL compiled successfully"}');       
            EXCEPTION WHEN OTHERS THEN       
                IF l_cursor_id IS NOT NULL AND DBMS_SQL.IS_OPEN(l_cursor_id) THEN       
                    DBMS_SQL.CLOSE_CURSOR(l_cursor_id);       
                END IF;       
                htp.p('{"status":"error","message":"' || SUBSTR(REPLACE(REPLACE(SQLERRM,'"','`'),CHR(10),' '), 1, 500) || '"}');       
            END;       
     
        ELSIF l_act = 'GEN_TREND_SQL' THEN     
            -- Generate trend SQL from value SQL     
            DECLARE     
                l_value_sql CLOB := l_p2;     
                l_trend_sql CLOB;     
                l_escaped VARCHAR2(32767);     
            BEGIN     
                l_trend_sql := ASKLYZE_CLOUD_CONNECTOR_PKG.GENERATE_TREND_SQL(l_value_sql);     
                IF l_trend_sql IS NOT NULL THEN     
                    -- Escape for JSON     
                    l_escaped := REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(     
                        SUBSTR(l_trend_sql, 1, 32000),     
                        '\', '\\'), '"', '\"'), CHR(10), '\n'), CHR(13), '\r'), CHR(9), '\t');     
                    htp.p('{"status":"success","trend_sql":"' || l_escaped || '"}');     
                ELSE     
                    htp.p('{"status":"error","message":"Could not generate trend SQL. The table may not have a suitable date column for comparison."}');     
                END IF;     
            EXCEPTION WHEN OTHERS THEN     
                htp.p('{"status":"error","message":"' || REPLACE(REPLACE(SQLERRM,'"','`'),CHR(10),' ') || '"}');     
            END;     
     
        -- =========================================================================       
        -- CLOUD API SETTINGS (replaces local AI settings)       
        -- =========================================================================       
        ELSIF l_act = 'GET_AI_SETTINGS' THEN     
            -- Return cloud API configuration     
            ASKLYZE_CLOUD_CONNECTOR_PKG.GET_CONFIG(l_out);     
            PRINT_CLOB(NVL(l_out,'{"status":"error","message":"Failed to get settings"}'));       
       
        ELSIF l_act = 'SET_AI_SETTINGS' THEN       
            -- Set API key / configuration      
            DECLARE       
                l_api_key VARCHAR2(4000);       
                l_model VARCHAR2(100);      
                l_api_url VARCHAR2(1000);      
            BEGIN       
                apex_json.parse(l_p2);       
                l_api_key := apex_json.get_varchar2('api_key');       
                l_model := apex_json.get_varchar2('model');      
                l_api_url := apex_json.get_varchar2('api_url');      
       
                -- Cloud mode: Only API key is needed (AI settings managed in cloud)     
                ASKLYZE_CLOUD_CONNECTOR_PKG.SET_API_KEY(l_api_key, l_out);      
                PRINT_CLOB(NVL(l_out,'{"status":"error","message":"Failed to save settings"}'));       
            END;       
      
        ELSIF l_act = 'SET_CONN_MODE' THEN      
            BEGIN      
                UPDATE ASKLYZE_CLOUD_CONFIG SET config_value = l_p1 WHERE config_key = 'CONNECTION_MODE';      
                COMMIT;      
                htp.p('{"status":"success"}');      
            EXCEPTION WHEN OTHERS THEN      
                htp.p('{"status":"error","message":"' || REPLACE(SQLERRM, '"', '''') || '"}');      
            END;      
      
        ELSIF l_act = 'TOGGLE_THEME' THEN      
            BEGIN      
                UPDATE ASKLYZE_CLOUD_CONFIG SET config_value = l_p1 WHERE config_key = 'THEME_MODE';      
                COMMIT;      
                htp.p('{"status":"success"}');      
            EXCEPTION WHEN OTHERS THEN      
                 htp.p('{"status":"error"}');      
            END;      
       
        -- =========================================================================       
        -- SCHEMA MANAGEMENT - Local operations       
        -- =========================================================================       
        ELSIF l_act = 'GET_SCHEMAS' THEN       
            ASKLYZE_CLOUD_CONNECTOR_PKG.GET_CONFIGURED_SCHEMAS(1, l_out);       
            PRINT_CLOB(NVL(l_out,'{"status":"error","message":"Failed to get schemas"}'));       
       
        ELSIF l_act = 'ADD_SCHEMA' THEN       
            ASKLYZE_CLOUD_CONNECTOR_PKG.ADD_SCHEMA(1, l_p1, l_out);       
            PRINT_CLOB(NVL(l_out,'{"status":"error","message":"Failed to add schema"}'));       
       
        ELSIF l_act = 'SET_DEFAULT_SCHEMA' THEN       
            ASKLYZE_CLOUD_CONNECTOR_PKG.SET_DEFAULT_SCHEMA(1, l_p1, l_out);       
            PRINT_CLOB(NVL(l_out,'{"status":"error","message":"Failed to set default schema"}'));       
       
        ELSIF l_act = 'REMOVE_SCHEMA' THEN       
            ASKLYZE_CLOUD_CONNECTOR_PKG.REMOVE_SCHEMA(1, l_p1, l_out);       
            PRINT_CLOB(NVL(l_out,'{"status":"error","message":"Failed to remove schema"}'));       
     
        -- =========================================================================       
        -- EXTERNAL CONNECTION MANAGEMENT       
        -- =========================================================================       
        ELSIF l_act = 'GET_EXT_CONNECTIONS' THEN     
            ASKLYZE_CLOUD_CONNECTOR_PKG.GET_EXTERNAL_CONNECTIONS(1, l_out);     
            PRINT_CLOB(NVL(l_out,'{"status":"error","message":"Failed to get connections"}'));     
     
        ELSIF l_act = 'ADD_EXT_CONNECTION' THEN     
            -- l_p2 = JSON with connection details     
            DECLARE     
                l_json JSON_OBJECT_T;     
                l_conn_type VARCHAR2(20);     
                l_host VARCHAR2(255);     
                l_port NUMBER;     
                l_service VARCHAR2(128);     
                l_conn_str VARCHAR2(500);     
                l_user VARCHAR2(128);     
                l_pwd VARCHAR2(500);     
                l_name VARCHAR2(100);     
            BEGIN     
                l_json := JSON_OBJECT_T.PARSE(l_p2);     
                l_name := l_json.get_string('name');     
                l_conn_type := l_json.get_string('type');     
                l_host := l_json.get_string('host');     
                l_port := NVL(l_json.get_number('port'), 1521);     
                l_service := l_json.get_string('service');     
                l_conn_str := l_json.get_string('conn_string');     
                l_user := l_json.get_string('user');     
                l_pwd := l_json.get_string('password');     
     
                ASKLYZE_CLOUD_CONNECTOR_PKG.ADD_EXTERNAL_CONNECTION(     
                    p_org_id => 1,     
                    p_connection_name => l_name,     
                    p_connection_type => l_conn_type,     
                    p_db_host => l_host,     
                    p_db_port => l_port,     
                    p_service_name => l_service,     
                    p_connection_string => l_conn_str,     
                    p_db_user => l_user,     
                    p_db_password => l_pwd,     
                    p_result_json => l_out     
                );     
                PRINT_CLOB(NVL(l_out,'{"status":"error","message":"Failed to add connection"}'));     
            END;     
     
        ELSIF l_act = 'UPDATE_EXT_CONNECTION' THEN     
            -- l_p1 = connection_id, l_p2 = JSON with connection details     
            DECLARE     
                l_json JSON_OBJECT_T;     
                l_conn_id NUMBER := TO_NUMBER(l_p1);     
            BEGIN     
                l_json := JSON_OBJECT_T.PARSE(l_p2);     
     
                ASKLYZE_CLOUD_CONNECTOR_PKG.UPDATE_EXTERNAL_CONNECTION(     
                    p_connection_id => l_conn_id,     
                    p_connection_name => l_json.get_string('name'),     
                    p_connection_type => l_json.get_string('type'),     
                    p_db_host => l_json.get_string('host'),     
                    p_db_port => l_json.get_number('port'),     
                    p_service_name => l_json.get_string('service'),     
                    p_connection_string => l_json.get_string('conn_string'),     
                    p_db_user => l_json.get_string('user'),     
                    p_db_password => l_json.get_string('password'),     
                    p_result_json => l_out     
                );     
                PRINT_CLOB(NVL(l_out,'{"status":"error","message":"Failed to update connection"}'));     
            END;     
     
        ELSIF l_act = 'DELETE_EXT_CONNECTION' THEN     
            -- l_p1 = connection_id     
            ASKLYZE_CLOUD_CONNECTOR_PKG.DELETE_EXTERNAL_CONNECTION(TO_NUMBER(l_p1), l_out);     
            PRINT_CLOB(NVL(l_out,'{"status":"error","message":"Failed to delete connection"}'));     
     
        ELSIF l_act = 'TEST_EXT_CONNECTION' THEN     
            -- l_p1 = connection_id     
            ASKLYZE_CLOUD_CONNECTOR_PKG.TEST_EXTERNAL_CONNECTION(TO_NUMBER(l_p1), l_out);     
            PRINT_CLOB(NVL(l_out,'{"status":"error","message":"Failed to test connection"}'));     
     
        -- =========================================================================       
        -- SUBSCRIPTION STATUS CHECK       
        -- =========================================================================       
        ELSIF l_act = 'CHECK_SUBSCRIPTION' THEN 
            -- First check schema overage against plan limit 
            IF l_schema_limit IS NOT NULL AND l_schema_limit > 0 THEN 
                SELECT COUNT(*) INTO l_enabled_cnt 
                FROM asklyze_catalog_schemas 
                WHERE org_id = 1 AND is_enabled = 'Y'; 
 
                IF l_enabled_cnt > l_schema_limit THEN 
                    htp.p('{"valid":false,"code":"SCHEMA_LIMIT","message":"Your plan allows ' || l_schema_limit || ' schema. You have ' || l_enabled_cnt || ' schemas configured. Please remove extra schemas or upgrade your plan."}'); 
                    RETURN; 
                END IF; 
            END IF; 
            l_validation := ASKLYZE_CLOUD_CONNECTOR_PKG.VALIDATE_SUBSCRIPTION; 
            PRINT_CLOB(l_validation);       
       
        -- ========================================================================= 
        -- VOICE TRANSCRIPTION - Routes to Cloud API 
        -- ========================================================================= 
        ELSIF l_act = 'TRANSCRIBE_AUDIO' THEN 
            DECLARE 
                l_audio_base64 CLOB; 
                l_mime_type VARCHAR2(100) := NVL(apex_application.g_x02, 'audio/webm'); 
                l_result CLOB; 
            BEGIN 
                -- Reconstruct base64 from chunks 
                DBMS_LOB.CREATETEMPORARY(l_audio_base64, TRUE); 
                FOR i IN 1..apex_application.g_f01.COUNT LOOP 
                    IF apex_application.g_f01(i) IS NOT NULL THEN 
                        DBMS_LOB.WRITEAPPEND(l_audio_base64, LENGTH(apex_application.g_f01(i)), apex_application.g_f01(i)); 
                    END IF; 
                END LOOP; 
 
                IF l_audio_base64 IS NULL OR DBMS_LOB.GETLENGTH(l_audio_base64) = 0 THEN 
                    DBMS_LOB.FREETEMPORARY(l_audio_base64); 
                    htp.p('{"status":"error","message":"No audio data received"}'); 
                    RETURN; 
                END IF; 
 
                -- Call Cloud API for transcription 
                l_result := ASKLYZE_CLOUD_CONNECTOR_PKG.TRANSCRIBE_AUDIO(l_audio_base64, l_mime_type); 
                DBMS_LOB.FREETEMPORARY(l_audio_base64); 
 
                PRINT_CLOB(l_result); 
 
            EXCEPTION WHEN OTHERS THEN 
                BEGIN DBMS_LOB.FREETEMPORARY(l_audio_base64); EXCEPTION WHEN OTHERS THEN NULL; END; 
                htp.p('{"status":"error","message":"Transcription error: ' || REPLACE(SQLERRM,'"','`') || '"}'); 
            END; 
 
        ELSIF l_act = 'TABLE_MENTION' THEN       
            DECLARE       
                l_org_id NUMBER := 1;       
                l_owner VARCHAR2(128) := NVL(NULLIF(TRIM(l_p1), ''), l_current_schema);       
                l_search VARCHAR2(200) := LOWER(TRIM(NVL(l_p2, '')));       
            BEGIN       
                apex_json.initialize_clob_output;       
                apex_json.open_object;       
                apex_json.write('status', 'success');       
                apex_json.open_array('tables');       
                -- Only search if filter term provided (min 2 chars from JS)       
                IF l_search IS NOT NULL AND LENGTH(l_search) >= 2 THEN       
                    FOR r IN (       
                        SELECT t.object_name, t.object_type,       
                               NVL(t.summary_en, t.table_comment) AS description,       
                               t.business_domain       
                        FROM asklyze_catalog_tables t       
                        JOIN asklyze_catalog_schemas s ON s.id = t.schema_id       
                        WHERE s.org_id = l_org_id        
                          AND UPPER(s.schema_owner) = UPPER(l_owner)       
                          AND t.is_whitelisted = 'Y'       
                          AND t.is_enabled = 'Y'       
                          AND t.object_name NOT LIKE 'ASKLYZE%'       
                          AND LOWER(t.object_name) LIKE '%' || l_search || '%'       
                        ORDER BY        
                            CASE WHEN LOWER(t.object_name) LIKE l_search || '%' THEN 0 ELSE 1 END,       
                            t.object_name       
                        FETCH FIRST 15 ROWS ONLY       
                    ) LOOP       
                        apex_json.open_object;       
                        apex_json.write('name', r.object_name);       
                        apex_json.write('type', r.object_type);       
                        apex_json.write('description', SUBSTR(r.description, 1, 100));       
                        apex_json.write('domain', r.business_domain);       
                        apex_json.close_object;       
                    END LOOP;       
                END IF;       
                apex_json.close_array;       
                apex_json.close_object;       
                l_out := apex_json.get_clob_output;       
                apex_json.free_output;       
                PRINT_CLOB(l_out);       
            EXCEPTION WHEN OTHERS THEN       
                htp.p('{"status":"error","message":"' || REPLACE(SQLERRM,'"','`') || '"}');       
            END;       
     
        ELSE       
            htp.p('{"status":"error","message":"Unknown action: ' || l_act || '"}');       
        END IF;     
       
    EXCEPTION WHEN OTHERS THEN       
         htp.p('{"status":"error","message":"Global Error: ' || REPLACE(SQLERRM,'"','`') || '"}');       
    END;       
END ajax_handler;       
END ASKLYZE_UI_PKG;
/
