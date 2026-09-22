"""The incident model: parsing, validation and the ordering the page depends on.

Severity is four levels, not five. The fifth level every status page starts with ("degraded"
next to "partial outage") was never chosen differently by anyone writing an incident, so it
cost a decision at the worst moment and told a reader nothing. See
docs/designs/2026-09-02-severity-scale.md in the spec repo.
"""

import datetime
import tomllib

SEVERITIES = ("resolved", "monitoring", "partial", "major")
SEVERITY_RANK = {name: i for i, name in enumerate(SEVERITIES)}

# A status page is read during an outage, so a parse error has to say which incident and which
# field, not just that the file is wrong.
class IncidentError(ValueError):
    pass


class Update:
    __slots__ = ("at", "body")

    def __init__(self, at, body):
        self.at = at
        self.body = body


class Incident:
    __slots__ = ("id", "title", "severity", "started", "resolved", "components", "updates")

    def __init__(self, id, title, severity, started, resolved, components, updates):
        self.id = id
        self.title = title
        self.severity = severity
        self.started = started
        self.resolved = resolved
        self.components = components
        self.updates = updates

    @property
    def is_open(self):
        return self.resolved is None

    @property
    def duration(self):
        """None while the incident is open: a running clock is the page's job, not the model's."""
        if self.resolved is None:
            return None
        return self.resolved - self.started

    @property
    def latest(self):
        return self.updates[-1] if self.updates else None


def _require(table, key, where):
    if key not in table:
        raise IncidentError(f"{where}: missing required field '{key}'")
    return table[key]


def _as_datetime(value, where, key):
    if isinstance(value, datetime.datetime):
        return value
    raise IncidentError(f"{where}: '{key}' must be a date-time, got {type(value).__name__}")


def parse_incident(table, where):
    ident = _require(table, "id", where)
    severity = _require(table, "severity", where)
    if severity not in SEVERITY_RANK:
        raise IncidentError(
            f"{where}: severity '{severity}' is not one of {', '.join(SEVERITIES)}")

    started = _as_datetime(_require(table, "started", where), where, "started")
    resolved = table.get("resolved")
    if resolved is not None:
        resolved = _as_datetime(resolved, where, "resolved")
        if resolved < started:
            raise IncidentError(f"{where}: resolved is before started")
    if severity == "resolved" and resolved is None:
        raise IncidentError(f"{where}: severity is 'resolved' but no resolved time is set")

    updates = []
    for i, raw in enumerate(table.get("updates", [])):
        at = _as_datetime(_require(raw, "at", f"{where} update {i + 1}"), where, "at")
        updates.append(Update(at, _require(raw, "body", f"{where} update {i + 1}")))
    updates.sort(key=lambda u: u.at)

    return Incident(
        id=ident,
        title=_require(table, "title", where),
        severity=severity,
        started=started,
        resolved=resolved,
        components=list(table.get("components", [])),
        updates=updates,
    )


def load(path):
    """Every incident in the file, open ones first, newest first within each group.

    Open before resolved is the whole ordering decision: a reader arriving during an outage
    wants the thing that is broken now, not the most recent thing that happened.
    """
    with open(path, "rb") as f:
        data = tomllib.load(f)
    raw = data.get("incident", [])
    if not isinstance(raw, list):
        raise IncidentError("'incident' must be an array of tables ([[incident]])")

    seen = set()
    incidents = []
    for i, table in enumerate(raw):
        inc = parse_incident(table, f"incident {i + 1}")
        if inc.id in seen:
            raise IncidentError(f"duplicate incident id '{inc.id}'")
        seen.add(inc.id)
        incidents.append(inc)

    incidents.sort(key=lambda inc: (inc.is_open is False, -inc.started.timestamp()))
    return incidents


def overall(incidents):
    """The single word at the top of the page: the worst severity still open."""
    open_ones = [i for i in incidents if i.is_open]
    if not open_ones:
        return "operational"
    return max(open_ones, key=lambda i: SEVERITY_RANK[i.severity]).severity
