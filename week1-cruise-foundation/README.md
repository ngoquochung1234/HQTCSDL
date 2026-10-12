# Aurora Cruise - Week 1 Foundation

This folder is the Week 1 baseline for the cruise activity and service management project.

## Week 1 scope

- Requirements and design documents
- ERD and data dictionary
- SQL Server schema and seed data
- A small web/API shell for demonstrating the foundation

Business procedures, full role workflows, POS synchronization, finance settlement,
and operational dashboards remain in the later-week implementation in `cruise-sql`.

## Folder structure

```text
database/
  01-schema.sql       SQL Server tables, keys, constraints, indexes, audit triggers
  03-seed.sql         Initial roles, packages, services, and demo data
docs/
  REQUIREMENTS.md     Functional and non-functional requirements
  ERD.md              Entity relationship design
  DICTIONARY.md       Data dictionary
  DESIGN.md           Design decisions and scope
public/
  index.html          Week 1 foundation page
  style.css           Responsive presentation styles
server.mjs            Minimal Node.js static web/API shell
package.json          Run commands
```

## Run the Week 1 web shell

Requires Node.js 18 or newer:

```powershell
npm start
```

Open <http://localhost:3000>.

The shell is intentionally independent of SQL Server so the Week 1 design can
be reviewed before the later business procedures are installed.

## Install the database foundation

The SQL scripts use SQL Server/T-SQL and SQLCMD mode. In SSMS, enable **SQLCMD
Mode**, then run:

1. `database/01-schema.sql`
2. `database/03-seed.sql`

The scripts create/use the `CruiseCoursework` database. Do not run the schema
script again on a database that already has tables.

## Source

This Week 1 folder is a reviewable subset of the complete implementation in
`../cruise-sql`. It excludes `node_modules`, generated bundles, tests, and
later-week business/API scripts.
