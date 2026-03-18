<p align="center">
  <img src="https://imagedelivery.net/lTxZgYILFzqBTIG5m0i9uA/2abe72ea-dac2-4992-2644-910c5ca84500/public"
       alt="ASKLYZE Logo"
       width="400">
</p>


<h2 align="center">Transform Oracle APEX into an AI-powered analytics experience.</h2>

<p align="center">
  <a href="https://asklyze.ai"><img src="https://img.shields.io/badge/Website-asklyze.ai-0066FF?style=flat-square&logo=globe&logoColor=white" alt="Website"></a>
  <a href="https://github.com/APEX-Experts/asklyze/releases"><img src="https://img.shields.io/github/v/release/APEX-Experts/asklyze?style=flat-square&color=0066FF&label=Latest%20Release" alt="Latest Release"></a>
  <a href="https://github.com/APEX-Experts/asklyze/issues"><img src="https://img.shields.io/github/issues/APEX-Experts/asklyze?style=flat-square&color=orange" alt="Issues"></a>
  <a href="mailto:support@asklyze.ai"><img src="https://img.shields.io/badge/Support-support%40asklyze.ai-green?style=flat-square&logo=mail&logoColor=white" alt="Support"></a>
  <img src="https://img.shields.io/badge/Oracle%20APEX-Compatible-red?style=flat-square&logo=oracle&logoColor=white" alt="Oracle APEX">
</p>

<br>

<p align="center">
  <img src="https://raw.githubusercontent.com/APEX-Experts/asklyze/main/asklyze-demo.gif"
       alt="ASKLYZE Demo — Dashboard Builder"
       width="900">
</p>

---

## What is ASKLYZE?

**ASKLYZE** is a commercial Oracle APEX region plug-in that brings natural language analytics and AI-powered data exploration directly into your Oracle APEX applications — with **zero data movement**.

Instead of exporting data to an external BI tool, ASKLYZE embeds inside your existing APEX environment. Your users ask questions in plain English (or Arabic), and ASKLYZE generates SQL, executes it against your own database, and returns interactive dashboards — all without your data ever leaving your infrastructure.

- 🌐 **Product Website:** [asklyze.ai](https://asklyze.ai)  
- 📧 **Support:** [support@asklyze.ai](mailto:support@asklyze.ai)  
- 🐛 **Issues:** [github.com/APEX-Experts/asklyze/issues](https://github.com/APEX-Experts/asklyze/issues)

---

## Key Features

| Feature | Description |
|---|---|
| 🗣️ **Natural Language to SQL** | Ask questions in plain English — ASKLYZE generates and executes the SQL automatically |
| 📊 **AI-Generated Dashboards** | Instantly renders interactive charts and reports from query results |
| 🔒 **Zero Data Movement** | Your data never leaves your Oracle environment — queries run locally |
| 🛡️ **Whitelisted Schema Security** | You control exactly which schemas and tables ASKLYZE can access |
| 🔌 **Native APEX Integration** | Delivered as a standard region plug-in — no external apps, no iframes, no complex setup |
| 🌍 **Bilingual Support** | Supports English and Arabic interfaces out of the box |
| ⚡ **No ETL Required** | Works directly against your live Oracle database with no data pipeline |

---

## How It Works

```
User asks a question in natural language
        │
        ▼
ASKLYZE sends the question + your whitelisted schema metadata to the AI
        │
        ▼
AI generates a SQL query (only against your approved tables)
        │
        ▼
Query executes inside YOUR Oracle database
        │
        ▼
Results are returned and rendered as an interactive dashboard inside APEX
```

At no point does your actual data leave your environment. Only table/column metadata is shared with the AI to generate the query.

---

## Requirements

- Oracle APEX (any modern version)
- Access to the target schema with permission to create tables and packages
- Permission to import plug-ins in the target APEX workspace/application
- A valid **ASKLYZE API key** — [get one at asklyze.ai](https://asklyze.ai)

---

## Installation

### What's Included

After extracting the installation package you will find:

```
asklyze/
├── database/
│   ├── install.sql                              ← Run this first
│   ├── deinstall.sql                            ← Removes all ASKLYZE objects
│   ├── tables.sql
│   ├── asklyze_cloud_connector_pkg.plb
│   └── asklyze_ui_pkg.sql
└── plugin/
    └── region_type_plugin_asklyze_ai_plugin.sql ← Import into APEX
```

---

### Step 1 — Install the Database Objects

Run `install.sql` from inside the `database/` folder so all referenced scripts resolve correctly.

**Option A — SQL Scripts inside APEX**

1. Upload all files from the `database/` folder into **SQL Scripts**
2. Run `install.sql`

**Option B — SQLcl / SQL\*Plus / Command Line**

```bash
cd database
sqlcl your_user/your_password@your_db @install.sql
```

> ⚠️ **Important:** Always run `install.sql` from within the `database/` folder, not from the parent directory.

---

### Step 2 — Import the Region Plug-in

1. Open your target Oracle APEX application
2. Navigate to **Shared Components → Plug-ins**
3. Click **Import**
4. Select and import:

   ```
   plugin/region_type_plugin_asklyze_ai_plugin.sql
   ```

---

### Step 3 — Configure the API Key

1. Open the **ASKLYZE** plug-in in Shared Components
2. Locate the **API Key** attribute
3. Enter your ASKLYZE API key
4. Save

> Don't have an API key yet? [Register at asklyze.ai](https://asklyze.ai)

---

### Step 4 — Add ASKLYZE to a Page

1. Open (or create) the page where ASKLYZE will live
2. Create a new **Region**
3. Set the region type to **ASKLYZE AI [Plug-in]**
4. Save the page

**Recommended page settings for best results:**

| Setting | Recommended Value |
|---|---|
| Page Template | `Minimal (No Navigation)` |
| Region Template | `Blank with Attributes (No Grid)` |

---

### Step 5 — Test the Connection

1. Run the page in the browser
2. Start the **ASKLYZE Connection Test** from the interface
3. Confirm the connection status shows as successful

> ⚠️ **Important:** The page must load successfully in the browser before the connection test will work. The plug-in establishes its link with the ASKLYZE server on page load.

---

### Step 6 — Configure Data Access

Once connected:

1. Open **Data Configuration** inside the ASKLYZE interface
2. Select the **schemas** and **tables** ASKLYZE is allowed to query
3. Save the configuration

Only the tables you explicitly select will be available to ASKLYZE. Everything else in your database remains invisible to the AI.

---

## Quick Start Summary

```
1. Extract the installation package
2. Run  database/install.sql
3. Import  plugin/region_type_plugin_asklyze_ai_plugin.sql  into your APEX application
4. Enter your API key in the plug-in settings
5. Add the ASKLYZE AI [Plug-in] region to a page
6. Apply the recommended page and region templates
7. Run the page and complete the connection test
8. Open Data Configuration and select your allowed tables
9. Start asking questions
```

---

## Security & Data Privacy

ASKLYZE is designed with enterprise data security as a core requirement, not an afterthought.

- **Your data stays in your database.** ASKLYZE never transfers, copies, or stores your actual records.
- **Schema whitelisting.** You explicitly choose which tables the AI can query. No table you haven't approved will ever be touched.
- **Metadata only.** When generating SQL, only table names and column names are sent to the AI — not data values.
- **Your Oracle credentials remain yours.** ASKLYZE connects through your existing Oracle APEX environment using your own database connection.

---

## Uninstall

To completely remove ASKLYZE from your schema:

```sql
@database/deinstall.sql
```

> ⚠️ **Warning:** This permanently removes all ASKLYZE tables, packages, and configuration data from the schema. This action cannot be undone.

To remove the plug-in from an APEX application, delete it from **Shared Components → Plug-ins**.

---

## Support

If you run into any issues during installation or configuration:

| Channel | Link |
|---|---|
| 📖 Documentation | [asklyze.ai](https://asklyze.ai) |
| 📧 Email Support | [support@asklyze.ai](mailto:support@asklyze.ai) |
| 🐛 Bug Reports | [GitHub Issues](https://github.com/APEX-Experts/asklyze/issues) |

When reporting a bug, please include your Oracle APEX version, the contents of any error messages, and the steps to reproduce the issue.

---

<p align="center">
  Built by <a href="https://github.com/APEX-Experts">APEX Experts</a> · <a href="https://asklyze.ai">asklyze.ai</a>
</p>
