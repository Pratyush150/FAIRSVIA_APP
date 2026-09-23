#!/usr/bin/env python3
"""Builds grafana/dashboards/analytics.json — the owner's "Grafana Dashboard
Core List", one row per section, one panel per item.

    python3 infra/monitoring/grafana/build_analytics.py

Edit this file, not the JSON. Business numbers are SQL on the Postgres
datasource (the ledger is the truth, and Prometheus only keeps 30 days);
live and system numbers are PromQL. Money panels filter on the ${currency}
variable: trips keep the currency they were priced in, and adding rupees to
dollars would be meaningless. "Today" is midnight in ${tz}.
"""
import json
import pathlib

PG = {"type": "grafana-postgresql-datasource", "uid": "ridevela-postgres"}
PROM = {"type": "prometheus", "uid": "ridevela-prometheus"}

# A payment is revenue once it is settled; later refunds are shown separately.
SETTLED = "('captured','collected','partial','refunded')"
# When a payment settled: rides at completion, cancellation fees when charged.
PAID_AT = "COALESCE(t.completed_at, p.updated_at)"

panels = []
_id = 0
_y = 0


def nid():
    global _id
    _id += 1
    return _id


def row(title):
    global _y
    panels.append({"type": "row", "title": title, "id": nid(), "collapsed": False,
                   "gridPos": {"h": 1, "w": 24, "x": 0, "y": _y}})
    _y += 1


def _target(ds, q, fmt, legend=None, instant=False):
    if ds is PG:
        return {"datasource": PG, "refId": "A", "rawQuery": True, "editorMode": "code",
                "format": fmt, "rawSql": q}
    t = {"datasource": PROM, "refId": "A", "expr": q, "range": not instant,
         "instant": instant, "editorMode": "code"}
    if legend:
        t["legendFormat"] = legend
    if fmt == "table":
        t["format"] = "table"
    return t


def stat(title, ds, q, x, w=4, h=4, unit="short", decimals=None, desc="",
         thresholds=None, instant=True):
    fc = {"unit": unit, "color": {"mode": "thresholds"},
          "thresholds": {"mode": "absolute", "steps": thresholds or [{"color": "green", "value": None}]}}
    if decimals is not None:
        fc["decimals"] = decimals
    panels.append({
        "type": "stat", "title": title, "id": nid(), "description": desc, "datasource": ds,
        "gridPos": {"h": h, "w": w, "x": x, "y": _y},
        "targets": [_target(ds, q, "table", instant=instant)],
        "fieldConfig": {"defaults": fc, "overrides": []},
        "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                    "colorMode": "value", "graphMode": "none", "justifyMode": "auto",
                    "textMode": "value", "orientation": "auto"},
    })


def series(title, ds, queries, x, w=12, h=8, unit="short", desc="", time_from=None,
           bars=False, stack=False):
    targets = []
    for i, (q, legend) in enumerate(queries):
        t = _target(ds, q, "time_series", legend)
        t["refId"] = chr(65 + i)
        targets.append(t)
    p = {
        "type": "timeseries", "title": title, "id": nid(), "description": desc, "datasource": ds,
        "gridPos": {"h": h, "w": w, "x": x, "y": _y}, "targets": targets,
        "fieldConfig": {"defaults": {"unit": unit, "custom": {
            "drawStyle": "bars" if bars else "line", "lineWidth": 2, "fillOpacity": 60 if bars else 12,
            "showPoints": "never", "spanNulls": True,
            "stacking": {"mode": "normal" if stack else "none", "group": "A"}}}, "overrides": []},
        "options": {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": True},
                    "tooltip": {"mode": "multi", "sort": "desc"}},
    }
    if time_from:
        p["timeFrom"] = time_from
    panels.append(p)


def table(title, ds, q, x, w=12, h=8, desc="", instant=True):
    panels.append({
        "type": "table", "title": title, "id": nid(), "description": desc, "datasource": ds,
        "gridPos": {"h": h, "w": w, "x": x, "y": _y},
        "targets": [_target(ds, q, "table", instant=instant)],
        "fieldConfig": {"defaults": {}, "overrides": []},
        "options": {"showHeader": True, "cellHeight": "sm"},
    })


def down(h):
    global _y
    _y += h


TODAY = "(now() AT TIME ZONE '${tz}')::date"
MONEY = "currency = '${currency}'"

# ---------------------------------------------------------------- App overview
row("📊 App overview")
stat("Total users", PG,
     "SELECT count(*) FROM users WHERE deleted_at IS NULL AND role <> 'admin'", 0,
     desc="Riders and drivers with an account (deleted accounts excluded).")
stat("DAU", PG, f"SELECT count(*) FROM user_active_days WHERE day = {TODAY}", 4,
     desc="People who used the app today (${tz} day). One row per person per day.")
stat("MAU", PG,
     f"SELECT count(DISTINCT user_id) FROM user_active_days WHERE day > {TODAY} - 30", 8,
     desc="Distinct people who used the app in the last 30 days.")
stat("DAU / MAU", PG,
     f"SELECT (SELECT count(*) FROM user_active_days WHERE day = {TODAY})::float"
     f" / NULLIF((SELECT count(DISTINCT user_id) FROM user_active_days WHERE day > {TODAY} - 30), 0)",
     12, unit="percentunit", decimals=0, desc="Stickiness: how much of the monthly base comes back daily.")
stat("New users", PG,
     "SELECT count(*) FROM users WHERE role <> 'admin' AND $__timeFilter(created_at)", 16,
     desc="Sign-ups in the selected time range.")
stat("Total rides (all time)", PG, "SELECT count(*) FROM trips WHERE status <> 'scheduled'", 20,
     desc="Every ride ever requested.")
down(4)
stat("Completed rides", PG,
     "SELECT count(*) FROM trips WHERE status = 'completed' AND $__timeFilter(completed_at)", 0,
     desc="Rides completed in the selected range.")
stat("Cancelled rides", PG,
     "SELECT count(*) FROM trips WHERE status = 'cancelled' AND $__timeFilter(requested_at)", 4,
     thresholds=[{"color": "green", "value": None}, {"color": "orange", "value": 10}],
     desc="Rides requested in the range that were cancelled (by rider or driver).")
stat("No driver found", PG,
     "SELECT count(*) FROM trips WHERE status IN ('no_drivers','expired') AND $__timeFilter(requested_at)", 8,
     thresholds=[{"color": "green", "value": None}, {"color": "red", "value": 1}],
     desc="Demand we could not serve — every one is a lost ride.")
stat("Completion rate", PG,
     "SELECT count(*) FILTER (WHERE status = 'completed')::float / NULLIF(count(*) FILTER (WHERE status IN "
     "('completed','cancelled','no_drivers','expired')), 0) FROM trips WHERE $__timeFilter(requested_at)", 12,
     unit="percentunit", decimals=0,
     thresholds=[{"color": "red", "value": None}, {"color": "orange", "value": 0.6}, {"color": "green", "value": 0.8}],
     desc="Of rides requested in the range that have ended, the share that completed.")
stat("Revenue (${currency})", PG,
     f"SELECT COALESCE(sum(p.amount), 0) FROM payments p JOIN trips t ON t.id = p.trip_id "
     f"WHERE p.status IN {SETTLED} AND p.{MONEY} AND $__timeFilter({PAID_AT})", 16, decimals=0,
     desc="Gross: fares and cancellation fees collected in the range, before refunds.")
stat("Average fare (${currency})", PG,
     f"SELECT avg(fare_final) FROM trips WHERE status = 'completed' AND {MONEY} AND $__timeFilter(completed_at)",
     20, decimals=0, desc="Average final fare of completed rides in the range.")
down(4)
series("Rides by outcome", PG, [(
    "SELECT $__timeGroupAlias(requested_at, $__interval, 0), status AS metric, count(*) AS value "
    "FROM trips WHERE $__timeFilter(requested_at) AND status <> 'scheduled' GROUP BY 1, 2 ORDER BY 1", None)],
    0, w=12, bars=True, stack=True, desc="Every ride requested, by where it ended up.")
series("Revenue (${currency})", PG, [(
    f"SELECT $__timeGroupAlias(paid_at, $__interval, 0), sum(amount) AS \"Gross\", "
    f"sum(platform_fee) AS \"Platform commission\" FROM (SELECT {PAID_AT} AS paid_at, p.amount, p.platform_fee "
    f"FROM payments p JOIN trips t ON t.id = p.trip_id WHERE p.status IN {SETTLED} AND p.{MONEY}) s "
    f"WHERE $__timeFilter(paid_at) GROUP BY 1 ORDER BY 1", None)],
    12, w=12, bars=True, desc="Gross collected and the platform's share, per interval.")
down(8)

# ------------------------------------------------------------ Live operations
row("🚕 Live operations")
stat("Active rides", PROM, "sum(active_trips)", 0, desc="Requested through in progress, right now.")
stat("Drivers online", PROM, "sum(drivers_online)", 4,
     thresholds=[{"color": "red", "value": None}, {"color": "green", "value": 1}])
stat("Available", PROM, "sum(drivers_online) - sum(drivers_on_trip)", 8,
     desc="Online and free to take a ride.")
stat("Busy (on a trip)", PROM, "sum(drivers_on_trip)", 12)
stat("Unassigned rides", PG,
     "SELECT count(*) FROM trips WHERE status IN ('requested','matching')", 16,
     thresholds=[{"color": "green", "value": None}, {"color": "orange", "value": 5}, {"color": "red", "value": 20}],
     desc="Riders waiting for a driver right now.")
stat("Avg pickup time", PG,
     "SELECT avg(extract(epoch FROM arrived_at - accepted_at)) FROM trips "
     "WHERE arrived_at IS NOT NULL AND $__timeFilter(accepted_at)", 20, unit="s", decimals=0,
     desc="Actual time from a driver accepting to arriving at the pickup, in the range.")
down(4)
stat("Driver acceptance rate", PROM,
     'sum(increase(dispatch_offers_total{outcome="accepted"}[$__range])) / sum(increase(dispatch_offers_total[$__range]))',
     0, unit="percentunit", decimals=0,
     thresholds=[{"color": "red", "value": None}, {"color": "orange", "value": 0.5}, {"color": "green", "value": 0.7}],
     desc="Share of ride offers drivers accepted (vs declined or let expire). No data = no offers in range.")
stat("Driver cancellation rate", PG,
     "SELECT count(*) FILTER (WHERE status = 'cancelled' AND cancelled_by = 'driver')::float "
     "/ NULLIF(count(*) FILTER (WHERE accepted_at IS NOT NULL), 0) FROM trips WHERE $__timeFilter(requested_at)",
     4, unit="percentunit", decimals=1,
     thresholds=[{"color": "green", "value": None}, {"color": "orange", "value": 0.05}, {"color": "red", "value": 0.1}],
     desc="Of rides a driver accepted, the share that driver then cancelled.")
stat("Match time p95", PROM,
     "histogram_quantile(0.95, sum(rate(trip_match_duration_seconds_bucket[$__range])) by (le))", 8,
     unit="s", decimals=1, desc="Request to driver accepted, 95th percentile, over the range.")
stat("Rides in the last hour", PG,
     "SELECT count(*) FROM trips WHERE requested_at > now() - interval '1 hour'", 12)
stat("Ride requests today", PG,
     f"SELECT count(*) FROM trips WHERE (requested_at AT TIME ZONE '${{tz}}')::date = {TODAY}", 16)
stat("Riders waiting > 2 min", PG,
     "SELECT count(*) FROM trips WHERE status IN ('requested','matching') AND requested_at < now() - interval '2 minutes'",
     20, thresholds=[{"color": "green", "value": None}, {"color": "red", "value": 1}],
     desc="Searches running longer than a normal match window.")
down(4)
series("Ride offers to drivers (per minute)", PROM, [
    ("sum by (outcome) (rate(dispatch_offers_total[5m])) * 60", "{{outcome}}")], 0, w=12,
    desc="Accepted / declined / expired offers.")
series("Driver supply", PROM, [
    ("sum(drivers_online)", "Online"), ("sum(drivers_on_trip)", "On a trip"),
    ("sum(drivers_online) - sum(drivers_on_trip)", "Available")], 12, w=12)
down(8)

# ------------------------------------------------------------- Users & drivers
row("👥 Users & drivers")
series("User & driver growth (30 days)", PG, [(
    "SELECT d AS time, "
    "(SELECT count(*) FROM users u WHERE u.role <> 'admin' AND u.deleted_at IS NULL AND u.created_at < d + interval '1 day') AS \"Users\", "
    "(SELECT count(*) FROM driver_profiles dp WHERE dp.created_at < d + interval '1 day') AS \"Drivers\" "
    "FROM generate_series(date_trunc('day', $__timeFrom()::timestamptz), date_trunc('day', $__timeTo()::timestamptz), interval '1 day') d "
    "ORDER BY 1", None)], 0, w=12, time_from="30d",
    desc="Accounts at the end of each day. Driver dates before 2026-09-23 are when tracking began, not onboarding.")
series("Active users per day (30 days)", PG, [(
    "SELECT a.day::timestamptz AS time, "
    "count(*) FILTER (WHERE dp.user_id IS NULL) AS \"Riders\", count(*) FILTER (WHERE dp.user_id IS NOT NULL) AS \"Drivers\" "
    "FROM user_active_days a LEFT JOIN driver_profiles dp ON dp.user_id = a.user_id "
    "WHERE a.day >= $__timeFrom()::date GROUP BY 1 ORDER BY 1", None)], 12, w=12, time_from="30d", bars=True,
    desc="Daily active people, split into riders and drivers.")
down(8)
stat("New users today", PG,
     f"SELECT count(*) FROM users WHERE role <> 'admin' AND (created_at AT TIME ZONE '${{tz}}')::date = {TODAY}", 0)
stat("New drivers today", PG,
     f"SELECT count(*) FROM driver_profiles WHERE (created_at AT TIME ZONE '${{tz}}')::date = {TODAY}", 4)
stat("Active drivers today", PG,
     f"SELECT count(*) FROM user_active_days a JOIN driver_profiles dp ON dp.user_id = a.user_id WHERE a.day = {TODAY}", 8)
stat("Driver utilisation", PROM,
     "avg_over_time((sum(drivers_on_trip) / sum(drivers_online))[$__range:1m])", 12,
     unit="percentunit", decimals=0,
     desc="Share of online driver-time spent on a trip, over the range.")
stat("Rides per driver", PG,
     "SELECT count(*)::float / NULLIF(count(DISTINCT driver_id), 0) FROM trips "
     "WHERE status = 'completed' AND $__timeFilter(completed_at)", 16, decimals=1,
     desc="Completed rides per driver who completed any, in the range.")
stat("Total drivers", PG, "SELECT count(*) FROM driver_profiles", 20)
down(4)
table("Top drivers (range)", PG,
      "SELECT COALESCE(u.full_name, 'Driver ' || right(u.phone, 4)) AS \"Driver\", count(*) AS \"Rides\", "
      f"round(sum(COALESCE(p.driver_payout, 0))::numeric, 0) AS \"Earned\" "
      "FROM trips t JOIN users u ON u.id = t.driver_id LEFT JOIN payments p ON p.trip_id = t.id "
      "WHERE t.status = 'completed' AND $__timeFilter(t.completed_at) GROUP BY u.id ORDER BY 2 DESC LIMIT 10",
      0, w=12, desc="Most completed rides in the range; earned = driver share incl. tips.")
series("Driver utilisation over time", PROM, [
    ("sum(drivers_on_trip) / sum(drivers_online)", "Utilisation")], 12, w=12, unit="percentunit")
down(8)

# ------------------------------------------------------- Revenue & payments
row("💰 Revenue & payments (${currency})")
stat("Gross revenue", PG,
     f"SELECT COALESCE(sum(p.amount), 0) FROM payments p JOIN trips t ON t.id = p.trip_id "
     f"WHERE p.status IN {SETTLED} AND p.{MONEY} AND $__timeFilter({PAID_AT})", 0, decimals=0)
stat("Platform commission", PG,
     f"SELECT COALESCE(sum(p.platform_fee), 0) FROM payments p JOIN trips t ON t.id = p.trip_id "
     f"WHERE p.status IN {SETTLED} AND p.{MONEY} AND $__timeFilter({PAID_AT})", 4, decimals=0)
stat("Net revenue", PG,
     f"SELECT COALESCE((SELECT sum(p.platform_fee) FROM payments p JOIN trips t ON t.id = p.trip_id "
     f"WHERE p.status IN {SETTLED} AND p.{MONEY} AND $__timeFilter({PAID_AT})), 0) "
     f"- COALESCE((SELECT sum(r.amount) FROM payment_refunds r JOIN payments p ON p.id = r.payment_id "
     f"WHERE r.status = 'succeeded' AND p.{MONEY} AND $__timeFilter(r.created_at)), 0) "
     f"+ COALESCE((SELECT -sum(amount) FROM ledger_entries WHERE type = 'adjustment' AND note LIKE 'Refund clawback%' "
     f"AND $__timeFilter(created_at)), 0)", 8, decimals=0,
     desc="Commission minus the part of refunds the platform bears (refunds minus the driver-share clawback).")
stat("Driver earnings", PG,
     f"SELECT COALESCE(sum(p.driver_payout), 0) FROM payments p JOIN trips t ON t.id = p.trip_id "
     f"WHERE p.status IN {SETTLED} AND p.{MONEY} AND $__timeFilter({PAID_AT})", 12, decimals=0,
     desc="What drivers earned: their share of fares, tips and cancellation compensation.")
stat("Paid out to drivers", PG,
     "SELECT COALESCE(-sum(amount), 0) FROM ledger_entries WHERE type = 'withdrawal' AND $__timeFilter(created_at)",
     16, decimals=0, desc="Withdrawals to drivers' bank accounts in the range.")
stat("Refunds", PG,
     f"SELECT COALESCE(sum(r.amount), 0) FROM payment_refunds r JOIN payments p ON p.id = r.payment_id "
     f"WHERE r.status = 'succeeded' AND p.{MONEY} AND $__timeFilter(r.created_at)", 20, decimals=0,
     thresholds=[{"color": "green", "value": None}, {"color": "orange", "value": 1}])
down(4)
stat("Payment success rate", PG,
     f"SELECT count(*) FILTER (WHERE p.status IN {SETTLED})::float / NULLIF(count(*) FILTER (WHERE p.status IN "
     f"{SETTLED[:-1]},'failed')), 0) FROM payments p JOIN trips t ON t.id = p.trip_id "
     f"WHERE $__timeFilter(p.created_at)", 0, unit="percentunit", decimals=1,
     thresholds=[{"color": "red", "value": None}, {"color": "orange", "value": 0.95}, {"color": "green", "value": 0.99}],
     desc="Settled vs failed payments started in the range (all currencies).")
stat("Failed payments", PG,
     "SELECT count(*) FROM payments WHERE status = 'failed' AND $__timeFilter(created_at)", 4,
     thresholds=[{"color": "green", "value": None}, {"color": "red", "value": 1}])
stat("Cash share", PG,
     f"SELECT count(*) FILTER (WHERE method = 'cash')::float / NULLIF(count(*), 0) FROM payments "
     f"WHERE status IN {SETTLED} AND $__timeFilter(created_at)", 8, unit="percentunit", decimals=0,
     desc="Share of settled payments paid in cash.")
stat("Tips", PG,
     f"SELECT COALESCE(sum(p.tip), 0) FROM payments p JOIN trips t ON t.id = p.trip_id "
     f"WHERE p.{MONEY} AND $__timeFilter({PAID_AT})", 12, decimals=0)
stat("Cancellation fees", PG,
     f"SELECT COALESCE(sum(amount), 0) FROM payments WHERE kind = 'cancellation' AND status IN {SETTLED} "
     f"AND {MONEY} AND $__timeFilter(updated_at)", 16, decimals=0)
stat("Payment failures (Prometheus)", PROM, "sum(increase(payment_failures_total[$__range]))", 20,
     decimals=0, thresholds=[{"color": "green", "value": None}, {"color": "red", "value": 1}],
     desc="Capture/charge attempts that failed, incl. retries, since the range began.")
down(4)
table("Payments by status (range)", PG,
      "SELECT kind AS \"Kind\", method AS \"Method\", status AS \"Status\", currency AS \"Currency\", "
      "count(*) AS \"Payments\", round(sum(amount)::numeric, 2) AS \"Amount\" FROM payments "
      "WHERE $__timeFilter(created_at) GROUP BY 1, 2, 3, 4 ORDER BY 5 DESC", 0, w=12)
series("Payment failures by reason", PROM, [
    ("sum by (kind, reason) (increase(payment_failures_total[5m]))", "{{kind}} · {{reason}}")], 12, w=12)
down(8)

# -------------------------------------------------------------- System health
row("🖥️ System health")
stat("CPU", PROM, '1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))', 0, unit="percentunit", decimals=0,
     thresholds=[{"color": "green", "value": None}, {"color": "orange", "value": 0.75}, {"color": "red", "value": 0.9}])
stat("RAM", PROM, "1 - sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes)", 4,
     unit="percentunit", decimals=0,
     thresholds=[{"color": "green", "value": None}, {"color": "orange", "value": 0.8}, {"color": "red", "value": 0.9}])
stat("Disk", PROM,
     '1 - node_filesystem_avail_bytes{mountpoint="/",fstype!~"tmpfs|overlay"} / node_filesystem_size_bytes{mountpoint="/",fstype!~"tmpfs|overlay"}',
     8, unit="percentunit", decimals=0,
     thresholds=[{"color": "green", "value": None}, {"color": "orange", "value": 0.8}, {"color": "red", "value": 0.9}])
stat("API requests/sec", PROM, "sum(rate(http_requests_total[5m]))", 12, unit="reqps", decimals=1)
stat("API p95", PROM,
     "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))", 16, unit="s",
     decimals=2, thresholds=[{"color": "green", "value": None}, {"color": "orange", "value": 0.6}, {"color": "red", "value": 1.5}])
stat("Error rate (5xx)", PROM,
     '(sum(rate(http_requests_total{status=~"5.."}[5m])) or vector(0)) / sum(rate(http_requests_total[5m]))', 20,
     unit="percentunit", decimals=2,
     thresholds=[{"color": "green", "value": None}, {"color": "orange", "value": 0.005}, {"color": "red", "value": 0.01}])
down(4)
stat("WebSocket connections", PROM, "sum(websocket_connections)", 0,
     desc="Apps connected for live updates right now (riders + drivers).")
stat("Backend uptime", PROM, 'time() - max(process_start_time_seconds{job="backend"})', 4, unit="s", decimals=0)
stat("Server uptime", PROM, "time() - max(node_boot_time_seconds)", 8, unit="s", decimals=0)
stat("Database", PROM, "max(pg_up)", 12,
     thresholds=[{"color": "red", "value": None}, {"color": "green", "value": 1}],
     desc="1 = Postgres reachable.")
stat("Redis", PROM, "max(redis_up)", 16, thresholds=[{"color": "red", "value": None}, {"color": "green", "value": 1}],
     desc="1 = Redis reachable.")
stat("DB cache hit ratio", PROM,
     'sum(rate(pg_stat_database_blks_hit{datname="ubernav"}[5m])) / (sum(rate(pg_stat_database_blks_hit{datname="ubernav"}[5m])) + sum(rate(pg_stat_database_blks_read{datname="ubernav"}[5m])))',
     20, unit="percentunit", decimals=1,
     thresholds=[{"color": "red", "value": None}, {"color": "orange", "value": 0.9}, {"color": "green", "value": 0.98}])
down(4)
series("API requests/sec by status", PROM, [
    ('sum by (status) (rate(http_requests_total[5m]))', "{{status}}")], 0, w=8, unit="reqps")
series("API latency", PROM, [
    ("histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))", "p95"),
    ("histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))", "p99")], 8, w=8, unit="s")
series("WebSocket connections", PROM, [
    ("sum by (role) (websocket_connections)", "{{role}}")], 16, w=8)
down(8)
series("Database activity", PROM, [
    ('sum(rate(pg_stat_database_xact_commit{datname="ubernav"}[5m]))', "commits/s"),
    ('sum(rate(pg_stat_database_xact_rollback{datname="ubernav"}[5m]))', "rollbacks/s")], 0, w=8)
series("Database connections", PROM, [
    ('sum by (state) (pg_stat_activity_count{datname="ubernav"})', "{{state}}")], 8, w=8)
series("Longest open transaction", PROM, [
    ('max(pg_stat_activity_max_tx_duration{datname="ubernav"})', "seconds")], 16, w=8, unit="s",
    desc="A transaction open for minutes holds locks and bloats tables.")
down(8)

# --------------------------------------------------------------------- Alerts
row("🚨 Alerts")
table("Firing now", PROM, 'ALERTS{alertstate="firing"}', 0, w=12, h=7,
      desc="Every alert currently firing. Rules: infra/monitoring/prometheus/alerts.yml.")
table("About to fire (pending)", PROM, 'ALERTS{alertstate="pending"}', 12, w=12, h=7,
      desc="Conditions met, waiting out their `for:` window.")
down(7)

dashboard = {
    "uid": "ridevela-analytics",
    "title": "RideVela — Analytics",
    "description": "The owner's core list: app overview, live operations, users & drivers, "
                   "revenue & payments, system health, alerts.",
    "tags": ["ridevela", "analytics"],
    "timezone": "browser",
    "editable": True,
    "graphTooltip": 1,
    "schemaVersion": 39,
    "version": 1,
    "refresh": "30s",
    "time": {"from": "now/d", "to": "now"},
    "timepicker": {},
    "templating": {"list": [
        {"name": "currency", "label": "Currency", "type": "query", "datasource": PG,
         "query": "SELECT DISTINCT currency FROM payments UNION SELECT DISTINCT currency FROM trips ORDER BY 1",
         "definition": "SELECT DISTINCT currency …", "refresh": 1,
         "current": {"text": "INR", "value": "INR"}, "options": [], "includeAll": False, "multi": False},
        {"name": "tz", "label": "Business time zone", "type": "custom",
         "query": "Asia/Kolkata,Asia/Tashkent,UTC", "current": {"text": "Asia/Kolkata", "value": "Asia/Kolkata"},
         "options": [], "includeAll": False, "multi": False},
    ]},
    "annotations": {"list": []},
    "links": [
        {"title": "Ops", "type": "link", "url": "/d/ridevela-ops"},
        {"title": "Business", "type": "link", "url": "/d/ridevela-business"},
        {"title": "Infrastructure", "type": "link", "url": "/d/ridevela-infrastructure"},
    ],
    "panels": panels,
}

out = pathlib.Path(__file__).parent / "dashboards" / "analytics.json"
out.write_text(json.dumps(dashboard, indent=2, ensure_ascii=False) + "\n")
print(f"wrote {out} — {sum(1 for p in panels if p['type'] != 'row')} panels")
