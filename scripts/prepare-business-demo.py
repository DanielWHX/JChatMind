"""Prepare a fictional SaaS support demo through the local public API. No model call."""
from pathlib import Path
import json,urllib.request,subprocess
ROOT=Path(__file__).resolve().parents[1]
BASE='http://127.0.0.1:8080'
def api(path,data=None):
 req=urllib.request.Request(BASE+path,data=None if data is None else json.dumps(data).encode(),headers={'Content-Type':'application/json'})
 with urllib.request.urlopen(req,timeout=90) as r: body=json.load(r)
 assert body['code']==200,body
 return body['data']
kb_name='OrbitDesk Product Handbook'
agent_name='OrbitDesk Support Copilot'
kbs=api('/api/knowledge-bases')['knowledgeBases']
kb=next((x['id'] for x in kbs if x['name']==kb_name),None)
if not kb: kb=api('/api/knowledge-bases',{'name':kb_name,'description':'Fictional SaaS demo: pricing, trials, onboarding and support policies.'})['knowledgeBaseId']
filename='orbitdesk-handbook.md'
if not any(d['filename']==filename for d in api('/api/documents/kb/'+kb)['documents']):
 result=json.loads(subprocess.check_output(['curl','-sf','--max-time','90','-F','kbId='+kb,'-F','file=@'+str(ROOT/'docs/business-demo'/filename),BASE+'/api/documents/upload']))
 assert result['code']==200,result
agents=api('/api/agents')['agents']
agent=next((x['id'] for x in agents if x['name']==agent_name),None)
if not agent:
 agent=api('/api/agents',{'name':agent_name,'description':'SaaS product questions, pricing calculations and customer reply drafts. Fictional demo.','systemPrompt':(ROOT/'docs/business-demo/agent-prompt.txt').read_text(),'model':'deepseek-chat','allowedTools':[],'allowedKbs':[kb],'chatOptions':{'temperature':0.3,'topP':1.0,'messageLength':60}})['agentId']
state={'agentId':agent,'knowledgeBaseId':kb}
(ROOT/'.local/business-demo.json').write_text(json.dumps(state,indent=2))
print(json.dumps(state))
