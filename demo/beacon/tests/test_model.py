import datetime
import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from beacon.model import IncidentError, load, overall, parse_incident

HERE = os.path.dirname(os.path.abspath(__file__))
EXAMPLES = os.path.join(os.path.dirname(HERE), "examples")


def dt(day, hour=0, minute=0):
    return datetime.datetime(2026, 9, day, hour, minute, tzinfo=datetime.timezone.utc)


class ParseIncident(unittest.TestCase):
    def base(self, **over):
        table = {"id": "x", "title": "T", "severity": "major", "started": dt(1)}
        table.update(over)
        return table

    def test_minimal_incident_parses(self):
        inc = parse_incident(self.base(), "incident 1")
        self.assertEqual(inc.id, "x")
        self.assertTrue(inc.is_open)
        self.assertIsNone(inc.duration)

    def test_unknown_severity_names_the_allowed_ones(self):
        with self.assertRaises(IncidentError) as cm:
            parse_incident(self.base(severity="degraded"), "incident 1")
        self.assertIn("degraded", str(cm.exception))
        self.assertIn("monitoring", str(cm.exception))

    def test_missing_field_names_the_field_and_the_incident(self):
        table = self.base()
        del table["title"]
        with self.assertRaises(IncidentError) as cm:
            parse_incident(table, "incident 3")
        self.assertIn("incident 3", str(cm.exception))
        self.assertIn("title", str(cm.exception))

    def test_resolved_before_started_is_refused(self):
        with self.assertRaises(IncidentError):
            parse_incident(self.base(started=dt(2), resolved=dt(1)), "incident 1")

    def test_resolved_severity_needs_a_resolved_time(self):
        with self.assertRaises(IncidentError):
            parse_incident(self.base(severity="resolved"), "incident 1")

    def test_updates_are_sorted_by_time(self):
        inc = parse_incident(self.base(updates=[
            {"at": dt(1, 9), "body": "second"},
            {"at": dt(1, 8), "body": "first"},
        ]), "incident 1")
        self.assertEqual([u.body for u in inc.updates], ["first", "second"])
        self.assertEqual(inc.latest.body, "second")

    def test_duration_is_the_closed_span(self):
        inc = parse_incident(self.base(started=dt(1, 3), resolved=dt(1, 5)), "incident 1")
        self.assertEqual(inc.duration, datetime.timedelta(hours=2))


class LoadFile(unittest.TestCase):
    def test_example_file_loads(self):
        incidents = load(os.path.join(EXAMPLES, "incidents.toml"))
        self.assertEqual(len(incidents), 3)

    def test_open_incidents_sort_before_resolved_ones(self):
        incidents = load(os.path.join(EXAMPLES, "incidents.toml"))
        self.assertTrue(incidents[0].is_open)
        self.assertFalse(any(i.is_open for i in incidents[1:]))

    def test_resolved_incidents_are_newest_first(self):
        resolved = [i for i in load(os.path.join(EXAMPLES, "incidents.toml")) if not i.is_open]
        self.assertEqual([i.id for i in resolved],
                         ["2026-09-09-webhook-backlog", "2026-08-30-api-outage"])

    def test_broken_file_raises(self):
        with self.assertRaises(IncidentError):
            load(os.path.join(EXAMPLES, "broken.toml"))

    # Two incidents copied from each other kept the same id, and the anchors on the page
    # silently collided, so a link to the second scrolled to the first.
    def test_duplicate_ids_are_refused(self):
        import tempfile
        body = ('[[incident]]\nid = "same"\ntitle = "A"\nseverity = "major"\n'
                'started = 2026-09-01T00:00:00Z\n\n'
                '[[incident]]\nid = "same"\ntitle = "B"\nseverity = "major"\n'
                'started = 2026-09-02T00:00:00Z\n')
        with tempfile.NamedTemporaryFile("w", suffix=".toml", delete=False) as f:
            f.write(body)
            path = f.name
        try:
            with self.assertRaises(IncidentError) as cm:
                load(path)
            self.assertIn("same", str(cm.exception))
        finally:
            os.unlink(path)


class Overall(unittest.TestCase):
    def test_no_open_incidents_is_operational(self):
        self.assertEqual(overall([]), "operational")

    def test_worst_open_severity_wins(self):
        incidents = [
            parse_incident({"id": "a", "title": "A", "severity": "monitoring", "started": dt(1)}, "a"),
            parse_incident({"id": "b", "title": "B", "severity": "major", "started": dt(1)}, "b"),
        ]
        self.assertEqual(overall(incidents), "major")

    def test_resolved_incidents_do_not_set_the_headline(self):
        incidents = load(os.path.join(EXAMPLES, "incidents.toml"))
        self.assertEqual(overall(incidents), "monitoring")


if __name__ == "__main__":
    unittest.main()
