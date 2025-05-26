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

请以 root 或具备 sudo 权限的用户运行本脚本。

OS_VARIANT请运行命令:`osinfo-query os`进行查询，可能需要先安装`apt-get install libosinfo-bin`