// Showcase: Complex SQL in Typst via typst-sqlite-zig
//
// Demonstrates JOINs, CTEs, window functions, subqueries,
// aggregations, CASE expressions, and more — all at compile time.

#import "sqlite.typ": sqlite, sqlite-table

#set page(margin: (x: 1.5cm, y: 1.8cm))
#set text(size: 9.5pt, font: "New Computer Modern")
#set heading(numbering: "1.")

#let db = sqlite(read("demo.sqlite", encoding: none))

// Helper: format a number with commas
#let fmt(n) = {
  let s = str(calc.round(n, digits: 0))
  let parts = ()
  let len = s.len()
  let start = if s.starts-with("-") { 1 } else { 0 }
  let digits = s.slice(start)
  let i = digits.len()
  while i > 3 {
    parts.push(digits.slice(i - 3, i))
    i -= 3
  }
  parts.push(digits.slice(0, i))
  let result = parts.rev().join(",")
  if start == 1 { "-" + result } else { result }
}

#let dollar(n) = "$" + fmt(n)

// Color palette
#let accent = rgb("#2563eb")
#let accent-light = rgb("#dbeafe")
#let success = rgb("#16a34a")
#let warning = rgb("#d97706")
#let critical = rgb("#dc2626")
#let muted = rgb("#6b7280")

// ─────────────────────────────────────────────────────────────────────────────

#align(center)[
  #text(size: 22pt, weight: "bold")[Acme Corp — Engineering Report]
  #v(4pt)
  #text(size: 11pt, fill: muted)[
    Generated at compile time from `demo.sqlite` using complex SQL queries
  ]
]
#v(8pt)

// ═══════════════════════════════════════════════════════════════════════════════
= Department Overview
// ═══════════════════════════════════════════════════════════════════════════════

// --- JOIN + GROUP BY + aggregate functions ---
#let dept_summary = (db.query)("
  SELECT
    d.name                          AS department,
    d.location                      AS location,
    COUNT(e.id)                     AS headcount,
    ROUND(AVG(e.salary))            AS avg_salary,
    ROUND(MIN(e.salary))            AS min_salary,
    ROUND(MAX(e.salary))            AS max_salary,
    ROUND(d.budget)                 AS budget
  FROM departments d
  LEFT JOIN employees e ON e.department_id = d.id
  GROUP BY d.id
  ORDER BY headcount DESC
")

#table(
  columns: (1fr, auto, auto, auto, auto, auto, auto),
  align: (left, left, right, right, right, right, right),
  stroke: 0.5pt + luma(200),
  fill: (x, y) => if y == 0 { accent-light } else if calc.rem(y, 2) == 0 { luma(248) },
  table.header(
    [*Department*], [*Location*], [*Count*], [*Avg Salary*], [*Min*], [*Max*], [*Budget*],
  ),
  ..dept_summary.rows.map(r => (
    [#r.at(0)],
    text(size: 8.5pt, fill: muted)[#r.at(1)],
    [*#r.at(2)*],
    [#dollar(r.at(3))],
    [#dollar(r.at(4))],
    [#dollar(r.at(5))],
    [#dollar(r.at(6))],
  )).flatten()
)

// ═══════════════════════════════════════════════════════════════════════════════
= Salary Analysis
// ═══════════════════════════════════════════════════════════════════════════════

== Top Earners by Department — Window Function

// --- RANK() OVER (PARTITION BY ...) ---
#let ranked = (db.query)("
  SELECT
    name,
    title,
    department,
    salary,
    rank
  FROM (
    SELECT
      e.name,
      e.title,
      d.name AS department,
      e.salary,
      RANK() OVER (PARTITION BY d.id ORDER BY e.salary DESC) AS rank
    FROM employees e
    JOIN departments d ON d.id = e.department_id
  )
  WHERE rank <= 2
  ORDER BY department, rank
")

#table(
  columns: (1fr, 1fr, auto, auto, auto),
  align: (left, left, left, right, center),
  stroke: 0.5pt + luma(200),
  fill: (x, y) => if y == 0 { accent-light } else if calc.rem(y, 2) == 0 { luma(248) },
  table.header([*Name*], [*Title*], [*Department*], [*Salary*], [*Rank*]),
  ..ranked.rows.map(r => (
    [#r.at(0)],
    text(size: 8.5pt)[#r.at(1)],
    [#r.at(2)],
    [#dollar(r.at(3))],
    {
      let rank = r.at(4)
      if rank == 1 { text(fill: success, weight: "bold")[#rank] }
      else { [#rank] }
    },
  )).flatten()
)

== Salaries Above Department Average — Correlated Subquery

// --- WHERE salary > (SELECT AVG ... correlated subquery) ---
#let above_avg = (db.query)("
  SELECT
    e.name,
    d.name AS department,
    e.salary,
    ROUND(dept_avg.avg_sal) AS dept_avg,
    ROUND(e.salary - dept_avg.avg_sal) AS delta
  FROM employees e
  JOIN departments d ON d.id = e.department_id
  JOIN (
    SELECT department_id, AVG(salary) AS avg_sal
    FROM employees
    GROUP BY department_id
  ) dept_avg ON dept_avg.department_id = e.department_id
  WHERE e.salary > dept_avg.avg_sal
  ORDER BY delta DESC
  LIMIT 10
")

#table(
  columns: (1fr, auto, auto, auto, auto),
  align: (left, left, right, right, right),
  stroke: 0.5pt + luma(200),
  fill: (x, y) => if y == 0 { accent-light } else if calc.rem(y, 2) == 0 { luma(248) },
  table.header([*Name*], [*Department*], [*Salary*], [*Dept Avg*], [*Above by*]),
  ..above_avg.rows.map(r => (
    [#r.at(0)],
    [#r.at(1)],
    [#dollar(r.at(2))],
    [#dollar(r.at(3))],
    text(fill: success)[+#dollar(r.at(4))],
  )).flatten()
)

// ═══════════════════════════════════════════════════════════════════════════════
= Project Status
// ═══════════════════════════════════════════════════════════════════════════════

== Active Projects — CTE + JOIN + CASE + Aggregation

// --- WITH cte AS (...) + CASE expression ---
#let active_projects = (db.query)("
  WITH project_stats AS (
    SELECT
      pa.project_id,
      COUNT(pa.employee_id) AS team_size,
      ROUND(SUM(pa.hours_per_week), 1) AS total_hours
    FROM project_assignments pa
    GROUP BY pa.project_id
  )
  SELECT
    p.name AS project,
    d.name AS department,
    CASE p.priority
      WHEN 'critical' THEN 'CRITICAL'
      WHEN 'high'     THEN 'High'
      WHEN 'medium'   THEN 'Medium'
      ELSE p.priority
    END AS priority,
    ps.team_size,
    ps.total_hours AS weekly_hours,
    p.start_date
  FROM projects p
  JOIN departments d ON d.id = p.department_id
  LEFT JOIN project_stats ps ON ps.project_id = p.id
  WHERE p.status = 'active'
  ORDER BY
    CASE p.priority
      WHEN 'critical' THEN 1
      WHEN 'high' THEN 2
      WHEN 'medium' THEN 3
      ELSE 4
    END,
    p.start_date
")

#table(
  columns: (1.5fr, auto, auto, auto, auto, auto),
  align: (left, left, center, right, right, left),
  stroke: 0.5pt + luma(200),
  fill: (x, y) => if y == 0 { accent-light } else if calc.rem(y, 2) == 0 { luma(248) },
  table.header([*Project*], [*Department*], [*Priority*], [*Team*], [*Hrs/Wk*], [*Started*]),
  ..active_projects.rows.map(r => (
    text(weight: "bold")[#r.at(0)],
    text(size: 8.5pt)[#r.at(1)],
    {
      let p = r.at(2)
      if p == "CRITICAL" { text(fill: critical, weight: "bold")[#p] }
      else if p == "High" { text(fill: warning, weight: "bold")[#p] }
      else { text(fill: muted)[#p] }
    },
    [#r.at(3)],
    [#r.at(4)],
    text(size: 8.5pt, fill: muted)[#r.at(5)],
  )).flatten()
)

== Completed Projects — Duration Calculation

// --- julianday() date arithmetic ---
#let completed = (db.query)("
  SELECT
    p.name,
    d.name AS department,
    p.start_date,
    p.end_date,
    CAST(julianday(p.end_date) - julianday(p.start_date) AS INTEGER) AS days,
    (SELECT COUNT(*) FROM project_assignments pa WHERE pa.project_id = p.id) AS team_size
  FROM projects p
  JOIN departments d ON d.id = p.department_id
  WHERE p.status = 'completed'
  ORDER BY days DESC
")

#table(
  columns: (1.5fr, auto, auto, auto, auto, auto),
  align: (left, left, left, left, right, right),
  stroke: 0.5pt + luma(200),
  fill: (x, y) => if y == 0 { accent-light } else if calc.rem(y, 2) == 0 { luma(248) },
  table.header([*Project*], [*Department*], [*Start*], [*End*], [*Days*], [*Team*]),
  ..completed.rows.map(r => (
    [#r.at(0)],
    text(size: 8.5pt)[#r.at(1)],
    text(size: 8.5pt, fill: muted)[#r.at(2)],
    text(size: 8.5pt, fill: muted)[#r.at(3)],
    [*#r.at(4)*],
    [#r.at(5)],
  )).flatten()
)

// ═══════════════════════════════════════════════════════════════════════════════
= People & Workload
// ═══════════════════════════════════════════════════════════════════════════════

== Busiest People — Multi-table JOIN + GROUP BY + HAVING

// --- HAVING clause to filter aggregates ---
#let busiest = (db.query)("
  SELECT
    e.name,
    e.title,
    d.name AS department,
    COUNT(pa.project_id) AS num_projects,
    ROUND(SUM(pa.hours_per_week), 1) AS total_hours,
    GROUP_CONCAT(p.name, ', ') AS projects
  FROM employees e
  JOIN departments d ON d.id = e.department_id
  JOIN project_assignments pa ON pa.employee_id = e.id
  JOIN projects p ON p.id = pa.project_id AND p.status IN ('active', 'planning')
  GROUP BY e.id
  HAVING COUNT(pa.project_id) >= 2
  ORDER BY total_hours DESC
")

#table(
  columns: (auto, auto, auto, auto, auto, 2fr),
  align: (left, left, left, right, right, left),
  stroke: 0.5pt + luma(200),
  fill: (x, y) => if y == 0 { accent-light } else if calc.rem(y, 2) == 0 { luma(248) },
  table.header([*Name*], [*Title*], [*Dept*], [*Projects*], [*Hrs/Wk*], [*Active Projects*]),
  ..busiest.rows.map(r => {
    let hours = r.at(4)
    let hours_cell = if hours >= 40 {
      text(fill: critical, weight: "bold")[#hours]
    } else if hours >= 30 {
      text(fill: warning)[#hours]
    } else {
      [#hours]
    }
    (
      [#r.at(0)],
      text(size: 8.5pt)[#r.at(1)],
      text(size: 8.5pt)[#r.at(2)],
      [*#r.at(3)*],
      hours_cell,
      text(size: 8pt, fill: muted)[#r.at(5)],
    )
  }).flatten()
)

== Management Chain — Self-JOIN

// --- Self-referencing join on employees.manager_id ---
#let org_tree = (db.query)("
  SELECT
    e.name AS employee,
    e.title,
    m.name AS reports_to,
    m.title AS manager_title,
    d.name AS department
  FROM employees e
  LEFT JOIN employees m ON m.id = e.manager_id
  JOIN departments d ON d.id = e.department_id
  ORDER BY d.name, m.name NULLS FIRST, e.name
")

#table(
  columns: (1fr, 1fr, 1fr, 1fr, auto),
  align: (left, left, left, left, left),
  stroke: 0.5pt + luma(200),
  fill: (x, y) => if y == 0 { accent-light } else if calc.rem(y, 2) == 0 { luma(248) },
  table.header([*Employee*], [*Title*], [*Reports To*], [*Manager Title*], [*Dept*]),
  ..org_tree.rows.map(r => (
    [#r.at(0)],
    text(size: 8.5pt)[#r.at(1)],
    if r.at(2) == none { text(fill: muted, size: 8.5pt)[_department head_] }
    else { [#r.at(2)] },
    if r.at(3) == none { [] } else { text(size: 8.5pt, fill: muted)[#r.at(3)] },
    text(size: 8.5pt)[#r.at(4)],
  )).flatten()
)

// ═══════════════════════════════════════════════════════════════════════════════
= Revenue & Financial
// ═══════════════════════════════════════════════════════════════════════════════

== Quarterly Revenue Trend — Year-over-Year Comparison

// --- CTE with self-join for YoY comparison ---
#let yoy = (db.query)("
  WITH q2024 AS (
    SELECT quarter, department_id, revenue, costs
    FROM quarterly_sales WHERE year = 2024
  ),
  q2023 AS (
    SELECT quarter, department_id, revenue, costs
    FROM quarterly_sales WHERE year = 2023
  )
  SELECT
    'Q' || q2024.quarter AS quarter,
    d.name AS department,
    ROUND(q2023.revenue) AS rev_2023,
    ROUND(q2024.revenue) AS rev_2024,
    ROUND((q2024.revenue - q2023.revenue) / q2023.revenue * 100, 1) AS growth_pct,
    ROUND(q2024.revenue - q2024.costs) AS profit_2024
  FROM q2024
  JOIN q2023 ON q2023.quarter = q2024.quarter
    AND q2023.department_id = q2024.department_id
  JOIN departments d ON d.id = q2024.department_id
  WHERE d.name = 'Sales'
  ORDER BY q2024.quarter
")

#table(
  columns: (auto, auto, auto, auto, auto, auto),
  align: (center, left, right, right, right, right),
  stroke: 0.5pt + luma(200),
  fill: (x, y) => if y == 0 { accent-light } else if calc.rem(y, 2) == 0 { luma(248) },
  table.header([*Quarter*], [*Dept*], [*2023 Rev*], [*2024 Rev*], [*YoY Growth*], [*2024 Profit*]),
  ..yoy.rows.map(r => (
    text(weight: "bold")[#r.at(0)],
    [#r.at(1)],
    [#dollar(r.at(2))],
    [#dollar(r.at(3))],
    text(fill: success)[+#r.at(4)%],
    text(fill: accent, weight: "bold")[#dollar(r.at(5))],
  )).flatten()
)

== Department Profitability — UNION + Aggregation

// --- UNION ALL to combine departments, then aggregate ---
#let profitability = (db.query)("
  SELECT
    d.name AS department,
    ROUND(SUM(qs.revenue)) AS total_revenue,
    ROUND(SUM(qs.costs)) AS total_costs,
    ROUND(SUM(qs.revenue) - SUM(qs.costs)) AS total_profit,
    ROUND((SUM(qs.revenue) - SUM(qs.costs)) / SUM(qs.revenue) * 100, 1) AS margin_pct
  FROM quarterly_sales qs
  JOIN departments d ON d.id = qs.department_id
  WHERE qs.year = 2024
  GROUP BY d.id
  ORDER BY total_profit DESC
")

#table(
  columns: (1fr, auto, auto, auto, auto),
  align: (left, right, right, right, right),
  stroke: 0.5pt + luma(200),
  fill: (x, y) => if y == 0 { accent-light } else if calc.rem(y, 2) == 0 { luma(248) },
  table.header([*Department*], [*Revenue*], [*Costs*], [*Profit*], [*Margin*]),
  ..profitability.rows.map(r => (
    text(weight: "bold")[#r.at(0)],
    [#dollar(r.at(1))],
    text(fill: muted)[#dollar(r.at(2))],
    text(fill: success, weight: "bold")[#dollar(r.at(3))],
    [#r.at(4)%],
  )).flatten()
)

// ═══════════════════════════════════════════════════════════════════════════════
= Cross-Cutting Insights
// ═══════════════════════════════════════════════════════════════════════════════

== Hiring Cohorts — Date Grouping + Running Total

// --- substr for year extraction, window function for running total ---
#let cohorts = (db.query)("
  SELECT
    hire_year,
    hires,
    SUM(hires) OVER (ORDER BY hire_year) AS running_total,
    ROUND(AVG(avg_sal)) AS cohort_avg_salary
  FROM (
    SELECT
      SUBSTR(hire_date, 1, 4) AS hire_year,
      COUNT(*) AS hires,
      AVG(salary) AS avg_sal
    FROM employees
    GROUP BY SUBSTR(hire_date, 1, 4)
  )
  ORDER BY hire_year
")

#table(
  columns: (auto, auto, auto, auto),
  align: (center, right, right, right),
  stroke: 0.5pt + luma(200),
  fill: (x, y) => if y == 0 { accent-light } else if calc.rem(y, 2) == 0 { luma(248) },
  table.header([*Year*], [*New Hires*], [*Running Total*], [*Cohort Avg Salary*]),
  ..cohorts.rows.map(r => (
    text(weight: "bold")[#r.at(0)],
    [#r.at(1)],
    [#r.at(2)],
    [#dollar(r.at(3))],
  )).flatten()
)

== Unassigned Employees — NOT EXISTS Subquery

// --- NOT EXISTS to find people with no active project ---
#let unassigned = (db.query)("
  SELECT
    e.name,
    e.title,
    d.name AS department,
    e.hire_date
  FROM employees e
  JOIN departments d ON d.id = e.department_id
  WHERE NOT EXISTS (
    SELECT 1
    FROM project_assignments pa
    JOIN projects p ON p.id = pa.project_id
    WHERE pa.employee_id = e.id
      AND p.status IN ('active', 'planning')
  )
  ORDER BY d.name, e.name
")

#if unassigned.rows.len() > 0 [
  #table(
    columns: (1fr, 1fr, auto, auto),
    align: (left, left, left, left),
    stroke: 0.5pt + luma(200),
    fill: (x, y) => if y == 0 { accent-light } else if calc.rem(y, 2) == 0 { luma(248) },
    table.header([*Name*], [*Title*], [*Department*], [*Hire Date*]),
    ..unassigned.rows.map(r => (
      [#r.at(0)],
      text(size: 8.5pt)[#r.at(1)],
      [#r.at(2)],
      text(size: 8.5pt, fill: muted)[#r.at(3)],
    )).flatten()
  )

  #text(size: 8.5pt, fill: muted)[
    #unassigned.rows.len() employee(s) not assigned to any active or planned project.
  ]
] else [
  _All employees are assigned to at least one active project._
]

== Database Schema — Introspection

#let tables = (db.tables)()

#for tbl in tables [
  #let s = (db.schema)(tbl)
  #text(weight: "bold")[#raw(tbl)] #text(fill: muted, size: 8.5pt)[
    — #s.columns.map(c => c.name + " " + text(fill: accent)[#c.type]).join(", ")
  ] \
]

// ─────────────────────────────────────────────────────────────────────────────

#v(1fr)
#line(length: 100%, stroke: 0.5pt + luma(200))
#text(size: 8pt, fill: muted)[
  This document was generated entirely at compile time.
  Every table above is a live SQL query executed against `demo.sqlite` via the `typst-sqlite-zig` WASM plugin.
  SQL features demonstrated: JOINs (inner, left, self), CTEs, window functions (RANK, SUM OVER),
  subqueries (correlated, NOT EXISTS), GROUP BY + HAVING, CASE expressions, date arithmetic,
  GROUP_CONCAT, and running totals.
]
