# ASKLYZE

<p align="center">
  <img src="https://imagedelivery.net/lTxZgYILFzqBTIG5m0i9uA/2abe72ea-dac2-4992-2644-910c5ca84500/public"
       alt="ASKLYZE Logo"
       width="220">
</p>

<p align="center"><strong>Transform Oracle APEX into an AI-powered analytics experience.</strong></p>

<p align="center">
  <a href="https://customer-nd6eq88q2tb3xwgl.cloudflarestream.com/6751079fa304be597c3140e0ed900d9a/iframe?preload=true&loop=true&autoplay=true&poster=https%3A%2F%2Fcustomer-nd6eq88q2tb3xwgl.cloudflarestream.com%2F6751079fa304be597c3140e0ed900d9a%2Fthumbnails%2Fthumbnail.jpg%3Ftime%3D%26height%3D600&controls=false">
    <img src="https://customer-nd6eq88q2tb3xwgl.cloudflarestream.com/6751079fa304be597c3140e0ed900d9a/thumbnails/thumbnail.jpg?height=600"
         alt="ASKLYZE Demo Video"
         width="900">
  </a>
</p>
**Transform Oracle APEX into an AI-powered analytics experience.**

ASKLYZE is a commercial Oracle APEX region plug-in that brings natural language analytics and AI-powered data exploration into Oracle APEX applications, while keeping customer data inside their own environment.

- Product Website: https://asklyze.ai
- Support: support@asklyze.ai
- Issues: https://github.com/APEX-Experts/asklyze/issues

---

## Overview

ASKLYZE allows Oracle APEX developers to embed an AI analytics experience directly inside an APEX page using a region plug-in. After installation, customers can configure their API key, connect the plug-in, choose the schemas and tables that ASKLYZE can access, and start using ASKLYZE inside their application.

This repository contains the installation files required for customer deployment.

---

## What is included

After extracting the installation package, the following folders are available:

```text
/database
  install.sql
  deinstall.sql
  tables.sql
  asklyze_cloud_connector_pkg.plb
  asklyze_ui_pkg.sql

/plugin
  region_type_plugin_asklyze_ai_plugin.sql
```

### Database installation files

The `database` folder contains the scripts required to install the ASKLYZE database objects.

Main files:

- `install.sql` – runs the installation scripts in the correct order
- `deinstall.sql` – removes ASKLYZE database objects from the schema
- `tables.sql`
- `asklyze_cloud_connector_pkg.plb`
- `asklyze_ui_pkg.sql`

### APEX plug-in file

The `plugin` folder contains the Oracle APEX region plug-in export file:

- `region_type_plugin_asklyze_ai_plugin.sql`

---

## Requirements

- Oracle APEX environment
- Access to the target schema
- Permission to import plug-ins in the target APEX workspace/application
- A valid ASKLYZE API key

---

## Installation

### 1. Install the database objects

Install the database files first.

#### Option A — SQL Scripts inside APEX

1. Upload the files from the `database` folder into **SQL Scripts**
2. Run:

```sql
install.sql
```

#### Option B — SQLcl / SQL*Plus / command line

Navigate to the `database` folder and run:

```sql
@install.sql
```

**Important:**  
Run `install.sql` from inside the `database` folder so all referenced files are resolved correctly.

---

### 2. Import the region plug-in

After database installation is complete:

1. Open the target Oracle APEX application
2. Go to **Shared Components**
3. Open **Plug-ins**
4. Click **Import**
5. Import:

```text
plugin/region_type_plugin_asklyze_ai_plugin.sql
```

---

### 3. Configure the API key

After importing the plug-in:

1. Open the ASKLYZE plug-in settings
2. Locate the **API Key** attribute
3. Enter your ASKLYZE API key
4. Save the changes

---

### 4. Add ASKLYZE to a page

1. Create or open the page where ASKLYZE will be used
2. Create a new **Region**
3. Select **ASKLYZE AI [Plug-in]**
4. Save the page

#### Recommended templates

For the best layout:

- **Page Template:** `Minimal (No Navigation)`
- **Region Template:** `Blank with Attributes (No Grid)`

---

### 5. Run the page and test the connection

1. Run the page in the browser
2. Start the ASKLYZE connection test
3. Confirm the page loads successfully before testing connectivity

**Important:**  
The page must be opened successfully so the connection with the ASKLYZE server can be established correctly.

---

### 6. Configure data access

After the connection test succeeds:

1. Open **Data Configuration**
2. Select the schemas and tables ASKLYZE should work with
3. Save the configuration

Only the selected tables will be available to ASKLYZE.

---

## Quick start

1. Extract the installation files
2. Run `database/install.sql`
3. Import `plugin/region_type_plugin_asklyze_ai_plugin.sql`
4. Enter the API key
5. Add **ASKLYZE AI [Plug-in]** to a page
6. Use the recommended page and region templates
7. Run the page
8. Test the connection
9. Configure the tables ASKLYZE can access

---

## Uninstall

To remove ASKLYZE from the schema, run:

```text
database/deinstall.sql
```

**Warning:**  
This permanently removes ASKLYZE tables and packages from the schema.

---

## Support

For installation, onboarding, or configuration help:

- Website: https://asklyze.ai
- Email: support@asklyze.ai
- GitHub Issues: https://github.com/APEX-Experts/asklyze/issues
