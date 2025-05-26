#!/bin/bash

# 检查是否以 root 用户运行
if [ "$EUID" -ne 0 ]; then
  echo "请使用 root 权限运行此脚本"
  exit 1
fi

# 检查是否安装了 iptables-persistent
if ! dpkg -s iptables-persistent &> /dev/null; then
  echo "未检测到 iptables-persistent，正在安装..."
  apt update
  DEBIAN_FRONTEND=noninteractive apt install -y iptables-persistent
fi

# 外部接口名称
EXT_IFACE="enp5s0"  # 根据实际情况修改这个值

# 端口映射配置文件
PORT_MAP_FILE="port_mappings.txt"

# 确保 IP 转发开启
function ensure_ip_forwarding() {
  echo "确保 IP 转发功能已开启..."
  sysctl -w net.ipv4.ip_forward=1
  sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
  echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
}

# 设置默认 FORWARD 策略为 ACCEPT
function set_default_forward_policy() {
  echo "设置默认 FORWARD 策略为 ACCEPT..."
  iptables -P FORWARD ACCEPT
}

# 添加 MASQUERADE 规则
function add_masquerade_rule() {
  echo "添加 MASQUERADE 规则..."
  iptables -t nat -A POSTROUTING -o $EXT_IFACE -j MASQUERADE
}

# 删除 MASQUERADE 规则
function remove_masquerade_rule() {
  echo "删除 MASQUERADE 规则..."
  iptables -t nat -D POSTROUTING -o $EXT_IFACE -j MASQUERADE
}

# 从文件中读取端口映射信息并应用
function apply_port_mappings() {
  local action=$1
  while IFS=' ' read -r port_spec guest_ip guest_port
  do
    # 跳过注释行和空行
    [[ "$port_spec" =~ ^#.*$ || -z "$port_spec" ]] && continue
    
    if [[ "$port_spec" == *-* ]]; then
      # 处理端口范围
      local start_port end_port
      start_port=$(echo $port_spec | cut -d'-' -f1)
      end_port=$(echo $port_spec | cut -d'-' -f2)
      
      echo "处理端口范围 $start_port-$end_port -> $guest_ip:$guest_port"
      
      # 计算目标端口的偏移量
      local port_offset=0
      
      for ((host_port=start_port; host_port<=end_port; host_port++)); do
        local target_port=$((guest_port + port_offset))
        if [ "$action" == "add" ]; then
          echo "添加 TCP/UDP DNAT 规则：$host_port -> $guest_ip:$target_port"
          # 添加 TCP 规则
          iptables -t nat -A PREROUTING -p tcp --dport $host_port -j DNAT --to-destination $guest_ip:$target_port
          # 添加 UDP 规则
          iptables -t nat -A PREROUTING -p udp --dport $host_port -j DNAT --to-destination $guest_ip:$target_port
        elif [ "$action" == "remove" ]; then
          echo "删除 TCP/UDP DNAT 规则：$host_port -> $guest_ip:$target_port"
          # 删除 TCP 规则
          iptables -t nat -D PREROUTING -p tcp --dport $host_port -j DNAT --to-destination $guest_ip:$target_port
          # 删除 UDP 规则
          iptables -t nat -D PREROUTING -p udp --dport $host_port -j DNAT --to-destination $guest_ip:$target_port
        fi
        ((port_offset++))
      done
    else
      # 处理单个端口映射
      if [[ ! -z "$port_spec" && ! -z "$guest_ip" && ! -z "$guest_port" ]]; then
        if [ "$action" == "add" ]; then
          echo "添加 TCP/UDP DNAT 规则：$port_spec -> $guest_ip:$guest_port"
          # 添加 TCP 规则
          iptables -t nat -A PREROUTING -p tcp --dport $port_spec -j DNAT --to-destination $guest_ip:$guest_port
          # 添加 UDP 规则
          iptables -t nat -A PREROUTING -p udp --dport $port_spec -j DNAT --to-destination $guest_ip:$guest_port
        elif [ "$action" == "remove" ]; then
          echo "删除 TCP/UDP DNAT 规则：$port_spec -> $guest_ip:$guest_port"
          # 删除 TCP 规则
          iptables -t nat -D PREROUTING -p tcp --dport $port_spec -j DNAT --to-destination $guest_ip:$guest_port
          # 删除 UDP 规则
          iptables -t nat -D PREROUTING -p udp --dport $port_spec -j DNAT --to-destination $guest_ip:$guest_port
        fi
      fi
    fi
  done < "$PORT_MAP_FILE"
}

# 保存 iptables 规则
function save_iptables_rules() {
  echo "保存 iptables 规则..."
  netfilter-persistent save
  netfilter-persistent reload
}

# 清除所有iptables规则
function clean_iptables(){
sudo iptables -F
sudo iptables -t nat -F
sudo iptables -t mangle -F
sudo iptables -X
}

# 主逻辑
case $1 in
  add)
    ensure_ip_forwarding
    clean_iptables
    set_default_forward_policy
    add_masquerade_rule
    apply_port_mappings "add"
    save_iptables_rules
    ;;
  remove)
    clean_iptables
    remove_masquerade_rule
    apply_port_mappings "remove"
    save_iptables_rules
    ;;
  *)
    echo "用法: $0 {add|remove}"
    exit 1
    ;;
esac
