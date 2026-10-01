#!/usr/bin/env python3
"""Builds the FAIRSVIA analytics pages in grafana/dashboards/:

    python3 infra/monitoring/grafana/build_dashboards.py

One plain-language **Today** home page plus five focused pages (Rides, Money,
People, Drivers, Tech health). Edit this file, not the JSON.

Design rules (plan §0c): titles are questions or plain phrases, every tile has
a one-sentence ⓘ, money is in rupees, colours mean the same everywhere
(green good / orange watch / red act), the same page buttons sit on top of
every page, and currency + time zone are fixed and hidden.
"""
import json
import pathlib

PG = {"type": "grafana-postgresql-datasource", "uid": "ridevela-postgres"}
PROM = {"type": "prometheus", "uid": "ridevela-prometheus"}
OUT = pathlib.Path(__file__).parent / "dashboards"

TZ = "Asia/Kolkata"
CUR = "INR"
MONEY_UNIT = "currencyINR"
TODAY = f"(now() AT TIME ZONE '{TZ}')::date"
IS_TODAY = lambda col: f"({col} AT TIME ZONE '{TZ}')::date = {TODAY}"  # noqa: E731
SETTLED = "('captured','collected','partial','refunded')"
PAID_AT = "COALESCE(t.completed_at, p.updated_at)"

GOOD = "green"
WATCH = "orange"
ACT = "red"
NEUTRAL = "#0FA3A8"  # brand turquoise: a number that is neither good nor bad


class Page:
    def __init__(self):
        self.panels = []
        self.y = 0
        self._id = 0

    def _nid(self):
        self._id += 1
        return self._id

    def note(self, markdown, h=2):
        self.panels.append({
            "type": "text", "id": self._nid(), "title": "",
            "gridPos": {"h": h, "w": 24, "x": 0, "y": self.y},
            "options": {"mode": "markdown", "content": markdown},
        })
        self.y += h

    def section(self, title):
        self.panels.append({"type": "row", "title": title, "id": self._nid(), "collapsed": False,
                            "gridPos": {"h": 1, "w": 24, "x": 0, "y": self.y}})
        self.y += 1

    def tile(self, title, ds, q, x, w, desc, unit="short", decimals=0, steps=None, h=5):
        steps = steps or [{"color": NEUTRAL, "value": None}]
        target = ({"datasource": PG, "refId": "A", "rawQuery": True, "editorMode": "code",
                   "format": "table", "rawSql": q} if ds is PG else
                  {"datasource": PROM, "refId": "A", "expr": q, "instant": True, "range": False,
                   "editorMode": "code"})
        self.panels.append({
            "type": "stat", "title": title, "id": self._nid(), "description": desc,
            "datasource": ds, "gridPos": {"h": h, "w": w, "x": x, "y": self.y},
            "targets": [target],
            "fieldConfig": {"defaults": {
                "unit": unit, "decimals": decimals, "noValue": "0",
                "color": {"mode": "thresholds"},
                "thresholds": {"mode": "absolute", "steps": steps}}, "overrides": []},
            "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
                        "colorMode": "background", "graphMode": "none", "justifyMode": "center",
                        "textMode": "value", "orientation": "auto", "wideLayout": True},
        })

    def chart(self, title, ds, queries, x, w, desc, unit="short", bars=False, stack=False,
              time_from=None, h=8):
        targets = []
        for i, (q, legend) in enumerate(queries):
            t = ({"datasource": PG, "refId": chr(65 + i), "rawQuery": True, "editorMode": "code",
                  "format": "time_series", "rawSql": q} if ds is PG else
                 {"datasource": PROM, "refId": chr(65 + i), "expr": q, "range": True,
                  "editorMode": "code", "legendFormat": legend or ""})
            targets.append(t)
        p = {
            "type": "timeseries", "title": title, "id": self._nid(), "description": desc,
            "datasource": ds, "gridPos": {"h": h, "w": w, "x": x, "y": self.y}, "targets": targets,
            "fieldConfig": {"defaults": {"unit": unit, "color": {"mode": "palette-classic"}, "custom": {
                "drawStyle": "bars" if bars else "line", "lineWidth": 2,
                "fillOpacity": 70 if bars else 15, "showPoints": "never", "spanNulls": True,
                "stacking": {"mode": "normal" if stack else "none", "group": "A"}}},
                "overrides": []},
            "options": {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": True},
                        "tooltip": {"mode": "multi", "sort": "desc"}},
        }
        if time_from:
            p["timeFrom"] = time_from
            p["hideTimeOverride"] = False
        self.panels.append(p)

    def table(self, title, ds, q, x, w, desc, h=8):
        target = ({"datasource": PG, "refId": "A", "rawQuery": True, "editorMode": "code",
                   "format": "table", "rawSql": q} if ds is PG else
                  {"datasource": PROM, "refId": "A", "expr": q, "instant": True, "range": False,
                   "format": "table", "editorMode": "code"})
        self.panels.append({
            "type": "table", "title": title, "id": self._nid(), "description": desc,
            "datasource": ds, "gridPos": {"h": h, "w": w, "x": x, "y": self.y},
            "targets": [target], "fieldConfig": {"defaults": {}, "overrides": []},
            "options": {"showHeader": True, "cellHeight": "md"},
        })

    def down(self, h):
        self.y += h


def dashboard(uid, title, description, page, time_from="now/d"):
    return {
        "uid": uid, "title": title, "description": description,
        "tags": ["ridevela-pages"], "timezone": TZ, "editable": True,
        "graphTooltip": 1, "schemaVersion": 39, "version": 1, "refresh": "30s",
        "time": {"from": time_from, "to": "now"}, "timepicker": {"hidden": False},
        "templating": {"list": []}, "annotations": {"list": []},
        # The same page buttons on every page, in page order (titles start 1…6).
        "links": [{"title": "Pages", "type": "dashboards", "tags": ["ridevela-pages"],
                   "asDropdown": False, "includeVars": False, "keepTime": True,
                   "targetBlank": False}],
        "panels": page.panels,
    }


# ------------------------------------------------------------------ 1. Today
today = Page()
today.note("### Today at a glance\nLive — updates every 30 seconds. Tap a page button above "
           "(**Rides, Money, People, Drivers, Tech health**) for the detail behind any number. "
           "**Green** = fine, **orange** = keep an eye on it, **red** = needs someone now.", h=3)
today.tile("Rides completed today", PG,
           f"SELECT count(*) FROM trips WHERE status = 'completed' AND {IS_TODAY('completed_at')}", 0, 8,
           "Rides that finished today (since midnight, India time).")
today.tile("Money in today", PG,
           f"SELECT COALESCE(sum(p.amount), 0) FROM payments p JOIN trips t ON t.id = p.trip_id "
           f"WHERE p.status IN {SETTLED} AND p.currency = '{CUR}' AND {IS_TODAY(PAID_AT)}", 8, 8,
           "Everything riders paid today — fares and cancellation fees, before refunds.",
           unit=MONEY_UNIT)
today.tile("People using the app today", PG,
           f"SELECT count(*) FROM user_active_days WHERE day = {TODAY}", 16, 8,
           "Riders and drivers who opened the app today, each counted once.")
today.down(5)
today.tile("Drivers online now", PROM, "sum(drivers_online) or vector(0)", 0, 8,
           "Drivers with the app on and ready, including those on a ride.",
           steps=[{"color": ACT, "value": None}, {"color": GOOD, "value": 1}])
today.tile("Riders waiting for a car now", PG,
           "SELECT count(*) FROM trips WHERE status IN ('requested','matching')", 8, 8,
           "Riders searching for a driver at this moment. More than a few means not enough drivers.",
           steps=[{"color": GOOD, "value": None}, {"color": WATCH, "value": 3}, {"color": ACT, "value": 10}])
today.tile("Problems right now", PROM, 'count(ALERTS{alertstate="firing"}) or vector(0)', 16, 8,
           "Automatic alarms that are going off. 0 is good. Tech health shows which ones.",
           steps=[{"color": GOOD, "value": None}, {"color": ACT, "value": 1}])
today.down(5)
today.chart("Rides today, hour by hour", PG, [(
    f"SELECT $__timeGroupAlias(requested_at, 1h, 0), "
    f"CASE status WHEN 'completed' THEN 'Completed' WHEN 'cancelled' THEN 'Cancelled' "
    f"WHEN 'no_drivers' THEN 'No driver found' WHEN 'expired' THEN 'No driver found' "
    f"ELSE 'In progress' END AS metric, count(*) AS value FROM trips "
    f"WHERE $__timeFilter(requested_at) AND status <> 'scheduled' GROUP BY 1, 2 ORDER BY 1", None)],
    0, 24, "Every ride requested today, by what happened to it.", bars=True, stack=True, h=9)

# ------------------------------------------------------------------ 2. Rides
rides = Page()
rides.note("### Rides\nHow many rides happened in the chosen period (top right), and how well they went.")
rides.tile("Completed", PG,
           "SELECT count(*) FROM trips WHERE status = 'completed' AND $__timeFilter(completed_at)", 0, 6,
           "Rides that reached the destination.", steps=[{"color": GOOD, "value": None}])
rides.tile("Cancelled", PG,
           "SELECT count(*) FROM trips WHERE status = 'cancelled' AND $__timeFilter(requested_at)", 6, 6,
           "Rides cancelled by the rider or the driver.",
           steps=[{"color": GOOD, "value": None}, {"color": WATCH, "value": 10}])
rides.tile("No driver found", PG,
           "SELECT count(*) FROM trips WHERE status IN ('no_drivers','expired') AND $__timeFilter(requested_at)",
           12, 6, "Riders who asked for a ride and nobody was available — lost rides.",
           steps=[{"color": GOOD, "value": None}, {"color": ACT, "value": 1}])
rides.tile("Success rate", PG,
           "SELECT count(*) FILTER (WHERE status = 'completed')::float / NULLIF(count(*) FILTER "
           "(WHERE status IN ('completed','cancelled','no_drivers','expired')), 0) FROM trips "
           "WHERE $__timeFilter(requested_at)", 18, 6,
           "Of the rides that have ended, how many were completed.", unit="percentunit",
           steps=[{"color": ACT, "value": None}, {"color": WATCH, "value": 0.6}, {"color": GOOD, "value": 0.8}])
rides.down(5)
rides.tile("Average fare", PG,
           f"SELECT avg(fare_final) FROM trips WHERE status = 'completed' AND currency = '{CUR}' "
           f"AND $__timeFilter(completed_at)", 0, 8, "What a completed ride cost on average.",
           unit=MONEY_UNIT)
rides.tile("Average wait for the car", PG,
           "SELECT avg(extract(epoch FROM arrived_at - accepted_at)) FROM trips "
           "WHERE arrived_at IS NOT NULL AND $__timeFilter(accepted_at)", 8, 8,
           "From a driver accepting to arriving at the pickup.", unit="s",
           steps=[{"color": GOOD, "value": None}, {"color": WATCH, "value": 480}, {"color": ACT, "value": 900}])
rides.tile("Time to find a driver", PROM,
           "histogram_quantile(0.95, sum(rate(trip_match_duration_seconds_bucket[$__range])) by (le))",
           16, 8, "How long the slowest 5% of riders waited for a driver to accept.", unit="s",
           decimals=1, steps=[{"color": GOOD, "value": None}, {"color": WATCH, "value": 30},
                              {"color": ACT, "value": 60}])
rides.down(5)
rides.chart("Rides per day", PG, [(
    "SELECT $__timeGroupAlias(requested_at, 1d, 0), "
    "CASE status WHEN 'completed' THEN 'Completed' WHEN 'cancelled' THEN 'Cancelled' "
    "WHEN 'no_drivers' THEN 'No driver found' WHEN 'expired' THEN 'No driver found' ELSE 'Other' END "
    "AS metric, count(*) AS value FROM trips WHERE $__timeFilter(requested_at) AND status <> 'scheduled' "
    "GROUP BY 1, 2 ORDER BY 1", None)], 0, 14, "Last 30 days, by outcome.", bars=True, stack=True,
    time_from="30d")
rides.table("Why rides were cancelled", PG,
            "SELECT COALESCE(cancel_reason, 'No reason given') AS \"Reason\", "
            "COALESCE(cancelled_by, 'system') AS \"By\", count(*) AS \"Rides\" FROM trips "
            "WHERE status = 'cancelled' AND $__timeFilter(requested_at) GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 10",
            14, 10, "The most common reasons, in the chosen period.")

# ------------------------------------------------------------------ 3. Money
money = Page()
money.note("### Money\nWhat came in, what FAIRSVIA kept and what drivers earned, in the chosen period.")
money_base = (f"FROM payments p JOIN trips t ON t.id = p.trip_id WHERE p.status IN {SETTLED} "
              f"AND p.currency = '{CUR}' AND $__timeFilter({PAID_AT})")
money.tile("Money in", PG, f"SELECT COALESCE(sum(p.amount), 0) {money_base}", 0, 6,
           "Everything riders paid: fares and cancellation fees, before refunds.", unit=MONEY_UNIT)
money.tile("Money we kept", PG, f"SELECT COALESCE(sum(p.platform_fee), 0) {money_base}", 6, 6,
           "FAIRSVIA's share (commission) of what riders paid.", unit=MONEY_UNIT,
           steps=[{"color": GOOD, "value": None}])
money.tile("Drivers earned", PG, f"SELECT COALESCE(sum(p.driver_payout), 0) {money_base}", 12, 6,
           "The drivers' share, including tips.", unit=MONEY_UNIT)
money.tile("Refunded", PG,
           f"SELECT COALESCE(sum(r.amount), 0) FROM payment_refunds r JOIN payments p ON p.id = r.payment_id "
           f"WHERE r.status = 'succeeded' AND p.currency = '{CUR}' AND $__timeFilter(r.created_at)", 18, 6,
           "Money given back to riders.", unit=MONEY_UNIT,
           steps=[{"color": GOOD, "value": None}, {"color": WATCH, "value": 1}])
money.down(5)
money.tile("Paid in cash", PG,
           f"SELECT count(*) FILTER (WHERE p.method = 'cash')::float / NULLIF(count(*), 0) {money_base}",
           0, 8, "Share of paid rides settled in cash.", unit="percentunit")
money.tile("Tips", PG, f"SELECT COALESCE(sum(p.tip), 0) {money_base}", 8, 8,
           "Tips riders added for drivers.", unit=MONEY_UNIT)
money.tile("Payments that failed", PG,
           "SELECT count(*) FROM payments WHERE status = 'failed' AND $__timeFilter(created_at)", 16, 8,
           "Rides where collecting the money failed. Anything above 0 needs a look.",
           steps=[{"color": GOOD, "value": None}, {"color": ACT, "value": 1}])
money.down(5)
money.chart("Money per day", PG, [(
    f"SELECT $__timeGroupAlias(paid_at, 1d, 0), sum(amount) AS \"Money in\", sum(platform_fee) AS \"We kept\" "
    f"FROM (SELECT {PAID_AT} AS paid_at, p.amount, p.platform_fee FROM payments p JOIN trips t ON t.id = p.trip_id "
    f"WHERE p.status IN {SETTLED} AND p.currency = '{CUR}') s WHERE $__timeFilter(paid_at) GROUP BY 1 ORDER BY 1",
    None)], 0, 24, "Last 30 days.", unit=MONEY_UNIT, bars=True, time_from="30d")

# ------------------------------------------------------------------ 4. People
people = Page()
people.note("### People\nWho uses FAIRSVIA — riders and drivers.")
people.tile("Everyone with an account", PG,
            "SELECT count(*) FROM users WHERE deleted_at IS NULL AND role <> 'admin'", 0, 6,
            "All riders and drivers who have signed up.")
people.tile("New sign-ups", PG,
            "SELECT count(*) FROM users WHERE role <> 'admin' AND $__timeFilter(created_at)", 6, 6,
            "People who created an account in the chosen period.")
people.tile("Used the app today", PG, f"SELECT count(*) FROM user_active_days WHERE day = {TODAY}", 12, 6,
            "People who opened the app today, each counted once.")
people.tile("Used it this month", PG,
            f"SELECT count(DISTINCT user_id) FROM user_active_days WHERE day > {TODAY} - 30", 18, 6,
            "Different people who opened the app in the last 30 days.")
people.down(5)
people.chart("People using the app each day", PG, [(
    "SELECT a.day::timestamptz AS time, "
    "count(*) FILTER (WHERE dp.user_id IS NULL) AS \"Riders\", "
    "count(*) FILTER (WHERE dp.user_id IS NOT NULL) AS \"Drivers\" "
    "FROM user_active_days a LEFT JOIN driver_profiles dp ON dp.user_id = a.user_id "
    "WHERE a.day >= $__timeFrom()::date GROUP BY 1 ORDER BY 1", None)], 0, 12,
    "Last 30 days.", bars=True, stack=True, time_from="30d")
people.chart("Total accounts over time", PG, [(
    "SELECT d AS time, "
    "(SELECT count(*) FROM users u WHERE u.role <> 'admin' AND u.deleted_at IS NULL "
    "AND u.created_at < d + interval '1 day') AS \"All accounts\", "
    "(SELECT count(*) FROM driver_profiles dp WHERE dp.created_at < d + interval '1 day') AS \"Drivers\" "
    "FROM generate_series(date_trunc('day', $__timeFrom()::timestamptz), date_trunc('day', $__timeTo()::timestamptz), "
    "interval '1 day') d ORDER BY 1", None)], 12, 12, "Last 30 days.", time_from="30d")

# ----------------------------------------------------------------- 5. Drivers
drivers = Page()
drivers.note("### Drivers\nSupply right now, and how drivers are responding to ride offers.")
drivers.tile("Online now", PROM, "sum(drivers_online) or vector(0)", 0, 6,
             "Drivers with the app on, free or on a ride.",
             steps=[{"color": ACT, "value": None}, {"color": GOOD, "value": 1}])
drivers.tile("Free now", PROM, "(sum(drivers_online) or vector(0)) - (sum(drivers_on_trip) or vector(0))", 6, 6,
             "Online and ready to take a ride right now.",
             steps=[{"color": ACT, "value": None}, {"color": GOOD, "value": 1}])
drivers.tile("On a ride now", PROM, "sum(drivers_on_trip) or vector(0)", 12, 6, "Drivers carrying a rider.")
drivers.tile("Used the app today", PG,
             f"SELECT count(*) FROM user_active_days a JOIN driver_profiles dp ON dp.user_id = a.user_id "
             f"WHERE a.day = {TODAY}", 18, 6, "Drivers who opened the driver app today.")
drivers.down(5)
drivers.tile("Offers accepted", PROM,
             'sum(increase(dispatch_offers_total{outcome="accepted"}[$__range])) '
             '/ sum(increase(dispatch_offers_total[$__range]))', 0, 8,
             "Of the ride offers sent to drivers, how many they accepted.", unit="percentunit",
             steps=[{"color": ACT, "value": None}, {"color": WATCH, "value": 0.5}, {"color": GOOD, "value": 0.7}])
drivers.tile("Rides cancelled by drivers", PG,
             "SELECT count(*) FILTER (WHERE status = 'cancelled' AND cancelled_by = 'driver')::float "
             "/ NULLIF(count(*) FILTER (WHERE accepted_at IS NOT NULL), 0) FROM trips "
             "WHERE $__timeFilter(requested_at)", 8, 8,
             "Of rides a driver accepted, how many that driver then cancelled.", unit="percentunit",
             decimals=1, steps=[{"color": GOOD, "value": None}, {"color": WATCH, "value": 0.05},
                                {"color": ACT, "value": 0.1}])
drivers.tile("Rides per driver", PG,
             "SELECT count(*)::float / NULLIF(count(DISTINCT driver_id), 0) FROM trips "
             "WHERE status = 'completed' AND $__timeFilter(completed_at)", 16, 8,
             "Average completed rides per driver who drove.", decimals=1)
drivers.down(5)
drivers.chart("Drivers online through the day", PROM, [
    ("sum(drivers_online) or vector(0)", "Online"),
    ("(sum(drivers_online) or vector(0)) - (sum(drivers_on_trip) or vector(0))", "Free"),
    ("sum(drivers_on_trip) or vector(0)", "On a ride")], 0, 12, "Supply in the chosen period.")
drivers.table("Top drivers", PG,
              "SELECT COALESCE(u.full_name, 'Driver ' || right(u.phone, 4)) AS \"Driver\", "
              "count(*) AS \"Rides\", round(sum(COALESCE(p.driver_payout, 0))::numeric, 0) AS \"Earned (₹)\" "
              "FROM trips t JOIN users u ON u.id = t.driver_id LEFT JOIN payments p ON p.trip_id = t.id "
              "WHERE t.status = 'completed' AND $__timeFilter(t.completed_at) GROUP BY u.id ORDER BY 2 DESC LIMIT 10",
              12, 12, "Most completed rides in the chosen period.")

# ------------------------------------------------------------- 6. Tech health
tech = Page()
tech.note("### Tech health\nIs the system healthy? For the tech team — business users can ignore this page "
          "unless **Problems right now** on Today is red.")
tech.table("Alarms going off now", PROM, 'ALERTS{alertstate="firing"}', 0, 24,
           "Every automatic alarm currently firing. Rules: infra/monitoring/prometheus/alerts.yml.", h=6)
tech.down(6)
tech.tile("App server", PROM, 'max(up{job="backend"}) or vector(0)', 0, 4, "1 = the server is answering.",
          steps=[{"color": ACT, "value": None}, {"color": GOOD, "value": 1}])
tech.tile("Database", PROM, "max(pg_up) or vector(0)", 4, 4, "1 = the database is reachable.",
          steps=[{"color": ACT, "value": None}, {"color": GOOD, "value": 1}])
tech.tile("Cache (Redis)", PROM, "max(redis_up) or vector(0)", 8, 4, "1 = the live cache is reachable.",
          steps=[{"color": ACT, "value": None}, {"color": GOOD, "value": 1}])
tech.tile("App speed", PROM,
          "histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))", 12, 4,
          "How long the slowest 5% of app requests take.", unit="s", decimals=2,
          steps=[{"color": GOOD, "value": None}, {"color": WATCH, "value": 0.6}, {"color": ACT, "value": 1.5}])
tech.tile("Errors", PROM,
          '(sum(rate(http_requests_total{status=~"5.."}[5m])) or vector(0)) / sum(rate(http_requests_total[5m]))',
          16, 4, "Share of app requests that failed on the server.", unit="percentunit", decimals=2,
          steps=[{"color": GOOD, "value": None}, {"color": WATCH, "value": 0.005}, {"color": ACT, "value": 0.01}])
tech.tile("Phones connected live", PROM, "sum(websocket_connections) or vector(0)", 20, 4,
          "Apps holding a live connection for ride updates.")
tech.down(5)
tech.tile("Server CPU", PROM, '1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m]))', 0, 6,
          "How busy the server's processor is.", unit="percentunit",
          steps=[{"color": GOOD, "value": None}, {"color": WATCH, "value": 0.75}, {"color": ACT, "value": 0.9}])
tech.tile("Server memory", PROM, "1 - sum(node_memory_MemAvailable_bytes) / sum(node_memory_MemTotal_bytes)",
          6, 6, "How full the server's memory is.", unit="percentunit",
          steps=[{"color": GOOD, "value": None}, {"color": WATCH, "value": 0.8}, {"color": ACT, "value": 0.9}])
tech.tile("Server disk", PROM,
          '1 - node_filesystem_avail_bytes{mountpoint="/",fstype!~"tmpfs|overlay"} '
          '/ node_filesystem_size_bytes{mountpoint="/",fstype!~"tmpfs|overlay"}', 12, 6,
          "How full the server's disk is.", unit="percentunit",
          steps=[{"color": GOOD, "value": None}, {"color": WATCH, "value": 0.8}, {"color": ACT, "value": 0.9}])
tech.tile("Server up for", PROM, "time() - max(node_boot_time_seconds)", 18, 6,
          "Time since the server last restarted.", unit="s")
tech.down(5)
tech.chart("App requests per second", PROM, [
    ('sum(rate(http_requests_total{status!~"5.."}[5m]))', "OK"),
    ('sum(rate(http_requests_total{status=~"5.."}[5m])) or vector(0)', "Failed")], 0, 12,
    "Traffic to the app server.", unit="reqps")
tech.chart("App speed over time", PROM, [
    ("histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))", "Slowest 5%"),
    ("histogram_quantile(0.50, sum(rate(http_request_duration_seconds_bucket[5m])) by (le))", "Typical")],
    12, 12, "Response time of app requests.", unit="s")

pages = [
    ("ridevela-analytics", "1. Today", "Today at a glance", today, "now/d"),
    ("ridevela-rides", "2. Rides", "Rides and how well they went", rides, "now-7d"),
    ("ridevela-money", "3. Money", "Money in, money kept, driver earnings", money, "now-7d"),
    ("ridevela-people", "4. People", "Riders and drivers using FAIRSVIA", people, "now-7d"),
    ("ridevela-drivers", "5. Drivers", "Driver supply and response", drivers, "now/d"),
    ("ridevela-tech", "6. Tech health", "Servers, speed, errors and alarms", tech, "now-6h"),
]
for uid, title, desc, page, t in pages:
    (OUT / f"{uid}.json").write_text(
        json.dumps(dashboard(uid, title, desc, page, t), indent=2, ensure_ascii=False) + "\n")
    print(f"{title:16} {sum(1 for p in page.panels if p['type'] not in ('row', 'text'))} panels")
