#!/bin/bash
stty erase ^H
# KVM虚拟机管理脚本，支持创建、查看、删除

# 环境检测
function check_env() {
  local missing=0
  for cmd in virsh virt-install qemu-img cloud-localds; do
    if ! command -v $cmd &>/dev/null; then
      echo "缺少命令: $cmd"
      missing=1
    fi
  done
  if [ "$missing" -eq 1 ]; then
    echo "检测到部分KVM/Cloud-Init环境未安装。"
    echo "安装所需环境："
    sudo apt update
    sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst cloud-image-utils
    echo "安装完成后请重新运行本脚本。"
    exit 1
  fi
}

check_env

function create_vm() {
  # KVM虚拟机创建脚本，使用nat1网络，指定静态IP

  read -p "请输入虚拟机名称: " VM_NAME
  read -p "请输入CPU核心数 [默认1]: " VM_CPU
  read -p "请输入内存大小(MB) [默认1024]: " VM_RAM
  read -p "请输入硬盘大小(GB) [默认5]: " VM_DISK
  read -p "请输入分配给虚拟机的静态IP(如192.168.6.2): " VM_IP
  read -p "请输入ISO名称 [默认ubuntu-20.04.6-live-server-amd64.iso]: " ISO_NAME
  ISO_NAME=${ISO_NAME:-ubuntu-20.04.6-live-server-amd64.iso}

  # 检查ISO路径权限问题
  if [[ "$ISO_NAME" == /root/* ]]; then
    echo "警告：ISO文件在/root目录下，libvirt/qemu默认无法访问。"
    echo "请将ISO文件移动到/home/iso/目录下，并输入新的ISO路径。"
    exit 1
  fi

  # 自动补全ISO绝对路径
  if [[ "$ISO_NAME" != /* ]]; then
    ISO_PATH="/home/iso/$ISO_NAME"
  else
    ISO_PATH="$ISO_NAME"
  fi

  # 检查ISO文件是否存在
  if [ ! -f "$ISO_PATH" ]; then
    echo "❌ 未找到ISO文件: $ISO_PATH"
    exit 1
  fi

  # read -p "请输入os-type [默认linux]: " OS_TYPE
  read -p "请输入os-variant [默认ubuntu20.04, win2k22]: " OS_VARIANT

  VM_CPU=${VM_CPU:-1}
  VM_RAM=${VM_RAM:-1024}
  VM_DISK=${VM_DISK:-5}
  # OS_TYPE=${OS_TYPE:-linux}
  OS_VARIANT=${OS_VARIANT:-ubuntu20.04}

  DISK_PATH="/var/lib/libvirt/images/${VM_NAME}.qcow2"
  NETWORK_NAME="nat1"

  # 创建磁盘
  qemu-img create -f qcow2 "$DISK_PATH" "${VM_DISK}G"

  read -p "是否使用自动安装(无人值守)? [y/N]: " AUTO_INSTALL

  if [[ "$AUTO_INSTALL" =~ ^[Yy]$ ]]; then
    SEED_DIR="/var/lib/libvirt/images/${VM_NAME}-seed"
    mkdir -p "$SEED_DIR"

    # 自动生成meta-data
    cat > "$SEED_DIR/meta-data" <<EOF
instance-id: $VM_NAME
local-hostname: $VM_NAME
EOF

    # 自动生成user-data（用户名ubuntu，密码ubuntu，静态IP）
    cat > "$SEED_DIR/user-data" <<EOF
#cloud-config
autoinstall:
  version: 1
  identity:
    hostname: $VM_NAME
    username: ubuntu
    password: $(openssl passwd -6 ubuntu)
  ssh:
    install-server: true
    allow-pw: true
  network:
    network:
      version: 2
      ethernets:
        enp1s0:
          dhcp4: false
          addresses: [$VM_IP/24]
          gateway4: 192.168.6.1
          nameservers:
            addresses: [8.8.8.8,114.114.114.114]
  locale: zh_CN.UTF-8
  keyboard:
    layout: us
    variant: ''
  storage:
    layout:
      name: lvm
  user-data:
    disable_root: false
    ssh_pwauth: true
EOF

    # 生成seed.iso
    cloud-localds "$SEED_DIR/seed.iso" "$SEED_DIR/user-data" "$SEED_DIR/meta-data"

    # 修正无人值守启动顺序，确保ISO为第一个cdrom，seed.iso为第二个
    virt-install \
      --name "$VM_NAME" \
      --vcpus "$VM_CPU" \
      --memory "$VM_RAM" \
      --cdrom "$ISO_PATH" \
      --disk path="$DISK_PATH",format=qcow2 \
      --disk path="$SEED_DIR/seed.iso",device=cdrom \
      --network network="$NETWORK_NAME",model=virtio \
      --os-variant "$OS_VARIANT" \
      --graphics vnc,listen=0.0.0.0 \
      --noautoconsole \
      --extra-args "autoinstall"

    echo "如遇'Boot failed: Could not read from CDROM'，请检查ISO文件是否为可引导的安装镜像，且路径正确。"
  else
    virt-install \
      --name "$VM_NAME" \
      --vcpus "$VM_CPU" \
      --memory "$VM_RAM" \
      --cdrom "$ISO_PATH" \
      --disk path="$DISK_PATH",format=qcow2 \
      --network network="$NETWORK_NAME",model=virtio \
      --os-variant "$OS_VARIANT" \
      --graphics vnc,listen=0.0.0.0 \
      --noautoconsole
  fi

  echo "虚拟机已创建。"
}

function list_vms() {
  echo "当前所有虚拟机："
  virsh list --all
}

function delete_vm() {
  read -p "请输入要删除的虚拟机名称: " VM_NAME
  virsh destroy "$VM_NAME" 2>/dev/null

  # 只删除虚拟机磁盘，不删除ISO等cdrom文件
  for disk_path in $(virsh domblklist "$VM_NAME" --details | awk '/disk/ {print $4}'); do
    if [[ "$disk_path" == *.iso ]]; then
      echo "跳过ISO镜像文件: $disk_path"
      continue
    fi
    if [[ -f "$disk_path" ]]; then
      rm -f "$disk_path"
      echo "已删除磁盘文件: $disk_path"
    fi
  done

  virsh undefine "$VM_NAME"
  echo "虚拟机 $VM_NAME 已删除（磁盘文件已清理，ISO镜像未删除）。"
}

function connect_vm() {
  read -p "请输入要连接的虚拟机名称: " VM_NAME
  echo "按 Ctrl+] 退出控制台"
  virsh console "$VM_NAME"
}

function start_vm() {
  read -p "请输入要启动的虚拟机名称: " VM_NAME
  virsh start "$VM_NAME"
  echo "虚拟机 $VM_NAME 已启动。"
}

function shutdown_vm() {
  read -p "请输入要关机的虚拟机名称: " VM_NAME
  virsh shutdown "$VM_NAME"
  echo "虚拟机 $VM_NAME 正在关机。"
}

function vnc_info_vm() {
  read -p "请输入要查询VNC信息的虚拟机名称: " VM_NAME
  VNC_DISPLAY=$(virsh vncdisplay "$VM_NAME")
  if [[ "$VNC_DISPLAY" == "error:"* ]]; then
    echo "未找到虚拟机 $VM_NAME 或该虚拟机未运行。"
  else
    HOST_IP=$(hostname -I | awk '{print $1}')
    PORT_NUM=$(echo "$VNC_DISPLAY" | sed 's/^://')
    VNC_PORT=$((5900 + PORT_NUM))
    echo "VNC地址：$HOST_IP:$VNC_PORT"
    echo "（如无法远程访问，请确保libvirt/qemu配置VNC监听0.0.0.0且防火墙已放行端口）"
  fi
}

function init_nat1_network() {
  NET_XML="/etc/libvirt/qemu/networks/nat1.xml"
  # 判断nat1网络是否已被定义
  if sudo virsh net-info nat1 &>/dev/null; then
    echo "nat1网络已被定义，跳过定义步骤。"
    return
  else
    if [ ! -f "$NET_XML" ]; then
      sudo mkdir -p /etc/libvirt/qemu/networks
      sudo tee "$NET_XML" > /dev/null <<EOF
<network>
  <name>nat1</name>
  <forward mode="nat"/>
  <bridge name="virbr1" stp="on" delay="0"/>
  <ip address="192.168.6.1" netmask="255.255.255.0">
    <dhcp>
      <range start="192.168.6.2" end="192.168.6.3"/>
    </dhcp>
  </ip>
</network>
EOF
      echo "已生成 $NET_XML"
    else
      echo "$NET_XML 已存在，跳过生成。"
    fi
    sudo virsh net-define "$NET_XML"
    sudo virsh net-start nat1
    sudo virsh net-autostart nat1
    echo "nat1网络已初始化并启动。"
  fi
}

function delete_nat1_network() {
  NET_XML="/etc/libvirt/qemu/networks/nat1.xml"
  # 检查是否有虚拟机存在
  VM_COUNT=$(virsh list --all --name | grep -v '^$' | wc -l)
  if [ "$VM_COUNT" -gt 0 ]; then
    echo "请先删除所有虚拟机后再删除nat1网络定义。当前仍有 $VM_COUNT 台虚拟机。"
    return
  fi
  if sudo virsh net-info nat1 &>/dev/null; then
    sudo virsh net-destroy nat1
    sudo virsh net-undefine nat1
    echo "nat1网络已删除。"
  else
    echo "nat1网络未定义，无需删除。"
  fi
  if [ -f "$NET_XML" ]; then
    sudo rm -f "$NET_XML"
    echo "$NET_XML 文件已删除。"
  fi
}

function start_nat1_network() {
  if sudo virsh net-info nat1 &>/dev/null; then
    # 检查nat1是否已active
    STATE=$(sudo virsh net-info nat1 | grep -i '^Active:' | awk '{print $2}')
    if [ "$STATE" == "yes" ]; then
      echo "nat1网络已处于启动状态。"
      return
    fi
    # 启动nat1网络
    if sudo virsh net-start nat1; then
      echo "nat1网络已启动。"
    else
      echo "nat1网络启动失败，可能与物理网卡冲突或已被占用。"
      echo "请检查网络配置或使用 'virsh net-info nat1' 查看详细信息。"
    fi
  else
    echo "nat1网络未定义，无法启动。"
  fi
}

function list_networks() {
  echo "当前所有KVM网络定义："
  virsh net-list --all
}

function export_vm_iso() {
  local VM_NAME
  read -p "请输入要导出的虚拟机名称: " VM_NAME

  # 获取磁盘路径
  DISK_PATH=$(virsh domblklist "$VM_NAME" --details | awk '/disk/ {print $4}' | head -n1)
  if [ -z "$DISK_PATH" ] || [ ! -f "$DISK_PATH" ]; then
    echo "未找到虚拟机 $VM_NAME 的磁盘文件。"
    return 1
  fi

  # 检查是否有.lock文件
  if [ -f "${DISK_PATH}.lock" ]; then
    echo "检测到磁盘文件存在.lock锁文件: ${DISK_PATH}.lock"
    echo "请确认没有其他进程占用该磁盘，必要时删除.lock文件后重试。"
    return 1
  fi

  # 检查是否有进程占用该磁盘文件
  if command -v lsof &>/dev/null; then
    if lsof "$DISK_PATH" | grep -q "$DISK_PATH"; then
      echo "检测到有进程正在占用磁盘文件:"
      lsof "$DISK_PATH"
      echo "请关闭相关进程后再试。"
      return 1
    fi
  fi

  # 检查磁盘文件权限
  if [ ! -r "$DISK_PATH" ] || [ ! -w "$DISK_PATH" ]; then
    echo "当前用户没有磁盘文件的读写权限: $DISK_PATH"
    echo "请检查文件权限。"
    return 1
  fi

  # 生成输出ISO路径
  ISO_NAME="${VM_NAME}-export.iso"
  ISO_PATH="$(pwd)/$ISO_NAME"

  # 创建临时raw文件
  RAW_PATH="/tmp/${VM_NAME}-export.raw"
  echo "正在将qcow2磁盘转换为raw格式..."
  qemu-img convert -f qcow2 -O raw "$DISK_PATH" "$RAW_PATH"
  if [ $? -ne 0 ]; then
    echo "qcow2转raw失败。"
    echo "可能原因：磁盘文件被占用、权限不足或格式不正确。"
    rm -f "$RAW_PATH"
    return 1
  fi

  # 检查genisoimage或mkisofs
  if command -v genisoimage &>/dev/null; then
    ISO_TOOL=genisoimage
  elif command -v mkisofs &>/dev/null; then
    ISO_TOOL=mkisofs
  else
    echo "未找到genisoimage或mkisofs，请先安装。"
    rm -f "$RAW_PATH"
    return 1
  fi

  # 检查raw文件大小，超过4GB则加参数
  ISO_EXTRA_OPTS=""
  RAW_SIZE=$(stat -c%s "$RAW_PATH")
  LIMIT_SIZE=$((4*1024*1024*1024-1))
  if [ "$RAW_SIZE" -gt "$LIMIT_SIZE" ]; then
    echo "检测到raw文件大于4GB，自动添加 -allow-limited-size 参数。"
    ISO_EXTRA_OPTS="-allow-limited-size"
  fi

  # 打包为ISO
  echo "正在打包为ISO镜像..."
  $ISO_TOOL $ISO_EXTRA_OPTS -o "$ISO_PATH" -V "${VM_NAME}_IMG" -J -r "$RAW_PATH"
  if [ $? -eq 0 ]; then
    echo "✅ 已导出ISO镜像: $ISO_PATH"
  else
    echo "ISO打包失败。"
  fi

  # 清理临时文件
  rm -f "$RAW_PATH"
}

while true; do
  echo "请选择操作类别："
  echo "1. 虚拟机管理"
  echo "2. nat1网络管理"
  echo "x. 退出"
  echo "✳需要先初始化nat1网络，才能创建虚拟机。"
  read -p "请输入类别序号: " MAIN_ACTION

  if [ "$MAIN_ACTION" == "x" ] || [ "$MAIN_ACTION" == "X" ]; then
    echo "已退出。"
    exit 0
  fi

  if [ "$MAIN_ACTION" == "1" ]; then
    echo "虚拟机管理："
    echo "1. 创建虚拟机"
    echo "2. 查看虚拟机（含VNC信息）"
    echo "3. 删除虚拟机"
    echo "4. 启动虚拟机"
    echo "5. 虚拟机关机"
    echo "6. 导出虚拟机磁盘为ISO镜像"
    echo "x. 返回主菜单"
    read -p "请输入虚拟机操作序号: " VM_ACTION
    if [ "$VM_ACTION" == "x" ] || [ "$VM_ACTION" == "X" ]; then
      continue
    fi
    case "$VM_ACTION" in
      1)
        create_vm
        ;;
      2)
        list_vms
        # 额外显示所有虚拟机的VNC信息
        echo "虚拟机VNC连接信息："
        for VM in $(virsh list --all --name | grep -v '^$'); do
          VNC_DISPLAY=$(virsh vncdisplay "$VM")
          if [[ "$VNC_DISPLAY" == "error:"* ]]; then
            echo "$VM: 未运行或无VNC"
          else
            HOST_IP=$(hostname -I | awk '{print $1}')
            PORT_NUM=$(echo "$VNC_DISPLAY" | sed 's/^://')
            VNC_PORT=$((5900 + PORT_NUM))
            echo "$VM: $HOST_IP:$VNC_PORT"
          fi
        done
        ;;
      3)
        delete_vm
        ;;
      4)
        start_vm
        ;;
      5)
        shutdown_vm
        ;;
      6)
        export_vm_iso
        ;;
      *)
        echo "无效选项"
        ;;
    esac
  elif [ "$MAIN_ACTION" == "2" ]; then
    echo "nat1网络管理："
    echo "1. 初始化nat1网络"
    echo "2. 删除nat1网络定义"
    echo "3. 查看全部KVM网络定义"
    echo "4. 启动nat1网络"
    echo "x. 返回主菜单"
    read -p "请输入网络操作序号: " NET_ACTION
    if [ "$NET_ACTION" == "x" ] || [ "$NET_ACTION" == "X" ]; then
      continue
    fi
    case "$NET_ACTION" in
      1)
        init_nat1_network
        ;;
      2)
        delete_nat1_network
        ;;
      3)
        list_networks
        ;;
      4)
        start_nat1_network
        ;;
      *)
        echo "无效选项"
        ;;
    esac
  else
    echo "无效选项"
  fi
done