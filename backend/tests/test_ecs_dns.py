import importlib.util
import tempfile
import unittest
from pathlib import Path

path=Path(__file__).resolve().parents[1]/'scripts/ecs/aliyun-dns.py'
spec=importlib.util.spec_from_file_location('ecs_dns',path)
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

class DNSImportTests(unittest.TestCase):
 def parse(self,text):
  with tempfile.TemporaryDirectory() as directory:
   source=Path(directory)/'zone.txt';source.write_text('$ORIGIN myleafy.space.\n'+text)
   return module.desired_records(source)
 def test_preserves_mail_chunks_and_priorities_and_replaces_only_service_addresses(self):
  records=self.parse('@ 600 IN NS vivienne.ns.cloudflare.com.\n@ 1 IN CNAME leafy.pages.dev.\napi 300 IN AAAA ::1\nsend 300 IN TXT "v=spf1" " include:amazonses.com ~all"\nsend 600 IN MX 10 feedback-smtp.example.org.\nother 3600 IN CNAME api.myleafy.space.\n')
  service=[r for r in records if r['RR'] in module.SERVICE_HOSTS]
  self.assertEqual(len(service),7)
  self.assertTrue(all(r['Type']=='A' and r['Value']=='8.141.82.15' for r in service))
  self.assertIn({'RR':'send','Type':'TXT','Value':'v=spf1 include:amazonses.com ~all','TTL':600,'Line':'default'},records)
  self.assertIn({'RR':'send','Type':'MX','Value':'feedback-smtp.example.org','Priority':10,'TTL':600,'Line':'default'},records)
  self.assertIn({'RR':'other','Type':'CNAME','Value':'api.myleafy.space','TTL':3600,'Line':'default'},records)
 def test_unmapped_cloudflare_service_stops_before_any_api_change(self):
  with self.assertRaisesRegex(ValueError,'explicit target mapping'):
   self.parse('unmapped 600 IN CNAME another.pages.dev.\n')
 def test_unknown_type_stops_instead_of_silently_dropping_it(self):
  with self.assertRaisesRegex(ValueError,'Unsupported'):
   self.parse('other 600 IN HTTPS 1 .\n')
