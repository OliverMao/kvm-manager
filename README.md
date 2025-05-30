# kvm-manager.sh

本脚本为 KVM 虚拟机管理工具，支持以下主要功能：

- 检查并自动安装 KVM/Cloud-Init 相关依赖环境
- 初始化、启动、删除 nat1 虚拟网络
- 创建虚拟机（支持静态IP、无人值守自动安装、ISO选择、资源配置）
- 查看所有虚拟机及其 VNC 连接信息
- 启动、关机、删除虚拟机（含磁盘清理）
- 导出虚拟机磁盘为 ISO 镜像
- 连接虚拟机控制台
- 查看和管理 KVM 网络定义

> 需先初始化 nat1 网络后，方可创建虚拟机。  
> 支持 Ubuntu Server系统的自动化安装。

```bash
# 赋予权限
chmod +x kvm-manager.sh
```

请以 root 或具备 sudo 权限的用户运行本脚本。

OS_VARIANT请运行命令:`osinfo-query os`进行查询，可能需要先安装`apt-get install libosinfo-bin`

> 注意：使用无人值守时，请检查代码中SEED的配置，请根据实际情况修改脚本中`cloud-config`的 `ethernets`（外部网卡名称）。

如忘记配置，可以手动修改netplan中的配置进行调整：

```bash
sudo vim /etc/netplan/50-cloud-init.yaml
```

```bash
sudo netplan apply
```

## windows  使用方法
windows安装完成后可能存在无网络的问题，需要挂载virtio-win的iso，
查询虚拟机磁盘：
```bash
virsh domblklist <vm_name>
```
可能如下：
```bash
root@faab:/etc/netplan# virsh domblklist win
 Target   Source
--------------------------------------------------------------------------------------
 sda      /var/lib/libvirt/images/win.qcow2
 sdb      /home/iso/zh-cn_windows_server_2022_updated_june_2024_x64_dvd_8c5a802d.iso
```
将sdb替换
```bash
virsh change-media win sdb --eject  # 先弹出现有的 ISO
virsh change-media win sdb /home/iso/virtio-win-0.1.271.iso --update  # 挂载新的 ISO
```
虚拟机无需关机，在文件管理可查看挂载的 ISO
在iso下运行`virtio-win-gt-x64.exe`安装即可

然后宿主机需要执行：
```bash
sysctl net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -s 192.168.6.0/24 ! -d 192.168.6.0/24 -j MASQUERADE
```
>192.168.6.0这个IP需要与kvm-manager.sh中配置的net1网络的IP一致

## 打包

```bash 
pip install pyinstaller

```

```bash 
pyinstaller --onefile --add-data "kvm-manager.sh:." web_manager.py
```

```bash
chmod +x web_manager
./web_manager
```

# forword_manager.sh

`forword_manager.sh` 是一个用于批量管理 KVM 虚拟机端口转发的脚本，主要功能如下：

- 自动检测并安装 `iptables-persistent` 依赖
- 支持单端口和端口范围的 TCP/UDP 转发
- 一键添加或移除所有端口转发规则
- 自动开启 IP 转发和 NAT（MASQUERADE）
- 规则配置文件支持注释和灵活格式

## 使用方法

1. **准备端口映射配置文件**

   复制示例文件并根据实际需求编辑：

   ```bash
   cp port_mappings.txt.example port_mappings.txt
   vim port_mappings.txt
   ```

   配置格式示例：

   ```
   20080 192.168.5.2 80
   20443 192.168.5.2 443
   20022 192.168.5.2 22

   # 端口范围格式：start-end guest_ip guest_port_start
   # 15000-19000 192.168.5.2 15000
   ```

2. **运行脚本添加端口转发规则**

   ```bash
   sudo bash forword_manager.sh add
   ```

3. **移除所有端口转发规则**

   ```bash
   sudo bash forword_manager.sh remove
   ```


>  注意：请根据实际需求修改端口映射配置文件以及网卡名称。


# 注意

## 遇到宿主机没有网络的情况

```bash
可能是/etc/resolv.conf文件的DNS指向为127.0.0.53
可以运行“resolvectl status”查看当前正在使用的上行DNS服务器的详细信息
修改方法：
修改：/etc/systemd/resolved.conf
DNS设置为： DNS=223.5.5.5 8.8.8.8
           FallbackDNS=114.114.114.114 1.1.1.1

运行：systemctl restart systemd-resolved

再次查看：resolvectl status

此时应该可以有效访问外网

```


   