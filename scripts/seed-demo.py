"""Create or reuse local demo content through JChatMind's public API."""
import json, urllib.request, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
BASE='http://127.0.0.1:8080'
def api(path,data=None,method=None):
    req=urllib.request.Request(BASE+path,data=None if data is None else json.dumps(data).encode(),headers={'Content-Type':'application/json'},method=method)
    with urllib.request.urlopen(req,timeout=60) as r: result=json.load(r)
    assert result['code']==200,result
    return result['data']
kbs=api('/api/knowledge-bases')['knowledgeBases']
kb=next((x['id'] for x in kbs if x['name']=='JChatMind Demo Knowledge'),None)
if not kb: kb=api('/api/knowledge-bases',{'name':'JChatMind Demo Knowledge','description':'Synthetic local demo facts and project overview'})['knowledgeBaseId']
if not api('/api/documents/kb/'+kb)['documents']:
    response=subprocess.check_output(['curl','-sf','--max-time','90','-F','kbId='+kb,'-F','file=@'+str(ROOT/'docs/demo-knowledge.md'),BASE+'/api/documents/upload'])
    result=json.loads(response);assert result['code']==200,result
agents=api('/api/agents')['agents']
agent=next((a['id'] for a in agents if a['name']=='JChatMind Demo'),None)
config={'name':'JChatMind Demo','description':'DeepSeek chat, real date tool and local knowledge retrieval','systemPrompt':'You are a concise, helpful demonstration assistant. Reply in the user\'s language. For questions about JChatMind demo facts, search the configured knowledge base and quote what it says. Use the date tool for today\'s date. City and weather tools are static examples, not live services. Complete the task with a clear answer and then terminate. Do not send email or execute SQL.','model':'deepseek-chat','allowedTools':[],'allowedKbs':[kb],'chatOptions':{'temperature':0.3,'topP':1.0,'messageLength':20}}
if not agent: agent=api('/api/agents',config)['agentId']
state={'agentId':agent,'knowledgeBaseId':kb}
(ROOT/'.local/demo.json').write_text(json.dumps(state,indent=2))
print(json.dumps(state))
