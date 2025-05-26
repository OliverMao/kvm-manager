import os
import subprocess
import sys
from flask import Flask, render_template_string, request, redirect, url_for, flash

app = Flask(__name__)
app.secret_key = 'kvm-manager-web'

# 自动适配 PyInstaller 打包路径
if hasattr(sys, '_MEIPASS'):
    SCRIPT_PATH = os.path.join(sys._MEIPASS, 'kvm-manager.sh')
else:
    SCRIPT_PATH = os.path.abspath('kvm-manager.sh')

# HTML模板
TEMPLATE = '''
<!DOCTYPE html>
<html lang="zh-cn">
<head>
    <meta charset="UTF-8">
    <title>KVM管理器 Web界面</title>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css">
</head>
<body class="bg-light">
<div class="container py-4">
    <h2 class="mb-4">KVM虚拟机管理 Web界面</h2>
    <ul class="nav nav-tabs mb-3">
      <li class="nav-item"><a class="nav-link {% if tab=='vms' %}active{% endif %}" href="/">虚拟机管理</a></li>
      <li class="nav-item"><a class="nav-link {% if tab=='network' %}active{% endif %}" href="/network">nat1网络管理</a></li>
    </ul>
    {% with messages = get_flashed_messages() %}
      {% if messages %}
        <div class="alert alert-info">{{ messages[0] }}</div>
      {% endif %}
    {% endwith %}
    {{ content|safe }}
</div>
</body>
</html>
'''

@app.route('/', methods=['GET', 'POST'])
def index():
    # 处理虚拟机操作
    if request.method == 'POST':
        vm_name = request.form.get('vm_name')
        action = request.form.get('action')
        if action == 'start':
            result = subprocess.run([SCRIPT_PATH], input=f'1\n4\n{vm_name}\nx\n', text=True, capture_output=True)
            flash(result.stdout[-500:])
        elif action == 'shutdown':
            result = subprocess.run([SCRIPT_PATH], input=f'1\n5\n{vm_name}\nx\n', text=True, capture_output=True)
            flash(result.stdout[-500:])
        elif action == 'delete':
            result = subprocess.run([SCRIPT_PATH], input=f'1\n3\n{vm_name}\nx\n', text=True, capture_output=True)
            flash(result.stdout[-500:])
        elif action == 'export':
            result = subprocess.run([SCRIPT_PATH], input=f'1\n6\n{vm_name}\nx\n', text=True, capture_output=True)
            flash(result.stdout[-500:])
        elif action == 'suspend':
            result = subprocess.run([SCRIPT_PATH], input=f'1\n8\n{vm_name}\nx\n', text=True, capture_output=True)
            flash(result.stdout[-500:])
        elif action == 'resume':
            result = subprocess.run([SCRIPT_PATH], input=f'1\n9\n{vm_name}\nx\n', text=True, capture_output=True)
            flash(result.stdout[-500:])
        return redirect(url_for('index'))
    # 获取虚拟机列表
    result = subprocess.run([SCRIPT_PATH], input='1\n2\nx\n', text=True, capture_output=True)
    vmlist = []
    vmlist_raw = []
    vncinfo = []
    lines = result.stdout.splitlines()
    in_vmlist = False
    for line in lines:
        if 'Id' in line and 'Name' in line and 'State' in line:
            in_vmlist = True
            continue
        if in_vmlist:
            if not line.strip():
                in_vmlist = False
                continue
            vmlist_raw.append(line)
            cols = line.split()
            if len(cols) >= 3:
                # 兼容无Id的情况
                if cols[0] == '-':
                    vm_name = cols[1]
                    state = cols[2]
                else:
                    vm_name = cols[1]
                    state = cols[2]
                vmlist.append({'name': vm_name, 'state': state})
        if 'VNC连接信息' in line:
            idx = lines.index(line)
            vncinfo = lines[idx+1:]
            break
    content_tpl = '''
    <h4>虚拟机列表</h4>
    <form method="post">
    <table class="table table-bordered table-sm align-middle">
      <thead><tr><th>名称</th><th>状态</th><th>操作</th></tr></thead>
      <tbody>
      {% for vm in vmlist %}
        <tr>
          <td>{{ vm.name }}</td>
          <td>{{ vm.state }}</td>
          <td>
            <button name="action" value="start" class="btn btn-success btn-sm" {% if vm.state=='running' %}disabled{% endif %} onclick="this.form.vm_name.value='{{ vm.name }}'">启动</button>
            <button name="action" value="shutdown" class="btn btn-warning btn-sm" {% if vm.state!='running' %}disabled{% endif %} onclick="this.form.vm_name.value='{{ vm.name }}'">关机</button>
            <button name="action" value="suspend" class="btn btn-secondary btn-sm" {% if vm.state!='running' %}disabled{% endif %} onclick="this.form.vm_name.value='{{ vm.name }}'">挂起</button>
            <button name="action" value="resume" class="btn btn-primary btn-sm" {% if vm.state!='paused' %}disabled{% endif %} onclick="this.form.vm_name.value='{{ vm.name }}'">恢复</button>
            <button name="action" value="delete" class="btn btn-danger btn-sm" onclick="this.form.vm_name.value='{{ vm.name }}'">删除</button>
            <button name="action" value="export" class="btn btn-info btn-sm" onclick="this.form.vm_name.value='{{ vm.name }}'">导出ISO</button>
          </td>
        </tr>
      {% endfor %}
      </tbody>
    </table>
    <input type="hidden" name="vm_name" value="">
    </form>
    <h5>VNC信息</h5>
    <pre>{{ vncinfo|join('\n') }}</pre>
    <a class="btn btn-primary" href="/create">创建虚拟机</a>
    '''
    content = render_template_string(content_tpl, vmlist=vmlist, vncinfo=vncinfo)
    return render_template_string(TEMPLATE, tab='vms', content=content)

@app.route('/create', methods=['GET', 'POST'])
def create_vm():
    if request.method == 'POST':
        # 构造交互输入
        inputs = [
            request.form.get('name',''),
            request.form.get('cpu','1'),
            request.form.get('ram','1024'),
            request.form.get('disk','5'),
            request.form.get('ip',''),
            request.form.get('iso','ubuntu-20.04.6-live-server-amd64.iso'),
            request.form.get('os_variant',''),
            request.form.get('auto_install','n'),
        ]
        input_str = '1\n' + '\n'.join(inputs) + '\n' + 'x\n'
        result = subprocess.run([SCRIPT_PATH], input=input_str, text=True, capture_output=True)
        flash(result.stdout[-500:])
        return redirect(url_for('index'))
    content = '''
    <h4>创建虚拟机</h4>
    <form method="post" class="row g-3">
      <div class="col-md-4"><label class="form-label">名称</label><input name="name" class="form-control" required></div>
      <div class="col-md-2"><label class="form-label">CPU</label><input name="cpu" class="form-control" value="1"></div>
      <div class="col-md-2"><label class="form-label">内存(MB)</label><input name="ram" class="form-control" value="1024"></div>
      <div class="col-md-2"><label class="form-label">硬盘(GB)</label><input name="disk" class="form-control" value="5"></div>
      <div class="col-md-4"><label class="form-label">静态IP</label><input name="ip" class="form-control"></div>
      <div class="col-md-6"><label class="form-label">ISO文件名</label><input name="iso" class="form-control" value="ubuntu-20.04.6-live-server-amd64.iso"></div>
      <div class="col-md-4"><label class="form-label">os-variant</label><input name="os_variant" class="form-control" placeholder="如ubuntu20.04, win2k22"></div>
      <div class="col-md-4"><label class="form-label">自动安装(无人值守)</label>
        <select name="auto_install" class="form-select">
          <option value="n">否</option>
          <option value="y">是</option>
        </select>
      </div>
      <div class="col-12"><button class="btn btn-success" type="submit">创建</button> <a href="/" class="btn btn-secondary">返回</a></div>
    </form>
    '''
    return render_template_string(TEMPLATE, tab='vms', content=content)

@app.route('/network', methods=['GET', 'POST'])
def network():
    msg = ''
    if request.method == 'POST':
        action = request.form.get('action')
        if action == 'init':
            result = subprocess.run([SCRIPT_PATH], input='2\n1\nx\n', text=True, capture_output=True)
            msg = result.stdout[-500:]
        elif action == 'delete':
            result = subprocess.run([SCRIPT_PATH], input='2\n2\nx\n', text=True, capture_output=True)
            msg = result.stdout[-500:]
        elif action == 'list':
            result = subprocess.run([SCRIPT_PATH], input='2\n3\nx\n', text=True, capture_output=True)
            msg = result.stdout[-500:]
        elif action == 'start':
            result = subprocess.run([SCRIPT_PATH], input='2\n4\nx\n', text=True, capture_output=True)
            msg = result.stdout[-500:]
        flash(msg)
        return redirect(url_for('network'))
    content = '''
    <h4>nat1网络管理</h4>
    <form method="post" class="mb-3">
      <button name="action" value="init" class="btn btn-primary">初始化nat1网络</button>
      <button name="action" value="delete" class="btn btn-danger">删除nat1网络</button>
      <button name="action" value="list" class="btn btn-info">查看全部网络</button>
      <button name="action" value="start" class="btn btn-success">启动nat1网络</button>
    </form>
    '''
    return render_template_string(TEMPLATE, tab='network', content=content)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=True)
