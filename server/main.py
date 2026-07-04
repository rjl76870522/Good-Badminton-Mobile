"""
Legacy browser-demo backend.

Do not use this file for the competition mobile frontend.
The only competition/mobile API entrypoint is:

  backend_api.py on port 8001

This legacy server is kept only for the older all-in-browser demo:

  python -m uvicorn server.main:app --host 0.0.0.0 --port 8000 --reload
"""
import os, sys, json, uuid, threading, traceback
from pathlib import Path

_BASE = Path(__file__).resolve().parent.parent
os.chdir(_BASE)
sys.path.insert(0, str(_BASE))

from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.responses import HTMLResponse, FileResponse
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import uvicorn

# ── 目录 ──
UPLOAD_DIR = _BASE / "server" / "uploads"
RESULT_DIR = _BASE / "server" / "results"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
RESULT_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI(title="Good-Badminton API", version="0.1")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])

# ── 任务状态存储（JSON 文件） ──
def _task_path(task_id: str) -> Path:
    return RESULT_DIR / f"{task_id}.json"

def _get_task(task_id: str) -> dict:
    p = _task_path(task_id)
    if not p.exists():
        raise HTTPException(404, f"任务 {task_id} 不存在")
    return json.loads(p.read_text("utf-8"))

def _save_task(task_id: str, data: dict):
    _task_path(task_id).write_text(json.dumps(data, ensure_ascii=False, indent=2), "utf-8")

# 上传文件索引（内存 + 持久化）
_UPLOAD_FILE = RESULT_DIR / "_uploads.json"
def _load_uploads() -> dict:
    if _UPLOAD_FILE.exists():
        return json.loads(_UPLOAD_FILE.read_text("utf-8"))
    return {}
def _save_upload(file_id: str, info: dict):
    d = _load_uploads()
    d[file_id] = info
    _UPLOAD_FILE.write_text(json.dumps(d, ensure_ascii=False, indent=2), "utf-8")

# ════════════════════════════════════════════════════
#  首页 — 简易测试页面
# ════════════════════════════════════════════════════
@app.get("/")
def index():
    return HTMLResponse("""<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Good-Badminton 🏸</title>
<style>
*{margin:0;padding:0;box-sizing:border-box;font-family:system-ui,sans-serif}
body{background:#1a1a2e;color:#e0e0e0;padding:16px}
h1{color:#4ecca3;font-size:22px}
.sub{color:#888;font-size:13px;margin:4px 0 14px}
.layout{display:flex;gap:14px;max-width:1100px;margin:auto;flex-wrap:wrap}
.left{flex:3;min-width:320px}
.right{flex:2;min-width:280px}
.card{background:#16213e;border-radius:10px;padding:14px;margin-bottom:10px}
.card h3{color:#4ecca3;font-size:14px;margin-bottom:6px}
label{display:block;font-size:12px;color:#aaa;margin:8px 0 3px}
input[type=file]{display:block;width:100%;padding:8px;border-radius:6px;background:#0d1117;color:#e0e0e0;font-size:12px;border:1px solid #333}
.file-row{display:flex;gap:8px;align-items:center}
.file-row input{flex:1}
button{background:#4ecca3;color:#111;border:none;padding:8px 16px;border-radius:6px;font-size:12px;font-weight:bold;cursor:pointer}
button:disabled{opacity:.5;cursor:default}
.btn-sm{padding:5px 12px;font-size:11px}
.btn-acc{background:#0f3460;color:#e0e0e0}
.btn-red{background:#e94560;color:#fff}
.btn-gray{background:#333;color:#e0e0e0}
.row{display:flex;gap:6px;flex-wrap:wrap;align-items:center;margin:6px 0}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:11px;font-weight:bold}
.green{background:#4ecca3;color:#111}
.red{background:#e94560;color:#fff}
.yellow{background:#ffa500;color:#111}
.gray{background:#333;color:#aaa}
.bar-wrap{background:#0d1117;border-radius:8px;height:18px;overflow:hidden}
.bar{height:100%;background:#4ecca3;transition:width .3s;border-radius:8px}
.preview-img{max-width:100%;border-radius:6px;margin:4px 0;cursor:pointer}
#corner-canvas{width:100%;border-radius:6px;margin:4px 0}
.tabs{display:flex;gap:4px;margin:6px 0}
.tab{padding:6px 14px;border-radius:6px;background:#333;font-size:12px;cursor:pointer}
.tab.active{background:#4ecca3;color:#111}
.tab-cont{display:none}
.tab-cont.show{display:block}
.stats-table td{padding:5px 8px;font-size:12px;border-bottom:1px solid #222}
.job-item{padding:8px;border-radius:6px;background:#0d1117;margin:4px 0;font-size:12px;cursor:pointer}
.job-item:hover{background:#1a1a2e}
select{background:#0d1117;color:#e0e0e0;border:1px solid #333;padding:5px 8px;border-radius:5px;font-size:12px}
.cb-row{display:flex;gap:10px;flex-wrap:wrap;margin:6px 0}
.cb-row label{display:inline-flex;align-items:center;gap:4px;font-size:12px;cursor:pointer;margin:0}
video{max-width:100%;border-radius:6px}
.modal{display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,.7);z-index:100;justify-content:center;align-items:center}
.modal.show{display:flex}
.modal img{max-width:90%;max-height:90%;border-radius:8px}
</style>
</head>
<body>
<div class="layout">

<!-- ═══ 左侧：操作区 ═══ -->
<div class="left">

<h1>🏸 Good-Badminton</h1>
<p class="sub">上传视频 → 检测球场 → 设置 → 分析</p>

<!-- 文件 -->
<div class="card">
  <h3>📁 输入文件</h3>
  <div class="file-row">
    <input type="file" id="fp-video" accept="video/*">
    <button class="btn-sm btn-acc" onclick="document.getElementById('fp-video').click()">选择视频</button>
  </div>
  <div id="video-info" style="font-size:11px;color:#888;margin:4px 0"></div>
  <div class="file-row" id="tmpl-row">
    <input type="file" id="fp-tmpl" accept="image/*">
    <button class="btn-sm btn-acc" onclick="document.getElementById('fp-tmpl').click()">选择本地文件</button>
  </div>
  <div id="tmpl-status" style="display:none;font-size:12px;color:#4ecca3;margin:4px 0"></div>
  <div class="row" style="margin-top:4px">
    <button class="btn-sm btn-gray" onclick="extractFromVideo()">🎯 从视频截取模板</button>
    <span id="extract-status" style="font-size:11px;color:#888"></span>
  </div>
</div>

<!-- 球场检测 -->
<div class="card">
  <h3>📍 球场检测</h3>
  <div class="row">
    <button onclick="detectCorners()">🔍 自动检测角点</button>
    <span id="corner-status" style="font-size:11px;color:#888">未检测</span>
  </div>
  <canvas id="corner-canvas" style="display:none"></canvas>
  <div id="corner-actions" style="display:none" class="row">
    <button onclick="confirmCorners()">✅ 满意，下一步</button>
    <button class="btn-gray" onclick="detectCorners()">🔄 重新检测</button>
    <button class="btn-gray" onclick="enterManualMode()">✏️ 手动标记</button>
  </div>
  <div id="corner-result" style="font-size:11px"></div>
  <canvas id="manual-canvas" style="display:none;cursor:crosshair;max-width:100%;border-radius:6px"></canvas>
  <div id="manual-actions" style="display:none" class="row">
    <span style="font-size:12px;color:#ffa500" id="manual-hint">点击球场的4个角点: 左上→右上→右下→左下</span>
    <button onclick="submitManualCorners()">✅ 提交角点</button>
    <button class="btn-gray" onclick="cancelManual()">取消</button>
  </div>
</div>

<!-- 设置 -->
<div class="card">
  <h3>⚙️ 分析设置</h3>
  <div class="row">
    <span style="font-size:12px">模型:</span>
    <select id="sel-pose"><option>yolo-pose</option><option>rtmpose</option><option>rtmo</option></select>
    <span style="font-size:12px;margin-left:10px">语言:</span>
    <select id="sel-lang"><option value="zh">中文</option><option value="en">English</option></select>
  </div>
  <div class="cb-row">
    <label><input type="checkbox" id="chk-sk" checked>🦴 骨架</label>
    <label><input type="checkbox" id="chk-tr" checked>👣 轨迹</label>
    <label><input type="checkbox" id="chk-co" checked>🗺️ 小地图</label>
    <label><input type="checkbox" id="chk-sh" checked>🏸 羽球</label>
    <label><input type="checkbox" id="chk-st" checked>📊 统计</label>
  </div>
</div>

<!-- 操作 -->
<div class="card">
  <div class="row">
    <button id="btn-run" onclick="startAnalysis()" style="padding:10px 24px;font-size:14px">▶ 开始分析</button>
    <span id="run-status" style="font-size:11px;color:#888"></span>
  </div>
  <div id="progress-card" style="display:none">
    <div class="row" style="justify-content:space-between"><span id="st">排队中</span><span id="pt">0%</span></div>
    <div class="bar-wrap"><div class="bar" id="bar" style="width:0%"></div></div>
  </div>
</div>

<!-- 结果 -->
<div class="card" id="result-card" style="display:none">
  <h3>📊 分析结果</h3>
  <div class="tabs" id="result-tabs">
    <span class="tab active" onclick="switchTab('video',this)">🎬 视频</span>
    <span class="tab" onclick="switchTab('heat',this)">🔥 热力图</span>
    <span class="tab" onclick="switchTab('scatter',this)">🔵 散点图</span>
    <span class="tab" onclick="switchTab('stats',this)">📊 统计</span>
  </div>
  <div id="tab-video" class="tab-cont show"></div>
  <div id="tab-heat" class="tab-cont"></div>
  <div id="tab-scatter" class="tab-cont"></div>
  <div id="tab-stats" class="tab-cont"></div>
</div>
</div>

<!-- ═══ 右侧：历史任务 ═══ -->
<div class="right">
<div class="card">
  <h3>📋 历史任务</h3>
  <div class="row"><button class="btn-sm btn-gray" onclick="loadJobs()">🔄 刷新</button></div>
  <div id="job-list"></div>
</div>
</div>

<!-- 图片放大弹窗 -->
<div class="modal" id="modal" onclick="this.classList.remove('show')">
  <img id="modal-img">
</div>

<script>
// ═══ 状态（localStorage 持久化） ═══
let STATE = { videoId: null, templateId: null, corners: null, taskId: null, cornersConfirmed: false };

function saveState(){
  try{ localStorage.setItem('gb_state', JSON.stringify({
    videoId: STATE.videoId,
    templateId: STATE.templateId,
    corners: STATE.corners,
    cornersConfirmed: STATE.cornersConfirmed
  })); }catch(e){}
}

function loadState(){
  try{
    const raw = localStorage.getItem('gb_state');
    if(!raw) return;
    const s = JSON.parse(raw);
    if(s.videoId) STATE.videoId = s.videoId;
    if(s.templateId){ STATE.templateId = s.templateId; setTemplateReady(s.templateId, '已恢复'); }
    if(s.corners){ STATE.corners = s.corners; STATE.cornersConfirmed = s.cornersConfirmed || false; }
    if(STATE.corners && STATE.cornersConfirmed){
      document.getElementById('corner-status').textContent = '✅ 角点已确认 (从上次会话恢复)';
      document.getElementById('corner-status').className = 'badge green';
    }
  }catch(e){}
}
window.addEventListener('beforeunload', saveState);
loadState();

// ═══ 文件选择 ═══
document.getElementById('fp-video').onchange = function(){
  document.getElementById('video-info').textContent = this.files[0]?.name + ' (' + (this.files[0]?.size/1024/1024).toFixed(1) + 'MB)';
};
document.getElementById('fp-tmpl').onchange = function(){
  // 上传模板并检测
  if(this.files[0]) uploadAndDetect(this.files[0]);
};

function setTemplateReady(fileId, label){
  STATE.templateId = fileId; saveState();
  document.getElementById('tmpl-row').style.display = 'none';
  const s = document.getElementById('tmpl-status');
  s.style.display = 'block';
  s.innerHTML = '✅ 模板: ' + label;
}

async function uploadAndDetect(file){
  const fd = new FormData(); fd.append('file', file);
  const r = await fetch('/api/templates/detect', {method:'POST', body:fd});
  const d = await r.json();
  if(d.corners && d.corners.length===4){
    STATE.corners = d.corners;
    setTemplateReady(d.template_id, '本地文件 ('+d.score+'分)');
    document.getElementById('corner-status').textContent = '✅ 检测到4个角点 (评分:'+d.score+')';
    document.getElementById('corner-status').className = 'badge green';
    showCornerPreview(d.preview_b64);
    document.getElementById('corner-actions').style.display = 'flex';
  } else {
    document.getElementById('corner-status').textContent = '❌ 检测失败，请重试';
    document.getElementById('corner-status').className = 'badge red';
  }
}

function showCornerPreview(b64){
  const canvas = document.getElementById('corner-canvas');
  canvas.style.display = 'block';
  const ctx = canvas.getContext('2d');
  const img = new Image();
  img.onload = function(){
    canvas.width = img.width; canvas.height = img.height;
    const maxW = canvas.parentElement.clientWidth - 28;
    if(img.width > maxW){ canvas.style.width = maxW+'px'; canvas.style.height = (maxW/img.width*img.height)+'px'; }
    ctx.drawImage(img, 0, 0);
  };
  img.src = 'data:image/png;base64,' + b64;
}

// ═══ 角点检测 ═══
async function extractFromVideo(){
  if(!STATE.videoId){
    const f = document.getElementById('fp-video').files[0];
    if(!f){ alert('请先选择视频'); return; }
    const fd = new FormData(); fd.append('file', f);
    document.getElementById('extract-status').textContent = '上传视频中...';
    const r = await fetch('/api/upload/video', {method:'POST', body:fd});
    const d = await r.json();
    STATE.videoId = d.file_id;
  }
  document.getElementById('extract-status').textContent = '⏳ 扫描最佳帧...';
  document.getElementById('fp-tmpl').disabled = true;
  try {
    const r = await fetch('/api/templates/extract/' + STATE.videoId, {method:'POST'});
    const d = await r.json();
    if(d.corners && d.corners.length===4){
      STATE.corners = d.corners;
      setTemplateReady(d.template_id, '帧#'+d.extracted_frame+' ('+d.score+'分)');
      document.getElementById('corner-status').textContent = '✅ 帧#'+d.extracted_frame+' 评分'+d.score;
      document.getElementById('corner-status').className = 'badge green';
      showCornerPreview(d.preview_b64);
      document.getElementById('corner-actions').style.display = 'flex';
    } else {
      document.getElementById('corner-status').textContent = '❌ 角点检测失败';
      document.getElementById('corner-status').className = 'badge red';
    }
    document.getElementById('extract-status').textContent = '✅ 帧#'+d.extracted_frame;
  } catch(e){
    document.getElementById('extract-status').textContent = '❌ 失败';
    alert('截取出错: '+e);
  }
  document.getElementById('fp-tmpl').disabled = false;
}

// ═══ 手动标记角点 ═══
let _manualPts = [];
let _manualImg = null;

async function enterManualMode(){
  // 获取模板图片
  let imgUrl = null;
  if(STATE.templateId){
    const r = await fetch('/api/templates/file/' + STATE.templateId);
    if(r.ok){ const blob = await r.blob(); imgUrl = URL.createObjectURL(blob); }
  }
  if(!imgUrl){
    const f = document.getElementById('fp-tmpl').files[0];
    if(!f){ alert('没有模板图片，请先选择或截取模板'); return; }
    imgUrl = URL.createObjectURL(f);
  }
  _manualPts = [];
  document.getElementById('corner-actions').style.display = 'none';
  document.getElementById('corner-canvas').style.display = 'none';
  document.getElementById('manual-canvas').style.display = 'block';
  document.getElementById('manual-actions').style.display = 'flex';
  document.getElementById('manual-hint').textContent = '点击球场的4个角点: 左上→右上→右下→左下 (已点0个)';

  const canvas = document.getElementById('manual-canvas');
  const ctx = canvas.getContext('2d');
  const img = new Image();
  _manualImg = img;
  img.onload = function(){
    canvas.width = img.width;
    canvas.height = img.height;
    const maxW = canvas.parentElement.clientWidth - 28;
    if(img.width > maxW){
      canvas.style.width = maxW+'px';
      canvas.style.height = (maxW/img.width*img.height)+'px';
    } else {
      canvas.style.width = img.width+'px';
      canvas.style.height = img.height+'px';
    }
    ctx.drawImage(img, 0, 0);
    drawManualPts();
  };
  img.src = imgUrl;
  canvas.onclick = function(e){
    const rect = canvas.getBoundingClientRect();
    const scaleX = canvas.width / rect.width;
    const scaleY = canvas.height / rect.height;
    const x = Math.round((e.clientX - rect.left) * scaleX);
    const y = Math.round((e.clientY - rect.top) * scaleY);
    if(_manualPts.length >= 4) return;
    _manualPts.push([x, y]);
    drawManualPts();
    document.getElementById('manual-hint').textContent =
      '点击球场的4个角点: 左上→右上→右下→左下 (已点'+_manualPts.length+'个)';
    if(_manualPts.length === 4){
      document.getElementById('manual-hint').textContent = '✅ 已点完4个角点，点击「提交角点」';
    }
  };
}

function drawManualPts(){
  const canvas = document.getElementById('manual-canvas');
  const ctx = canvas.getContext('2d');
  if(_manualImg) ctx.drawImage(_manualImg, 0, 0);
  _manualPts.forEach((pt, i) => {
    ctx.beginPath();
    ctx.arc(pt[0], pt[1], 6, 0, 2*Math.PI);
    ctx.fillStyle = '#e94560'; ctx.fill();
    ctx.strokeStyle = 'white'; ctx.lineWidth = 2; ctx.stroke();
    ctx.fillStyle = 'white';
    ctx.font = 'bold 16px sans-serif';
    ctx.fillText(i+1, pt[0]+10, pt[1]-5);
  });
  if(_manualPts.length === 4){
    ctx.beginPath();
    ctx.moveTo(_manualPts[0][0], _manualPts[0][1]);
    for(let i=1; i<4; i++) ctx.lineTo(_manualPts[i][0], _manualPts[i][1]);
    ctx.closePath();
    ctx.strokeStyle = '#4ecca3'; ctx.lineWidth = 3; ctx.stroke();
  }
}

function cancelManual(){
  _manualPts = [];
  document.getElementById('manual-canvas').style.display = 'none';
  document.getElementById('manual-actions').style.display = 'none';
  if(STATE.corners) document.getElementById('corner-actions').style.display = 'flex';
}

async function submitManualCorners(){
  if(_manualPts.length !== 4){ alert('请点击4个角点'); return; }
  // 提交前先上传模板获取template_id
  if(!STATE.templateId){
    const f = document.getElementById('fp-tmpl').files[0];
    if(f){
      const fd = new FormData(); fd.append('file', f);
      const r = await fetch('/api/upload/template', {method:'POST', body:fd});
      const d = await r.json();
      STATE.templateId = d.file_id;
    }
  }
  if(!STATE.templateId){
    // 如果还没有templateId，创建一个
    const fd = new FormData();
    fd.append('file', new Blob(['placeholder']), 'manual.png');
    const r = await fetch('/api/upload/template', {method:'POST', body:fd});
    const d = await r.json();
    STATE.templateId = d.file_id;
  }
  // 保存角点到服务器
  await fetch('/api/templates/'+STATE.templateId+'/corners', {
    method:'PUT',
    headers:{'Content-Type':'application/json'},
    body: JSON.stringify({corners: _manualPts})
  });
  STATE.corners = _manualPts;
  document.getElementById('manual-canvas').style.display = 'none';
  document.getElementById('manual-actions').style.display = 'none';
  document.getElementById('corner-status').textContent = '✅ 手动标注完成';
  document.getElementById('corner-status').className = 'badge green';
  document.getElementById('corner-actions').style.display = 'flex';
  // 在普通canvas上画预览
  const canvas = document.getElementById('corner-canvas');
  canvas.style.display = 'block';
  const ctx = canvas.getContext('2d');
  const img = _manualImg;
  canvas.width = img.width; canvas.height = img.height;
  const maxW = canvas.parentElement.clientWidth - 28;
  if(img.width > maxW){ canvas.style.width = maxW+'px'; canvas.style.height = (maxW/img.width*img.height)+'px'; }
  else { canvas.style.width = img.width+'px'; canvas.style.height = img.height+'px'; }
  ctx.drawImage(img, 0, 0);
  // 画角点和边框
  _manualPts.forEach((pt, i) => {
    ctx.beginPath(); ctx.arc(pt[0], pt[1], 6, 0, 2*Math.PI);
    ctx.fillStyle = '#e94560'; ctx.fill(); ctx.strokeStyle = 'white'; ctx.lineWidth = 2; ctx.stroke();
    ctx.fillStyle = 'white'; ctx.font = 'bold 16px sans-serif';
    ctx.fillText(i+1, pt[0]+10, pt[1]-5);
  });
  ctx.beginPath(); ctx.moveTo(_manualPts[0][0], _manualPts[0][1]);
  for(let i=1; i<4; i++) ctx.lineTo(_manualPts[i][0], _manualPts[i][1]);
  ctx.closePath(); ctx.strokeStyle = '#4ecca3'; ctx.lineWidth = 3; ctx.stroke();
}

async function detectCorners(){
  cancelManual();
  // 如果有模板ID但没文件（截取的模板），重新检测已上传的模板
  if(STATE.templateId && !document.getElementById('fp-tmpl').files[0]){
    document.getElementById('corner-status').textContent = '⏳ 重新检测中...';
    document.getElementById('corner-status').className = 'badge yellow';
    // 从上传记录中重新获取模板文件并检测
    const r = await fetch('/api/templates/' + STATE.templateId);
    const info = await r.json();
    if(info.file_id){
      // 重新上传同一个模板来触发检测
      const resp = await fetch('/api/templates/detect', {method:'POST',
        body:(()=>{const fd=new FormData();
          // 用hidden方法：先获取原文件路径，让服务端重新检测
          fd.append('file', new Blob(['re-detect']), 'redetect.png');
          return fd;
        })()
      });
    }
    // 简单方式：直接调用重新检测端点（需要后端支持）
    // 当前先强制用已有模板ID重新检测
    const fd = new FormData();
    // 从服务器获取模板文件
    const fileResp = await fetch('/api/templates/file/' + STATE.templateId);
    if(fileResp.ok){
      const blob = await fileResp.blob();
      fd.append('file', blob, 'template.png');
      const r = await fetch('/api/templates/detect', {method:'POST', body:fd});
      const d = await r.json();
      if(d.corners && d.corners.length===4){
        STATE.corners = d.corners;
        STATE.templateId = d.template_id;
        document.getElementById('corner-status').textContent = '✅ 重新检测成功 (评分:'+d.score+')';
        document.getElementById('corner-status').className = 'badge green';
        showCornerPreview(d.preview_b64);
        document.getElementById('corner-actions').style.display = 'flex';
      } else {
        document.getElementById('corner-status').textContent = '❌ 检测失败';
        document.getElementById('corner-status').className = 'badge red';
      }
    }
    return;
  }
  const file = document.getElementById('fp-tmpl').files[0];
  if(!file){ alert('请先选择模板图片'); return; }
  document.getElementById('corner-status').textContent = '⏳ 检测中...';
  document.getElementById('corner-status').className = 'badge yellow';
  await uploadAndDetect(file);
}

function confirmCorners(){
  STATE.cornersConfirmed = true;
  document.getElementById('corner-status').textContent = '✅ 已确认角点，可以开始分析';
  document.getElementById('corner-status').className = 'badge green';
  document.getElementById('corner-actions').style.display = 'none';
}

// ═══ 开始分析 ═══
async function startAnalysis(){
  if(STATE.taskId) return;
  if(!STATE.cornersConfirmed && !STATE.corners){
    alert('请先检测并确认球场角点（点击「✅ 满意，下一步」）');
    return;
  }
  const vFile = document.getElementById('fp-video').files[0];
  if(!vFile && !STATE.videoId){ alert('请选择视频'); return; }

  document.getElementById('btn-run').disabled = true;
  document.getElementById('run-status').textContent = '上传中...';
  document.getElementById('progress-card').style.display = 'block';

  // 1. 上传视频
  if(!STATE.videoId){
    const fd = new FormData(); fd.append('file', vFile);
    const r = await fetch('/api/upload/video', {method:'POST', body:fd});
    const d = await r.json();
    STATE.videoId = d.file_id;
  }

  // 2. 上传模板（如果还没有，检查STATE和文件输入）
  if(!STATE.templateId){
    const tFile = document.getElementById('fp-tmpl').files[0];
    if(!tFile){ alert('请先选择或截取球场模板'); document.getElementById('btn-run').disabled=false; return; }
    const fd = new FormData(); fd.append('file', tFile);
    const r = await fetch('/api/upload/template', {method:'POST', body:fd});
    const d = await r.json();
    STATE.templateId = d.file_id;
  }

  // 3. 提交分析
  document.getElementById('run-status').textContent = '提交中...';
  const opt = {
    video_id: STATE.videoId,
    template_id: STATE.templateId,
    language: document.getElementById('sel-lang').value,
    pose_family: document.getElementById('sel-pose').value,
    show_skeletons: document.getElementById('chk-sk').checked,
    show_traj: document.getElementById('chk-tr').checked,
    show_court: document.getElementById('chk-co').checked,
    show_shuttle: document.getElementById('chk-sh').checked,
    show_stats: document.getElementById('chk-st').checked,
  };
  const r = await fetch('/api/analyze', {method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(opt)});
  const d = await r.json();
  STATE.taskId = d.task_id;
  document.getElementById('run-status').textContent = '任务已提交';

  // 4. 轮询进度
  pollStatus(STATE.taskId);
}

async function pollStatus(taskId){
  const r = await fetch('/api/status/' + taskId);
  const s = await r.json();
  const p = s.progress || 0;
  document.getElementById('bar').style.width = p+'%';
  document.getElementById('pt').textContent = p+'%';
  document.getElementById('st').textContent = s.status;

  if(s.status === 'completed'){
    document.getElementById('st').textContent = '✅ 完成';
    document.getElementById('bar').style.width = '100%';
    document.getElementById('run-status').textContent = '✅ 完成';
    document.getElementById('btn-run').disabled = false;
    STATE.taskId = null;
    // 获取结果
    const rr = await fetch('/api/result/' + taskId);
    const rd = await rr.json();
    showResults(rd);
    loadJobs();
    return;
  }
  if(s.status === 'failed'){
    document.getElementById('st').textContent = '❌ ' + (s.error || '失败');
    document.getElementById('run-status').textContent = '❌ 失败';
    document.getElementById('btn-run').disabled = false;
    STATE.taskId = null;
    return;
  }
  setTimeout(() => pollStatus(taskId), 1500);
}

// ═══ 结果展示 ═══
let _lastResult = null;

function showResults(r){
  _lastResult = r;
  document.getElementById('result-card').style.display = 'block';
  // 视频
  const vDiv = document.getElementById('tab-video');
  if(r.video_url) vDiv.innerHTML = '<video controls src="'+r.video_url+'" style="max-height:400px"></video>';
  else vDiv.innerHTML = '<p style="color:#888">无视频输出</p>';
  // 热力图
  const hDiv = document.getElementById('tab-heat');
  hDiv.innerHTML = '';
  if(r.visualizations && r.visualizations.length){
    r.visualizations.forEach((u,i) => {
      if(u.includes('heatmap'))
        hDiv.innerHTML += '<img class="preview-img" src="'+u+'" onclick="zoomImg(this.src)">';
    });
  }
  if(!hDiv.innerHTML) hDiv.innerHTML = '<p style="color:#888">无热力图</p>';
  // 散点图
  const sDiv = document.getElementById('tab-scatter');
  sDiv.innerHTML = '';
  if(r.visualizations){
    r.visualizations.forEach((u,i) => {
      if(u.includes('scatter'))
        sDiv.innerHTML += '<img class="preview-img" src="'+u+'" onclick="zoomImg(this.src)">';
    });
  }
  if(!sDiv.innerHTML) sDiv.innerHTML = '<p style="color:#888">无散点图</p>';
  // 统计
  const tDiv = document.getElementById('tab-stats');
  if(r.stats){
    let html = '<table class="stats-table">';
    for(const[k,v] of Object.entries(r.stats)){
      html += '<tr><td>'+k+'</td><td>'+JSON.stringify(v).slice(0,300)+'</td></tr>';
    }
    tDiv.innerHTML = html + '</table>';
  } else { tDiv.innerHTML = '<p style="color:#888">无统计数据</p>'; }
  switchTab('video', document.querySelector('.tab'));
}

function switchTab(name, el){
  document.querySelectorAll('.tab').forEach(t=>t.classList.remove('active'));
  el.classList.add('active');
  document.querySelectorAll('.tab-cont').forEach(c=>c.classList.remove('show'));
  document.getElementById('tab-'+name).classList.add('show');
}

function zoomImg(src){
  document.getElementById('modal').classList.add('show');
  document.getElementById('modal-img').src = src;
}

// ═══ 历史任务 ═══
async function loadJobs(){
  const r = await fetch('/api/jobs');
  const d = await r.json();
  const list = document.getElementById('job-list');
  list.innerHTML = '';
  if(!d.jobs || !d.jobs.length){ list.innerHTML = '<p style="color:#888;font-size:12px">暂无任务</p>'; return; }
  d.jobs.forEach(j => {
    const div = document.createElement('div');
    div.className = 'job-item';
    const statusClass = j.status==='completed'?'green': j.status==='failed'?'red': j.status==='processing'?'yellow':'gray';
    div.innerHTML = '<span class="badge '+statusClass+'">'+j.status+'</span> '+(j.video_name||'')+' <span style="color:#666;float:right">'+(j.progress||0)+'%</span>';
    div.onclick = async function(){
      if(j.status==='completed'){
        const rr = await fetch('/api/result/'+j.task_id);
        const rd = await rr.json();
        showResults(rd);
      }
    };
    list.appendChild(div);
  });
}

// ═══ 初始化 ═══
loadJobs();
</script>
</body>
</html>""")


# ════════════════════════════════════════════════════
#  上传接口
# ════════════════════════════════════════════════════

@app.post("/api/upload/video")
async def upload_video(file: UploadFile = File(...)):
    file_id = uuid.uuid4().hex[:12]
    ext = os.path.splitext(file.filename or "video.mp4")[1] or ".mp4"
    save_path = UPLOAD_DIR / f"{file_id}{ext}"
    content = await file.read()
    save_path.write_bytes(content)
    info = {"path": str(save_path), "filename": file.filename, "size": len(content), "type": "video"}
    _save_upload(file_id, info)
    return {"file_id": file_id, "filename": file.filename, "size": len(content)}


@app.post("/api/upload/template")
async def upload_template(file: UploadFile = File(...)):
    file_id = uuid.uuid4().hex[:12]
    ext = os.path.splitext(file.filename or "template.png")[1] or ".png"
    save_path = UPLOAD_DIR / f"{file_id}{ext}"
    content = await file.read()
    save_path.write_bytes(content)
    info = {"path": str(save_path), "filename": file.filename, "size": len(content), "type": "template"}
    _save_upload(file_id, info)
    return {"file_id": file_id, "filename": file.filename, "size": len(content)}


# ════════════════════════════════════════════════════
#  分析接口
# ════════════════════════════════════════════════════

class AnalyzeRequest(BaseModel):
    video_id: str
    template_id: str
    language: str = "zh"
    pose_family: str = "yolo-pose"
    show_skeletons: bool = True
    show_traj: bool = True
    show_court: bool = True
    show_shuttle: bool = True
    show_stats: bool = True


# ── 新增：历史任务列表 ──
_JOB_INDEX_FILE = RESULT_DIR / "_job_index.json"

def _load_job_index() -> list:
    if _JOB_INDEX_FILE.exists():
        return json.loads(_JOB_INDEX_FILE.read_text("utf-8"))
    return []

def _save_job_index(idx: list):
    _JOB_INDEX_FILE.write_text(json.dumps(idx, ensure_ascii=False), "utf-8")

@app.get("/api/jobs")
def list_jobs(status: str = None):
    """列出所有分析任务，可按状态筛选。"""
    idx = _load_job_index()
    jobs = []
    for task_id in idx:
        try:
            t = _get_task(task_id)
            jobs.append({
                "task_id": task_id,
                "status": t["status"],
                "progress": t["progress"],
                "video_name": os.path.basename(t.get("video_path", "")),
                "created_at": t.get("created_at", ""),
                "error": t.get("error"),
            })
        except Exception:
            pass
    if status:
        jobs = [j for j in jobs if j["status"] == status]
    jobs.sort(key=lambda x: x.get("created_at", ""), reverse=True)
    return {"jobs": jobs, "total": len(jobs)}


@app.delete("/api/jobs/{task_id}")
def delete_job(task_id: str):
    """删除任务及其结果文件。"""
    t = _get_task(task_id)
    # 删除结果目录
    out_dir = t.get("result", {}).get("output_dir", "") if t.get("result") else ""
    if out_dir and os.path.exists(out_dir):
        import shutil
        shutil.rmtree(out_dir, ignore_errors=True)
    # 删除任务文件
    _task_path(task_id).unlink(missing_ok=True)
    # 从索引中移除
    idx = _load_job_index()
    if task_id in idx:
        idx.remove(task_id)
        _save_job_index(idx)
    return {"status": "deleted"}


# ── 新增：球场角点检测 ──
@app.post("/api/templates/detect")
async def detect_template_corners(file: UploadFile = File(...)):
    """上传模板图并自动检测球场角点。"""
    file_id = uuid.uuid4().hex[:12]
    ext = os.path.splitext(file.filename or "template.png")[1] or ".png"
    save_path = UPLOAD_DIR / f"{file_id}{ext}"
    content = await file.read()
    save_path.write_bytes(content)
    info = {"path": str(save_path), "filename": file.filename, "size": len(content), "type": "template"}
    _save_upload(file_id, info)

    # 自动检测角点
    import cv2 as _cv2
    img = _cv2.imread(str(save_path))
    corners = None
    preview_b64 = None
    score = 0

    if img is not None:
        from badminton_analysis.court.detector import auto_detect_court_corners, render_auto_court_preview
        from badminton_analysis.court.mapper import compute_expanded_roi
        import base64 as _b64

        detected, _mask, debug = auto_detect_court_corners(img)
        if detected and len(detected) == 4:
            corners = detected
            score = debug.get("score", 0) if debug else 0
            roi = compute_expanded_roi(corners, img.shape)
            preview_img = render_auto_court_preview(img, corners, roi, debug)
            # 调整预览图尺寸
            ph, pw = preview_img.shape[:2]
            if ph > 600:
                scale = 600 / ph
                pw, ph = int(pw * scale), 600
                preview_img = _cv2.resize(preview_img, (pw, ph))
            _, buf = _cv2.imencode(".png", preview_img)
            preview_b64 = _b64.b64encode(buf).decode()

    # 保存角点到模板记录
    template_info = {
        "file_id": file_id,
        "filename": file.filename,
        "corners": corners,
        "score": round(score, 1) if score else 0,
        "detect_method": "auto" if corners else "failed",
    }
    _save_upload(file_id, {**info, **template_info})

    return {
        "template_id": file_id,
        "filename": file.filename,
        "corners": corners,
        "score": round(score, 1) if score else 0,
        "detect_method": "auto" if corners else "failed",
        "preview_b64": preview_b64,
    }


@app.get("/api/templates/file/{template_id}")
def get_template_file(template_id: str):
    """获取模板图片文件。"""
    uploads = _load_uploads()
    if template_id not in uploads:
        raise HTTPException(404, "模板不存在")
    path = uploads[template_id].get("path", "")
    if not path or not os.path.exists(path):
        raise HTTPException(404, "模板文件不存在")
    return FileResponse(path)


@app.get("/api/templates/{template_id}")
def get_template(template_id: str):
    """获取模板信息及角点。"""
    uploads = _load_uploads()
    if template_id not in uploads:
        raise HTTPException(404, "模板不存在")
    info = uploads[template_id]
    return {
        "template_id": template_id,
        "filename": info.get("filename"),
        "corners": info.get("corners"),
        "score": info.get("score"),
        "detect_method": info.get("detect_method"),
    }


# ── 从视频截取模板帧 ──
@app.post("/api/templates/extract/{video_id}")
async def extract_template_from_video(video_id: str):
    uploads = _load_uploads()
    if video_id not in uploads:
        raise HTTPException(404, "视频不存在")
    video_path = uploads[video_id]["path"]
    if not os.path.exists(video_path):
        raise HTTPException(404, "视频文件不存在")
    import cv2 as _cv2
    cap = _cv2.VideoCapture(video_path)
    total = int(cap.get(_cv2.CAP_PROP_FRAME_COUNT))
    fps = cap.get(_cv2.CAP_PROP_FPS)
    if total < 1:
        raise HTTPException(400, "视频无效")

    def score_frame(fr):
        g = _cv2.cvtColor(fr, _cv2.COLOR_BGR2GRAY)
        e = _cv2.Canny(g, 50, 150)
        edge = min(1, _cv2.countNonZero(e) / (g.size * 0.15))
        bri = 1 - abs(g.mean() - 90) / 90
        var = min(1, g.std() / 50)
        hsv = _cv2.cvtColor(fr, _cv2.COLOR_BGR2HSV)
        grn = min(1, ((hsv[:,:,0]>=35)&(hsv[:,:,0]<=95)&(hsv[:,:,1]>=30)).sum()/g.size/0.2)
        return edge*40 + max(0,bri)*25 + var*20 + grn*15

    start_pos = int(total * 0.10)
    end_pos = int(total * 0.90)
    interval = max(1, int(fps * 2))
    best_score, best_frame, best_pos = -1, None, 0
    for pos in range(start_pos, min(end_pos, total), interval):
        cap.set(_cv2.CAP_PROP_POS_FRAMES, pos)
        ret, fr = cap.read()
        if not ret: continue
        sc = score_frame(fr)
        if sc > best_score:
            best_score, best_frame, best_pos = sc, fr.copy(), pos
    cap.release()
    if best_frame is None:
        raise HTTPException(500, "无法提取帧")

    file_id = uuid.uuid4().hex[:12]
    save_path = UPLOAD_DIR / f"{file_id}.png"
    _cv2.imwrite(str(save_path), best_frame)
    info = {"path":str(save_path), "filename":f"extract_{video_id}.png",
            "size":os.path.getsize(save_path), "type":"template", "source_video":video_id}
    _save_upload(file_id, info)

    from badminton_analysis.court.detector import auto_detect_court_corners, render_auto_court_preview
    from badminton_analysis.court.mapper import compute_expanded_roi
    import base64 as _b64
    img = _cv2.imread(str(save_path))
    corners, preview_b64 = None, None
    if img is not None:
        detected, _mask, debug = auto_detect_court_corners(img)
        if detected and len(detected) == 4:
            corners = detected
            roi = compute_expanded_roi(corners, img.shape)
            pv = render_auto_court_preview(img, corners, roi, debug)
            ph, pw = pv.shape[:2]
            if ph > 600:
                s = 600/ph; pw, ph = int(pw*s), 600
                pv = _cv2.resize(pv, (pw, ph))
            _, buf = _cv2.imencode(".png", pv)
            preview_b64 = _b64.b64encode(buf).decode()
    _save_upload(file_id, {**info, "corners":corners, "detect_method":"auto" if corners else "failed"})
    return {"template_id":file_id, "filename":f"extract_{video_id}.png",
            "extracted_frame":best_pos, "extract_score":round(best_score,1),
            "corners":corners, "score":round(debug.get("score",0) if corners else 0,1),
            "detect_method":"auto" if corners else "failed", "preview_b64":preview_b64}


class CornersRequest(BaseModel):
    corners: list

@app.put("/api/templates/{template_id}/corners")
def update_template_corners(template_id: str, req: CornersRequest):
    """手动修正球场角点。"""
    uploads = _load_uploads()
    if template_id not in uploads:
        raise HTTPException(404, "模板不存在")
    corners = req.corners
    if len(corners) != 4:
        raise HTTPException(400, "需要4个角点坐标")
    uploads[template_id]["corners"] = corners
    uploads[template_id]["detect_method"] = "manual"
    _UPLOAD_FILE.write_text(json.dumps(uploads, ensure_ascii=False, indent=2), "utf-8")
    return {"template_id": template_id, "corners": corners, "status": "updated"}


# ════════════════════════════════════════════════════
#  分析接口
# ════════════════════════════════════════════════════

@app.post("/api/analyze")
async def start_analysis(req: AnalyzeRequest):
    uploads = _load_uploads()
    if req.video_id not in uploads:
        raise HTTPException(400, f"video_id '{req.video_id}' 不存在，请先上传")
    if req.template_id not in uploads:
        raise HTTPException(400, f"template_id '{req.template_id}' 不存在，请先上传")

    task_id = uuid.uuid4().hex[:12]
    task = {
        "task_id": task_id, "status": "queued", "progress": 0,
        "video_path": uploads[req.video_id]["path"],
        "template_path": uploads[req.template_id]["path"],
        "options": req.model_dump(),
        "result": None, "error": None,
        "created_at": str(__import__("datetime").datetime.now()),
    }
    _save_task(task_id, task)

    # 加入索引
    idx = _load_job_index()
    idx.append(task_id)
    _save_job_index(idx)

    threading.Thread(target=_run_analysis, args=(task_id,), daemon=True).start()
    return {"task_id": task_id, "status": "queued"}


@app.get("/api/status/{task_id}")
def get_status(task_id: str):
    t = _get_task(task_id)
    return {"task_id": task_id, "status": t["status"], "progress": t["progress"], "error": t.get("error")}


@app.get("/api/result/{task_id}")
def get_result(task_id: str):
    t = _get_task(task_id)
    if t["status"] != "completed":
        raise HTTPException(400, f"任务状态: {t['status']}，尚未完成")
    return t["result"]


@app.get("/api/results/{task_id}/{filename:path}")
def serve_result_file(task_id: str, filename: str):
    t = _get_task(task_id)
    out_dir = t.get("result", {}).get("output_dir", "")
    file_path = Path(out_dir) / filename
    if not file_path.exists():
        raise HTTPException(404, f"文件不存在: {filename}")
    return FileResponse(str(file_path))


# ════════════════════════════════════════════════════
#  后台分析线程
# ════════════════════════════════════════════════════

def _run_analysis(task_id: str):
    task = _get_task(task_id)
    video_path = task["video_path"]
    template_path = task["template_path"]
    opts = task["options"]

    def progress_cb(frame, total):
        pct = int(frame / max(total, 1) * 100)
        t = _get_task(task_id)
        t["status"] = "processing"
        t["progress"] = pct
        _save_task(task_id, t)

    try:
        # Step 1: auto-detect court corners (server-side, no GUI)
        task["status"] = "processing"
        task["progress"] = 1
        _save_task(task_id, task)

        import cv2 as _cv2
        img = _cv2.imread(template_path)
        corners = None
        if img is not None:
            from badminton_analysis.court.mapper import auto_detect_preview, resolve_court_corners
            corners_auto, _preview = auto_detect_preview(img)
            if corners_auto:
                _result = resolve_court_corners(img, manual_corners=corners_auto)
                if _result and _result[0]:
                    corners = _result[0]
                    task["progress"] = 5
                    _save_task(task_id, task)

        # Step 2: run analysis with (or without) pre-detected corners
        from analyze_badminton import analyze_badminton_video

        result = analyze_badminton_video(
            video_path=video_path,
            template_path=template_path,
            court_corners=corners,  # will skip GUI if provided
            show_display=False,
            language=opts.get("language", "zh"),
            pose_family=opts.get("pose_family", "yolo-pose"),
            show_skeletons=opts.get("show_skeletons", True),
            show_player_trajectories=opts.get("show_traj", True),
            show_court_trajectory=opts.get("show_court", True),
            show_shuttlecock_trajectory=opts.get("show_shuttle", True),
            show_player_stats=opts.get("show_stats", True),
            progress_callback=progress_cb,
        )

        output_dir = result.get("output_dir", "")
        video_file = result.get("video", "")
        viz_paths = result.get("visualizations", [])

        def rel_url(p):
            if not p: return None
            p_str = str(p)
            # If the file doesn't exist, try temp_detect_ version
            if not os.path.exists(p_str):
                alt = p_str.replace("detect_", "temp_detect_")
                if os.path.exists(alt):
                    p_str = alt
            if output_dir and output_dir in p_str:
                relative = os.path.relpath(p_str, output_dir)
                return f"/api/results/{task_id}/{relative.replace(os.sep, '/')}"
            return None

        task["status"] = "completed"
        task["progress"] = 100
        task["result"] = {
            "output_dir": output_dir,
            "video_url": rel_url(video_file) if video_file else None,
            "detections_url": rel_url(result.get("detections", "")),
            "visualizations": [rel_url(v) for v in viz_paths if rel_url(v)],
            "stats": {
                "total_frames": result.get("total_frames"),
                "fps": result.get("fps"),
                "processing_time_sec": result.get("processing_time_sec"),
                "speedup_ratio": result.get("speedup_ratio"),
            },
        }
        _save_task(task_id, task)

    except Exception as e:
        task["status"] = "failed"
        task["error"] = str(e)
        _save_task(task_id, task)
        print(f"[{task_id}] ❌ 分析失败: {e}", file=sys.stderr)
        traceback.print_exc()


# ════════════════════════════════════════════════════
if __name__ == "__main__":
    uvicorn.run("server.main:app", host="0.0.0.0", port=8000, reload=True)
