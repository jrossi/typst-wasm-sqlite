const std = @import("std");
const c = @cImport({
    @cInclude("sqlite3.h");
});

fn exec(db: *c.sqlite3, sql: [*:0]const u8) void {
    var err_msg: [*c]u8 = null;
    const rc = c.sqlite3_exec(db, sql, null, null, &err_msg);
    if (rc != c.SQLITE_OK) {
        if (err_msg != null) {
            const msg: [*:0]const u8 = @ptrCast(err_msg);
            std.debug.print("SQL error: {s}\n", .{msg});
            c.sqlite3_free(err_msg);
        }
        std.process.exit(1);
    }
}

fn prepare(db: *c.sqlite3, sql: [*:0]const u8) *c.sqlite3_stmt {
    var stmt: ?*c.sqlite3_stmt = null;
    const rc = c.sqlite3_prepare_v2(db, sql, -1, &stmt, null);
    if (rc != c.SQLITE_OK) {
        const msg = c.sqlite3_errmsg(db);
        std.debug.print("Prepare error: {s}\n", .{std.mem.span(msg)});
        std.process.exit(1);
    }
    return stmt.?;
}

fn step(db: *c.sqlite3, stmt: *c.sqlite3_stmt) void {
    const rc = c.sqlite3_step(stmt);
    if (rc != c.SQLITE_DONE) {
        const msg = c.sqlite3_errmsg(db);
        std.debug.print("Step error: {s}\n", .{std.mem.span(msg)});
        std.process.exit(1);
    }
    _ = c.sqlite3_reset(stmt);
}

fn bindText(stmt: *c.sqlite3_stmt, col: c_int, val: [*:0]const u8) void {
    _ = c.sqlite3_bind_text(stmt, col, val, -1, null);
}

fn bindInt(stmt: *c.sqlite3_stmt, col: c_int, val: i64) void {
    _ = c.sqlite3_bind_int64(stmt, col, val);
}

fn bindDouble(stmt: *c.sqlite3_stmt, col: c_int, val: f64) void {
    _ = c.sqlite3_bind_double(stmt, col, val);
}

fn bindNull(stmt: *c.sqlite3_stmt, col: c_int) void {
    _ = c.sqlite3_bind_null(stmt, col);
}

pub fn main() !void {
    var db: ?*c.sqlite3 = null;
    const rc = c.sqlite3_open("demo.sqlite", &db);
    if (rc != c.SQLITE_OK) {
        std.debug.print("Cannot open database\n", .{});
        return error.DatabaseOpen;
    }
    defer _ = c.sqlite3_close(db);
    const d = db.?;

    exec(d, "PRAGMA journal_mode=OFF");
    exec(d, "BEGIN TRANSACTION");

    // =========================================================================
    // departments
    // =========================================================================
    exec(d, "DROP TABLE IF EXISTS project_assignments");
    exec(d, "DROP TABLE IF EXISTS quarterly_sales");
    exec(d, "DROP TABLE IF EXISTS projects");
    exec(d, "DROP TABLE IF EXISTS employees");
    exec(d, "DROP TABLE IF EXISTS departments");

    exec(d,
        \\CREATE TABLE departments (
        \\  id INTEGER PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  budget REAL NOT NULL,
        \\  location TEXT NOT NULL
        \\)
    );
    {
        const s = prepare(d, "INSERT INTO departments VALUES (?, ?, ?, ?)");
        defer _ = c.sqlite3_finalize(s);

        const depts = [_]struct { id: i64, name: [*:0]const u8, budget: f64, location: [*:0]const u8 }{
            .{ .id = 1, .name = "Engineering", .budget = 2400000, .location = "Building A" },
            .{ .id = 2, .name = "Product", .budget = 1200000, .location = "Building A" },
            .{ .id = 3, .name = "Design", .budget = 800000, .location = "Building B" },
            .{ .id = 4, .name = "Marketing", .budget = 950000, .location = "Building C" },
            .{ .id = 5, .name = "Sales", .budget = 1800000, .location = "Building C" },
            .{ .id = 6, .name = "Data Science", .budget = 1600000, .location = "Building A" },
            .{ .id = 7, .name = "Operations", .budget = 700000, .location = "Building D" },
        };

        for (depts) |dept| {
            bindInt(s, 1, dept.id);
            bindText(s, 2, dept.name);
            bindDouble(s, 3, dept.budget);
            bindText(s, 4, dept.location);
            step(d, s);
        }
    }

    // =========================================================================
    // employees
    // =========================================================================
    exec(d,
        \\CREATE TABLE employees (
        \\  id INTEGER PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  department_id INTEGER NOT NULL REFERENCES departments(id),
        \\  title TEXT NOT NULL,
        \\  salary REAL NOT NULL,
        \\  hire_date TEXT NOT NULL,
        \\  manager_id INTEGER REFERENCES employees(id)
        \\)
    );
    {
        const s = prepare(d, "INSERT INTO employees VALUES (?, ?, ?, ?, ?, ?, ?)");
        defer _ = c.sqlite3_finalize(s);

        const E = struct { id: i64, name: [*:0]const u8, dept: i64, title: [*:0]const u8, salary: f64, hire: [*:0]const u8, mgr: ?i64 };
        const emps = [_]E{
            // Engineering (dept 1)
            .{ .id = 1, .name = "Alice Chen", .dept = 1, .title = "VP Engineering", .salary = 245000, .hire = "2019-03-15", .mgr = null },
            .{ .id = 2, .name = "Bob Martinez", .dept = 1, .title = "Staff Engineer", .salary = 195000, .hire = "2019-06-01", .mgr = 1 },
            .{ .id = 3, .name = "Carol Wu", .dept = 1, .title = "Senior Engineer", .salary = 175000, .hire = "2020-01-10", .mgr = 1 },
            .{ .id = 4, .name = "David Kim", .dept = 1, .title = "Senior Engineer", .salary = 170000, .hire = "2020-08-20", .mgr = 1 },
            .{ .id = 5, .name = "Eva Novak", .dept = 1, .title = "Engineer", .salary = 140000, .hire = "2021-04-01", .mgr = 2 },
            .{ .id = 6, .name = "Frank Osei", .dept = 1, .title = "Engineer", .salary = 135000, .hire = "2021-09-15", .mgr = 2 },
            .{ .id = 7, .name = "Grace Liu", .dept = 1, .title = "Junior Engineer", .salary = 110000, .hire = "2023-01-10", .mgr = 3 },
            .{ .id = 8, .name = "Hiro Tanaka", .dept = 1, .title = "Junior Engineer", .salary = 105000, .hire = "2023-06-01", .mgr = 3 },
            // Product (dept 2)
            .{ .id = 9, .name = "Irene Popov", .dept = 2, .title = "VP Product", .salary = 230000, .hire = "2019-04-01", .mgr = null },
            .{ .id = 10, .name = "James Okafor", .dept = 2, .title = "Senior PM", .salary = 165000, .hire = "2020-03-15", .mgr = 9 },
            .{ .id = 11, .name = "Karen Singh", .dept = 2, .title = "PM", .salary = 145000, .hire = "2021-02-01", .mgr = 9 },
            .{ .id = 12, .name = "Leo Herrera", .dept = 2, .title = "Associate PM", .salary = 115000, .hire = "2022-08-10", .mgr = 10 },
            // Design (dept 3)
            .{ .id = 13, .name = "Mina Johansson", .dept = 3, .title = "Design Lead", .salary = 175000, .hire = "2019-07-01", .mgr = null },
            .{ .id = 14, .name = "Nabil Farouk", .dept = 3, .title = "Senior Designer", .salary = 150000, .hire = "2020-11-01", .mgr = 13 },
            .{ .id = 15, .name = "Olivia Park", .dept = 3, .title = "Designer", .salary = 125000, .hire = "2022-01-15", .mgr = 13 },
            // Marketing (dept 4)
            .{ .id = 16, .name = "Priya Sharma", .dept = 4, .title = "Marketing Director", .salary = 190000, .hire = "2019-05-01", .mgr = null },
            .{ .id = 17, .name = "Quinn O'Brien", .dept = 4, .title = "Content Lead", .salary = 130000, .hire = "2021-03-01", .mgr = 16 },
            .{ .id = 18, .name = "Rosa Gutierrez", .dept = 4, .title = "Marketing Analyst", .salary = 110000, .hire = "2022-06-01", .mgr = 16 },
            // Sales (dept 5)
            .{ .id = 19, .name = "Sam Abadi", .dept = 5, .title = "Sales Director", .salary = 200000, .hire = "2019-08-01", .mgr = null },
            .{ .id = 20, .name = "Tanya Volkov", .dept = 5, .title = "Senior AE", .salary = 155000, .hire = "2020-04-01", .mgr = 19 },
            .{ .id = 21, .name = "Umar Diallo", .dept = 5, .title = "Account Executive", .salary = 120000, .hire = "2021-07-01", .mgr = 19 },
            .{ .id = 22, .name = "Vera Costa", .dept = 5, .title = "Account Executive", .salary = 118000, .hire = "2022-02-15", .mgr = 20 },
            .{ .id = 23, .name = "Wei Zhang", .dept = 5, .title = "SDR", .salary = 85000, .hire = "2023-03-01", .mgr = 20 },
            // Data Science (dept 6)
            .{ .id = 24, .name = "Xena Papadopoulos", .dept = 6, .title = "Data Science Lead", .salary = 210000, .hire = "2020-01-15", .mgr = null },
            .{ .id = 25, .name = "Yusuf Al-Rashid", .dept = 6, .title = "Senior Data Scientist", .salary = 180000, .hire = "2020-09-01", .mgr = 24 },
            .{ .id = 26, .name = "Zara Mbeki", .dept = 6, .title = "Data Scientist", .salary = 155000, .hire = "2021-06-01", .mgr = 24 },
            .{ .id = 27, .name = "Aiden O'Connor", .dept = 6, .title = "ML Engineer", .salary = 165000, .hire = "2022-01-10", .mgr = 24 },
            // Operations (dept 7)
            .{ .id = 28, .name = "Bianca Rossi", .dept = 7, .title = "Ops Manager", .salary = 140000, .hire = "2020-05-01", .mgr = null },
            .{ .id = 29, .name = "Carlos Mendez", .dept = 7, .title = "DevOps Engineer", .salary = 150000, .hire = "2021-01-15", .mgr = 28 },
            .{ .id = 30, .name = "Diana Petrova", .dept = 7, .title = "SRE", .salary = 155000, .hire = "2021-11-01", .mgr = 28 },
        };

        for (emps) |e| {
            bindInt(s, 1, e.id);
            bindText(s, 2, e.name);
            bindInt(s, 3, e.dept);
            bindText(s, 4, e.title);
            bindDouble(s, 5, e.salary);
            bindText(s, 6, e.hire);
            if (e.mgr) |mgr| {
                bindInt(s, 7, mgr);
            } else {
                bindNull(s, 7);
            }
            step(d, s);
        }
    }

    // =========================================================================
    // projects
    // =========================================================================
    exec(d,
        \\CREATE TABLE projects (
        \\  id INTEGER PRIMARY KEY,
        \\  name TEXT NOT NULL,
        \\  department_id INTEGER NOT NULL REFERENCES departments(id),
        \\  status TEXT NOT NULL,
        \\  start_date TEXT NOT NULL,
        \\  end_date TEXT,
        \\  priority TEXT NOT NULL
        \\)
    );
    {
        const s = prepare(d, "INSERT INTO projects VALUES (?, ?, ?, ?, ?, ?, ?)");
        defer _ = c.sqlite3_finalize(s);

        const P = struct { id: i64, name: [*:0]const u8, dept: i64, status: [*:0]const u8, start: [*:0]const u8, end: ?[*:0]const u8, priority: [*:0]const u8 };
        const projects = [_]P{
            .{ .id = 1, .name = "Platform Rewrite", .dept = 1, .status = "active", .start = "2024-01-15", .end = null, .priority = "critical" },
            .{ .id = 2, .name = "Mobile App v2", .dept = 1, .status = "active", .start = "2024-03-01", .end = null, .priority = "high" },
            .{ .id = 3, .name = "API Gateway", .dept = 1, .status = "completed", .start = "2023-06-01", .end = "2024-02-28", .priority = "high" },
            .{ .id = 4, .name = "Design System", .dept = 3, .status = "active", .start = "2024-02-01", .end = null, .priority = "high" },
            .{ .id = 5, .name = "Customer Portal", .dept = 2, .status = "active", .start = "2024-04-01", .end = null, .priority = "critical" },
            .{ .id = 6, .name = "Data Pipeline v3", .dept = 6, .status = "active", .start = "2024-01-10", .end = null, .priority = "high" },
            .{ .id = 7, .name = "Brand Refresh", .dept = 4, .status = "completed", .start = "2023-09-01", .end = "2024-01-31", .priority = "medium" },
            .{ .id = 8, .name = "Sales Dashboard", .dept = 5, .status = "active", .start = "2024-05-01", .end = null, .priority = "medium" },
            .{ .id = 9, .name = "Infrastructure Migration", .dept = 7, .status = "active", .start = "2024-02-15", .end = null, .priority = "critical" },
            .{ .id = 10, .name = "Recommendation Engine", .dept = 6, .status = "planning", .start = "2024-07-01", .end = null, .priority = "high" },
            .{ .id = 11, .name = "Onboarding Flow", .dept = 2, .status = "completed", .start = "2023-04-01", .end = "2023-11-30", .priority = "high" },
            .{ .id = 12, .name = "Security Audit", .dept = 7, .status = "completed", .start = "2023-10-01", .end = "2024-03-15", .priority = "critical" },
        };

        for (projects) |p| {
            bindInt(s, 1, p.id);
            bindText(s, 2, p.name);
            bindInt(s, 3, p.dept);
            bindText(s, 4, p.status);
            bindText(s, 5, p.start);
            if (p.end) |end| {
                bindText(s, 6, end);
            } else {
                bindNull(s, 6);
            }
            bindText(s, 7, p.priority);
            step(d, s);
        }
    }

    // =========================================================================
    // project_assignments
    // =========================================================================
    exec(d,
        \\CREATE TABLE project_assignments (
        \\  employee_id INTEGER NOT NULL REFERENCES employees(id),
        \\  project_id INTEGER NOT NULL REFERENCES projects(id),
        \\  role TEXT NOT NULL,
        \\  hours_per_week REAL NOT NULL,
        \\  PRIMARY KEY (employee_id, project_id)
        \\)
    );
    {
        const s = prepare(d, "INSERT INTO project_assignments VALUES (?, ?, ?, ?)");
        defer _ = c.sqlite3_finalize(s);

        const A = struct { emp: i64, proj: i64, role: [*:0]const u8, hours: f64 };
        const assignments = [_]A{
            // Platform Rewrite (proj 1)
            .{ .emp = 1, .proj = 1, .role = "sponsor", .hours = 5 },
            .{ .emp = 2, .proj = 1, .role = "tech lead", .hours = 30 },
            .{ .emp = 3, .proj = 1, .role = "developer", .hours = 35 },
            .{ .emp = 5, .proj = 1, .role = "developer", .hours = 40 },
            .{ .emp = 7, .proj = 1, .role = "developer", .hours = 40 },
            .{ .emp = 10, .proj = 1, .role = "product", .hours = 10 },
            // Mobile App v2 (proj 2)
            .{ .emp = 4, .proj = 2, .role = "tech lead", .hours = 30 },
            .{ .emp = 6, .proj = 2, .role = "developer", .hours = 35 },
            .{ .emp = 8, .proj = 2, .role = "developer", .hours = 40 },
            .{ .emp = 11, .proj = 2, .role = "product", .hours = 15 },
            .{ .emp = 15, .proj = 2, .role = "designer", .hours = 20 },
            // API Gateway (proj 3 - completed)
            .{ .emp = 2, .proj = 3, .role = "tech lead", .hours = 25 },
            .{ .emp = 3, .proj = 3, .role = "developer", .hours = 30 },
            .{ .emp = 29, .proj = 3, .role = "devops", .hours = 15 },
            // Design System (proj 4)
            .{ .emp = 13, .proj = 4, .role = "lead", .hours = 25 },
            .{ .emp = 14, .proj = 4, .role = "designer", .hours = 30 },
            .{ .emp = 15, .proj = 4, .role = "designer", .hours = 20 },
            .{ .emp = 3, .proj = 4, .role = "frontend", .hours = 5 },
            // Customer Portal (proj 5)
            .{ .emp = 9, .proj = 5, .role = "sponsor", .hours = 5 },
            .{ .emp = 10, .proj = 5, .role = "product lead", .hours = 25 },
            .{ .emp = 12, .proj = 5, .role = "product", .hours = 30 },
            .{ .emp = 4, .proj = 5, .role = "developer", .hours = 10 },
            .{ .emp = 14, .proj = 5, .role = "designer", .hours = 10 },
            // Data Pipeline v3 (proj 6)
            .{ .emp = 24, .proj = 6, .role = "lead", .hours = 20 },
            .{ .emp = 25, .proj = 6, .role = "developer", .hours = 30 },
            .{ .emp = 27, .proj = 6, .role = "ml engineer", .hours = 35 },
            .{ .emp = 29, .proj = 6, .role = "devops", .hours = 10 },
            // Brand Refresh (proj 7 - completed)
            .{ .emp = 16, .proj = 7, .role = "lead", .hours = 15 },
            .{ .emp = 17, .proj = 7, .role = "content", .hours = 25 },
            .{ .emp = 13, .proj = 7, .role = "designer", .hours = 15 },
            // Sales Dashboard (proj 8)
            .{ .emp = 19, .proj = 8, .role = "sponsor", .hours = 5 },
            .{ .emp = 20, .proj = 8, .role = "requirements", .hours = 10 },
            .{ .emp = 26, .proj = 8, .role = "analyst", .hours = 25 },
            .{ .emp = 18, .proj = 8, .role = "analyst", .hours = 15 },
            // Infrastructure Migration (proj 9)
            .{ .emp = 28, .proj = 9, .role = "lead", .hours = 25 },
            .{ .emp = 29, .proj = 9, .role = "devops", .hours = 15 },
            .{ .emp = 30, .proj = 9, .role = "sre", .hours = 30 },
            // Recommendation Engine (proj 10 - planning)
            .{ .emp = 24, .proj = 10, .role = "lead", .hours = 10 },
            .{ .emp = 25, .proj = 10, .role = "researcher", .hours = 10 },
            .{ .emp = 27, .proj = 10, .role = "ml engineer", .hours = 5 },
            // Onboarding Flow (proj 11 - completed)
            .{ .emp = 9, .proj = 11, .role = "sponsor", .hours = 5 },
            .{ .emp = 11, .proj = 11, .role = "product lead", .hours = 30 },
            .{ .emp = 14, .proj = 11, .role = "designer", .hours = 20 },
            // Security Audit (proj 12 - completed)
            .{ .emp = 28, .proj = 12, .role = "lead", .hours = 20 },
            .{ .emp = 30, .proj = 12, .role = "auditor", .hours = 35 },
            .{ .emp = 2, .proj = 12, .role = "reviewer", .hours = 10 },
        };

        for (assignments) |a| {
            bindInt(s, 1, a.emp);
            bindInt(s, 2, a.proj);
            bindText(s, 3, a.role);
            bindDouble(s, 4, a.hours);
            step(d, s);
        }
    }

    // =========================================================================
    // quarterly_sales
    // =========================================================================
    exec(d,
        \\CREATE TABLE quarterly_sales (
        \\  id INTEGER PRIMARY KEY,
        \\  year INTEGER NOT NULL,
        \\  quarter INTEGER NOT NULL,
        \\  department_id INTEGER NOT NULL REFERENCES departments(id),
        \\  revenue REAL NOT NULL,
        \\  costs REAL NOT NULL
        \\)
    );
    {
        const s = prepare(d, "INSERT INTO quarterly_sales VALUES (?, ?, ?, ?, ?, ?)");
        defer _ = c.sqlite3_finalize(s);

        const Q = struct { id: i64, year: i64, q: i64, dept: i64, revenue: f64, costs: f64 };
        const sales = [_]Q{
            // 2023
            .{ .id = 1, .year = 2023, .q = 1, .dept = 5, .revenue = 1250000, .costs = 420000 },
            .{ .id = 2, .year = 2023, .q = 2, .dept = 5, .revenue = 1380000, .costs = 445000 },
            .{ .id = 3, .year = 2023, .q = 3, .dept = 5, .revenue = 1420000, .costs = 460000 },
            .{ .id = 4, .year = 2023, .q = 4, .dept = 5, .revenue = 1650000, .costs = 510000 },
            .{ .id = 5, .year = 2023, .q = 1, .dept = 4, .revenue = 320000, .costs = 280000 },
            .{ .id = 6, .year = 2023, .q = 2, .dept = 4, .revenue = 350000, .costs = 290000 },
            .{ .id = 7, .year = 2023, .q = 3, .dept = 4, .revenue = 380000, .costs = 310000 },
            .{ .id = 8, .year = 2023, .q = 4, .dept = 4, .revenue = 410000, .costs = 340000 },
            // 2024
            .{ .id = 9, .year = 2024, .q = 1, .dept = 5, .revenue = 1720000, .costs = 530000 },
            .{ .id = 10, .year = 2024, .q = 2, .dept = 5, .revenue = 1850000, .costs = 555000 },
            .{ .id = 11, .year = 2024, .q = 3, .dept = 5, .revenue = 1960000, .costs = 580000 },
            .{ .id = 12, .year = 2024, .q = 4, .dept = 5, .revenue = 2150000, .costs = 620000 },
            .{ .id = 13, .year = 2024, .q = 1, .dept = 4, .revenue = 440000, .costs = 350000 },
            .{ .id = 14, .year = 2024, .q = 2, .dept = 4, .revenue = 480000, .costs = 365000 },
            .{ .id = 15, .year = 2024, .q = 3, .dept = 4, .revenue = 510000, .costs = 380000 },
            .{ .id = 16, .year = 2024, .q = 4, .dept = 4, .revenue = 560000, .costs = 400000 },
        };

        for (sales) |q| {
            bindInt(s, 1, q.id);
            bindInt(s, 2, q.year);
            bindInt(s, 3, q.q);
            bindInt(s, 4, q.dept);
            bindDouble(s, 5, q.revenue);
            bindDouble(s, 6, q.costs);
            step(d, s);
        }
    }

    exec(d, "COMMIT");
    std.debug.print("Generated demo.sqlite (5 tables, 30 employees, 12 projects)\n", .{});
}
