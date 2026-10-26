import importlib.util,unittest
from pathlib import Path
path=Path(__file__).resolve().parents[1]/'scripts/ecs/provision-ci.py'
spec=importlib.util.spec_from_file_location('ecs_ci',path)
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class CIPolicyTests(unittest.TestCase):
 def test_terminal_and_login_are_scoped_to_only_the_target_instance(self):
  document=module.policy('1234567890123456')
  execution=[s for s in document['Statement'] if 'ecs:StartTerminalSession' in s['Action']]
  self.assertEqual(len(execution),1)
  self.assertEqual(execution[0]['Resource'],'acs:ecs:cn-beijing:1234567890123456:instance/i-2ze251tg6q9u5s25jkq4')
  self.assertIn('ecs-workbench:LoginECSInstance',execution[0]['Action'])
  self.assertFalse(any('Action' in s and (s['Action']=='*' or isinstance(s['Action'],list) and '*' in s['Action']) for s in document['Statement']))
 def test_service_role_creation_is_restricted_and_account_is_not_interpolatable(self):
  statement=next(s for s in module.policy('1234567890123456')['Statement'] if s['Action']=='ram:CreateServiceLinkedRole')
  self.assertEqual(statement['Condition'],{'StringEquals':{'ram:ServiceName':'workbench.ecs.aliyuncs.com'}})
  with self.assertRaises(ValueError):module.policy('123:*')
