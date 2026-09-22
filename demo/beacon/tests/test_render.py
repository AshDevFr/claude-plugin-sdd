import datetime
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from beacon.model import load, parse_incident
from beacon.render import human_duration, render

HERE = os.path.dirname(os.path.abspath(__file__))
EXAMPLES = os.path.join(os.path.dirname(HERE), "examples")
NOW = datetime.datetime(2026, 9, 15, 12, 0, tzinfo=datetime.timezone.utc)


def dt(day, hour=0, minute=0):
    return datetime.datetime(2026, 9, day, hour, minute, tzinfo=datetime.timezone.utc)


class Duration(unittest.TestCase):
    def test_under_an_hour_is_minutes(self):
        self.assertEqual(human_duration(datetime.timedelta(minutes=22)), "22 min")

    def test_hours_carry_padded_minutes(self):
        self.assertEqual(human_duration(datetime.timedelta(hours=2, minutes=40)), "2 h 40 min")

    def test_a_whole_number_of_hours_drops_the_minutes(self):
        self.assertEqual(human_duration(datetime.timedelta(hours=3)), "3 h")

    def test_past_a_day_reads_in_days(self):
        self.assertEqual(human_duration(datetime.timedelta(days=1, hours=5)), "1 d 5 h")


class Page(unittest.TestCase):
    def setUp(self):
        self.incidents = load(os.path.join(EXAMPLES, "incidents.toml"))
        self.page = render(self.incidents, title="Acme Status", now=NOW)

    def test_headline_reports_the_worst_open_severity(self):
        self.assertIn("Monitoring", self.page.split("</h1>")[0])

    def test_title_is_used(self):
        self.assertIn("<title>Acme Status</title>", self.page)

    def test_every_incident_appears(self):
        for inc in self.incidents:
            self.assertIn(f'id="{inc.id}"', self.page)

    # The page is served from object storage during an outage, when whatever would serve a
    # stylesheet is often the thing that is down.
    def test_page_makes_no_external_requests(self):
        for pattern in (r'src="https?://', r'href="https?://', r"@import"):
            self.assertIsNone(re.search(pattern, self.page), f"page reaches out: {pattern}")

    def test_updates_render_newest_first(self):
        body = self.page.split('id="2026-09-14-checkout-latency"')[1].split("</article>")[0]
        self.assertLess(body.index("Latency back under"), body.index("Traced to a connection"))

    def test_open_incident_says_ongoing(self):
        body = self.page.split('id="2026-09-14-checkout-latency"')[1].split("</article>")[0]
        self.assertIn("ongoing", body)

    def test_resolved_incident_reports_its_duration(self):
        body = self.page.split('id="2026-08-30-api-outage"')[1].split("</article>")[0]
        self.assertIn("lasted 22 min", body)

    def test_title_is_escaped(self):
        page = render([], title="<script>x</script>", now=NOW)
        self.assertNotIn("<script>x", page)

    def test_incident_text_is_escaped(self):
        inc = parse_incident(
            {"id": "e", "title": "5 < 6 & \"quoted\"", "severity": "major", "started": dt(1)}, "e")
        page = render([inc], now=NOW)
        self.assertIn("5 &lt; 6 &amp;", page)

    def test_empty_file_still_renders_a_page(self):
        page = render([], now=NOW)
        self.assertIn("All systems operational", page)
        self.assertIn("No incidents recorded", page)


if __name__ == "__main__":
    unittest.main()
